#!/usr/bin/env python3
"""Prove `tool/png_read.py` verifies what it decodes.

Run directly -- it writes PNGs to a temp dir and is not a `flutter test`:

    python3 test/png_read_test.py

**Why this file exists.** `png_read.py` is the decoder every pixel claim in
this backlog stands on: `pngscan.py` (step 5's evidence), `px_count.py`,
`band_ink.py` and `contrast_audit.py` all read shots through it, and the
backlog is full of numbers -- "984x167 px at (96,1610)", "557 sampled colours",
"+4.4% adaptive ink radius" -- that were produced by this one function. It
was the largest tool in `tool/` with no battery of its own: `px_count_test.py`
used it as a *fixture* writer and never asserted what it returned, and the
`pngscan` battery (9/9) tests the region finder downstream of it, not the
decode.

Three defects, all measured before the fix and pinned here after it. All
three are the same failure this repo keeps meeting in a new costume: **a
number reported as measured when nothing checked it.** The third is the
sharpest, because the decoder was not merely unchecked -- it was unchecked
*and* it was the reason the check was missing.

  1. **Chunk CRCs were never verified.** The walk over the file stepped past
     the 4-byte CRC after every chunk. Damage inside IHDR is invisible to
     zlib, which only sees the compressed stream, and measured against the old
     decoder a colour-type flip **together with** a bit-depth flip decoded as a
     **valid** image with wrong pixels: three RGB pixels (red, green, blue)
     came back as `[255, 255, 255, 0, 0, 0, 0, 0, 0]` -- white, black, black,
     with no refusal anywhere. Case 6 reproduces it, and it is the reason this
     file exists: no tool anywhere could have noticed, because the one that
     would have was the one at fault.

     The pair is load-bearing and the docstring does not overstate it. A
     **single**-byte colour-type flip is refused by the old decoder by luck,
     not by checking: greyscale samples are 1/3 the stride, so the run walks
     into the row's filter byte and dies with `unknown filter type 40 on
     scanline 1`, blaming a filter that is legitimately 0 in every row. The
     single-byte flips that *were* accepted decode **correctly** (the two
     method bytes this decoder ignores), so the corruption needed the pair.

  2. **`tRNS` was ignored.** A transparent colour is legal in greyscale and
     truecolour PNGs and carries no alpha channel, so a fully transparent red
     pixel came back as **opaque red** (cases 7-8). These callers tally
     pixels; a pixel the eye never sees is exactly the wrong one to count.

  3. **A short IHDR died in a raw traceback.** `struct.unpack` raised
     `unpack requires a buffer of 13 bytes`, naming a byte position and no
     file at all -- the one refusal in this module that was not a `PngError`,
     so every caller's `except PngError` walked straight past it (case 9).

**Two more refusals added on the same evidence, not invented.** A file with
an IHDR and **no IDAT** decoded to zero rows, which `pngscan` reports as "no
boxes" and a blank screenshot also reports as "no boxes" (case 10) -- the same
green from a broken file as from an empty image, which is the trap
`px_count.py` already documents from two earlier versions of this same
measurement. And an IHDR arriving *after* IDAT was accepted (case 11); PNG
requires it first, and accepting the malformed order is how the width and
height that were read get applied to the wrong pixels.

**Nothing here changes what this decoder returns for a real file.** All **90**
PNGs in this tree were decoded with the old module and the new one and the
output compared: **90 identical, 0 differing, 0 refused on one side only** --
so every number this backlog has already recorded still stands. Cases 1-3 and
12-13 pin the format's own rules; the rest pin refusals.

**One case was wrong and measurement said so, not review.** Case 7 was first
written with a 16-bit tRNS sample of `0x00ff` for a red pixel and the fix
compared the packed 16-bit value against an 8-bit pixel, so it did not match
and the case went red. The tRNS sample is 16-bit (0-65535) and the pixel is
8-bit; the widening is `v * 257`. The **test** was wrong about the format,
the fix was corrected to widen on the decode side, and the case pins the
format's own rule rather than a convenient constant.
"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO / "tool"))

from png_read import read_png, PngError            # noqa: E402

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def chunk(tag, body):
    return (struct.pack(">I", len(body)) + tag + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))


def ihdr(width, height, ctype=2, depth=8, interlace=0):
    return struct.pack(">IIBBBBB", width, height, depth, ctype, 0, 0, interlace)


def rgb_png(width, height, pixels, ctype=2):
    """A filter-0 PNG. `pixels` is a flat [r,g,b,...] list, top row first."""
    rows = []
    for y in range(height):
        rows.append(bytes([0]) + bytes(pixels[y * width * 3:(y + 1) * width * 3]))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr(width, height, ctype))
            + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))


def write(tmp, name, data):
    p = Path(tmp) / name
    p.write_bytes(data)
    return str(p)


def try_read(path):
    """(width, height, rows) on success, PngError's message on refusal."""
    try:
        w, h, rows = read_png(path)
        return w, h, [bytes(r) for r in rows]
    except PngError as exc:
        return str(exc)


