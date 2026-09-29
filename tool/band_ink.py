#!/usr/bin/env python3
"""Count dark pixels in a rectangular band of a PNG.

    python3 tool/band_ink.py shot.png y0 y1 [x_from] [threshold]

`px_count.py` answers "how many pixels are exactly this token colour", which is
the right question for "did the list draw at all". It cannot answer the one
this file exists for: **is there ink in this band, whatever colour it is** —
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
"""
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0] or '.')

from png_read import read_png


def band_ink(path, y0, y1, x_from=0, threshold=170):
    width, height, rows = read_png(path)
    if not rows:
        return 0
    stride = len(rows[0]) // width
    ya, yb = int(y0 * height), int(y1 * height)
    xa = int(x_from * width)
    total = 0
    for y in range(max(0, ya), min(height, yb)):
        row = rows[y]
        for x in range(xa, width):
            o = x * stride
            r, g, b = row[o], row[o + 1], row[o + 2]
            # Darker than paper on all three channels: the app's body ink and
            # its muted grey both qualify, the white sheet and the dimmed
            # scrim behind it do not.
            if r < threshold and g < threshold and b < threshold + 20:
                total += 1
    return total


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    y0, y1 = float(argv[2]), float(argv[3])
    x_from = float(argv[4]) if len(argv) > 4 else 0.0
    threshold = int(argv[5]) if len(argv) > 5 else 170
    print(band_ink(argv[1], y0, y1, x_from, threshold))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
