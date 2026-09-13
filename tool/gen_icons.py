#!/usr/bin/env python3
"""Generate every app-icon asset from the one brand mark.

Why this exists: the launcher icons were hand-made once, and the result was a
near-white rounded square (#F5F4F1) with the logo floating small inside it.
The founder's report, verbatim: "the app logo is small in white background
fix it make it just logo with no white background i mean the app icon logo".
A hand-made icon also cannot be regenerated when the mark changes — which is
exactly what happened when the mark was re-centred, so the generator is what
keeps the artwork and the icons in step.

What it emits, all from assets/brand/mark.png:
  android mipmap-*/ic_launcher.png          legacy icon, TRANSPARENT, mark big
  android mipmap-*/ic_launcher_round.png    round-mask variant
  android mipmap-*/ic_launcher_foreground.png  adaptive layer, inside the safe
                                            circle but as large as it can go
  android drawable-*/launch_image.png       splash mark, centred by the
                                            launch_background.xml layer list
  ios AppIcon.appiconset/*.png              OPAQUE cream tile — iOS rejects an
                                            icon with an alpha channel, so the
                                            iOS set deliberately keeps a
                                            background where Android drops it

Run: python3 tool/gen_icons.py [--check]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from prep_mark import max_ink_radius  # noqa: E402  (sibling script, not a package)

REPO = Path(__file__).resolve().parent.parent
MARK = REPO / "assets" / "brand" / "mark.png"
RES = REPO / "android" / "app" / "src" / "main" / "res"
IOS = REPO / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

# Android density buckets and the pixel size of a 48dp / 108dp asset.
DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}

# Fractions of the canvas the mark's bounding box should span.
LEGACY_FILL = 0.94  # no mask: the icon is a plain square, so fill it
# Masks are circles, and the mark is taller than it is wide, so a width/height
# fill would let a corner poke out of the mask while leaving the icon small.
# Both masked layers are therefore sized by the mark's farthest ink pixel from
# its centre: the icon is as large as the mask allows, never clipped.
ROUND_INK_RADIUS = 0.44      # of a 48dp legacy round icon
ADAPTIVE_INK_RADIUS = 0.3056  # of the 108dp adaptive canvas == 33dp safe radius
SPLASH_FILL = 1.00
IOS_FILL = 0.72  # iOS icons want breathing room inside their rounded square
# The founder's call: a white tile behind the mark. The artwork is dark ink with
# gold accents, so on a transparent icon it disappears against a dark launcher
# wallpaper. White keeps the mark clear and matches the white first screen.
ICON_BG = (255, 255, 255, 255)
IOS_BG = ICON_BG  # iOS forbids an alpha channel in AppIcon anyway


def load_mark() -> Image.Image:
    return Image.open(MARK).convert("RGBA")


def place(mark: Image.Image, size: int, fill: float, bg=None) -> Image.Image:
    """Centre the mark in a size x size canvas, scaled to `fill` of the width."""
    canvas = Image.new("RGBA", (size, size), bg or (0, 0, 0, 0))
    target_w = max(1, int(round(size * fill)))
    scale = target_w / mark.width
    target_h = max(1, int(round(mark.height * scale)))
    # Never let the mark spill out of the canvas if it is taller than wide.
    if target_h > int(size * fill):
        scale = (size * fill) / mark.height
        target_w = max(1, int(round(mark.width * scale)))
        target_h = max(1, int(round(mark.height * scale)))
    resized = mark.resize((target_w, target_h), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((size - target_w) // 2, (size - target_h) // 2), resized)
    return canvas


def place_by_radius(mark: Image.Image, size: int, radius_frac: float, bg=None) -> Image.Image:
    """Scale the mark so its farthest ink pixel sits at radius_frac of `size`."""
    target_r = size * radius_frac
    r = max_ink_radius(mark)
    scale = target_r / r if r else 1.0
    w = max(1, int(round(mark.width * scale)))
    h = max(1, int(round(mark.height * scale)))
    canvas = Image.new("RGBA", (size, size), bg or (0, 0, 0, 0))
    resized = mark.resize((w, h), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((size - w) // 2, (size - h) // 2), resized)
    return canvas


def strip_bands(mark: Image.Image, width: int) -> Image.Image:
    """A wide strip for the splash, scaled to `width` with a proportional height."""
    scale = width / mark.width
    h = max(1, int(round(mark.height * scale)))
    out = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    resized = mark.resize((width, h), Image.Resampling.LANCZOS)
    out.paste(resized, (0, 0), resized)
    return out


def ink_report(im: Image.Image) -> str:
    bbox = im.split()[3].getbbox()
    if bbox is None:
        return "EMPTY"
    l, t, r, b = bbox
    return (f"ink {100 * (r - l) / im.width:.0f}%x{100 * (b - t) / im.height:.0f}% "
            f"margins L{100 * l / im.width:.0f}% R{100 * (im.width - r) / im.width:.0f}%")


def main() -> int:
    check = "--check" in sys.argv
    mark = load_mark()
    print(f"mark: {mark.width}x{mark.height}")
    written = 0

    for bucket, dpr in DENSITIES.items():
        out_dir = RES / f"mipmap-{bucket}"
        out_dir.mkdir(parents=True, exist_ok=True)

        legacy_size = int(round(48 * dpr))
        legacy = place(mark, legacy_size, LEGACY_FILL, bg=ICON_BG)
        legacy.save(out_dir / "ic_launcher.png")

        rnd = place_by_radius(mark, legacy_size, ROUND_INK_RADIUS, bg=ICON_BG)
        rnd.save(out_dir / "ic_launcher_round.png")

        fg_size = int(round(108 * dpr))
        fg = place_by_radius(mark, fg_size, ADAPTIVE_INK_RADIUS)
        fg.save(out_dir / "ic_launcher_foreground.png")

        splash_dir = RES / f"drawable-{bucket}"
        splash_dir.mkdir(parents=True, exist_ok=True)
        strip_bands(mark, int(round(120 * dpr))).save(splash_dir / "launch_image.png")

        written += 4
        print(f"  {bucket:8s} launcher {legacy_size:3d}px [{ink_report(legacy)}]  "
              f"adaptive {fg_size:3d}px [{ink_report(fg)}]  "
              f"round [{ink_report(rnd)}]")

    # The adaptive background is the white tile the founder asked for: the mark is
    # dark ink with gold accents, so it needs a light plate behind it on API 26+.
    bg_xml = RES / "values" / "ic_launcher_background.xml"
    bg_xml.parent.mkdir(parents=True, exist_ok=True)
    bg_xml.write_text(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<resources>\n"
        "    <!-- White plate behind the mark so the dark artwork stays legible on\n"
        "         any wallpaper. See tool/gen_icons.py. -->\n"
        "    <color name=\"ic_launcher_background\">#FFFFFF</color>\n"
        "</resources>\n"
    )
    night = RES / "values-night" / "ic_launcher_background.xml"
    if night.exists():
        night.write_text(bg_xml.read_text())
        print(f"  wrote {night.relative_to(REPO)} (white, night too)")
    print(f"  wrote {bg_xml.relative_to(REPO)} (white)")

    # iOS: opaque, because an AppIcon with an alpha channel is rejected.
    if IOS.exists():
        contents = json.loads((IOS / "Contents.json").read_text())
        n = 0
        for entry in contents.get("images", []):
            fname = entry.get("filename")
            if not fname:
                continue
            size = float(entry["size"].split("x")[0])
            scale = int(entry["scale"].rstrip("x"))
            px = int(round(size * scale))
            place(mark, px, IOS_FILL, bg=IOS_BG).convert("RGB").save(
                IOS / fname, format="PNG")
            n += 1
        print(f"  iOS AppIcon: {n} files on opaque cream")
        written += n

    print(f"{'checked' if check else 'generated'} {written} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