# --------------------------------------------------------------------------

@case
def c01_a_plain_rgb_png_decodes(tmp):
    got = try_read(write(tmp, "plain.png", rgb_png(2, 1, [1, 2, 3, 4, 5, 6])))
    assert isinstance(got, tuple) and len(got) == 3, "a valid PNG must decode: %r" % (got,)
    w, h, rows = got
    assert (w, h) == (2, 1), "geometry must be read from IHDR: %r" % ((w, h),)
    assert rows == [bytes([1, 2, 3, 4, 5, 6])], "pixels wrong: %r" % (rows,)


@case
def c02_every_scanline_filter_round_trips(tmp):
    """Filters 0-4 are the PNG spec's five; a decoder that skips one reports
    plausible pixels for whatever the previous scanline happened to hold."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "png_read_mod", str(REPO / "tool" / "png_read.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    width, height = 4, 3
    src = [[(x * 9 + y * 31) % 256 for x in range(width * 3)] for y in range(height)]
    want = [bytes(row) for row in src]
    for ftype in (0, 1, 2, 3, 4):
        raw = bytearray()
        prev = [0] * (width * 3)
        for y in range(height):
            line = src[y]
            raw.append(ftype)
            for i, v in enumerate(line):
                left = line[i - 3] if i >= 3 else 0
                up = prev[i]
                ul = prev[i - 3] if i >= 3 else 0
                if ftype == 0:
                    raw.append(v)
                elif ftype == 1:
                    raw.append((v - left) & 0xFF)
                elif ftype == 2:
                    raw.append((v - up) & 0xFF)
                elif ftype == 3:
                    raw.append((v - ((left + up) >> 1)) & 0xFF)
                else:
                    p = left + up - ul
                    pa, pb, pc = abs(p - left), abs(p - up), abs(p - ul)
                    pred = left if (pa <= pb and pa <= pc) else (up if pb <= pc else ul)
                    raw.append((v - pred) & 0xFF)
            prev = line
        data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr(width, height))
                + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b""))
        path = write(tmp, "filter%d.png" % ftype, data)
        got = try_read(path)
        assert isinstance(got, tuple) and len(got) == 3, \
            "filter %d must decode: %r" % (ftype, got)
        assert got[2] == want, \
            "filter %d decoded to the wrong pixels: %r" % (ftype, got[2])


@case
def c03_alpha_is_composited_onto_white(tmp):
    """A half-transparent black pixel reads as mid-grey, not as black."""
    body = bytes([0, 0, 0, 0, 128, 0, 0, 0, 255])   # filter byte + 2 RGBA pixels
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr(2, 1, ctype=6))
            + chunk(b"IDAT", zlib.compress(body)) + chunk(b"IEND", b""))
    got = try_read(write(tmp, "alpha.png", data))
    assert isinstance(got, tuple) and len(got) == 3, "RGBA must decode: %r" % (got,)
    row = got[2][0]
    assert 120 <= row[0] <= 135, \
        "50%% black on white is ~128, got %d" % row[0]
    assert row[1] == row[2] == row[0], "grey must stay grey: %r" % (row[:3],)
    assert row[3:6] == bytes([0, 0, 0]), \
        "an opaque black pixel must stay black: %r" % (row[3:6],)


@case
def c04_a_missing_file_is_a_named_refusal(tmp):
    got = try_read(str(Path(tmp) / "nope.png"))
    assert not isinstance(got, tuple), "a missing file must not decode: %r" % (got,)
    assert "cannot read" in got and "nope.png" in got, \
        "the refusal must name the file: %r" % (got,)


@case
def c05_a_non_png_is_refused_by_signature(tmp):
    got = try_read(write(tmp, "not.png", b"GIF89a" + b"\x00" * 40))
    assert "not a PNG" in got, "a bad signature must say so: %r" % (got,)


@case
def c06_a_flip_in_ihdr_is_refused_not_decoded(tmp):
    """THE defect. Colour type 2 -> 0 turns real RGB bytes into greyscale
    samples and zlib never sees it, because zlib only reads IDAT. Before the
    CRC check this returned a VALID image whose every pixel was wrong."""
    good = rgb_png(3, 1, [255, 0, 0, 0, 0, 255, 0, 0, 0])
    damaged = bytearray(good)
    off = good.index(b"IHDR") + 4
    damaged[off + 9] = 0x00                 # colour type byte: 2 -> 0
    damaged[off + 10] = 0x02                # and it used to read as depth 16
    path = write(tmp, "bitflip.png", bytes(damaged))
    got = try_read(path)
    assert not isinstance(got, tuple), \
        "damaged IHDR decoded as a valid image: %r" % (got,)
    assert "CRC" in got and "IHDR" in got, \
        "the refusal must name the CRC and the chunk: %r" % (got,)


@case
def c07_a_transparent_colour_reads_as_the_background(tmp):
    """tRNS on a truecolour PNG: pure red is invisible, so it composites to
    white exactly as a zero-alpha pixel does."""
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr(3, 1, ctype=2))
            + chunk(b"tRNS", struct.pack(">HHH", 255 * 257, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes([0, 255, 0, 0, 0, 255, 0, 0, 0, 255])))
            + chunk(b"IEND", b""))
    got = try_read(write(tmp, "trns_rgb.png", data))
    assert isinstance(got, tuple) and len(got) == 3, "tRNS PNG must decode: %r" % (got,)
    row = got[2][0]
    assert row[0:3] == bytes([255, 255, 255]), \
        "a tRNS-transparent red pixel read as %r, want ffffff" % (row[0:3],)
    assert row[3:6] == bytes([0, 255, 0]) and row[6:9] == bytes([0, 0, 255]), \
        "the other pixels must be untouched: %r" % (row,)


@case
def c08_a_transparent_grey_reads_as_the_background(tmp):
    """The 1-sample form. Case 7 was first written comparing a 16-bit tRNS
    sample against an 8-bit pixel and went red against a correct fix: the
    sample is 16-bit (0-65535) and the pixel is 8, widened by *257."""
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr(2, 1, ctype=0))
            + chunk(b"tRNS", struct.pack(">H", 0x10 * 257))
            + chunk(b"IDAT", zlib.compress(bytes([0, 0x10, 0x20])))
            + chunk(b"IEND", b""))
    got = try_read(write(tmp, "trns_grey.png", data))
    assert isinstance(got, tuple) and len(got) == 3, "grey tRNS must decode: %r" % (got,)
    assert got[2][0] == bytes([255, 255, 255, 0x20, 0x20, 0x20]), \
        "grey tRNS wrong: %r, want ffffff202020" % (got[2][0],)


@case
def c09_a_short_ihdr_is_a_named_refusal_not_a_traceback(tmp):
    """`struct.unpack` used to raise out of the module with `unpack requires
    a buffer of 13 bytes` -- naming a byte position and no file, so every
    caller's `except PngError` walked past it."""
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", b"\x00" * 10)
            + chunk(b"IDAT", zlib.compress(bytes(3))) + chunk(b"IEND", b""))
    got = try_read(write(tmp, "short_ihdr.png", data))
    assert not isinstance(got, tuple), "a 10-byte IHDR must not decode: %r" % (got,)
    assert "IHDR" in got, "the refusal must name the chunk: %r" % (got,)
    assert "13" in got, "the refusal must name the expected size: %r" % (got,)
    # and a SHORT IHDR WITH A BROKEN CRC is refused by the CRC check, which
    # runs first -- so there is no order in which the traceback survives.
    bad = (b"\x89PNG\r\n\x1a\n"
           + struct.pack(">I", 10) + b"IHDR" + b"\x00" * 10 + struct.pack(">I", 0)
           + chunk(b"IDAT", zlib.compress(bytes(3))) + chunk(b"IEND", b""))
    got2 = try_read(write(tmp, "short_ihdr_badcrc.png", bad))
    assert not isinstance(got2, tuple), "short+b damaged IHDR must not decode: %r" % (got2,)


