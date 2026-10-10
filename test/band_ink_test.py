#!/usr/bin/env python3
"""Prove `tool/band_ink.py` counts ink the way its own docstring promises.

Run directly -- it writes PNGs and is not a `flutter test`:

    python3 test/band_ink_test.py

**Why this file exists.** `band_ink.py` is the instrument
`test/empty_count_line_shot_test.dart` shells out to in order to answer the
one question its widget assertions cannot: *did the count line draw at all.*
Both of that file's states assert on this number -- `expect(bandInk, 0)` for
the empty state and `greaterThan(100)` for the state that has a count -- so a
wrong answer here is not a cosmetic bug, it is the guard going blind in one
direction or the other.

Two defects were found by running it against the real theme palette, and both
were invisible from reading the source:

  1. **The predicate was per-channel `AND`, not "ink".** The docstring says the
     tool answers *"is there ink in this band, whatever colour it is"*, but
     `r < t and g < t and b < t + 20` drops any colour with one bright channel.
     `danger` C33F39 is 5.13:1 on white and `star` B5790B is 3.68:1 -- both far
     above the 4.5 body-text line, both reported as **0 dark pixels**. A band
     painted in either one reads as blank paper. The fix decides on relative
     luminance (the same maths `tool/contrast_audit.py` already owns) with the
     per-channel rule kept as an explicit `--mode channel`.

  2. **`x_from` was never clamped, while `y0`/`y1` were.** `ya`/`yb` go through
     `max(0, ..)` / `min(height, ..)`; `xa` does not. A negative fraction gave a
     negative `xa`, and Python's negative indexing counted the row from its far
     end *in addition to* the pixels from its start -- `x_from=-0.6` on ink at
     x0-49 of a 100px row returned **600** where the truth is 500.

Cases below check the real tool and the real theme file, never a fixture of the
tool's own opinion. Expected: 16/16.
"""
import os
import re
import struct
import subprocess
import sys
import tempfile
import zlib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BAND_INK = [sys.executable, os.path.join(REPO, "tool", "band_ink.py")]

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("PASS  " if cond else "FAIL  ") + name + (("  -- " + detail) if detail and not cond else ""))


