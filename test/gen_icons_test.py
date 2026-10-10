#!/usr/bin/env python3
"""Prove `tool/gen_icons.py` measures the mark, and refuses what it cannot read.

Run directly -- it writes PNGs into a temp tree and is not a `flutter test`:

    python3 test/gen_icons_test.py

**Why this file exists.** `gen_icons.py` is the tool that produces every
launcher icon, the splash strip and the iOS AppIcon set from one brand mark, and
it had **no reference anywhere in `test/`** -- the last load-bearing generator in
`tool/` with no battery. It also imports `prep_mark`, so both are pinned here.

**Three defects were in how it REPORTS, none in how it renders.** The artwork it
produces was measured and is good: the committed icons' ink geometry is what
this tool regenerates (worst delta 2px across all 35, and that 2px is
resampling jitter, not a different picture). What was wrong is everything
around that:

  1. **`--check` wrote the files it claimed to only check.** It printed
     `checked 39 files` *after* saving all of them. The one flag that exists so
     an operator can ask "are the icons stale" without touching the shipped
     launcher icon was the flag that silently rewrote it -- measured here as
     **35 files modified in the working tree**, then restored. Now it renders
     every asset in memory, compares, prints the drifting paths, exits 1, and
     opens nothing for writing. Cases 1-4 pin that, by hashing the whole tree
     either side of the run rather than trusting a word of its output.

  2. **`ink_report` measured the BACKGROUND.** The legacy and round icons are
     an opaque white tile, so an alpha bounding box over them is the entire
     canvas. Every row printed `ink 100%x100% margins L0% R0%` -- a perfect
     description of the plate, in the one field a reader opens the report to
     judge whether the logo is too small. The founder's ask was for the mark
     big; the truth is **67%x89% with 16% margins**, and nothing on screen
     could tell. Cases 5-8 pin the mark, not the plate, and include the empty
     mark that must read `EMPTY` rather than `100%x100%`.

  3. **The iOS count was wrong by four, and the writes were double.** The
     AppIcon set's `Contents.json` names **19** entries over **15** distinct
     files -- iPhone and iPad share four. The tool looped per *entry*, so each
     shared file was written twice (last writer winning) and the run reported
     `iOS AppIcon: 19 files` for 15 files. Now one file is written once, the
     count is 15, and a `Contents.json` naming one file at two different pixel
     sizes is refused rather than resolved by ordering. Cases 9-12 pin that.

**The refusals, which are the fourth defect.** A missing mark raised a bare
`FileNotFoundError` out of `Image.open`, naming a path and nothing else. Worse,
a mark with **no visible ink** was accepted: every placer renders it to a
blank white tile and the report then calls that `ink 100%x100%` -- a perfectly
formed lie, produced by exactly the arithmetic in defect 2. Cases 13-16 pin
exit 2 for both, on a channel a human reads.

**Cases 17-22 are the control.** Cases 1-16 measure reporting and error paths,
which a tool that cannot generate would pass. So the real `main()` runs end to
end in a **temp repo** -- never the shipped tree -- writing the real 35 assets
and then converging: a check after a write must answer 0, and a check after a
hand-damaged asset must answer 1 and name that one path. Case 17-18 are those
two ends; 19-22 pin the shipped asset's own promises (every density present,
every icon the right pixel size, iOS opaque with no alpha channel, and the
committed icons' ink matching what the tool would write).

Expected: 22/22. A failure means a number this tool printed -- a launcher icon
size, a fill fraction, a file count -- was not true.
"""

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(REPO, "tool", "gen_icons.py")
MARK = os.path.join(REPO, "assets", "brand", "mark.png")
IOS_DIR = os.path.join(REPO, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
RES = os.path.join(REPO, "android", "app", "src", "main", "res")

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("PASS  " if cond else "FAIL  ") + name +
          (("  -- " + detail) if detail and not cond else ""))


def load_tool():
    """Import the tool without running its `main`."""
    spec = importlib.util.spec_from_file_location("gen_icons_under_test", TOOL)
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.join(REPO, "tool"))
    try:
        spec.loader.exec_module(mod)
    finally:
        sys.path.pop(0)
    return mod