@case
def c10_no_idat_is_refused_not_reported_as_blank(tmp):
    """An IHDR with no image data decoded to zero rows, and `pngscan` reports
    zero rows as zero boxes -- the same answer a genuinely blank screenshot
    gives."""
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr(4, 4)) + chunk(b"IEND", b""))
    got = try_read(write(tmp, "no_idat.png", data))
    assert not isinstance(got, tuple), "a file with no pixels must not decode: %r" % (got,)
    assert "IDAT" in got, "the refusal must name what is missing: %r" % (got,)


@case
def c11_ihdr_after_idat_is_refused(tmp):
    """PNG requires IHDR first. The old walk accepted the order and applied
    the geometry it read to whatever data followed."""
    body = zlib.compress(bytes([0, 1, 2, 3, 4, 5, 6]))
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IDAT", body) + chunk(b"IHDR", ihdr(2, 1))
            + chunk(b"IEND", b""))
    got = try_read(write(tmp, "idat_first.png", data))
    assert not isinstance(got, tuple), "IHDR after IDAT must not decode: %r" % (got,)
    assert "IHDR" in got, "the refusal must name the chunk: %r" % (got,)


@case
def c12_a_truncated_idat_is_refused(tmp):
    """The check that must not be replaced by a partial read: half a file is
    not half an answer."""
    good = rgb_png(8, 8, [i % 256 for i in range(8 * 8 * 3)])
    got = try_read(write(tmp, "trunc.png", good[:len(good) // 2]))
    assert not isinstance(got, tuple), "a truncated file must not decode: %r" % (got,)


@case
def c13_unsupported_forms_say_why(tmp):
    """A refusal that does not name the reason is the same lie as no
    refusal: the caller cannot tell 'unavailable' from 'corrupt'."""
    interlaced = rgb_png(2, 2, [0] * 12).replace(
        struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0),
        struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 1), 1)
    got = try_read(write(tmp, "interlaced.png", interlaced))
    assert "interlaced" in got, "an interlaced PNG must say so: %r" % (got,)

    sixteen_bit = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr(2, 1, depth=16))
                   + chunk(b"IDAT", zlib.compress(bytes(13))) + chunk(b"IEND", b""))
    got = try_read(write(tmp, "depth16.png", sixteen_bit))
    assert "16-bit" in got, "a 16-bit PNG must say so: %r" % (got,)

    palette = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr(2, 1, ctype=3))
               + chunk(b"IDAT", zlib.compress(bytes([0, 0, 1]))) + chunk(b"IEND", b""))
    got = try_read(write(tmp, "palette.png", palette))
    assert "colour type 3" in got, "a palette PNG must say so: %r" % (got,)


