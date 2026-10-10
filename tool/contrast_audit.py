#!/usr/bin/env python3
"""WCAG contrast audit for the Allo Mokawil palette and its real renders.

Two questions, answered without PIL or numpy (neither is installed):

  1. Does every foreground/background pair the app declares clear WCAG AA
     (4.5:1 for body text, 3:1 for large text and for meaningful graphics)?
  2. Do the pairs we claim actually appear on screen? A ratio computed from
     two hex strings is only meaningful if those two colours really are drawn
     together — so this reads the coverage that the design shots back up.

The palette is parsed straight out of `lib/src/core/theme/app_theme.dart`
instead of being copied here, so a token change can never leave a stale
audit behind.

Usage:
  contrast_audit.py token                  # maths only, from the theme file
  contrast_audit.py shots /tmp/shots       # + presence check in real PNGs
  contrast_audit.py shots /tmp/shots --json
"""
import argparse
import glob
import json
import math
import os
import re
import sys

_HEX6 = re.compile(r"[0-9A-F]{6}")

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

THEME = os.path.join(HERE, "..", "lib", "src", "core",
                     "theme", "app_theme.dart")

# (token or literal fg, token or literal bg, kind) — kind picks the threshold.
# "body" 4.5:1 · "large" 3:1 · "graphic" 3:1 (WCAG 1.4.11 non-text).
PAIRS = [
    ("textPrimary", "bg", "body"),
    ("textPrimary", "surfaceAlt", "body"),
    ("textSecondary", "bg", "body"),
    ("textSecondary", "surfaceAlt", "body"),
    ("textMuted", "bg", "body"),
    ("textMuted", "surfaceAlt", "body"),
    ("textMuted", "accentWash", "body"),
    ("navy", "accent", "body"),          # ink that sits on the gold CTA
    ("onNavy", "navy", "body"),
    ("onNavyMuted", "navy", "body"),
    ("onNavyMuted", "navyDeep", "body"),
    ("accent", "navy", "body"),
    ("accentDeep", "accentWash", "body"),
    ("accentDeep", "bg", "body"),
    ("success", "successWash", "body"),
    ("danger", "dangerWash", "body"),
    ("info", "infoWash", "body"),
    ("success", "bg", "body"),
    ("danger", "bg", "body"),
    ("info", "bg", "body"),
    # ── Meaningful graphics (WCAG 1.4.11, 3:1) ─────────────────────────────
    # The star glyph is drawn on white, on `surfaceAlt` cards and on the
    # `accentWash` tiles, so all three are checked.
    ("star", "bg", "graphic"),
    ("star", "surfaceAlt", "graphic"),
    ("star", "accentWash", "graphic"),
    ("star", "navy", "graphic"),
    # The unselected half of the rating input — a control track, not a divider.
    ("starEmpty", "bg", "graphic"),
    ("starEmpty", "surfaceAlt", "graphic"),
    # Outline of a secondary button: the only thing marking the tap target.
    ("controlLine", "bg", "graphic"),
    ("controlLine", "surfaceAlt", "graphic"),
    # Decorative only, judged at no threshold — carried so the ratio is on the
    # record. `line` is the card hairline and the divider; it must stay light
    # or the calm canvas dies. It is not the boundary of any control (that is
    # `controlLine`) and it never carries meaning on its own.
    ("line", "bg", "decor"),
]

NEED = {"body": 4.5, "large": 3.0, "graphic": 3.0, "decor": 0.0}


def parse_palette(path):
    """Every `static const Color name = Color(0xAARRGGBB);` in the theme."""
    src = open(path, encoding="utf-8").read()
    out = {}
    for name, argb in re.findall(
            r"static const Color (\w+)\s*=\s*Color\(0x([0-9A-Fa-f]{8})\)", src):
        out[name] = argb[2:].upper()          # drop the alpha channel
    return out


