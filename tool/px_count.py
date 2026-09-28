#!/usr/bin/env python3
"""Count the pixels of one exact colour in a PNG.

    python3 tool/px_count.py shot.png 22,33,62

Used by the inbox re-read test, which has to answer a question a widget
assertion cannot: **did the second frame still draw the list, or did a
re-read blank it into skeleton bars?** The answer is a pixel count against
the app's own navy token, and it is made here rather than inline in the
test so the test file carries no embedded Python that a quoting mistake can
silently turn into a no-op.

That is not hypothetical. Two earlier versions of this measurement lived
inside the Dart test as an escaped `python3 -c` string, and the escaping
broke first into a `FormatException` and then into a filter that matched
nothing and reported `0` for a screen full of text. A count of zero from a
broken probe is indistinguishable from a count of zero from a blank screen,
and the assertion built on it would have passed on a regression it was
written to catch.

`png_read` returns each scanline as a flat `bytearray`, so this walks the
rows by channel offset and derives the stride from the row length rather
than assuming 3 or 4 channels.
"""
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0] or '.')

from png_read import read_png


def count(path, want):
    width, _height, rows = read_png(path)
    if not rows:
        return 0
    stride = len(rows[0]) // width
    total = 0
    for row in rows:
        for x in range(0, len(row), stride):
            if (row[x], row[x + 1], row[x + 2]) == want:
                total += 1
    return total


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    r, g, b = (int(p) for p in argv[2].split(','))
    print(count(argv[1], (r, g, b)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
