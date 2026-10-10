#!/usr/bin/env python3
"""Prove `tool/px_count.py` answers a pixel question, and refuses a bad one.

Run directly -- it writes PNGs and is not a `flutter test`:

    python3 test/px_count_test.py

**Why this file exists.** `px_count.py` is the instrument
`test/message_tab_unread_badge_test.dart` shells out to, to answer the one
question its widget assertions cannot: *did the pip actually repaint.* Both of
that file's states assert on the number -- `goldBefore > 0` and
`goldAfter < goldBefore` -- so a wrong answer here blinds the guard in one
direction or the other.

**What was already right, and this battery pins.** Measured on a real
2400x1800 Flutter capture, the count agrees with the decoder's own histogram
to the pixel (1333959 for `16213E`). The counting was never the defect.

**Two defects were in the argument, and both are invisible from the source.**

  1. **An impossible colour printed an honest-looking `0`.** `300,0,0` and
     `-1,0,0` are not colours -- no 8-bit pixel can carry them -- yet both
     parsed, matched nothing and printed `0` with **exit 0**. That is the
     number this file's own header calls the dangerous one: "a count of zero
     from a broken probe is indistinguishable from a count of zero from a
     blank screen". The caller reads stdout and nothing else, so a typo in the
     caller's own argument looked exactly like a screen that had not drawn.
     The live caller asserts `greaterThan`, so it would have failed loudly --
     but a caller asserting "no muted ink" would have passed on a typo.

  2. **The repo had two grammars for a colour.** `pngscan.py` accepts
     `E8A33D`, `#E8A33D` and `232,163,61` through one `parse_color`; this
     tool used a bare `int(p)` and accepted only the `r,g,b` spelling. The
     Dart caller builds its argument as `r,g,b` today *only* because this
     file demanded it -- so a correct, documented alternative spelling, one
     directory over, was a traceback here. Now one parser, and the tool
     agrees with its sibling on every spelling.

**Case 11 runs against the real app.** It counts `AppTheme.navy` in a real
Flutter capture of the tab bar rather than a synthetic image, so "did the
counting agree with the decoder" is answered against a file the rasteriser
produced, not a file this test drew itself.

Expected: 14/14. A failure means a pixel assertion in the suite is resting on
a number that does not mean what the assertion reads it to mean.
"""
import os
import struct
import subprocess
import sys
import tempfile
import zlib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PX_COUNT = [sys.executable, os.path.join(REPO, "tool", "px_count.py")]
PNGSCAN = [sys.executable, os.path.join(REPO, "tool", "pngscan.py")]

# The app's own tokens, from `lib/src/core/theme/app_theme.dart`.
NAVY = (0x16, 0x21, 0x3E)      # AppTheme.navy
ACCENT = (0xE8, 0xA3, 0x3D)    # AppTheme.accent
WHITE = (255, 255, 255)
GREY = (0x4D, 0x4D, 0x4D)   # a colour a 1-channel file can actually hold

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("PASS  " if cond else "FAIL  ") + name +
          (("  -- " + detail) if detail and not cond else ""))


#: Bytes per pixel for each PNG colour type at 8 bits per sample -- the same
#: table `tool/png_read.py` decodes with.
_CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}


def _chunk(tag, body):
    return (struct.pack(">I", len(body)) + tag + body +
            struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))


def write_png_ct(ctype, path, width, height, pixels):
    """`pixels(x, y) -> (r,g,b)` in an 8-bit non-interlaced PNG of `ctype`."""
    bpp = _CHANNELS[ctype]
    raw = bytearray()
    for y in range(height):
        raw.append(0)                      # filter: none
        for x in range(width):
            r, g, b = pixels(x, y)
            samples = {0: (r,), 4: (r, 0xFF), 2: (r, g, b), 6: (r, g, b, 0xFF)}[ctype]
            raw += bytes(samples)

    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, ctype, 0, 0, 0)))
        fh.write(_chunk(b"IDAT", zlib.compress(bytes(raw))))
        fh.write(_chunk(b"IEND", b""))