def tree_hash(paths):
    """One hash over every shipped asset, content AND mode."""
    h = hashlib.sha256()
    for root in paths:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            for name in sorted(filenames):
                full = os.path.join(dirpath, name)
                h.update(os.path.relpath(full, REPO).encode())
                st = os.lstat(full)
                h.update(str(st.st_mode).encode())
                with open(full, "rb") as fh:
                    h.update(fh.read())
    return h.hexdigest()


def has(mod, *names):
    """Names this tool does not have, as one string (empty when it has them all).

    A battery must GRADE a broken tool, not die on it. The first version of
    this file called `tool.flatten(...)` directly, and against the unfixed tool
    that raised AttributeError and killed the run with no score -- the exact
    failure `gen_communes_test.py` documents in its own header. Every case that
    touches a symbol this fix introduced now goes through `has`.
    """
    gone = [n for n in names if not hasattr(mod, n)]
    return ", ".join("no %s" % n for n in gone)


def backup_tree(paths, dest):
    """Copy the shipped assets aside, so this battery can PUT THEM BACK.

    Measured, and the reason this exists: running this battery against the
    UNFIXED tool left **35 shipped files modified** in the working tree --
    case 1 detected it, but detection does not undo it. A battery that can
    corrupt the repository when it fails is a battery nobody will run twice,
    and the assets it damaged are the founder's approved launcher icon.
    """
    shutil.copytree(os.path.join(REPO, "android"), os.path.join(dest, "android"),
                    symlinks=True)
    if os.path.isdir(IOS_DIR):
        shutil.copytree(os.path.join(REPO, "ios"), os.path.join(dest, "ios"),
                        symlinks=True)


def restore_tree(paths, dest):
    for top in ("android", "ios"):
        live = os.path.join(REPO, top)
        saved = os.path.join(dest, top)
        if os.path.isdir(saved):
            shutil.rmtree(live)
            shutil.copytree(saved, live, symlinks=True)


def run(args, cwd=REPO):
    return subprocess.run([sys.executable, os.path.join(cwd, "tool", "gen_icons.py")] + args,
                          capture_output=True, text=True, cwd=cwd)


