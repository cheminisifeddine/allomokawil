#!/usr/bin/env python3
"""Find boxes of one exact colour in a PNG — the loop's pixel probe.

    python3 tool/pngscan.py shot.png --color E8A33D
    python3 tool/pngscan.py shot.png --color E8E8EC --min-box 20

The improvement loop's step 5 says a layout claim must be backed by a real
screenshot, and that a screenshot is checked by "running pngscan against it
and looking at the numbers". This file is that probe. It was lost with the
machine it used to live on, and the gap it left is worse than a missing tool:
ticks that could not scan fell back to *asserting nothing* and saying so in
the report, which reads exactly like a passing check.

**Counting pixels is not enough, and that is the whole design.** The claim
this probe exists to support is geometric — "the amber CTA is one 984x167 box
at (96,1610)", "the recipe hairline is a full-width 1 px outline, x33-378 at
y463". A bare count cannot tell a 984x167 button from the same 164,568 pixels
scattered as dither, and it cannot say *where* anything is. So the unit here
is a **connected region** with a bounding box, not a tally.

Four-connected, deliberately: 8-connectivity would bridge a 1 px diagonal gap
and merge two stacked hairlines (y463 and y542) into one region spanning the
gap, reporting one tall box where the design has two 1 px rules. That is
precisely the mistake the hairline check exists to catch.

**Failing loudly is part of the contract.** An unreadable or unsupported file
exits non-zero and prints the reason on stderr. It does not print "0 boxes",
because a zero from a broken probe is indistinguishable from a zero from a
blank screen — the exact trap that `tool/px_count.py` documents from two
earlier escaped-shell versions of this same measurement. A tool that cannot
open a single image must never be able to report success.

Decoding is `png_read.read_png`, pure stdlib, which composites alpha onto
white so a transparent pixel reads as the background it looks like.
"""
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0] or '.')

from png_read import read_png, PngError


def parse_color(text):
    """`E8A33D`, `#E8A33D` or `232,163,61` -> (232, 163, 61)."""
    s = text.strip().lstrip('#')
    if len(s) == 6 and all(c in '0123456789abcdefABCDEF' for c in s):
        return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))
    parts = s.split(',')
    if len(parts) == 3 and all(p.strip().isdigit() for p in parts):
        return tuple(int(p) for p in parts)
    raise ValueError(
        f"--color {text!r} is not a hex triple (E8A33D) or r,g,b (232,163,61)")


def scan(width, height, rows, want):
    """Return every 4-connected region of `want` as (x, y, w, h, npix).

    Sorted by reading order (top-left first), which is the order a person
    scrolling a screenshot would name them in.
    """
    seen = [bytearray(width) for _ in range(height)]
    boxes = []
    for y0 in range(height):
        row = rows[y0]
        for x0 in range(width):
            if seen[y0][x0] or row[x0 * 3] != want[0] \
                    or row[x0 * 3 + 1] != want[1] or row[x0 * 3 + 2] != want[2]:
                continue
            # Flood fill this region. `stack` holds flat x coords with `y`
            # implied per layer of the loop below, to keep the tuple small.
            stack = [(x0, y0)]
            seen[y0][x0] = 1
            minx = maxx = x0
            miny = maxy = y0
            n = 0
            while stack:
                x, y = stack.pop()
                n += 1
                if x < minx:
                    minx = x
                if x > maxx:
                    maxx = x
                if y < miny:
                    miny = y
                if y > maxy:
                    maxy = y
                if x > 0 and not seen[y][x - 1] \
                        and rows[y][(x - 1) * 3] == want[0] \
                        and rows[y][(x - 1) * 3 + 1] == want[1] \
                        and rows[y][(x - 1) * 3 + 2] == want[2]:
                    seen[y][x - 1] = 1
                    stack.append((x - 1, y))
                if x + 1 < width and not seen[y][x + 1] \
                        and rows[y][(x + 1) * 3] == want[0] \
                        and rows[y][(x + 1) * 3 + 1] == want[1] \
                        and rows[y][(x + 1) * 3 + 2] == want[2]:
                    seen[y][x + 1] = 1
                    stack.append((x + 1, y))
                if y > 0 and not seen[y - 1][x] \
                        and rows[y - 1][x * 3] == want[0] \
                        and rows[y - 1][x * 3 + 1] == want[1] \
                        and rows[y - 1][x * 3 + 2] == want[2]:
                    seen[y - 1][x] = 1
                    stack.append((x, y - 1))
                if y + 1 < height and not seen[y + 1][x] \
                        and rows[y + 1][x * 3] == want[0] \
                        and rows[y + 1][x * 3 + 1] == want[1] \
                        and rows[y + 1][x * 3 + 2] == want[2]:
                    seen[y + 1][x] = 1
                    stack.append((x, y + 1))
            boxes.append((minx, miny, maxx - minx + 1, maxy - miny + 1, n))
    return boxes


def _fmt(box):
    x, y, w, h, n = box
    return f"{w}x{h} px at ({x},{y}) [{n} px]"


def main(argv):
    color = None
    path = None
    min_box = 1
    max_boxes = 20
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == '--color' and i + 1 < len(argv):
            i += 1
            color = argv[i]
        elif a.startswith('--color='):
            color = a.split('=', 1)[1]
        elif a == '--min-box' and i + 1 < len(argv):
            i += 1
            min_box = int(argv[i])
        elif a == '--max' and i + 1 < len(argv):
            i += 1
            max_boxes = int(argv[i])
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif not a.startswith('-') and path is None:
            path = a
        else:
            print(f"pngscan: unexpected argument {a!r}", file=sys.stderr)
            return 2
        i += 1

    if path is None or color is None:
        print("usage: pngscan.py <file.png> --color <E8A33D>", file=sys.stderr)
        return 2
    try:
        want = parse_color(color)
    except ValueError as exc:
        print(f"pngscan: {exc}", file=sys.stderr)
        return 2

    try:
        width, height, rows = read_png(path)
    except PngError as exc:
        # Deliberately not a zero. See the module docstring.
        print(f"pngscan: {exc}", file=sys.stderr)
        return 1

    boxes = [b for b in scan(width, height, rows, want) if b[2] * b[3] >= min_box]
    print(f"{path} {width}x{height}  color #{want[0]:02X}{want[1]:02X}{want[2]:02X}"
          f"  {len(boxes)} box(es)")
    for box in boxes[:max_boxes]:
        print("  " + _fmt(box))
    if len(boxes) > max_boxes:
        print(f"  ... and {len(boxes) - max_boxes} more (raise --max to see them)")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
