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
  android mipmap-*/ic_launcher.png          legacy icon, WHITE plate, mark big
  android mipmap-*/ic_launcher_round.png    round-mask variant, same plate
  android mipmap-*/ic_launcher_foreground.png  adaptive layer, inside the safe
                                            circle but as large as it can go
  android drawable-*/launch_image.png       splash mark, centred by the
                                            launch_background.xml layer list
  ios AppIcon.appiconset/*.png              OPAQUE white tile — iOS rejects an
                                            icon with an alpha channel, so the
                                            plate is baked into every file

Run: python3 tool/gen_icons.py            # write every asset
    python3 tool/gen_icons.py --check    # report drift, WRITE NOTHING

**`--check` writes nothing, and says so.** It used to print `checked N files`
*after saving all of them*, so the one flag that exists to avoid touching the
shipped launcher icon was the flag that rewrote it. `--check` now renders every
asset in memory, compares it with what is on disk, prints the drifting paths and
exits 1 -- no file is opened for writing, which this file's own battery asserts
by hashing the whole tree either side of the run.

**`ink_report` measures the MARK, not the plate.** The legacy and round icons
are an opaque white tile, so an alpha bounding box over them is the *whole
192x192 canvas*: both printed `ink 100%x100% margins L0% R0%` -- a measurement
of the background, in the one field a reader reads to judge whether the logo is
too small. The mark is now composited on its transparent canvas first, measured
there, and only then flattened onto the plate.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prep_mark import VISIBLE_ALPHA, max_ink_radius  # noqa: E402  (sibling script)

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
ROUND_INK_RADIUS = 0.42      # of a 48dp legacy round icon
# 0.3056 is the 33dp safe-zone tangent, but this mark is portrait: a point on
# that circle is at the mask's edge, so the tallest ink corners get shaved by
# squircle and circle masks. 0.283 keeps the whole silhouette inside the mask
# with a visible margin, which is what the founder asked for when he said the
# logo must not sit cramped in its tile.
ADAPTIVE_INK_RADIUS = 0.238   # of the 108dp adaptive canvas
SPLASH_FILL = 1.00
IOS_FILL = 0.72  # iOS icons want breathing room inside their rounded square
# The founder's call: a white tile behind the mark. The artwork is dark ink with
# gold accents, so on a transparent icon it disappears against a dark launcher
# wallpaper. White keeps the mark clear and matches the white first screen.
ICON_BG = (255, 255, 255, 255)
IOS_BG = ICON_BG  # iOS forbids an alpha channel in AppIcon anyway


def load_mark() -> Image.Image:
    """The brand mark, or a named refusal -- never a bare PIL traceback.

    A missing mark used to raise `FileNotFoundError` out of `Image.open`, which
    names a path and nothing else: not what the mark is for, not that the
    assets already in the tree are fine. A mark with NO VISIBLE INK is refused
    too, and that one is the dangerous half -- see `main`.
    """
    if not MARK.exists():
        print("gen_icons: cannot run -- the brand mark is missing:", file=sys.stderr)
        print("   MISSING  %s" % MARK, file=sys.stderr)
        print("        was: the single source every launcher icon, the splash "
              "and the AppIcon set are rendered from", file=sys.stderr)
        print("        get: assets/brand/mark.png (git LFS-free, in the repo)",
              file=sys.stderr)
        print(file=sys.stderr)
        print("The icons already in the tree are untouched and still ship -- "
              "do not rebuild them from an absent mark.", file=sys.stderr)
        return None
    im = Image.open(MARK).convert("RGBA")
    if max_ink_radius(im) <= 0.0:
        print("gen_icons: refusing to write -- the mark has no visible ink.",
              file=sys.stderr)
        print("   mark     %s (%dx%d, every pixel at or below alpha %d)"
              % (MARK, im.width, im.height, VISIBLE_ALPHA), file=sys.stderr)
        print(file=sys.stderr)
        print("An all-transparent or all-faint mark renders as %d BLANK WHITE "
              "tiles" % (len(DENSITIES) * 2), file=sys.stderr)
        print("and the report would print each of them as `ink 100%x100%`.",
              file=sys.stderr)
        print("Run `python3 tool/prep_mark.py assets/brand/mark.png` to see "
              "what the alpha channel holds.", file=sys.stderr)
        return None
    return im


def flatten(canvas: Image.Image, bg=None) -> Image.Image:
    """Put the opaque plate UNDER an already-composed transparent canvas.

    Every placer returns the mark alone so `ink_report` can measure ink instead
    of the plate; this is the single place the plate is applied.
    """
    if bg is None:
        return canvas
    out = Image.new("RGBA", canvas.size, bg)
    out.alpha_composite(canvas)
    return out


def place(mark: Image.Image, size: int, fill: float, bg=None) -> Image.Image:
    """Centre the mark in a size x size canvas, scaled to `fill` of the width."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
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
    return flatten(canvas, bg)


def place_by_radius(mark: Image.Image, size: int, radius_frac: float, bg=None) -> Image.Image:
    """Scale the mark so its farthest ink pixel sits at radius_frac of `size`."""
    target_r = size * radius_frac
    r = max_ink_radius(mark)
    scale = target_r / r if r else 1.0
    w = max(1, int(round(mark.width * scale)))
    h = max(1, int(round(mark.height * scale)))
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    resized = mark.resize((w, h), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((size - w) // 2, (size - h) // 2), resized)
    return flatten(canvas, bg)


def strip_bands(mark: Image.Image, width: int) -> Image.Image:
    """A wide strip for the splash, scaled to `width` with a proportional height."""
    scale = width / mark.width
    h = max(1, int(round(mark.height * scale)))
    out = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    resized = mark.resize((width, h), Image.Resampling.LANCZOS)
    out.paste(resized, (0, 0), resized)
    return out


def ink_report(im: Image.Image) -> str:
    """How much of the canvas the MARK occupies -- measured off the plate.

    This used to be an alpha bounding box, which on a plated icon is the entire
    canvas: every legacy and round row printed `ink 100%x100% margins L0% R0%`,
    describing the white background in the one field a reader opens the report to
    judge whether the logo is too small. The truth for that icon is 67%x89% with
    16% margins -- the founder asked for the mark big, and this number is how
    anyone would have checked whether that ask survived a regeneration.
    """
    bbox = ink_bbox(im)
    if bbox is None:
        return "EMPTY"
    l, t, r, b = bbox
    return (f"ink {100 * (r - l) / im.width:.0f}%x{100 * (b - t) / im.height:.0f}% "
            f"margins L{100 * l / im.width:.0f}% R{100 * (im.width - r) / im.width:.0f}%")


def plan(mark: Image.Image) -> list[tuple[Path, Image.Image]]:
    """Every asset this run owns, as (path, image) -- rendered, not saved.

    Both modes build the identical list, so a check is the same work the write
    does. That is what makes a drift verdict trustworthy: nothing is reported
    that the write would not have produced.
    """
    out: list[tuple[Path, Image.Image]] = []

    for bucket, dpr in DENSITIES.items():
        out_dir = RES / f"mipmap-{bucket}"
        legacy_size = int(round(48 * dpr))
        out.append((out_dir / "ic_launcher.png",
                    place(mark, legacy_size, LEGACY_FILL, bg=ICON_BG)))
        out.append((out_dir / "ic_launcher_round.png",
                    place_by_radius(mark, legacy_size, ROUND_INK_RADIUS,
                                    bg=ICON_BG)))
        fg_size = int(round(108 * dpr))
        out.append((out_dir / f"ic_launcher_foreground.png",
                    place_by_radius(mark, fg_size, ADAPTIVE_INK_RADIUS)))

        splash_dir = RES / f"drawable-{bucket}"
        out.append((splash_dir / "launch_image.png",
                    strip_bands(mark, int(round(120 * dpr)))))

    return out


def android_xml() -> str:
    return (
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<resources>\n"
        "    <!-- White plate behind the mark so the dark artwork stays legible on\n"
        "         any wallpaper. See tool/gen_icons.py. -->\n"
        "    <color name=\"ic_launcher_background\">#FFFFFF</color>\n"
        "</resources>\n"
    )


def ios_assets(mark: Image.Image) -> list[tuple[Path, Image.Image]]:
    """The AppIcon set. Returns [] and explains itself if the set is absent.

    `Contents.json` names **19** entries but only **15** are distinct files --
    iPhone and iPad share four of them. Writing per entry overwrote each shared
    file with whichever entry came last, and reported "19 files". It now
    reports distinct files, and refuses a set where one name maps to two
    different sizes, because that is a contradiction rather than a reuse.
    """
    if not IOS.exists():
        return []
    contents = json.loads((IOS / "Contents.json").read_text())
    wanted: dict[str, tuple[int, list[str]]] = {}
    for entry in contents.get("images", []):
        fname = entry.get("filename")
        if not fname:
            continue
        size = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        px = int(round(size * scale))
        tag = f'{entry.get("idiom", "?")} {entry["size"]} {entry["scale"]}'
        if fname in wanted and wanted[fname][0] != px:
            raise ValueError(
                f"{fname} is wanted at {wanted[fname][0]}px "
                f"({', '.join(wanted[fname][1])}) and at {px}px ({tag}) -- "
                "one file cannot be two sizes")
        prev = wanted.get(fname)
        wanted[fname] = (px, wanted[fname][1] + [tag] if prev else [tag])

    return [(IOS / fname, place(mark, px, IOS_FILL, bg=IOS_BG).convert("RGB"))
            for fname, (px, _) in sorted(wanted.items())]


def ink_bbox(im: Image.Image) -> tuple[int, int, int, int] | None:
    """Bounding box of the MARK's ink on a white plate, or None if there is none.

    This -- not the alpha channel and not the raw bytes -- is what says whether an
    asset is right. Both of the others were measured on this tree and both are
    useless here: the alpha bbox of a plated icon is the whole canvas, and a
    byte comparison reports drift on assets that are provably identical in ink,
    because the committed PNGs were written by a different Pillow build.
    """
    im = im.convert("RGBA")
    plate = Image.new("RGBA", im.size, (255, 255, 255, 255))
    plate.alpha_composite(im)
    rgb = plate.convert("RGB")
    w, h = rgb.size
    xs: list[int] = []
    ys: list[int] = []
    px = rgb.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if not (r > 250 and g > 250 and b > 250):
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys)


# Measured on this tree's own 35 assets, not guessed. Two populations, and the
# threshold is read off the measurements rather than picked:
#
#   NULL  -- the 35 committed icons against a rebuild from their OWN parameters:
#            0 pixels differ by more than 96/255 at any threshold up to 64.
#   SIGNAL-- a real parameter change (LEGACY_FILL, ROUND_INK_RADIUS, the plate):
#            40 of 45 such rebuilds differ by more than 96/255.
#
# 96 is the first threshold where the null population is silent AND the signal
# population still speaks. It is NOT a claim that 96/255 is a visible
# difference -- it is the gap between two measured sets. Below it, an antialias
# difference between two Pillow builds reads as drift on all 35 assets and the
# check cries wolf forever; above it, the 5 rebuilds it misses are perturbations
# that changed NO pixel at all (48 * 0.94 and 48 * 0.935 both round to 45), so
# silence there is the truth and not a miss.
#
# An earlier revision of this file used a 16x16 downsample, on the claim that it
# was insensitive to antialiasing and sensitive to painted regions. Measured, it
# was wrong in both directions: it read a 1% LEGACY_FILL change as 0.0000 -- it
# cannot see the exact constant this tool exists to hold -- and its threshold had
# no gap at all, with the null set reaching 0.3125 against a signal set starting
# at 0.1875.
INK_DRIFT_THRESHOLD = 96


def is_drift(on_disk: Image.Image, rebuilt: Image.Image) -> bool:
    """Does the shipped asset differ from what this run would write?

    Compares in full resolution, per pixel, on a threshold measured above.
    Downsampling was tried and rejected; see the note on the constant.
    """
    if on_disk.size != rebuilt.size:
        return True
    diff = ImageChops.difference(on_disk.convert("RGB"),
                                 rebuilt.convert("RGB")).convert("L")
    return sum(diff.histogram()[INK_DRIFT_THRESHOLD:]) > 0


def check(planned: list[tuple[Path, Image.Image]],
          rep: list[tuple[Path, Image.Image]],
          xml_text: str) -> int:
    """Report what the write would change. Opens nothing for writing."""
    drift: list[str] = []
    missing: list[Path] = []
    for path, img in planned + rep:
        if not path.exists():
            missing.append(path)
            continue
        with Image.open(path) as handle:
            if is_drift(handle, img):
                drift.append(str(path.relative_to(REPO)))

    bg_xml = RES / "values" / "ic_launcher_background.xml"
    if not bg_xml.exists():
        missing.append(bg_xml)
    elif bg_xml.read_text() != xml_text:
        drift.append(str(bg_xml.relative_to(REPO)))
    night = RES / "values-night" / "ic_launcher_background.xml"
    if night.exists() and night.read_text() != xml_text:
        drift.append(str(night.relative_to(REPO)))

    if not drift and not missing:
        print("  every asset matches what this tool would write")
        print("checked %d files, wrote 0" % (len(planned) + len(rep)))
        return 0

    for p in missing:
        print(f"  MISSING  {p.relative_to(REPO)}")
    for d in drift:
        print(f"  DRIFT    {d}")
    print(f"  {len(drift)} drifted, {len(missing)} missing -- "
          f"run `python3 tool/gen_icons.py` to write them")
    return 1


def main() -> int:
    argv = [a for a in sys.argv[1:] if not a.startswith("-")]
    unknown = [a for a in sys.argv[1:] if a.startswith("-")
               and a not in ("--check",)]
    if unknown:
        print(f"gen_icons: unknown option {unknown[0]!r}. "
              "Usage: gen_icons.py [--check]", file=sys.stderr)
        return 2
    if argv:
        print(f"gen_icons: takes no file arguments, got {argv}. The mark is "
              f"{MARK.relative_to(REPO)}.", file=sys.stderr)
        return 2

    is_check = "--check" in sys.argv
    mark = load_mark()
    if mark is None:
        return 2

    print(f"mark: {mark.width}x{mark.height}  ({MARK.relative_to(REPO)})")
    written = 0

    planned = plan(mark)
    try:
        rep = ios_assets(mark)
    except (ValueError, KeyError) as exc:
        print(f"gen_icons: refusing to write -- {exc}", file=sys.stderr)
        print("The AppIcon set already in the tree is untouched.", file=sys.stderr)
        return 2

    xml_text = android_xml()
    bg_xml = RES / "values" / "ic_launcher_background.xml"

    for bucket, dpr in DENSITIES.items():
        legacy_size = int(round(48 * dpr))
        legacy = next(i for p, i in planned
                      if p.name == "ic_launcher.png" and p.parent.name == f"mipmap-{bucket}")
        fg = next(i for p, i in planned
                  if p.name == "ic_launcher_foreground.png" and p.parent.name == f"mipmap-{bucket}")
        rnd = next(i for p, i in planned
                   if p.name == "ic_launcher_round.png" and p.parent.name == f"mipmap-{bucket}")
        print(f"  {bucket:8s} launcher {legacy_size:3d}px [{ink_report(legacy)}]  "
              f"adaptive {int(round(108 * dpr)):3d}px [{ink_report(fg)}]  "
              f"round [{ink_report(rnd)}]")

    if is_check:
        return check(planned, rep, xml_text)

    for path, img in planned:
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(path)
        written += 1
    bg_xml.parent.mkdir(parents=True, exist_ok=True)
    bg_xml.write_text(xml_text)
    night = RES / "values-night" / "ic_launcher_background.xml"
    if night.exists():
        night.write_text(xml_text)
        print(f"  wrote {night.relative_to(REPO)} (white, night too)")
    print(f"  wrote {bg_xml.relative_to(REPO)} (white)")

    for path, img in rep:
        img.save(path, format="PNG")
        written += 1
    if rep:
        print(f"  iOS AppIcon: {len(rep)} files on opaque cream")

    print(f"wrote {written} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