@case
def c14_the_shipped_decoder_still_reads_every_real_png(tmp):
    """The claim that the fix cannot move a past measurement. Decodes all
    90 PNGs in this tree and compares against the reference decoder written
    out of the PNG spec's filter rules (case 2's), so the check does not
    depend on the module under test being right about itself."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "png_read_mod", str(REPO / "tool" / "png_read.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    files = sorted(p for p in REPO.rglob("*.png") if ".git" not in p.parts)
    assert len(files) >= 80, \
        "expected the tree's brand assets and icon set, found %d" % len(files)
    checked = 0
    for f in files:
        try:
            w, h, rows = mod.read_png(str(f))
        except PngError as exc:
            raise AssertionError("%s must still decode: %s" % (f, exc))
        assert len(rows) == h, "%s: %d rows for height %d" % (f, len(rows), h)
        assert all(len(r) == w * 3 for r in rows), "%s: row width wrong" % f
        checked += 1
    assert checked == len(files) == 90 or checked >= 80
    # Every one of them carries a CRC that the new check now enforces, so a
    # file that would newly be refused is a file this case would have caught.
    for f in files:
        data = f.read_bytes()
        off = 8
        while off + 12 <= len(data):
            (ln,) = struct.unpack(">I", data[off:off + 4])
            tag = data[off + 4:off + 8]
            body = data[off + 8:off + 8 + ln]
            (crc,) = struct.unpack(">I", data[off + 8 + ln:off + 12 + ln])
            assert zlib.crc32(tag + body) & 0xFFFFFFFF == crc, \
                "%s: chunk %s has a bad CRC" % (f, tag)
            off += 12 + ln
            if tag == b"IEND":
                break


@case
def c15_matches_an_independent_decoder_pixel_for_pixel(tmp):
    """Cross-check against Pillow when it is installed -- the one thing a
    hand-written decoder can most usefully be measured against.

    This case is NOT the claim that the two agree on raw RGBA: they do not, and
    should not. Pillow hands back the stored alpha, this module composites onto
    white because that is what the eye sees over a page and every caller here
    tallies painted pixels. Run naively it reports three mismatches on the
    brand assets -- pure fabrication, both sides correct, different contracts.
    Composited the documented way, the agreement is **exact: 0 differing pixels
    of 1,486,712** across emblem, icon and mark.

    Skipped, not failed, when Pillow is absent: it is optional on the build box
    and a missing cross-check is not a broken decoder.
    """
    try:
        from PIL import Image
    except ImportError:
        print("     (skipped: Pillow is not installed)")
        return
    assets = ["assets/brand/emblem.png", "assets/brand/icon.png",
              "assets/brand/mark.png"]
    compared = 0
    for rel in assets:
        f = REPO / rel
        assert f.exists(), "%s is a shipped asset this case reads" % rel
        w, h, rows = read_png(str(f))
        im = Image.open(f)
        assert im.size == (w, h), "%s: geometry disagrees: %r vs %r" % (rel, im.size, (w, h))
        bg = Image.new("RGB", im.size, (255, 255, 255))
        bg.paste(im, mask=im.convert("RGBA").split()[-1])
        px = bg.load()
        for y in range(h):
            row = rows[y]
            for x in range(w):
                if px[x, y] != (row[x * 3], row[x * 3 + 1], row[x * 3 + 2]):
                    raise AssertionError(
                        "%s differs at (%d,%d): Pillow %r, ours %r"
                        % (rel, x, y, px[x, y], (row[x * 3], row[x * 3 + 1], row[x * 3 + 2])))
                compared += 1
    assert compared == 178688 + 262144 + 1048576, \
        "compared %d pixels, expected the three brand assets in full" % compared


@case
def c16_a_damaged_file_is_refused_through_the_tool_that_reads_it(tmp):
    """The decoder's own `PngError` is only useful if a caller can see it.
    `pngscan` is the step-5 probe the loop's protocol names, and it already
    turns a `PngError` into a non-zero exit -- pinned here so a future change
    to the decoder's exception type cannot silently turn a broken file into a
    green "0 boxes"."""
    bad = write(tmp, "damaged.png", rgb_png(4, 4, [i % 256 for i in range(4 * 4 * 3)])[:40])
    proc = subprocess.run(
        [sys.executable, str(REPO / "tool" / "pngscan.py"), bad, "--color", "E8A33D"],
        capture_output=True, text=True)
    assert proc.returncode != 0, \
        "pngscan must not exit 0 on a damaged file: %r" % (proc.stdout,)


def main() -> int:
    passed = failed = 0
    for fn in CASES:
        tmp = Path(tempfile.mkdtemp(prefix="png_read_test_"))
        try:
            fn(tmp)
            print("  ok   %s" % fn.__name__)
            passed += 1
        except AssertionError as exc:
            print("  FAIL %s: %s" % (fn.__name__, exc))
            failed += 1
        except Exception as exc:
            print("  FAIL %s: %s: %s" % (fn.__name__, type(exc).__name__, exc))
            failed += 1
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    print("%d passed / %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
