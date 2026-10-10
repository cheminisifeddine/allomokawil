#!/usr/bin/env python3
"""Count dark pixels in a rectangular band of a PNG.

    python3 tool/band_ink.py shot.png y0 y1 [x_from] [threshold] [--mode M]

`px_count.py` answers "how many pixels are exactly this token colour", which is
the right question for "did the list draw at all". It cannot answer the one
this file exists for: **is there ink in this band, whatever colour it is** --
the question a widget assertion cannot ask, because an empty `Text` is a real
widget with a real line box and the widget tree is identical with and without
it.

That is not theoretical. The guard added to the wilaya sheet on 29 Sep was
sabotaged on purpose and every widget assertion in its test file stayed green;
the only instrument that noticed was a pixel count in the band the count line
occupies. So the measurement lives in a tool, for the same reason
`px_count.py` does: a probe written as an escaped string inside a Dart test
broke silently twice before, and a broken probe that reports `0` is
indistinguishable from a blank screen.

The band is given as fractions of the image by the caller that knows the
layout, and the default threshold treats "ink" as anything meaningfully darker
than the paper the sheet is painted on.

**What counts as ink is a luminance question, not a per-channel one.** The
predicate used to be `r < t and g < t and b < t + 20`, which sounds like "ink"
and is not: an `and` across three channels means any colour with one bright
channel is invisible to it. Measured on the real theme, `danger` C33F39 (5.13:1
on white, well past the 4.5 body line) and `star` B5790B (3.68:1) both counted
as **zero**, so a band painted in either read as blank paper -- and the Dart
test that calls this answers `0` for the empty state, so the defect was
indistinguishable from the guard working. The rule is now relative luminance
against white paper, reusing the maths `tool/contrast_audit.py` already owns,
with the same default threshold reinterpreted: grey 170 has relative luminance
**0.401978**, and every theme token falls on the correct side of it (all body
and label text in, every wash / surface / hairline out).

The old per-channel rule is still reachable as `--mode channel`, so the
behaviour the tool had for a fortnight is a choice rather than a silent
change, and a shot measured the old way can still be compared like for like.
"""
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0] or '.')

from png_read import read_png

#: Grey 170, the shipped default threshold, as a relative luminance against
#: white paper. Keeping the *same* number means the boundary did not move --
#: only the question asked of each pixel did.
DEFAULT_LUMINANCE = 0.401978


def _chan(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def luminance(r, g, b):
    """WCAG relative luminance of one pixel. Same maths as contrast_audit."""
    return 0.2126 * _chan(r) + 0.7152 * _chan(g) + 0.0722 * _chan(b)


def band_ink(path, y0, y1, x_from=0, threshold=170, mode="luminance"):
    """Count pixels in the band `[y0, y1) x [x_from, 1)` that are ink.

    `y0`/`y1`/`x_from` are fractions of the image, clamped to the image the
    way a caller expects: a band can run off the edge of the shot without
    wrapping around it. Both axes are clamped, because only the Y axis used
    to be -- a negative `x_from` indexed Python-side from the far end of the
    row and counted those pixels a *second* time.
    """
    width, height, rows = read_png(path)
    if not rows:
        return 0
    stride = len(rows[0]) // width
    ya, yb = int(y0 * height), int(y1 * height)
    xa = int(x_from * width)
    total = 0
    if mode == "channel":
        # The original rule: ink is darker than paper on all three channels.
        for y in range(max(0, ya), min(height, yb)):
            row = rows[y]
            for x in range(max(0, xa), width):
                o = x * stride
                r, g, b = row[o], row[o + 1], row[o + 2]
                # the white sheet and the dimmed scrim behind it do not count;
                # the app's body ink and its muted grey do.
                if r < threshold and g < threshold and b < threshold + 20:
                    total += 1
        return total

    limit = luminance(threshold, threshold, threshold)
    for y in range(max(0, ya), min(height, yb)):
        row = rows[y]
        for x in range(max(0, xa), width):
            o = x * stride
            if luminance(row[o], row[o + 1], row[o + 2]) < limit:
                total += 1
    return total


def main(argv):
    args = list(argv[1:])
    mode = "luminance"
    if "--mode" in args:
        i = args.index("--mode")
        if i + 1 >= len(args):
            print(__doc__)
            return 2
        mode = args.pop(i + 1)
        args.pop(i)
    if mode not in ("luminance", "channel"):
        print(f"--mode must be 'luminance' or 'channel', not {mode!r}")
        return 2
    if len(args) < 3:
        print(__doc__)
        return 2
    y0, y1 = float(args[1]), float(args[2])
    x_from = float(args[3]) if len(args) > 3 else 0.0
    threshold = int(args[4]) if len(args) > 4 else 170
    print(band_ink(args[0], y0, y1, x_from, threshold, mode))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
