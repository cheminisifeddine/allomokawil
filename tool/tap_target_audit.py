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

R7  A hand-rolled tap -- `InkWell(` / `GestureDetector(` with a non-null
    `onTap:` -- whose own child is a box with an explicit dimension below 56.
    The hit area of a hand-rolled tap *is* its child, so `Container(width: 26,
    height: 26)` behind a `GestureDetector` is a 26 dp target no matter what
    the theme says; `iconButtonTheme` and `textButtonTheme` cannot reach it.
    A dimension that comes from layout (Expanded/Row/Column/Padding) is not
    judged -- those sites are listed as ADVISORY with their padding numbers.

R8  `Checkbox(` / `Switch(` / `Radio(` at the framework default are 48 dp
    padded (kMinInteractiveDimension), below 56, but only *if* nothing around
    them is bigger. ADVISORY, not a failure: the row that wraps the app's one
    checkbox adds v6 padding and is genuinely 60 dp tall.

Exit code is 1 while a *provable* sub-56 site remains. ADVISORY sites are
printed but do not fail the tool: their size can only be settled by measuring
the real hit rect in a widget test (`test/tap_target_test.dart`), and a static
tool that guesses would send the next loop to "fix" a control that is fine.
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

# --- R7/R8: hand-rolled taps and framework-default 48 dp controls -----------
TAP_WIDGET = re.compile(r"\b(InkWell|GestureDetector)\(")
BOX = re.compile(r"\b(?:SizedBox|AnimatedContainer|Container)\(")
EXPLICIT_W = re.compile(r"\bwidth:\s*([\d.]+)\b")
EXPLICIT_H = re.compile(r"\bheight:\s*([\d.]+)\b")
PAD_SYM = re.compile(r"padding:\s*(?:const\s+)?EdgeInsets\.symmetric\(([^)]*)\)")
PAD_ALL = re.compile(r"padding:\s*(?:const\s+)?EdgeInsets\.all\(([\d.]+)\)")
VERT = re.compile(r"vertical:\s*([\d.]+)")
HORIZ = re.compile(r"horizontal:\s*([\d.]+)")
# A widget in this list between the tap and its box means the hit area is not
# the box alone -- layout decides, so the site becomes ADVISORY, never a FAIL.
LAYOUT_BETWEEN = re.compile(
    r"\b(?:Padding|Column|Row|Expanded|Flexible|Stack|Align|Center|Wrap|"
    r"ListView|Positioned|Table|Spacer|SafeArea|SingleChildScrollView|"
    r"IntrinsicHeight|ConstrainedBox)\(")
DEFAULT48 = re.compile(r"\b(Checkbox|Switch|Radio)\(")
# A `width:` inside a Border/BorderSide/BorderRadius is a stroke or a curve, not
# a size, and a `SizedBox` further down is somebody else's box: only the box's own
# argument list counts.
DECOR_CALL = re.compile(
    r"\b(?:Border|BorderSide|BorderRadius|BoxShadow|BoxConstraints)\.[A-Za-z]+\([^()]*\)")
OWN_ARGS = re.compile(r"\bchild:|\bchildren:")



def call_body(src, open_idx):
    """Body of the constructor call whose '(' sits at open_idx."""
    depth, i = 0, open_idx
    while i < len(src):
        c = src[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return src[open_idx + 1:i], i
        i += 1
    return src[open_idx + 1:], len(src)


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

    advisory = []
    for path in dart_files(root):
        rel = os.path.relpath(path, root)
        src2 = open(path, encoding="utf-8").read()

        for m in TAP_WIDGET.finditer(src2):
            line_no = src2.count("\n", 0, m.start()) + 1
            body, _end = call_body(src2, m.end() - 1)
            if not re.search(r"\bon(?:Tap|Pressed):\s*(?!null)", body):
                continue  # not a tap
            box = BOX.search(body)
            detail_pad = ""
            pm = PAD_SYM.search(body)
            am = PAD_ALL.search(body)
            if pm:
                v = VERT.search(pm.group(1))
                detail_pad = f", padding v{v.group(1) if v else '?'}"
            elif am:
                detail_pad = f", padding {am.group(1)}"
            if box is None:
                advisory.append((rel, line_no, "hand-rolled tap, no box",
                                 "hit area comes from layout" + detail_pad))
                continue
            prefix = body[:box.start()]
            if LAYOUT_BETWEEN.search(prefix):
                advisory.append((rel, line_no, "hand-rolled tap, box not root",
                                 "layout between tap and box" + detail_pad))
                continue
            box_body, _ = call_body(src2, m.end() + box.end() - 1)
            own = OWN_ARGS.split(box_body, 1)[0]
            own = DECOR_CALL.sub(" ", own)
            h = EXPLICIT_H.search(own)
            w = EXPLICIT_W.search(own)
            hh = float(h.group(1)) if h else None
            ww = float(w.group(1)) if w else None
            if hh is not None and hh < MIN:
                fails.append((rel, line_no, "hand-rolled tap box",
                              f"height {hh:g} < 56 ({m.group(1)})"))
            elif ww is not None and ww < MIN:
                fails.append((rel, line_no, "hand-rolled tap box",
                              f"width {ww:g} < 56 ({m.group(1)})"))
            elif hh is None and ww is None:
                advisory.append((rel, line_no, "hand-rolled tap, sized by layout",
                                 "no explicit dimension" + detail_pad))

        for m in DEFAULT48.finditer(src2):
            advisory.append((os.path.relpath(path, root),
                             src2.count("\n", 0, m.start()) + 1,
                             "framework control at 48 dp padded",
                             f"{m.group(1)}: fine only if its row is >= 56 dp"))

    taps = sum(len(TAP.findall(open(p, encoding="utf-8").read()))
               for p in dart_files(root))
    return fails, taps, advisory


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    fails, taps, advisory = audit(root)
    fails.sort(key=lambda f: (f[0], f[1]))
    advisory.sort(key=lambda f: (f[0], f[1]))
    print(f"tap-target audit — {taps} tap sites, minimum {MIN:g} dp")

    def dedupe(rows):
        seen, out = set(), []
        for row in rows:
            key = (row[0], row[1], row[2])
            if key not in seen:
                seen.add(key)
                out.append(row)
        return out

    fails, advisory = dedupe(fails), dedupe(advisory)
    for rel, line, rule, detail in fails:
        loc = f"{rel}:{line}" if line else rel
        print(f"FAIL      {loc:66} {rule:28} {detail}")
    for rel, line, rule, detail in advisory:
        loc = f"{rel}:{line}" if line else rel
        print(f"ADVISORY  {loc:66} {rule:28} {detail}")
    print(f"\n{len(fails)} provable fail(s), {len(advisory)} site(s) whose size"
          " only a widget measurement can settle.")
    if fails:
        print("Exit 1: fix the provable sites (or drop them under 56 with a"
              " theme/global change) before this item can be ticked.")
        return 1
    print("Exit 0: no provably sub-56 tap target left. ADVISORY rows are not"
          " proof of anything — pin them in test/tap_target_test.dart.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
