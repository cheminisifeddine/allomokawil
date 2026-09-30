#!/usr/bin/env python3
"""Prove `tool/pngscan.py` measures boxes instead of counting pixels.

Run directly — it writes PNGs and is not a `flutter test`:

    python3 test/pngscan_test.py

**Why this file exists.** `pngscan.py` is the probe the improvement loop's
step 5 depends on: "a layout claim must be backed by a real screenshot",
checked by running pngscan over the capture and reading the geometry. It was
lost when the machine it lived on was rebuilt, and what the loop did in the
gap is the dangerous part — ticks that could not scan fell back to asserting
nothing and noting it in the report, which is indistinguishable from a check
that passed.

Every case here is a shape the probe has to get right, taken from the claims
the backlog actually makes:

  1. a single filled box reports its true size and origin — the amber CTA,
     recorded across many ticks as "984x167 px at (96,1610)";
  2. the same pixels as scattered dither are **not** a box — the reason a
     tally is not enough, and the reason the unit here is a region;
  3. two rules separated by a gap are two boxes, not one — the case 8-way
     connectivity gets wrong by bridging the diagonal;
  4. two boxes that touch are reported as two, so "one 984x167 button" is not
     an accident of where the neighbours happen to sit;
  5. a colour that is not in the image yields zero boxes and still exits 0,
     because "absent" is a real answer;
  6. **an unreadable file exits non-zero** — never "0 boxes", because a zero
     from a broken probe is indistinguishable from a zero from a blank screen
     (the trap `tool/px_count.py` documents from two earlier broken versions
     of this same measurement);
  7. `--min-box` drops specks that are ink, not furniture;
  8. a truncated PNG is rejected rather than half-decoded.

Expected: 9/9. A failure means the loop's step-5 evidence is a number
somebody made up.
"""
import os
import struct
import subprocess
import sys
import tempfile
import zlib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PNGSCAN = [sys.executable, os.path.join(REPO, "tool", "pngscan.py")]

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("PASS  " if cond else "FAIL  ") + name + (("  -- " + detail) if detail and not cond else ""))