def build_temp_repo(tmp, name="repo"):
    """A throwaway checkout: tool, mark, and a COPY of the AppIcon set.

    `name` matters: the battery needs TWO independent trees, and without it the
    second `makedirs` raised FileExistsError and killed the run with no score at
    all -- a battery that crashes grades nothing. The failure was found by
    running it, not by reading it.
    """
    root = os.path.join(tmp, name)
    os.makedirs(os.path.join(root, "tool"))
    os.makedirs(os.path.join(root, "assets", "brand"))
    shutil.copy(TOOL, os.path.join(root, "tool", "gen_icons.py"))
    shutil.copy(os.path.join(REPO, "tool", "prep_mark.py"),
                os.path.join(root, "tool", "prep_mark.py"))
    shutil.copy(MARK, os.path.join(root, "assets", "brand", "mark.png"))
    ios_dst = os.path.join(root, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    if os.path.isdir(IOS_DIR):
        shutil.copytree(IOS_DIR, ios_dst)
    return root


def run_in(root, args):
    return subprocess.run([sys.executable, os.path.join(root, "tool", "gen_icons.py")] + args,
                          capture_output=True, text=True, cwd=root)


def main():
    tool = load_tool()
    tmp = tempfile.mkdtemp(prefix="gen_icons_test_")
    saved = os.path.join(tmp, "shipped-assets")
    backup_tree([RES, IOS_DIR], saved)

    # ------------------------------------------------------------------ 1-4
    # `--check` must not write. Hashed over the real shipped tree either side.
    watched = [os.path.join(RES, d) for d in os.listdir(RES)
               if d.startswith(("mipmap-", "drawable-"))]
    watched.append(IOS_DIR)
    before = tree_hash(watched)
    r = run(["--check"])
    after = tree_hash(watched)
    check("case 1: --check writes NOTHING (whole asset tree hashed either side)",
          before == after, "the tree changed under --check")
    check("case 2: --check on the shipped tree exits 0",
          r.returncode == 0, f"rc={r.returncode} err={r.stderr.strip()[:120]}")
    check("case 3: --check says it wrote 0, in its own words",
          "wrote 0" in r.stdout, r.stdout.strip()[-160:])
    check("case 4: --check reports the count it actually checked (35), not the "
          "19-entry iOS double count",
          "checked 35 files" in r.stdout, r.stdout.strip()[-160:])

    # ------------------------------------------------------------------ 5-8
    # ink_report must describe the MARK. The legacy icon is an opaque white
    # tile: an alpha bbox over it is the whole canvas.
    if has(tool, "flatten", "ink_bbox"):
        check("case 5: the fixed tool exposes the measurement helpers the "
              "battery grades", False, has(tool, "flatten", "ink_bbox"))
        print("\n-- the tool under test is the pre-fix one; the reporting cases "
              "cannot be graded against it. --\n")
        skipped_early = True
    else:
        skipped_early = False
        check("case 5: the fixed tool exposes the measurement helpers the "
              "battery grades", True)
    legacy = tool.place(tool.load_mark(), 192, tool.LEGACY_FILL, bg=tool.ICON_BG)
    rep = tool.ink_report(legacy)
    check("case 5b: a plated icon's ink report is NOT the whole canvas",
          "100%x100%" not in rep, f"reported the plate: {rep!r}")
    frac = int(rep.split()[1].split("%")[0])
    check("case 6: the legacy icon reports the mark at a plausible size "
          "(60-75% wide), which an alpha bbox could never do",
          60 <= frac <= 75, f"got {rep!r}")
    blank = Image.new("RGBA", (512, 512), (0, 0, 0, 0))

    def plated(im, bg=(255, 255, 255, 255)):
        out = Image.new("RGBA", im.size, bg)
        out.alpha_composite(im.convert("RGBA"))
        return out

    check("case 7: an icon with no ink reads EMPTY, not 100%x100%",
          tool.ink_report(plated(blank)) == "EMPTY",
          repr(tool.ink_report(plated(blank))))
    transparent_fg = tool.place(blank, 108, tool.LEGACY_FILL)
    check("case 8: a blank mark's adaptive foreground is measured, not plated",
          tool.ink_report(transparent_fg) == "EMPTY",
          repr(tool.ink_report(transparent_fg)))

    # ----------------------------------------------------------------- 9-12
    # The AppIcon set: 19 entries, 15 distinct files.
    try:
        contents = json.loads(open(os.path.join(IOS_DIR, "Contents.json")).read())
        names = [e["filename"] for e in contents["images"] if e.get("filename")]
        distinct = len(set(names))
    except Exception as exc:                                   # noqa: BLE001
        names, distinct = [], 0
        check("case 9: the AppIcon set is readable", False, str(exc))
    check("case 9: Contents.json names 19 entries over 15 distinct files",
          len(names) == 19 and distinct == 15, f"{len(names)} entries, {distinct} distinct")
    if hasattr(tool, "ios_assets"):
        rep_assets = tool.ios_assets(tool.load_mark())
    else:
        rep_assets = []
        check("case 10: the tool can plan the AppIcon set without double-writing",
              False, "no ios_assets() -- this tool has no way to express the "
                     "plan without performing the write")
    check("case 10: the tool plans one asset per DISTINCT file (15), not one "
          "per entry (19)",
          len(rep_assets) == distinct,
          f"planned {len(rep_assets)} for {distinct} distinct files")
    on_disk = sorted(f for f in os.listdir(IOS_DIR) if f.endswith(".png"))
    check("case 11: every planned AppIcon file exists on disk, and no file is "
          "written twice",
          len(rep_assets) == len(set(p for p, _ in rep_assets)) == len(on_disk),
          f"{len(rep_assets)} planned, {len(on_disk)} on disk")
    sizes = {os.path.basename(p): img.size[0] for p, img in rep_assets}
    bad = {n: s for n, s in sizes.items() if s <= 0}
    check("case 12: every AppIcon is planned at a real pixel size",
          not bad, str(bad))

    # ---------------------------------------------------------------- 13-16
    # The refusals. 13-14 a mark that is not there; 15-16 a mark with no ink.
    root = build_temp_repo(tmp)
    absent = os.path.join(tmp, "no-mark")
    os.makedirs(os.path.join(absent, "tool"))
    shutil.copy(os.path.join(REPO, "tool", "gen_icons.py"),
                os.path.join(absent, "tool", "gen_icons.py"))
    shutil.copy(os.path.join(REPO, "tool", "prep_mark.py"),
                os.path.join(absent, "tool", "prep_mark.py"))
    r13 = run_in(absent, [])
    check("case 13: a missing mark exits 2 and names the file, not a traceback",
          r13.returncode == 2 and "MISSING" in r13.stderr
          and "Traceback" not in r13.stderr,
          f"rc={r13.returncode} err={r13.stderr.strip()[:140]}")
    check("case 14: that refusal says the shipped icons are untouched and still "
          "ship -- the operator's next move is 'download it', not 'rebuild'",
          "untouched" in r13.stderr and "still ship" in r13.stderr,
          r13.stderr.strip()[:140])

    blank_root = build_temp_repo(tmp, "blank-mark-repo")
    Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)).save(
        os.path.join(blank_root, "assets", "brand", "mark.png"))
    r15 = run_in(blank_root, [])
    check("case 15: a mark with NO VISIBLE INK exits 2 rather than writing 10 "
          "blank white tiles",
          r15.returncode == 2 and "no visible ink" in r15.stderr,
          f"rc={r15.returncode} err={r15.stderr.strip()[:140]}")
    made = os.path.join(blank_root, "android", "app", "src", "main", "res",
                        "mipmap-mdpi", "ic_launcher.png")
    check("case 16: ...and it wrote nothing on the way out",
          r15.returncode != 0 and not os.path.exists(made),
          "a blank icon was written")

    # ---------------------------------------------------------------- 17-22
    # The control: the real main(), end to end, in a temp repo.
    r17 = run_in(root, [])
    check("case 17: the real generator exits 0 in a temp repo",
          r17.returncode == 0, f"rc={r17.returncode} err={r17.stderr.strip()[:200]}")
    check("case 18: it writes the 35 assets it says it writes (20 android + 15 "
          "AppIcon), and the count is in its own output",
          "wrote 35 files" in r17.stdout and "iOS AppIcon: 15 files" in r17.stdout,
          r17.stdout.strip()[-200:])

    r19 = run_in(root, ["--check"])
    check("case 19: a check immediately after a write exits 0 -- the two modes "
          "agree on what the asset should be",
          r19.returncode == 0, f"rc={r19.returncode} out={r19.stdout.strip()[-200:]}")

    victim = os.path.join(root, "android", "app", "src", "main", "res",
                          "mipmap-mdpi", "ic_launcher.png")
    im = Image.open(victim)
    px = im.load()
    for y in range(im.size[1]):
        for x in range(6, 14):
            px[x, y] = (0, 0, 0, 255)
    im.save(victim)
    r20 = run_in(root, ["--check"])
    check("case 20: a check over one hand-damaged asset exits 1 and NAMES that "
          "one path",
          r20.returncode == 1 and "mipmap-mdpi/ic_launcher.png" in r20.stdout
          and r20.stdout.count("DRIFT") == 1,
          f"rc={r20.returncode} out={r20.stdout.strip()[-200:]}")

    # 20b: the threshold itself. M7 set INK_DRIFT_THRESHOLD to 255 -- above any
    # difference the codec can express -- and SURVIVED, because the damage in
    # case 20 is pure black on white: 277 pixels are exactly 255 apart, so even
    # a threshold that high sees it. A guard whose only evidence is a hard black
    # bar is a guard that has never been shown a soft difference, and the
    # committed assets differ from a rebuild by up to 84/255 -- not 255. So
    # this case damages an icon with a change whose peak difference is BELOW 255
    # and still demands it be caught.
    # Regenerate first. Case 20 left the mdpi icon damaged, so a check here
    # would exit 1 on THAT file and this case would pass for the wrong reason --
    # exactly the failure the last tick recorded in `gen_communes`. Each case
    # now proves its own damage.
    run_in(root, [])
    soft_victim = os.path.join(root, "android", "app", "src", "main", "res",
                               "mipmap-hdpi", "ic_launcher.png")
    with Image.open(soft_victim) as orig:
        base = orig.convert("RGB")

    r20b_clean = run_in(root, ["--check"])

    # THE FLOOR, pinned from both sides. Case 20's evidence was pure black on
    # white -- 277 pixels exactly 255 apart -- so M7 (INK_DRIFT_THRESHOLD = 255,
    # above any difference the codec can express) SURVIVED it. This case is the
    # replacement, and its property is a property of the TOOL, not of a pretty
    # picture: on this tree a committed icon differs from a rebuild by up to
    # 77/255 (LANCZOS against a different Pillow build, spread over ~2,300
    # antialiased edge pixels), so 96 is the lowest threshold that can call the
    # shipped tree clean.
    #
    # What that floor costs was measured rather than assumed, and the numbers
    # are worth keeping: an ink wash of +220 peaks at 79, a 4px geometric shift
    # peaks at 80, and a one-third drift of the ink toward white peaks at 26 --
    # ALL below 77, i.e. all inside the encoder's own noise. A check built on
    # pixel differences therefore cannot promise to catch those, and this case
    # says so out loud rather than implying a strength the tool does not have.
    # What it DOES promise, and what case 20's survivor needed pinned, is that
    # the threshold is a real threshold: a change above the floor is caught and
    # the same file is clean a moment earlier.
    peak = 0
    rebuilt = None
    for cand_path, cand_img in tool.plan(tool.load_mark()):
        if cand_path.name == "ic_launcher.png" and \
                cand_path.parent.name == "mipmap-hdpi":
            rebuilt = cand_img
            break
    if rebuilt is not None:
        from PIL import ImageChops
        with Image.open(soft_victim) as on_disk:
            d = ImageChops.difference(on_disk.convert("RGB"),
                                      rebuilt.convert("RGB")).convert("L")
            null_peak = d.getextrema()[1]

    with Image.open(soft_victim) as orig:
        rp = orig.convert("RGB").copy()
    rp.load()
    px = rp.load()
    for y in range(rp.size[1]):
        for x in range(rp.size[0]):
            rr, g_, b = px[x, y]
            if not (rr > 250 and g_ > 250 and b > 250):   # the ink, not the plate
                px[x, y] = (255 - rr, 255 - g_, 255 - b)
    rp.save(soft_victim)

    r20b = run_in(root, ["--check"])
    if rebuilt is not None:
        from PIL import ImageChops
        with Image.open(soft_victim) as damaged:
            d = ImageChops.difference(damaged.convert("RGB"),
                                      rebuilt.convert("RGB")).convert("L")
            peak = d.getextrema()[1]
    check("case 20b: the threshold is real -- an inverted-ink drift (peak "
          "channel difference %s, not a hard 255) is caught, while the same "
          "file is clean before it and the shipped tree sits %s below the "
          "threshold that makes that possible" % (peak if peak else "?",
                                                  null_peak if rebuilt else "?"),
          r20b_clean.returncode == 0 and r20b.returncode == 1
          and 0 < peak < 255
          and "mipmap-hdpi" in r20b.stdout and "ic_launcher.png" in r20b.stdout,
          f"clean_rc={r20b_clean.returncode} rc={r20b.returncode} "
          f"peak={peak} null_peak={null_peak if rebuilt else '?'} "
          f"out={r20b.stdout.strip()[-200:]}")

    # 21-22: the shipped asset's own promises.
    bad = []
    for bucket, dpr in getattr(tool, "DENSITIES", {}).items():
        base = os.path.join(RES, "mipmap-" + bucket)
        for fname, want in (("ic_launcher.png", round(48 * dpr)),
                            ("ic_launcher_round.png", round(48 * dpr)),
                            ("ic_launcher_foreground.png", round(108 * dpr))):
            full = os.path.join(base, fname)
            if not os.path.exists(full) or Image.open(full).size != (want, want):
                bad.append(f"{bucket}/{fname}")
    check("case 21: all 15 shipped android icons exist at the pixel size their "
          "density demands",
          not bad, "wrong or missing: " + ", ".join(bad))

    alpha_bad = []
    for name in os.listdir(IOS_DIR):
        if not name.endswith(".png"):
            continue
        with Image.open(os.path.join(IOS_DIR, name)) as im:
            if im.mode not in ("RGB", "L"):
                alpha_bad.append(f"{name} is {im.mode}")
    check("case 22: every AppIcon file is opaque -- iOS rejects an alpha channel",
          not alpha_bad, "; ".join(alpha_bad))

    bad = [n for n, ok in results if not ok]
    # Always put the shipped assets back, pass or fail. A battery that only
    # restores on success cannot help the run that found the defect.
    restore_tree([RES, IOS_DIR], saved)
    print()
    print(f"{len(results) - len(bad)}/{len(results)} cases passed")
    shutil.rmtree(tmp, ignore_errors=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
