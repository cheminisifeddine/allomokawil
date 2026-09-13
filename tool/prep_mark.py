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

Idempotent by construction: once centred, both steps are no-ops.

Run: python3 tool/prep_mark.py assets/brand/mark.png [--write]
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

# Alpha at or below this is invisible on any screen; it is shadow halo, not art.
VISIBLE_ALPHA = 32


def loaded_alpha(im: Image.Image):
    alpha = im.split()[3]
    w, h = im.size
    return alpha, w, h, [int(v) for v in alpha.get_flattened_data()]


def trim_to_ink(im: Image.Image, thr: int = VISIBLE_ALPHA) -> Image.Image:
    alpha, w, h, data = loaded_alpha(im)
    cols = [x for x in range(w) if any(data[y * w + x] > thr for y in range(h))]
    rows = [y for y in range(h) if any(data[y * w + x] > thr for x in range(w))]
    if not cols or not rows:
        raise SystemExit("nothing visible in this image")
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
    empty.
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


def prep(path: Path, write: bool) -> int:
    im = Image.open(path).convert("RGBA")
    w0, h0 = im.size
    print(f"{path.name}: {w0}x{h0}")

    trimmed = trim_to_ink(im)
    if trimmed.size != (w0, h0):
        print(f"  trim   {w0}x{h0} -> {trimmed.size[0]}x{trimmed.size[1]} "
              f"(visible ink was {100 * trimmed.size[0] / w0:.0f}% wide)")

    w, h = trimmed.size
    cx, cy = centroid(trimmed)
    dx = 2 * (w / 2 - cx)
    dy = 2 * (h / 2 - cy)
    dx = 0.0 if abs(dx) < 0.5 else dx
    dy = 0.0 if abs(dy) < 0.5 else dy

    if not dx and not dy:
        print(f"  centred already (residual {cx - w / 2:+.2f},{cy - h / 2:+.2f}px)")
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
        print(f"  centre pad=({pad_l},{pad_r},{pad_t},{pad_b}) "
              f"-> {trimmed.size[0]}x{trimmed.size[1]} "
              f"residual ({cx2 - trimmed.size[0] / 2:+.2f},"
              f"{cy2 - trimmed.size[1] / 2:+.2f})px")

    if write:
        trimmed.save(path)
        print(f"  written  {trimmed.size[0]}x{trimmed.size[1]}")
    else:
        print("  (dry run — pass --write to save)")
    return 0


def main() -> int:
    write = "--write" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for a in args or ["assets/brand/mark.png"]:
        prep(Path(a), write)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