def _chan(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def luminance(hex6):
    r, g, b = (int(hex6[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * _chan(r) + 0.7152 * _chan(g) + 0.0722 * _chan(b)


def ratio(fg, bg):
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


#: Decimals the ratio is printed at. The row's MARK is decided on the exact
#: double; this only governs the number printed beside it.
PRINT_DP = 3

#: A row whose exact ratio sits within this of its threshold is printed as
#: EDGE. It is not a fudge factor -- it exists because the printed number is
#: necessarily rounded, and "4.5" beside a FAIL is a lie a reader cannot see.
EDGE_BAND = 0.01


def printed_ratio(raw, dp=PRINT_DP):
    """`raw` at `dp` decimals, **never rounded up**.

    The mark is decided on the exact double, so the number printed beside it
    must not disagree with it. Rounding can: `#959595` on white is
    `2.995346`, which used to print `3.00 (need 3.0)` directly above a FAIL
    marker, and raising the precision does not remove the hole, it moves it --
    over all 16.7M sRGB colours the largest value that still lands within one
    unit in the last place *below* a threshold is `2.999999768`
    (`#989A30` on white), which prints `3.0`. Flooring is what makes the
    invariant true by construction instead of by luck: `printed <= raw`, so a
    row judged FAIL can never print at or above its threshold. The error is
    bounded by one unit in the last place and is one-sided, which is why
    EDGE_BAND exists -- a row that close to the line is named, not rounded
    through.
    """
    return math.floor(raw * (10 ** dp)) / (10 ** dp)


def edge(raw, need):
    return abs(raw - need) <= EDGE_BAND


def is_hex6(v):
    return isinstance(v, str) and len(v) == 6 and _HEX6.fullmatch(v) is not None


def resolve(token, palette):
    """The six hex digits for `token`, or **None** when it names nothing.

    A pair in PAIRS may name a theme token or carry a literal `#RRGGBB`. It
    used to return `token.lstrip("#").upper()` for anything missing from the
    palette, so a token DELETED from `app_theme.dart` came back as the string
    `"textMuted"` and the tool died two lines later with
    `ValueError: invalid literal for int() with base 16: 'TE'`. That is the
    wrong answer twice over: the crash names the arithmetic, not the cause,
    and the `is None` guard in `token_report` written to catch it was dead
    code that never once fired.
    """
    if token in palette:
        return palette[token]
    lit = token.lstrip("#").upper()
    return lit if is_hex6(lit) else None


def token_report(palette):
    """One row per declared pair, every time -- never a silently dropped one."""
    rows = []
    for fg_t, bg_t, kind in PAIRS:
        fg, bg = resolve(fg_t, palette), resolve(bg_t, palette)
        if fg is None or bg is None:
            # A pair the palette cannot answer is UNRESOLVED, not absent. It
            # used to be skipped, which would have printed "28/28 judged
            # pairs pass" over 27 pairs actually measured.
            rows.append({
                "fg": fg_t, "bg": bg_t, "fg_hex": None, "bg_hex": None,
                "kind": kind, "ratio": None, "raw": None, "need": NEED[kind],
                "pass": False, "unresolved": True, "edge": False,
            })
            continue
        raw = ratio(fg, bg)
        rows.append({
            "fg": fg_t, "bg": bg_t, "fg_hex": fg, "bg_hex": bg, "kind": kind,
            "ratio": printed_ratio(raw), "raw": raw, "need": NEED[kind],
            "pass": raw >= NEED[kind], "unresolved": False,
            "edge": edge(raw, NEED[kind]),
        })
    return rows


def _histogram(path, step=2):
    # Imported lazily and resolved relative to this file. The module used to
    # be sys.path-inserted from a hardcoded absolute path on a machine that
    # no longer exists; the import failing was then swallowed per file, so
    # the audit reported every pair as "not drawn in any shot" and still
    # exited 0. A missing decoder is a hard error, never a quiet result.
    from png_read import read_png
    w, h, rows = read_png(path)
    counts = {}
    for y in range(0, h, step):
        row = rows[y]
        for x in range(0, w, step):
            i = x * 3
            key = (row[i] << 16) | (row[i + 1] << 8) | row[i + 2]
            counts[key] = counts.get(key, 0) + 1
    return counts


def presence(rows, shots_dir):
    """Which design shots really draw both colours of a pair together.

    Counts are sampled every 2nd pixel; a pair counts as present when the
    background shows at least 40 samples and the ink at least 25, which is
    enough to rule out a stray antialiasing pixel being mistaken for a pair.
    """
    files = sorted(glob.glob(os.path.join(shots_dir, "*.png")))
    wanted = {(r["bg_hex"], r["fg_hex"]): [] for r in rows}
    unreadable = []
    for f in files:
        try:
            hist = _histogram(f)
        except Exception as exc:                       # unreadable PNG
            print(f"  ! {os.path.basename(f)}: {exc}", file=sys.stderr)
            unreadable.append(os.path.basename(f))
            continue
        for (bg, fg), seen in wanted.items():
            nb = hist.get(int(bg, 16), 0)
            nf = hist.get(int(fg, 16), 0)
            if nb >= 40 and nf >= 25:
                seen.append({"shot": os.path.basename(f), "bg_px": nb,
                             "fg_px": nf})
    for r in rows:
        r["shots"] = wanted[(r["bg_hex"], r["fg_hex"])]
        r["present"] = bool(r["shots"])
    if not files:
        raise SystemExit(f"no PNGs in {shots_dir} — nothing was checked")
    if len(unreadable) == len(files):
        # Every shot failed to decode. Saying "not drawn in any shot" here
        # would be a lie: the tool never looked at a single pixel.
        raise SystemExit(
            f"could not read any of the {len(files)} PNGs in {shots_dir} "
            f"(e.g. {unreadable[0]}: see above) — the audit did not run")
    if unreadable:
        print(f"  note: {len(unreadable)}/{len(files)} shots unreadable, "
              f"presence judged on the rest", file=sys.stderr)
    return len(files) - len(unreadable)


def verdict(rows):
    """(judged, failed, unresolved, edged) -- the numbers one exit code needs."""
    judged = [r for r in rows if r["kind"] != "decor"]
    return (len(judged),
            len([r for r in judged
                 if not r["pass"] and not r["unresolved"]]),
            len([r for r in judged if r["unresolved"]]),
            len([r for r in judged if r["edge"]]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["token", "shots"])
    ap.add_argument("dir", nargs="?")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    palette = parse_palette(os.path.abspath(THEME))
    rows = token_report(palette)
    total_shots = 0
    if args.mode == "shots":
        if not args.dir:
            ap.error("shots needs a directory of PNGs")
        total_shots = presence(rows, args.dir)

    judged, bad, missing, edged = verdict(rows)

    if args.json:
        # This branch returned 0 unconditionally, so `--json` reported success
        # on a palette that failed: a synthetic palette with three pairs under
        # threshold printed 28 rows with `"pass": false` and still exited 0.
        # Anything piping this into a script got a green verdict from a red
        # palette. The exit code is now the SAME number both branches return.
        print(json.dumps({"shots": total_shots, "pairs": rows}, indent=2))
        return 1 if (bad or missing) else 0

    print(f"palette: {len(palette)} tokens from {os.path.basename(THEME)}")
    decor = 0
    for r in rows:
        if r["kind"] == "decor":
            decor += 1
            mark = "----"
        elif r["unresolved"]:
            mark = "MISS"
        elif r["edge"]:
            mark = "EDGE"
        else:
            mark = "PASS" if r["pass"] else "FAIL"
        if r["unresolved"]:
            where = "  token not in the palette — not measured"
        elif r["edge"]:
            where = ("  within %s of the threshold — judge the raw value"
                     % EDGE_BAND)
        elif args.mode == "shots":
            if r["present"]:
                s = r["shots"][0]
                where = (f"  in {len(r['shots'])}/{total_shots} shots "
                         f"(e.g. {s['shot']})")
            else:
                where = "  not drawn in any shot"
        else:
            where = ""
        shown = "  n/a  " if r["ratio"] is None else f"{r['ratio']:6.3f}"
        print(f"  {mark}  {shown} (need {r['need']})  "
              f"{r['fg']} on {r['bg']}{where}")
    print(f"\n{judged - bad - missing}/{judged} judged pairs pass, "
          f"{bad} below threshold"
          + (f", {missing} unresolved" if missing else "")
          + (f", {edged} on the threshold" if edged else "")
          + (f" ({decor} decorative pair(s) not judged)" if decor else ""))
    return 1 if (bad or missing) else 0


if __name__ == "__main__":
    sys.exit(main())
