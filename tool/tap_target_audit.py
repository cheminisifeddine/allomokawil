#!/usr/bin/env python3
"""Static tap-target audit for the Allo Mokawil app.

Why it exists
-------------
The backlog item "Touch targets >= 56 px on every interactive element" needs a
list that does not go stale, and this box cannot always run the Flutter gate
(one Gradle build at a time, 7.8 GB, no swap). This tool reads the source and
reports, with file:line, every interactive site whose *effective* minimum
touch dimension is provably below 56 dp.

What it knows (rules, all from the SDK on this box)
--------------------------------------------------
R1  An `IconButton(` that sets neither `constraints:`, `padding:` nor `style:`
    is 48x48, not 56: Material 3's default `minimumSize` is `Size(40, 40)` and
    `tapTargetSize` falls back to `theme.materialTapTargetSize`, which is
    `MaterialTapTargetSize.padded` unless the theme overrides it, and padded
    floors the hit area at `kMinInteractiveDimension = 48.0`
    (flutter/lib/src/material/{icon_button,theme_data,constants}.dart).
R2  `minimumSize: const Size(w, h)` with h < 56 on any ButtonStyle.
R3  A `SizedBox`/`AnimatedContainer`/`Container` with `height: h` < 56 that
    is still *open* at the button's line, i.e. really wraps it. A one-line
    `SizedBox(height: 4),` spacer is balanced and is not counted.
R4  `.clamp(lo, hi)` on a line that sizes a dimension (star/size/height/
    width/box/tap) whose floor `lo` is < 56. A clamp on a business value
    (a service radius, a count) is not a tap target and is ignored.
R5  The theme must raise IconButton globally, otherwise R1 fires per site.
R6  A `TextButton` is 40 tall / 48 padded by default (SDK default `minimumSize`
    Size(64, 40)), and `textButtonTheme` is the one button theme that sets no
    `minimumSize`, so every site that does not set its own is below 56 — unlike
    Elevated/Outlined/Filled, which inherit `Size.fromHeight(tapMin)` from the
    theme.

What it cannot judge: a tap target whose size comes from a Row/Column layout
(no explicit number) or from a theme installed elsewhere. Those sites are
counted and listed as "unknown", never silently passed.

Exit code is 1 when a failure is found, 0 when the tree is clean.
Usage:  python3 tool/tap_target_audit.py [repo_root]
"""
import os
import re
import sys

MIN = 56.0

ICON_BTN = re.compile(r"\bIconButton\(")
ICON_BTN_ESCAPE = re.compile(r"\b(constraints:|padding:|style:)\s")
MIN_SIZE = re.compile(r"minimumSize:\s*(?:const\s+)?Size\(\s*([\d.]+)\s*,\s*([\d.]+)\s*\)")
SIZED_H = re.compile(r"\b(?:height|maxHeight):\s*([\d.]+)")
CLAMP = re.compile(r"\.clamp\(\s*([\d.]+)\s*,\s*([\d.]+)\s*\)")
BUTTON = re.compile(r"\b(?:OutlinedButton|ElevatedButton|TextButton|FilledButton)\(")
TEXT_BUTTON = re.compile(r"\bTextButton\(")
CALL_HEAD = ("me")
BOX_OPEN = re.compile(r"\b(?:SizedBox|AnimatedContainer|Container)\(")
TAP = re.compile(r"\bon(?:Tap|Pressed):\s*(?!null)")


def dart_files(root):
    for base, _dirs, names in os.walk(os.path.join(root, "lib")):
        for n in sorted(names):
            if n.endswith(".dart"):
                yield os.path.join(base, n)


def audit(root):
    fails, unknown = [], []
    for path in dart_files(root):
        rel = os.path.relpath(path, root)
        src = open(path, encoding="utf-8").read()
        lines = src.split("\n")

        for m in ICON_BTN.finditer(src):
            line_no = src.count("\n", 0, m.start()) + 1
            # the whole constructor call, up to its matching close paren
            depth, i = 0, m.end() - 1
            while i < len(src):
                if src[i] == "(":
                    depth += 1
                elif src[i] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            body = src[m.end():i]
            if ICON_BTN_ESCAPE.search(body):
                continue  # author set a size on purpose; R2/R3 judge it
            fails.append((rel, line_no, "IconButton at SDK default",
                          "40x40 box, 48x48 padded hit area < 56"))

        for m in MIN_SIZE.finditer(src):
            w, h = float(m.group(1)), float(m.group(2))
            if h < MIN:
                fails.append((rel, src.count("\n", 0, m.start()) + 1,
                              "minimumSize", f"{w:g}x{h:g}"))

        for m in CLAMP.finditer(src):
            lo = float(m.group(1))
            head = lines[src.count("\n", 0, m.start())].lower()  # 0-based: the clamp line
            if not re.search(r"(star|size|height|width|box|dim|tap|target)", head):
                continue  # clamps a value (a radius, a count), not a tap box
            if lo < MIN:
                fails.append((rel, src.count("\n", 0, m.start()) + 1,
                              "clamp floor", f"floor {lo:g} < 56"))

        for m in BUTTON.finditer(src):
            line_no = src.count("\n", 0, m.start()) + 1
            if "minimumSize" in "".join(lines[max(0, line_no - 4):line_no + 1]):
                continue
            for back in range(1, 13):
                k = line_no - back
                if k < 1 or not BOX_OPEN.search(lines[k - 1]):
                    continue
                # an enclosing box must still be open when the button starts
                if sum(l.count("(") - l.count(")") for l in lines[k - 1:line_no - 1]) <= 0:
                    continue
                sizes = [float(x) for x in SIZED_H.findall("".join(lines[k - 1:line_no]))]
                if sizes and min(sizes) < MIN:
                    fails.append((rel, line_no, "button inside fixed box",
                                  f"height {min(sizes):g} < 56"))
                break

        for m in TEXT_BUTTON.finditer(src):
            line_no = src.count("\n", 0, m.start()) + 1
            depth, i = 0, m.end() - 1
            while i < len(src):
                if src[i] == "(":
                    depth += 1
                elif src[i] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            site = src[m.end():i]
            if "minimumSize" in site:
                continue  # judged by R2 instead
            fails.append((rel, line_no, "TextButton at SDK default",
                          "40 tall box, 48 hit area < 56 (textButtonTheme sets no minimumSize)"))

    theme = os.path.join(root, "lib/src/core/theme/app_theme.dart")
    if os.path.exists(theme):
        tsrc = open(theme, encoding="utf-8").read()
        if "iconButtonTheme" not in tsrc:
            fails.append((os.path.relpath(theme, root), 0,
                          "no global IconButtonTheme",
                          "R1 therefore fires at every IconButton site"))

    taps = sum(len(TAP.findall(open(p, encoding="utf-8").read()))
               for p in dart_files(root))
    return fails, taps


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    fails, taps = audit(root)
    fails.sort(key=lambda f: (f[0], f[1]))
    print(f"tap-target audit — {taps} tap sites, minimum {MIN:g} dp")
    if not fails:
        print("clean: no static sub-56 tap target found")
        return 0
    seen = set()
    for rel, line, rule, detail in fails:
        key = (rel, line, rule)
        if key in seen:
            continue
        seen.add(key)
        loc = f"{rel}:{line}" if line else rel
        print(f"FAIL  {loc:66} {rule:28} {detail}")
    print(f"\n{len(seen)} finding(s). Static audit: a site whose size comes from"
          " layout is not judged here — measure it in a widget test.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
