#!/usr/bin/env python3
"""Read PNG pixels with nothing but the standard library.

The design-shot audits (`contrast_audit.py`) used to import a `pngscan`
module that lived outside this repository. When the machine it was on was
rebuilt the file disappeared, and because the import sat inside a per-file
`try`, every shot silently failed to read while the audit still printed a
green pass. A tool that cannot open a single image must not be able to
report success, so the decoder lives here, next to the tool that needs it,
where it is versioned and cannot vanish with a host.

Pure stdlib on purpose: no Pillow, no numpy. Both are optional on the build
box and this file is small enough not to need them.

Supports what the Flutter rasteriser actually emits for these shots: 8-bit
non-interlaced greyscale, RGB, greyscale+alpha, and RGBA, with all five PNG
scanline filters. Anything else raises, rather than returning pixels that
look plausible and are wrong.

A decoder is the last thing in the chain before a number reaches a report, and
this one had three ways to hand back pixels it had not checked (10 Oct, all
three measured and pinned by `test/png_read_test.py`):

  * **chunk CRCs were never verified.** The loop over the file walked straight
    past the 4-byte CRC after every chunk. Damage in IHDR is invisible to
    zlib -- the compressed stream is untouched -- and measured against the old
    decoder, a colour-type flip *together with* a bit-depth flip read as a
    *valid* image with wrong pixels: three RGB pixels (red, green, blue)
    decoded to `[255, 255, 255, 0, 0, 0, 0, 0, 0]`, white/black/black, no
    refusal anywhere. Every CRC is now checked, and a failure names the chunk.
    (All 90 PNGs in this tree decode identically under old and new, so no past
    measurement moves.)
  * **`tRNS` was ignored.** A transparent colour is legal in greyscale and
    truecolour PNGs and carries no alpha channel, so a fully transparent red
    pixel was returned as opaque red. It is now composited like alpha.
  * **a short IHDR raised `struct.error`** from inside `struct.unpack` -- a
    raw traceback naming a byte position, not a path. Every refusal here is a
    `PngError` naming the file.

    from png_read import read_png
    width, height, rows = read_png("shot.png")
    rows[0][0:3]          # b"\xff\xff\xff" -> the first pixel
"""
import struct
import zlib

# Bytes per complete pixel for each PNG colour type at 8 bits per sample.
_CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}

#: Samples per pixel in a `tRNS` chunk, by colour type (3 is palette, which
#: stores a table of alpha bytes rather than one transparent colour).
_TRNS_SAMPLES = {0: 1, 2: 3}