def write_png(path, width, height, pixels):
    """`pixels` is (width, height, rgb) tuples; (None,None,None) = white."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)                      # filter: none
        for x in range(width):
            r, g, b = pixels[x][y] or (255, 255, 255)
            raw += bytes((r, g, b))

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body +
                struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(bytes(raw))))
        fh.write(chunk(b"IEND", b""))


def run(path, *args):
    return subprocess.run(PNGSCAN + [path] + list(args), capture_output=True, text=True)


AMBER = (232, 163, 61)
GREY = (232, 232, 236)


def main():
    tmp = tempfile.mkdtemp(prefix="pngscan_test_")
    try:
        # 1. one filled box, true size and origin
        px = [[(AMBER if 10 <= x < 30 and 5 <= y < 12 else (255, 255, 255))
                for y in range(20)] for x in range(40)]
        p = os.path.join(tmp, "box.png")
        write_png(p, 40, 20, px)
        r = run(p, "--color", "E8A33D")
        check("case 1: a single box reports its true size and origin",
              "20x7 px at (10,5)" in r.stdout and "1 box(es)" in r.stdout,
              r.stdout.strip())

        # 2. identical pixel *count* scattered as dither is not a box
        px = [[(AMBER if (x + y) % 2 == 0 else (255, 255, 255))
                for y in range(14)] for x in range(28)]
        p = os.path.join(tmp, "dither.png")
        write_png(p, 28, 14, px)
        r = run(p, "--color", "E8A33D")
        # every pixel is its own 4-connected region -> many 1x1 boxes
        check("case 2: dither is reported as specks, never as one filled box",
              "28x14 px at (0,0)" not in r.stdout and "14x28" not in r.stdout
              and "box(es)" in r.stdout,
              r.stdout.strip())

        # 3. a 1px rule and a second 1px rule 3 rows down stay two boxes
        px = [[(GREY if (y == 4 or y == 7) else (255, 255, 255))
                for y in range(12)] for x in range(30)]
        p = os.path.join(tmp, "rules.png")
        write_png(p, 30, 12, px)
        r = run(p, "--color", "E8E8EC")
        check("case 3: two rules separated by a gap stay two boxes",
              "2 box(es)" in r.stdout and "30x1 px at (0,4)" in r.stdout
              and "30x1 px at (0,7)" in r.stdout,
              r.stdout.strip())

        # 4. boxes sharing a full edge are one region, not two
        px = [[(AMBER if (0 <= x < 10 and 0 <= y < 5) or
                            (10 <= x < 20 and 0 <= y < 5) else (255, 255, 255))
                for y in range(12)] for x in range(22)]
        p = os.path.join(tmp, "touch.png")
        write_png(p, 22, 12, px)
        r = run(p, "--color", "E8A33D")
        check("case 4: boxes sharing a full edge merge into one region",
              "1 box(es)" in r.stdout and "20x5 px at (0,0)" in r.stdout,
              r.stdout.strip())

        # 4b. boxes meeting only at a CORNER stay two regions. This is the
        # case that licenses 4-connectivity: 8-way would bridge the diagonal
        # and report one 11x11 box where the design has two 10x5 rules.
        px = [[(AMBER if (0 <= x < 10 and 0 <= y < 5) or
                            (10 <= x < 20 and 5 <= y < 10) else (255, 255, 255))
                for y in range(12)] for x in range(22)]
        p = os.path.join(tmp, "corner.png")
        write_png(p, 22, 12, px)
        r = run(p, "--color", "E8A33D")
        check("case 4b: corner-touching boxes stay two, never bridged into one",
              "2 box(es)" in r.stdout and "10x5 px at (0,0)" in r.stdout
              and "10x5 px at (10,5)" in r.stdout,
              r.stdout.strip())

        # 5. absent colour is a real answer: zero boxes, clean exit
        r = run(p, "--color", "C33F39")
        check("case 5: an absent colour reports zero boxes and exits 0",
              "0 box(es)" in r.stdout and r.returncode == 0,
              r.stdout.strip() + r.stderr.strip())

        # 6. an unreadable file must NOT look like a clean zero
        p = os.path.join(tmp, "broken.png")
        with open(p, "wb") as fh:
            fh.write(b"\x89PNG\r\n\x1a\n" + b"\x00" * 40)
        r = run(p, "--color", "E8A33D")
        check("case 6: an unreadable PNG exits non-zero, never '0 boxes'",
              r.returncode != 0 and "0 box(es)" not in r.stdout,
              f"rc={r.returncode} out={r.stdout.strip()!r}")

        # 7. --min-box drops specks that are ink but not furniture
        px = [[(AMBER if (x == 0 and y == 0) or
                            (10 <= x < 30 and 5 <= y < 15) else (255, 255, 255))
                for y in range(20)] for x in range(35)]
        p = os.path.join(tmp, "speck.png")
        write_png(p, 35, 20, px)
        r = run(p, "--color", "E8A33D", "--min-box", "20")
        check("case 7: --min-box drops a 1px speck and keeps the 20x10 box",
              "1 box(es)" in r.stdout and "20x10 px at (10,5)" in r.stdout,
              r.stdout.strip())

        # 8. a truncated image is rejected, not half-decoded
        px = [[(AMBER if 0 <= x < 8 and 0 <= y < 4 else (255, 255, 255))
                for y in range(10)] for x in range(10)]
        p = os.path.join(tmp, "trunc.png")
        write_png(p, 10, 10, px)
        data = open(p, "rb").read()
        with open(p, "wb") as fh:
            fh.write(data[:len(data) // 2])          # cut the image data short
        r = run(p, "--color", "E8A33D")
        check("case 8: a truncated PNG is rejected rather than half-decoded",
              r.returncode != 0 and "0 box(es)" not in r.stdout,
              f"rc={r.returncode} out={r.stdout.strip()!r}")

        bad = [n for n, ok in results if not ok]
        print(f"\n{len(results) - len(bad)}/{len(results)} cases passed")
        if bad:
            print("FAILED: " + ", ".join(bad))
        return 1 if bad else 0
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