def write_png(path, width, height, pixels):
    """`pixels(x, y) -> (r,g,b)`; written as an 8-bit non-interlaced RGB PNG."""
    write_png_ct(2, path, width, height, pixels)


def run(*args):
    return subprocess.run(PX_COUNT + [str(a) for a in args],
                          capture_output=True, text=True)


def answered(out):
    """The integer the tool printed, or None if it printed no number.

    None is the point: stdout carrying no digits is how a caller learns the
    probe failed, and it must be distinguishable from the integer 0.
    """
    t = (out or "").strip()
    return int(t) if t.isdigit() or (t.startswith("-") and t[1:].isdigit()) else None


def _chan(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def theme_tokens():
    """Every `static const Color name = Color(0xAARRGGBB);` in the real theme."""
    import re
    src = open(os.path.join(REPO, "lib", "src", "core", "theme", "app_theme.dart"),
               encoding="utf-8").read()
    out = {}
    for name, argb in re.findall(
            r"static const Color (\w+)\s*=\s*Color\(0x([0-9A-Fa-f]{8})\)", src):
        h = argb[2:]
        out[name] = (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    return out


def main():
    tmp = tempfile.mkdtemp(prefix="px_count_test_")
    try:
        # 1. the base contract: exact colour, exact pixels
        p = os.path.join(tmp, "block.png")
        write_png(p, 10, 10, lambda x, y: NAVY if (x < 5 and y < 5) else WHITE)
        r = run(p, "22,33,62")
        check("case 1: 25 navy pixels in a 10x10 block count 25",
              answered(r.stdout) == 25 and r.returncode == 0,
              f"rc={r.returncode} out={r.stdout.strip()!r}")

        # 2. a colour that is simply absent is a real 0 and still exits 0 --
        #    "absent" is an answer. Only the IMPOSSIBLE is refused (case 8).
        r = run(p, "255,0,255")
        check("case 2: an absent but legal colour answers 0 and exits 0",
              answered(r.stdout) == 0 and r.returncode == 0,
              f"rc={r.returncode} out={r.stdout.strip()!r}")

        # 3. a single pixel in a wide row: no off-by-one at the row end
        p3 = os.path.join(tmp, "one.png")
        write_png(p3, 200, 3, lambda x, y: NAVY if (x == 199 and y == 1) else WHITE)
        check("case 3: the last pixel of a wide row is counted",
              answered(run(p3, "22,33,62").stdout) == 1,
              run(p3, "22,33,62").stdout.strip())

        # 4. THE CONTRACT with the sibling: one grammar for a colour. Every
        #    spelling `pngscan` accepts must answer identically here, so the
        #    two pixel probes cannot disagree about what a colour is.
        spellings = ["16213E", "#16213E", "22,33,62", " 22,33,62 "]
        bad = []
        for s in spellings:
            rr = run(p3, s)
            if answered(rr.stdout) != 1:
                bad.append(f"{s!r}->{rr.stdout.strip()!r}")
        check("case 4: hex, #hex and r,g,b all count the same pixels",
              not bad, "disagreed: " + ", ".join(bad))

        # 5. ...and the two tools agree on the SAME file and colour, which is
        #    the claim being made; one agreeing with itself proves nothing.
        sc = subprocess.run(PNGSCAN + [p3, "--color", "16213E"],
                            capture_output=True, text=True)
        #    pngscan reports boxes, not pixels; a 1px box is the same pixel.
        check("case 5: pngscan finds the same single pixel px_count counted",
              sc.returncode == 0 and "1 box(es)" in sc.stdout,
              f"rc={sc.returncode} out={sc.stdout.strip()!r}")

        # 6. an unreadable file exits 1 and prints NO number. Never a 0: that
        #    is the trap this file's own header is about.
        #     The stderr assertion is load-bearing, and it is there because of
        #     M5: catching `Exception` instead of `PngError` still exits
        #     non-zero with empty stdout, so `rc != 0 and no number` was
        #     satisfied by a bare traceback and the mutation survived. A
        #     REFUSAL has to be named on a channel a human reads, so the case
        #     demands the message and refuses a traceback outright.
        miss = run(os.path.join(tmp, "nope.png"), "22,33,62")
        check("case 6: a missing file exits 1, prints no count, names the "
              "failure (never a traceback)",
              miss.returncode == 1 and answered(miss.stdout) is None and
              "cannot read" in miss.stderr and "Traceback" not in miss.stderr,
              f"rc={miss.returncode} out={miss.stdout.strip()!r} "
              f"err={miss.stderr.strip()[:90]!r}")

        # 7. a truncated PNG is rejected rather than half-counted
        data = open(p3, "rb").read()
        tp = os.path.join(tmp, "trunc.png")
        with open(tp, "wb") as fh:
            fh.write(data[:len(data) // 2])
        tr = run(tp, "22,33,62")
        check("case 7: a truncated PNG exits 1, prints no count, names the "
              "failure (never a traceback)",
              tr.returncode == 1 and answered(tr.stdout) is None and
              "Traceback" not in tr.stderr,
              f"rc={tr.returncode} out={tr.stdout.strip()!r} "
              f"err={tr.stderr.strip()[:90]!r}")

        # 8. THE DEFECT. An impossible colour -- a channel outside 0..255 --
        #    cannot occur in an 8-bit image, so printing 0 for it is a lie
        #    that reads exactly like "the list did not draw".
        for bad_colour in ("300,0,0", "22,33,300", "0,0,256", "1000,1000,1000"):
            rr = run(p, bad_colour)
            check(f"case 8 ({bad_colour}): an out-of-range colour is refused",
                  rr.returncode == 2 and answered(rr.stdout) is None,
                  f"rc={rr.returncode} out={rr.stdout.strip()!r}")

        # 9. the SAME impossible answer must not slip through as an exit 0
        #    elsewhere: `-1,0,0` is negative, and it must be refused too.
        rr = run(p, "-1,0,0")
        check("case 9: a negative channel is refused, not answered 0",
              rr.returncode == 2 and answered(rr.stdout) is None,
              f"rc={rr.returncode} out={rr.stdout.strip()!r}")

        # 10. a malformed colour is refused by NAME on stderr, not a traceback
        #     the caller never reads.
        rr = run(p, "notacolour")
        check("case 10: a malformed colour is named on stderr, exit 2",
              rr.returncode == 2 and answered(rr.stdout) is None and
              "not a hex triple" in rr.stderr,
              f"rc={rr.returncode} out={rr.stdout.strip()!r} err={rr.stderr.strip()!r}")

        # 11. THE REAL APP. Count `AppTheme.navy` in a real Flutter capture of
        #     the tab bar and check it against the decoder's own histogram.
        #     Written by `test/message_tab_unread_badge_test.dart`; skipped,
        #     never faked, when that file has not run on this machine.
        shot = "/tmp/shots/tab_badge_unconfirmed.png"
        if not os.path.exists(shot):
            check("case 11: real Flutter capture counted (SKIPPED: no capture "
                  "-- run message_tab_unread_badge_test.dart first)", True)
        else:
            sys.path.insert(0, os.path.join(REPO, "tool"))
            from png_read import read_png
            from collections import Counter
            w, h, rows = read_png(shot)
            hist = Counter()
            for row in rows:
                for i in range(0, len(row), 3):
                    hist[(row[i], row[i + 1], row[i + 2])] += 1
            navy = theme_tokens()["navy"]
            want = "%d,%d,%d" % navy
            got = answered(run(shot, want).stdout)
            check("case 11: on a real %dx%d capture, px_count agrees with the "
                  "decoder's histogram for navy" % (w, h),
                  got == hist[navy] and got and got > 0,
                  f"px_count={got} histogram={hist[navy]}")

            # 12. the live caller's real question, on the real file: accent is
            #     the pip's colour in the confirmed state and is a large,
            #     unambiguous region. Counting it must land on the histogram
            #     too -- and this is the number `expect(goldBefore, > 0)` rests.
            acc = theme_tokens()["accent"]
            got_a = answered(run(shot, "%d,%d,%d" % acc).stdout)
            check("case 12: accent (the pip's colour) counts the same on the "
                  "real capture, and is visibly present",
                  got_a == hist[acc] and got_a > 1000,
                  f"px_count={got_a} histogram={hist[acc]}")

            # 13. every theme token, whatever it is, counts consistently --
            #     a token added tomorrow is covered by construction.
            #
            #     Run against a CROP of the real capture, not the whole thing:
            #     one subprocess per token, and each one re-decodes the file it
            #     is given, so 25 tokens x a 2400x1800 decode is ~90 s of this
            #     file's own runtime for no extra evidence -- the crop is the
            #     same rasteriser's output, just fewer pixels to walk, and the
            #     oracle below is the crop's own histogram.
            crop = os.path.join(tmp, "crop.png")
            cw, ch = 240, 180
            write_png(crop, cw, ch, lambda x, y: tuple(rows[y][(x * 3):(x * 3) + 3]))
            crop_hist = Counter()
            for y in range(ch):
                row = rows[y]
                for x in range(cw):
                    crop_hist[tuple(row[x * 3:x * 3 + 3])] += 1
            mismatched = []
            for name, rgb in sorted(theme_tokens().items()):
                spec = "%d,%d,%d" % rgb
                if answered(run(crop, spec).stdout) != crop_hist[rgb]:
                    mismatched.append(f"{name} {spec}")
            check("case 13: every one of the %d theme tokens counts "
                  "consistently on real captured pixels" % len(theme_tokens()),
                  not mismatched, "mismatched: " + ", ".join(mismatched))

            # 14. the fix holds on the real file too: an impossible colour on
            #     the real capture is refused rather than answering 0 -- the
            #     exact failure the live caller's `greaterThan` would read.
            rr = run(shot, "300,0,0")
            check("case 14: an impossible colour is refused on the real "
                  "capture, not answered 0",
                  rr.returncode == 2 and answered(rr.stdout) is None,
                  f"rc={rr.returncode} out={rr.stdout.strip()!r}")
        # 15. THE COLOUR-TYPE CONTRACT. Mutation M10 -- hardcoding `stride = 3`
        #     instead of deriving it from the row length -- SURVIVED, and the
        #     honest answer is that it is *equivalent*, not a coverage hole:
        #     `png_read` normalises every colour type (grey, grey+alpha, RGB,
        #     RGBA) to three bytes per pixel, so the derived stride is always 3
        #     for every input the tool can accept. Rather than leave that
        #     invariant assumed, it is pinned here: the same 25 navy pixels
        #     must count 25 whether they arrive in a 1-, 2-, 3- or 4-channel
        #     file. If `png_read` ever stops normalising, this goes red, and so
        #     does the derived stride's reason to exist.
        for ctype, label, nch in ((0, "grey", 1), (4, "grey+alpha", 2),
                                  (2, "RGB", 3), (6, "RGBA", 4)):
            cp = os.path.join(tmp, f"ct{ctype}.png")
            #     A GREY file cannot carry navy -- R=G=B, so `22,33,62` is not a
            #     colour it can hold, and the first version of this case
            #     asserted 25 against a 1-channel file and "failed" a tool that
            #     was right. Same error class the backlog keeps recording: an
            #     assertion written against an assumed input, not a measured
            #     one. The grey cases are given a colour they CAN hold, and
            #     the point of the case -- that the count does not depend on
            #     how the channels are packed -- is what they still prove.
            probe = GREY if ctype in (0, 4) else NAVY
            write_png_ct(ctype, cp, 10, 10,
                         lambda x, y: probe if (x < 5 and y < 5) else WHITE)
            spec = "%d,%d,%d" % probe
            rr = run(cp, spec)
            check(f"case 15 ({label}, {nch}-channel file): the same 25 pixels "
                  f"count 25 whatever the file's colour type",
                  answered(rr.stdout) == 25,
                  f"colour {spec} got {rr.stdout.strip()!r}")

    finally:
        pass

    bad = [n for n, ok in results if not ok]
    print()
    print(f"{len(results) - len(bad)}/{len(results)} cases passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
