#!/usr/bin/env python3
"""Count the pixels of one exact colour in a PNG.

    python3 tool/px_count.py shot.png 22,33,62
    python3 tool/px_count.py shot.png E8A33D

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

**The counting was never the defect; the argument was.** Measured on a real
2400x1800 Flutter capture, `16213E` answers 1333959 and agrees with the
decoder's own histogram to the pixel. What could not be trusted was how the
colour reached it:

  * `16213E`, `#16213E` and `0x16,0x21,0x3e` all died on a bare `int(p)`.
    `pngscan.py`, the sibling probe one directory over, accepts all three
    through one `parse_color` -- so the repo had two grammars for "a colour"
    and the Dart caller builds its argument as `r,g,b` only because this file
    happened to demand that spelling.
  * `300,0,0` and `-1,0,0` parsed, matched nothing, and printed **0 with
    exit 0**. Those are not colours -- a channel outside 0..255 cannot occur
    in an 8-bit image -- and the honest-looking 0 is exactly the number the
    caller must never invent. `expect(mutedAfter, greaterThan(mutedBefore))`
    would fail on it, but a caller asserting "no muted ink" would have passed
    on a typo in its own argument. A broken probe reporting an honest 0 is the
    trap in this file's own header, reached by the argument rather than by the
    filter.

So the colour argument goes through **`pngscan.parse_color`** -- one
definition, one grammar, no second spelling to remember -- and is then
**range-checked**. Out of range is a typo, and a typo exits 2 with the usage
on stderr rather than printing a number nothing downstream can tell from a
blank screen.

What is deliberately unchanged: a *well-formed* colour that simply is not in
the image still answers `0` and still exits 0. "Absent" is a real answer, and
so is an empty band; only the impossible is refused. And `PngError` is now
caught and named rather than left as a traceback -- `pngscan` prints
`pngscan: cannot read ...` and exits 1, and two pixel probes should fail the
same way.

`png_read` returns each scanline as a flat `bytearray`, so this walks the
rows by channel offset and derives the stride from the row length rather
than assuming 3 or 4 channels.
"""
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0] or '.')

from png_read import read_png, PngError
from pngscan import parse_color


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


def parse_colour(text):
    """The colour argument, refusing anything that cannot be a pixel.

    `pngscan.parse_color` accepts `E8A33D`, `#E8A33D` and `232,163,61` and
    raises `ValueError` with a message naming all three. This adds the one
    thing neither tool had: **a channel must be 0..255.** `300,0,0` parses
    cleanly, matches nothing and used to answer `0` -- indistinguishable from
    a screen with no ink in it.
    """
    rgb = parse_color(text)
    if not all(0 <= c <= 255 for c in rgb):
        raise ValueError(
            f"colour {text!r} is out of range: "
            f"{','.join(str(c) for c in rgb)} -- each channel must be 0..255")
    return rgb


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    try:
        want = parse_colour(argv[2])
    except ValueError as exc:
        print(f"px_count: {exc}", file=sys.stderr)
        return 2
    try:
        print(count(argv[1], want))
    except PngError as exc:
        print(f"px_count: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