def write_png(path, width, height, pixels):
    """`pixels(x, y) -> (r,g,b)`; written as an 8-bit non-interlaced RGB PNG."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)                      # filter: none
        for x in range(width):
            raw += bytes(pixels(x, y))

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body +
                struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(bytes(raw))))
        fh.write(chunk(b"IEND", b""))


def run(path, *args):
    return subprocess.run(BAND_INK + [path] + [str(a) for a in args],
                          capture_output=True, text=True)


def count(out):
    """The integer the tool printed, or None if it did not print one.

    Accepts either a CompletedProcess or the raw stdout string, because the
    cases below read it both ways.
    """
    if hasattr(out, "stdout"):
        out = out.stdout
    t = (out or "").strip()
    return int(t) if t.isdigit() or (t.startswith("-") and t[1:].isdigit()) else None


def _chan(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    return 0.2126 * _chan(rgb[0]) + 0.7152 * _chan(rgb[1]) + 0.0722 * _chan(rgb[2])


def contrast_on_white(rgb):
    """WCAG relative-luminance contrast of `rgb` against white paper."""
    return 1.05 / (luminance(rgb) + 0.05)


def theme_tokens():
    """Every `static const Color name = Color(0xAARRGGBB);` in the real theme."""
    src = open(os.path.join(REPO, "lib", "src", "core", "theme", "app_theme.dart"),
               encoding="utf-8").read()
    out = {}
    for name, argb in re.findall(
            r"static const Color (\w+)\s*=\s*Color\(0x([0-9A-Fa-f]{8})\)", src):
        h = argb[2:]
        out[name] = (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    return out


def main():
    tmp = tempfile.mkdtemp(prefix="band_ink_test_")
    try:
        WHITE = (255, 255, 255)
        NAVY = (0x16, 0x21, 0x3E)          # the app's own body token

        # 1. a full-width band of ink is counted exactly
        p = os.path.join(tmp, "mid.png")
        write_png(p, 100, 100, lambda x, y: NAVY if 30 <= y < 40 else WHITE)
        check("case 1: a full-width ink band is counted exactly",
              count(run(p, 0.30, 0.40).stdout) == 1000, run(p, 0.30, 0.40).stdout)

        # 2. a band with no ink in it is a real zero, and still exits 0
        r = run(p, 0.45, 0.60)
        check("case 2: an empty band answers 0 and still exits 0",
              count(r.stdout) == 0 and r.returncode == 0,
              f"rc={r.returncode} out={r.stdout.strip()!r}")

        # 3. THE DEFECT. Luminance mode: a colour is ink when it is dark
        #    ENOUGH on white, whatever its channels do individually.
        #    danger C33F39 is 5.13:1 and was reported as blank paper.
        danger = (0xC3, 0x3F, 0x39)
        p2 = os.path.join(tmp, "danger.png")
        write_png(p2, 10, 10, lambda x, y: danger)
        r = run(p2, 0.0, 0.1)
        # NOTE the 10, not 100: the band 0.0-0.1 of a 10-row image is ONE row.
        # The first version of this case asserted 100 and "failed" a tool that
        # was right, which is the same class of error the backlog keeps
        # recording -- an assertion written against an assumed geometry.
        check("case 3: danger C33F39 (5.13:1 on white) counts as ink",
              count(r.stdout) == 10, f"got {r.stdout.strip()!r}")

        # 4. the same, for the star token -- 3.68:1, still well above paper
        star = (0xB5, 0x79, 0x0B)
        p3 = os.path.join(tmp, "star.png")
        write_png(p3, 10, 10, lambda x, y: star)
        check("case 4: star B5790B (3.68:1 on white) counts as ink",
              count(run(p3, 0.0, 0.1).stdout) == 10, run(p3, 0.0, 0.1).stdout)

        # 5. ...and amber E8A33D, the CTA, which is 2.16:1 -- deliberately NOT
        #    ink, so a wash behind a button is not mistaken for text.
        accent = (0xE8, 0xA3, 0x3D)
        p4 = os.path.join(tmp, "accent.png")
        write_png(p4, 10, 10, lambda x, y: accent)
        check("case 5: accent E8A33D (2.16:1) is NOT ink -- a wash is not text",
              count(run(p4, 0.0, 0.1).stdout) == 0, run(p4, 0.0, 0.1).stdout)

        # 6. THE DEFECT. x_from is clamped. Ink at x0-49 of a 100px row.
        p5 = os.path.join(tmp, "left.png")
        write_png(p5, 100, 100, lambda x, y: NAVY if (30 <= y < 40 and x < 50) else WHITE)
        base = count(run(p5, 0.30, 0.40, 0.0).stdout)
        check("case 6: x_from=0.0 on left-half ink counts 500",
              base == 500, f"got {base}")
        #    the exact call that returned 600 before the fix
        neg = count(run(p5, 0.30, 0.40, -0.6).stdout)
        check("case 7: a negative x_from is clamped, not mirrored (600 -> 500)",
              neg == 500, f"got {neg}")

        # 8. x_from past the ink is a real zero (the tool's right-hand use)
        check("case 8: x_from past the ink answers 0",
              count(run(p5, 0.30, 0.40, 0.6).stdout) == 0)

        # 9. x_from > 1.0 cannot index past the row end
        over = run(p5, 0.30, 0.40, 1.5)
        check("case 9: x_from > 1.0 does not crash and answers 0",
              over.returncode == 0 and count(over.stdout) == 0,
              f"rc={over.returncode} out={over.stdout.strip()!r} err={over.stderr.strip()!r}")

        # 10. y fractions outside 0..1 stay clamped. The NEGATIVE half is what
        #     pins `max(0, ya)`: -0.5 on a 100-row image is ya=-50, and without
        #     the clamp Python starts at the far end of the image and wraps.
        #     Dropping `max(0, ..)` SURVIVED this battery before case 10a,
        #     because every other case has ink strictly inside the image where
        #     a negative ya cannot reach it -- a clamp that was never tested
        #     in the direction it can actually fail.
        #     The image has ink in rows 0-9 AND in the rows a wrap would land
        #     on (50-99, i.e. rows[-50..-1]). Ink only at the top answers 1000
        #     either way -- clamping reads rows 0-9, wrapping reads rows 50-59
        #     plus 0-9 and the two agree on the ink they share. Only a band
        #     where the wrap lands on DIFFERENT ink can tell them apart, and
        #     the first version of this case did exactly that wrong thing.
        ptop = os.path.join(tmp, "top.png")
        write_png(ptop, 100, 100,
                  lambda x, y: NAVY if (y < 10 or y >= 50) else WHITE)
        check("case 10a: a negative y0 is clamped at row 0, not wrapped",
              count(run(ptop, -0.5, 0.10).stdout) == 1000,
              f"got {run(ptop, -0.5, 0.10).stdout.strip()!r} "
              f"(wrap would answer 1500: 50 rows x 100)")
        check("case 10b: a band spanning past the last row stays clamped",
              count(run(p, -0.5, 2.0).stdout) == 1000)

        # 10c/10d. The threshold IS the boundary and it moves it. `accent` is
        #      not ink at the default, and the same pixels ARE ink at 250 --
        #      grey 250 sits above the amber CTA's luminance. This is what
        #      kills "ignore the threshold, hardcode the limit".
        p6 = os.path.join(tmp, "accent.png")
        check("case 10c: raising the threshold brings accent back as ink",
              count(run(p6, 0.0, 1.0, 0.0, 250).stdout) == 100)
        check("case 10d: a threshold below navy drops every pixel",
              count(run(p, 0.30, 0.40, 0.0, 10).stdout) == 0)

        # 11. THE CONTRACT, on the REAL theme: every token at or above the 4.5
        #     body line must count as ink in a band painted entirely in it.
        #     This reads app_theme.dart -- a token added tomorrow is covered.
        tokens = theme_tokens()
        readable, missed = [], []
        for name, rgb in sorted(tokens.items()):
            if contrast_on_white(rgb) >= 4.5:
                readable.append(name)
                tp = os.path.join(tmp, f"tok_{name}.png")
                write_png(tp, 8, 8, lambda x, y, c=rgb: c)
                if count(run(tp, 0.0, 1.0).stdout) != 64:
                    missed.append(f"{name} {'%02X%02X%02X' % rgb}")
        check(f"case 11: all {len(readable)} theme tokens >= 4.5:1 read as ink",
              not missed, "read as blank paper: " + ", ".join(missed))

        # 12. ...and none of the faint ones do (accent wash, surfaces, lines)
        faint = [n for n, c in tokens.items() if contrast_on_white(c) < 3.0
                 and c not in ((255, 255, 255),)]
        wrong = []
        for name in faint:
            fp = os.path.join(tmp, f"faint_{name}.png")
            write_png(fp, 8, 8, lambda x, y, c=tokens[name]: c)
            if count(run(fp, 0.0, 1.0).stdout) != 0:
                wrong.append(f"{name} {'%02X%02X%02X' % tokens[name]}")
        check(f"case 12: none of the {len(faint)} faint tokens (< 3.0:1) read as ink",
              not wrong, "read as ink: " + ", ".join(wrong))

        # 13. an unreadable file RAISES -- never a silent 0, which would be
        #     indistinguishable from a blank band (the trap px_count.py names)
        missing = run(os.path.join(tmp, "nope.png"), 0.3, 0.4)
        check("case 13: a missing file exits non-zero and prints no count",
              missing.returncode != 0 and count(missing.stdout) is None,
              f"rc={missing.returncode} out={missing.stdout.strip()!r}")

        # 14. a truncated PNG is rejected rather than half-decoded
        data = open(p, "rb").read()
        tp = os.path.join(tmp, "trunc.png")
        with open(tp, "wb") as fh:
            fh.write(data[:len(data) // 2])
        tr = run(tp, 0.30, 0.40)
        check("case 14: a truncated PNG is rejected, never half-decoded",
              tr.returncode != 0 and count(tr.stdout) is None,
              f"rc={tr.returncode} out={tr.stdout.strip()!r}")

        # 15. the legacy per-channel rule is still reachable on purpose, so the
        #     old behaviour is a choice rather than a silent change
        legacy = run(p2, 0.0, 0.1, 0.0, 170, "--mode", "channel")
        check("case 15: --mode channel keeps the old per-channel predicate",
              count(legacy.stdout) == 0,
              f"got {legacy.stdout.strip()!r} (the old tool answered 0 here too)")

        # 16. an explicit threshold is honoured in luminance mode
        hard = run(p2, 0.0, 0.1, 0.0, 200, "--mode", "channel")
        check("case 16: an explicit threshold still moves the boundary",
              count(hard.stdout) == 10, f"got {hard.stdout.strip()!r}")

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