def _matches_trns(r, g, b, transparent):
    """True when an 8-bit pixel is the colour `tRNS` marks transparent.

    A tRNS sample is 16 bits (0-65535); a decoded pixel is 8 (0-255). The
    widening is exact: v * 257 is the value the 16-bit field holds for v.
    """
    if len(transparent) == 1:
        return r == transparent[0] // 257
    return (r, g, b) == tuple(v // 257 for v in transparent)


def _crc_ok(data, off, length, ctag):
    """True when the 4 bytes after `data[off+8+length : ...]` are the CRC of
    the chunk at `off`. Returns None instead of raising: the caller names the
    chunk, so a malformed tail is not a second failure hiding the first.
    """
    if off + 12 + length > len(data):
        return None
    want = struct.unpack(">I", data[off + 8 + length:off + 12 + length])[0]
    return zlib.crc32(data[off + 4:off + 8 + length]) & 0xFFFFFFFF == want


class PngError(Exception):
    """Raised for a file that is not a PNG this decoder can read."""


def _unfilter(raw, width, height, bpp):
    """Reverse the per-scanline PNG filters into plain bytes.

    `bpp` is bytes per pixel, which is what the filter maths is defined in.
    """
    stride = width * bpp
    out = bytearray(stride * height)
    pos = 0
    prev = bytearray(stride)
    for y in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if len(line) != stride:
            raise PngError(f"truncated scanline {y}")
        if ftype == 0:
            pass
        elif ftype == 1:                      # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ftype == 2:                      # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:                      # Average
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:                      # Paeth
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                up = prev[i]
                ul = prev[i - bpp] if i >= bpp else 0
                p = left + up - ul
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - ul)
                if pa <= pb and pa <= pc:
                    pred = left
                elif pb <= pc:
                    pred = up
                else:
                    pred = ul
                line[i] = (line[i] + pred) & 0xFF
        else:
            raise PngError(f"unknown filter type {ftype} on scanline {y}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return out, stride


def read_png(path):
    """Decode `path` and return (width, height, rows).

    `rows` is a list of `height` bytes objects, three bytes per pixel, so a
    pixel is read as `(rows[y][x * 3] << 16) | (rows[y][x * 3 + 1] << 8) |
    rows[y][x * 3 + 2]`. An alpha channel, if present, is composited against
    white so a transparent pixel reads as the background it looks like.
    """
    try:
        data = open(path, "rb").read()
    except OSError as exc:
        raise PngError(f"cannot read {path}: {exc}") from exc

    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise PngError(f"{path} is not a PNG (bad signature)")

    off = 8
    width = height = depth = ctype = interlace = None
    idat = []
    trns = None
    seen_ihdr = False
    while off + 8 <= len(data):
        (length,) = struct.unpack(">I", data[off:off + 4])
        ctag = data[off + 4:off + 8]
        body = data[off + 8:off + 8 + length]
        if len(body) != length:
            raise PngError(f"{path}: chunk {ctag!r} runs past end of file")
        # Every chunk carries a CRC and the file below is the loop's evidence,
        # so an unchecked CRC is the decoder agreeing to describe damage it
        # cannot see. Checked here rather than at the end so the message can
        # name the chunk that is actually wrong.
        if _crc_ok(data, off, length, ctag) is False:
            raise PngError(f"{path}: CRC mismatch in chunk {ctag.decode('latin1')} "
                           f"({length} bytes of payload are damaged)")
        if ctag == b"IHDR":
            if length != 13:
                # A short IHDR used to reach struct.unpack and die with
                # `unpack requires a buffer of 13 bytes`, naming no file.
                raise PngError(f"{path}: IHDR is {length} bytes, expected 13")
            if seen_ihdr or idat:
                raise PngError(f"{path}: IHDR appears after the image data")
            (width, height, depth, ctype, _comp, _filt,
             interlace) = struct.unpack(">IIBBBBB", body)
            seen_ihdr = True
        elif ctag == b"IDAT":
            idat.append(body)
        elif ctag == b"tRNS":
            trns = body
        elif ctag == b"IEND":
            break
        off += 12 + length                      # length + type + data + crc

    if not seen_ihdr:
        raise PngError(f"{path}: no IHDR chunk")
    if not idat:
        # A file with an IHDR and no pixels decodes to zero rows today, which
        # every caller reads as "the shot is blank" -- the same green from a
        # broken file as from a genuinely empty one.
        raise PngError(f"{path}: no IDAT chunk, so there are no pixels to read")
    if not width or not height:
        raise PngError(f"{path}: zero-sized image {width}x{height}")
    if interlace:
        raise PngError(f"{path}: interlaced PNGs are not supported")
    if depth != 8:
        raise PngError(f"{path}: {depth}-bit samples are not supported (need 8)")
    if ctype not in _CHANNELS:
        raise PngError(f"{path}: colour type {ctype} is not supported")

    transparent = None
    if trns is not None:
        if ctype not in _TRNS_SAMPLES:
            raise PngError(f"{path}: tRNS is not valid for colour type {ctype}")
        if len(trns) != _TRNS_SAMPLES[ctype] * 2:
            raise PngError(f"{path}: tRNS is {len(trns)} bytes, expected "
                           f"{_TRNS_SAMPLES[ctype] * 2} for colour type {ctype}")
        # Stored big-endian at 16 bits per sample, while a pixel below is
        # read at 8. `_matches_trns` does the widening; comparing the packed
        # pair directly would compare 65280 against 255 and never match, which
        # is how a transparent pixel was called opaque in the first place.
        transparent = struct.unpack(">" + "H" * _TRNS_SAMPLES[ctype], trns)

    try:
        raw = zlib.decompress(b"".join(idat))
    except zlib.error as exc:
        raise PngError(f"{path}: corrupt image data ({exc})") from exc

    bpp = _CHANNELS[ctype]
    expected = (width * bpp + 1) * height
    if len(raw) < expected:
        # A short stream would otherwise raise an IndexError from deep inside
        # the unfilter loop, naming a byte offset instead of the real problem.
        raise PngError(f"{path}: image data is {len(raw)} bytes, "
                       f"expected {expected} for {width}x{height}")
    pixels, stride = _unfilter(raw, width, height, bpp)
    if len(pixels) != stride * height:
        raise PngError(f"{path}: decoded {len(pixels)} bytes, expected "
                       f"{stride * height}")

    # Hand back one flat bytes object per scanline, three bytes per pixel,
    # which is the contract every caller here indexes with `row[x * 3]`.
    rows = []
    for y in range(height):
        line = pixels[y * stride:(y + 1) * stride]
        flat = bytearray(width * 3)
        for x in range(width):
            i = x * bpp
            if ctype == 6:                    # RGBA
                r, g, b, a = line[i], line[i + 1], line[i + 2], line[i + 3]
            elif ctype == 4:                  # grey + alpha: two bytes, not four
                r = g = b = line[i]
                a = line[i + 1]
            elif ctype == 0:                  # plain grey
                r = g = b = line[i]
                a = 0xFF
            else:                             # RGB
                r, g, b = line[i], line[i + 1], line[i + 2]
                a = 0xFF
            if transparent is not None and _matches_trns(r, g, b, transparent):
                # A tRNS PNG has no alpha channel at all; the colour that
                # matches is invisible. Reported as opaque was a pixel the
                # eye never sees, which is exactly what these callers tally.
                a = 0x00
            if a != 0xFF:
                # Composite onto white: what the eye sees is the page behind
                # it, not the stored value.
                f = a / 255.0
                r = round(r * f + 255 * (1 - f))
                g = round(g * f + 255 * (1 - f))
                b = round(b * f + 255 * (1 - f))
            j = x * 3
            flat[j], flat[j + 1], flat[j + 2] = r, g, b
        rows.append(flat)
    return width, height, rows


if __name__ == "__main__":       # quick self-check against a known file
    import sys
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(2)
    w, h, rows = read_png(sys.argv[1])
    print(f"{sys.argv[1]}: {w}x{h}, first pixel {rows[0][0:3]!r}, "
          f"last pixel {rows[h - 1][(w - 1) * 3:][:3]!r}")
