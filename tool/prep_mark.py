#!/usr/bin/env python3
"""Trim a logo to its visible ink, then centre it by that ink's mass.

Why two steps, not one:

1. TRIM. mark.png carried a large faint halo — pixels with alpha 1-32, about
   12% of the file, a soft shadow nobody can see. A `getbbox()` trim counts
   them, so the artwork measured as "100% of the canvas" while the *visible*
   logo was only 53% wide. Every screen drawing this asset at `width: 200`
   therefore drew ~106px of logo, which is why it read as small. Trimming at
   a threshold the eye cannot see (32/255) removes the halo and, on its own,
   makes the drawn logo ~2x bigger.

2. CENTRE. After the trim the visible ink still sat 7px left of centre, because
   the remaining soft shadow is heavier on the lower-right. Centring is done
   by the alpha-weighted centroid, not the bounding box: a bbox is blind to
   where the weight actually is.

Padding does double duty — it slides the artwork and widens the canvas, so the
centre it is measured against moves half as far as the ink does. The offset is
therefore applied twice:  want cx + p == (w + p) / 2  ->  p == 2 * (w/2 - cx).

Idempotent by construction: once centred, both steps are no-ops. **`--check`
exists to let you BELIEVE that without performing it** — it runs the same two
steps in memory, writes nothing, and exits 1 if the mark is not already prepped.

Run: python3 tool/prep_mark.py assets/brand/mark.png [--write | --check]

Exit codes: 0 ok (and, under `--check`, already prepped) · 1 stale, only under
`--check` · 2 refused — the file is missing, unreadable, or has no visible ink.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

# Alpha at or below this is invisible on any screen; it is shadow halo, not art.
VISIBLE_ALPHA = 32

DEFAULT_MARK = Path("assets/brand/mark.png")

EXIT_OK = 0
EXIT_STALE = 1
EXIT_REFUSED = 2


class Refused(Exception):
    """A reason the mark cannot be prepared, in words a human can act on."""


def loaded_alpha(im: Image.Image):
    alpha = im.split()[3]
    w, h = im.size
    return alpha, w, h, [int(v) for v in alpha.get_flattened_data()]


def load_mark(path: Path) -> Image.Image:
    """Open the mark fully decoded, or refuse it by name.

    A bare `Image.open` is lazy: a missing file raises a raw `FileNotFoundError`
    traceback out of this module, and a truncated file raises the same way much
    later, from inside a crop. `load()` forces the decode here so both are one
    decision with one message, on the channel a human reads.
    """
    if not path.is_file():
        raise Refused("no such file: %s" % path)
    try:
        im = Image.open(path)
        im.load()
        return im.convert("RGBA")
    except Refused:
        raise
    except Exception as exc:
        raise Refused("cannot read %s: %s: %s"
                      % (path, type(exc).__name__, exc))


def trim_to_ink(im: Image.Image, thr: int = VISIBLE_ALPHA) -> Image.Image:
    alpha, w, h, data = loaded_alpha(im)
    cols = [x for x in range(w) if any(data[y * w + x] > thr for y in range(h))]
    rows = [y for y in range(h) if any(data[y * w + x] > thr for x in range(w))]
    if not cols or not rows:
        raise Refused("nothing visible in this image: every pixel is at or "
                      "below alpha %d, so there is no ink to trim or centre "
                      "(trim would have nothing to keep, and the centroid has "
                      "no weight to average)" % VISIBLE_ALPHA)
    return im.crop((cols[0], rows[0], cols[-1] + 1, rows[-1] + 1))


def centroid(im: Image.Image) -> tuple[float, float]:
    alpha, w, h, data = loaded_alpha(im)
    sx = sy = sw = 0.0
    for y in range(h):
        row = y * w
        for x in range(w):
            v = int(data[row + x])
            if v > VISIBLE_ALPHA:
                sx += x * v
                sy += y * v
                sw += v
    if sw:
        return sx / sw, sy / sw
    return w / 2, h / 2


def max_ink_radius(im: Image.Image) -> float:
    """Farthest visible ink pixel from the canvas centre, in pixels.

    This is what decides how large the mark may be inside a circular icon mask:
    the bounding box of a portrait mark overstates it, because its corners are
    empty. The canvas centre is the right origin and not the ink's own centroid
    — `gen_icons.place_by_radius` pastes the mark centred by its box, so the
    canvas centre is what a circular mask actually shares with the artwork.
    """
    alpha, w, h, data = loaded_alpha(im)
    cx, cy = w / 2, h / 2
    best = 0.0
    for y in range(h):
        row = y * w
        dy = y - cy
        for x in range(w):
            if data[row + x] > VISIBLE_ALPHA:
                d = ((x - cx) ** 2 + dy * dy) ** 0.5
                if d > best:
                    best = d
    return best


def plan(im: Image.Image):
    """Run both steps in memory. Returns (prepared, lines) and writes nothing.

    `lines` is what the operator reads, and it is built from measurements taken
    here — never from a guess about what the steps must have done.
    """
    lines = []
    w0, h0 = im.size
    trimmed = trim_to_ink(im)
    if trimmed.size != (w0, h0):
        lines.append(
            "  trim   %dx%d -> %dx%d (visible ink was %.0f%% wide)"
            % (w0, h0, trimmed.size[0], trimmed.size[1],
               100 * trimmed.size[0] / w0))

    w, h = trimmed.size
    cx, cy = centroid(trimmed)
    dx = 2 * (w / 2 - cx)
    dy = 2 * (h / 2 - cy)
    dx = 0.0 if abs(dx) < 0.5 else dx
    dy = 0.0 if abs(dy) < 0.5 else dy

    if not dx and not dy:
        lines.append("  centred already (residual %+.2f,%+.2fpx)"
                     % (cx - w / 2, cy - h / 2))
    else:
        pad_l = max(0, int(round(dx)))
        pad_r = max(0, int(round(-dx)))
        pad_t = max(0, int(round(dy)))
        pad_b = max(0, int(round(-dy)))
        canvas = Image.new("RGBA", (w + pad_l + pad_r, h + pad_t + pad_b),
                           (0, 0, 0, 0))
        canvas.paste(trimmed, (pad_l, pad_t))
        trimmed = canvas
        cx2, cy2 = centroid(trimmed)
        lines.append(
            "  centre pad=(%d,%d,%d,%d) -> %dx%d residual (%+.2f,%+.2f)px"
            % (pad_l, pad_r, pad_t, pad_b, trimmed.size[0], trimmed.size[1],
               cx2 - trimmed.size[0] / 2, cy2 - trimmed.size[1] / 2))
    return trimmed, lines


def differs(prepared: Image.Image, original: Image.Image) -> bool:
    """True if saving `prepared` would not reproduce `original` exactly.

    Compared as DECODED PIXELS, not re-encoded PNG bytes: the question is
    whether the artwork changes, and re-encoding would report a difference
    every run for the same untouched file.
    """
    return (prepared.size != original.size
            or prepared.tobytes() != original.tobytes())


def prep(path: Path, write: bool, check: bool) -> int:
    im = load_mark(path)
    w0, h0 = im.size
    print("%s: %dx%d" % (path.name, w0, h0))

    prepared, lines = plan(im)
    for line in lines:
        print(line)

    stale = differs(prepared, im)
    if check:
        if stale:
            print("  STALE   --check wrote nothing; %s would change "
                  "(%dx%d -> %dx%d). Pass --write to apply."
                  % (path.name, w0, h0, prepared.size[0], prepared.size[1]))
            return EXIT_STALE
        print("  prepped already; --check wrote nothing")
        return EXIT_OK

    if not write:
        print("  (dry run — pass --write to save)")
        return EXIT_OK

    if not stale:
        # The steps are no-ops on an already-prepped mark. Saving anyway would
        # rewrite byte-identical artwork and print `written`, which reads as
        # work done. Say what is actually true: nothing changed.
        print("  already prepped — %s left untouched (%dx%d)"
              % (path.name, w0, h0))
        return EXIT_OK

    prepared.save(path)
    print("  written  %dx%d" % (prepared.size[0], prepared.size[1]))
    return EXIT_OK


def main() -> int:
    argv = sys.argv[1:]
    write = "--write" in argv
    check = "--check" in argv
    unknown = [a for a in argv
               if a.startswith("--") and a not in ("--write", "--check")]
    if unknown:
        print("prep_mark: unknown option(s): %s" % ", ".join(unknown),
              file=sys.stderr)
        print("usage: prep_mark.py [FILE ...] [--write | --check]",
              file=sys.stderr)
        return EXIT_REFUSED
    if write and check:
        print("prep_mark: --write and --check are opposites; pass one.",
              file=sys.stderr)
        return EXIT_REFUSED

    paths = [a for a in argv if not a.startswith("--")]
    worst = EXIT_OK
    for a in paths or [str(DEFAULT_MARK)]:
        try:
            rc = prep(Path(a), write=write, check=check)
        except Refused as why:
            print("prep_mark: refusing -- %s" % why, file=sys.stderr)
            rc = EXIT_REFUSED
        worst = max(worst, rc)
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
