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
R5  The theme must raise IconButton globally: `iconButtonTheme` with a
    `minimumSize` of at least 56. With that in place an unadorned `IconButton(`
    is a 56 dp target and is reported COVERED instead of failed -- and if the
    theme entry is missing or smaller, the tool fails on the theme itself.
R6  A `TextButton` is 40 tall / 48 padded by default (SDK default `minimumSize`
    Size(64, 40)), so every site that does not set its own is below 56 — unlike
    Elevated/Outlined/Filled, which inherit `Size.fromHeight(tapMin)` from the
    theme. `textButtonTheme` carries the same `minimumSize` now; as with R5, a
    site that rides on it is COVERED, and a theme that loses it fails the tool.

The token
---------
`AppTheme.tapMin` is 56, and the rules below read it as 56 rather than ignoring
it. Before, a control sized by the token was invisible to R3/R4/R7 (the regexes
wanted a literal) and had to be hand-measured into MEASURED; now
`SizedBox(width: AppTheme.tapMin, height: AppTheme.tapMin)` is *provably* 56 and
a token clamp floor is provably at the target. A dimension written as any other
named constant is still out of reach and stays ADVISORY.

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
R9  A row the rules above had to leave ADVISORY is settled by hand when every
    number in its sum is declared in the source -- see MEASURED below. Those
    rows are reported as MEASURED pass / fail with the arithmetic written out,
    and the anchor on each row is re-checked every run (a moved construct prints
    STALE and fails the tool rather than quietly scoring a control it no longer
    describes). A hand measurement is still a measurement of a *floor*: it says
    the control cannot be smaller than the sum, never that a widget test is
    unnecessary -- test/tap_target_test.dart still pins the real hit rects.

Usage:  python3 tool/tap_target_audit.py [repo_root]
"""
import os
import re
import sys

MIN = 56.0

ICON_BTN = re.compile(r"\bIconButton\(")
ICON_BTN_ESCAPE = re.compile(r"\b(constraints:|padding:|style:)\s")
# `AppTheme.tapMin` is the 56 dp target written as a token: a dimension spelled
# with it is as provable as a literal one.
DIM = r"(?:AppTheme\.tapMin|([\d.]+))"
MIN_SIZE = re.compile(
    r"minimumSize:\s*(?:const\s+)?Size\(\s*" + DIM + r"\s*,\s*" + DIM + r"\s*\)")
# `Size.fromHeight(h)` is the *other* spelling of the same guarantee, and R2 was
# blind to it: the regex above needs a comma, so it matched nothing here. The
# button rule compounds it -- a site whose `minimumSize:` is within four lines is
# `continue`d out of the theme rule "judged by R2 instead", so a
# `minimumSize: const Size.fromHeight(40)` was skipped by BOTH rules and
# passed silently. 11 sites spell it this way at HEAD; all are `tapMin`.
MIN_SIZE_H = re.compile(
    r"minimumSize:\s*(?:const\s+)?Size\.fromHeight\(\s*" + DIM + r"\s*\)")
SIZED_H = re.compile(r"\b(?:height|maxHeight):\s*" + DIM)
CLAMP = re.compile(r"\.clamp\(\s*" + DIM + r"\s*,\s*" + DIM + r"\s*\)")


def dim(m, group=1):
    """The 56 behind a DIM match, or the literal that was written."""
    return 56.0 if m.group(group) is None else float(m.group(group))
BUTTON = re.compile(r"\b(?:OutlinedButton|ElevatedButton|TextButton|FilledButton)\(")
TEXT_BUTTON = re.compile(r"\bTextButton\(")
CALL_HEAD = ("me")
BOX_OPEN = re.compile(r"\b(?:SizedBox|AnimatedContainer|Container)\(")
TAP = re.compile(r"\bon(?:Tap|Pressed):\s*(?!null)")

# --- R7/R8: hand-rolled taps and framework-default 48 dp controls -----------
TAP_WIDGET = re.compile(r"\b(InkWell|GestureDetector)\(")
BOX = re.compile(r"\b(?:SizedBox|AnimatedContainer|Container)\(")
EXPLICIT_W = re.compile(r"\bwidth:\s*" + DIM + r"\b")
EXPLICIT_H = re.compile(r"\bheight:\s*" + DIM + r"\b")
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



# --- hand-measured verdicts --------------------------------------------------
# The rules above only see the numbers declared on the control itself, so a
# hand-rolled tap whose size comes from the layout around it lands in ADVISORY
# and is deliberately left alone -- "a static tool that guesses would send the
# next loop to fix a control that is fine". These entries are the other way
# round: every number in the sum is written down in the source (by token, never
# a copied literal), so the effective minimum dimension is arithmetic. Each row
# is (file, probe, verdict, arithmetic). The probe -- a slice of the construct
# itself -- is re-checked on every run and the line is RESOLVED from it, because
# a line number is not an identity: every edit above a construct moves it. If the
# construct has moved the row follows it; if it is gone the entry is reported
# STALE and the tool exits 1, so the table can neither rot in silence nor expire
# on the next unrelated edit above it. A probe that stops being unique is
# reported too -- a probe matching two sites does not identify one.
FAIL_, PASS_ = "FAIL", "PASS"
MEASURED = [
    # Refreshed 2026-09-13: every line below was re-read at its new
    # position after a week of edits, so the arithmetic could be checked
    # against the construct it describes. The anchor is what proves it —
    # if a construct moves again this table says STALE, not PASS.
    # ui.dart:119 is no longer here on purpose: the «عرض الكل» tap is wrapped in
    # a `SizedBox(height: AppTheme.tapMin)`, which R7 now reads as 56 and proves
    # on its own. The pill below sits in a `Wrap`, so nothing stretches it and
    # only its own padding can settle it.
    ("lib/src/screens/project/project_new_screen.dart", "child: InkWell(\n        onTap: onTap,\n        borderRadius: BorderRadius.circular(AppTheme.rPill),\n        // The 56 dp floor is `AppTheme.tapMin`, so it is *stated* rather than\n        // reached by arithmetic: the padding below is 16 (on the grid, which\n        // the old 19 was not) and this constraint is what keeps the pill\n        // tappable. Before, v19 x2 + the 18.9 dp row = 56.9", PASS_,
     "BoxConstraints(minHeight: tapMin 56) wins over 16x2 + max(17, 13.5x1.4=18.9) = 50.9"),
    # Checkbox is 48 dp padded (kMinInteractiveDimension) and the row adds v6.
    # Anchors moved 582 -> 592 and 589 -> 599 on 6 Oct: the R4 auth slice put
    # the reason for the 18 dp vertical field padding above `authInput`, which
    # pushed both constructs down ten lines. The arithmetic is UNCHANGED — the
    # slice moved the field's *horizontal* inset (14 -> AppTheme.fieldPad) and
    # deliberately left the vertical `18` alone because it is what clears
    # AppTheme.tapMin here — so these two rows are re-pinned, not re-decided.
    # Anchors moved again 592 -> 594 and 599 -> 601 on 7 Oct: the eleventh slice
    # re-pinned the auth screen's own page insets and wrapped two of them, which
    # shifted these two constructs down two lines. Re-pinned again, NOT
    # re-decided — the vertical `6` on the remember row is untouched by that
    # slice, so the 48 + 6x2 = 60 arithmetic below is still the same sum.
    ("lib/src/screens/auth/auth_screen.dart", "child: InkWell(\n          borderRadius: BorderRadius.circular(AppTheme.rSm),\n          onTap: () => onChanged(!value),\n          child: Padding(\n            padding: const EdgeInsets.only(top: 6, bottom: 6),\n            child: Row(\n              children: [\n                Checkbox(", PASS_,
     "48 (Checkbox, padded) + 6x2 = 60.0"),
    ("lib/src/screens/auth/auth_screen.dart", "child: Row(\n              children: [\n                Checkbox(\n                  value: value,\n                  semanticLabel: S.rememberMe,", PASS_,
     "48 inside the 60 dp row above"),
    # **This row was a FAIL and is now a PASS, for a change measured, not
    # argued.** It is the row that made `tool/tap_target_audit.py` exit 1 with
    # a *real* defect rather than with housekeeping: the strip's anchor had
    # rotted from `browse_screen.dart:317` to here, and its arithmetic had
    # moved onto a number nobody re-decided -- `SizedBox(height: 60)` with
    # `fromLTRB(gutter, s4, gutter, s4)`, so the painted pill was
    # `60 - 4 - 4 = 52` dp, 4 under [AppTheme.tapMin], on all eighteen chips.
    #
    # The strip now reads `height: AppTheme.tapMin + AppTheme.s4 * 2` = 64, so
    # the pill is exactly 56. Both halves of that claim are measured, not
    # inferred:
    #
    #   * Before: the committed golden `10_browse.png` (392x850, DPR 1.0, so
    #     1 px = 1 dp) had the pill's non-background pixels on
    #     **y138..y189 inclusive = 52 px**.
    #   * After: the re-baselined golden has them on **y138..y193 = 56 px**.
    #     Same top edge, +4 px of height -- the strip grew downward, which is
    #     what an extra 4 dp of pad below the pill must do.
    #   * And nothing else moved *except* by that shift: every row from y202
    #     down in the new golden is **byte-identical to the old one displaced
    #     by exactly 4 px** -- 253,232 identical pixels and **0** differing
    #     across y202..849. So the re-baseline is the 4 dp and nothing more;
    #     no card, label or colour in the directory moved on its own.
    #
    # `test/trade_filter_bar_test.dart` now measures the real hit rect of all
    # eighteen chips against `AppTheme.tapMin`, so this row is the *floor* and
    # that test is the proof: the row cannot rot silently again, because the
    # test fails on the widget, not on a stale line number.
    ("lib/src/widgets/trade_filter_bar.dart", "child: InkWell(\n          borderRadius: BorderRadius.circular(AppTheme.rPill),\n          onTap: onTap,\n          child: AnimatedContainer(", PASS_,
     "strip height tapMin + s4*2 = 64 - s4*2 = 56.0 (golden ink y138..y193 = 56 px)"),
    # Re-pinned 7 Oct after eight STALE rows: every one of these constructs is
    # still the widget the row was written for, and each arithmetic below is
    # re-read against the source at its new line, not carried over. They are
    # re-decided on the same numbers, which is the only honest reason to leave
    # a verdict alone.
    #
    # The chat row was the icon bubble: `SizedBox(width: AppTheme.tapMin,
    # height: AppTheme.tapMin)` around a 24 dp icon, so 56x56 exactly. R7
    # proved this one on its own the day it was written; the row still earns
    # its place because it is the audit's own record that the floor holds.
    ("lib/src/screens/chat/chat_screen.dart", "child: InkWell(\n          onTap: onTap,\n          child: SizedBox(\n            width: AppTheme.tapMin,\n            height: AppTheme.tapMin,\n            child: Icon(icon, size: 24", PASS_,
     "SizedBox(width/height: tapMin 56) = 56.0"),
    ("lib/src/screens/customer/customer_home_screen.dart", "child: InkWell(\n        onTap: onTap,\n        borderRadius: BorderRadius.circular(AppTheme.rMd),\n        child: Container(\n          constraints: const BoxConstraints(minHeight: AppTheme.tapMin),", PASS_,
     "BoxConstraints(minHeight: tapMin 56) = 56.0"),
    ("lib/src/screens/customer/customer_home_screen.dart", "child: InkWell(\n        onTap: onTap,\n        borderRadius: BorderRadius.circular(AppTheme.rLg),\n        child: Padding(\n          padding: const EdgeInsets.all(16),\n          child: Row(\n            children: [\n              Container(\n                width: 56,\n                height: 56,", PASS_,
     "16x2 + 56 dp dot = 88.0"),
    # fieldPad is still `symmetric(horizontal: s16, vertical: 18)` at
    # app_theme.dart:215, and the field still paints `AppTheme.body` inside it.
    ("lib/src/screens/project/project_new_screen.dart", "child: InkWell(\n        onTap: onTap,\n        borderRadius: BorderRadius.circular(AppTheme.rMd),\n        child: Container(\n          padding: AppTheme.fieldPad,", PASS_,
     "18x2 + 15.5x1.65=25.6 = 61.6"),
    ("lib/src/screens/worker/worker_home_screen.dart", "child: InkWell(\n        borderRadius: BorderRadius.circular(AppTheme.rPill),\n        onTap: onTap,\n        child: Center(", PASS_,
     "enclosing SizedBox(height: tapMin 56) = 56.0"),
    ("lib/src/widgets/app_tab_bar.dart", "child: GestureDetector(\n        key: Key('tab-$i'),\n        behavior: HitTestBehavior.opaque,", PASS_,
     "Container(height: 60) bar = 60.0"),
    # Re-read at the call sites, not from the old note: `auth_screen.dart` passes
    # 92 and 92, `category_grid.dart` passes `double.infinity` twice. The default
    # is 104 and still is. No call site passes anything else, so the row's claim
    # ("92 or infinity") is the whole set, not a sample of it.
    ("lib/src/widgets/ui.dart", "child: InkWell(\n        borderRadius: BorderRadius.circular(AppTheme.rMd),\n        onTap: onTap,\n        child: AnimatedContainer(\n        duration: AppMotion.fast,", PASS_,
     "call sites pass 92 (auth) or double.infinity (grid)"),
]


def _strip_line(ln):
    """Drop a trailing // comment that is not inside a string literal."""
    i = ln.find("//")
    if i >= 0 and ln[:i].count("'") % 2 == 0 and ln[:i].count('"') % 2 == 0:
        return ln[:i]
    return ln


def _norm(text):
    """Whitespace-insensitive, comment-stripped form of a source slice.

    A hand measurement is about the CONSTRUCT, and a comment is prose about the
    construct, so the probe is compared without comments and without
    formatting. Two edits differing only in spacing, or only in an explanatory
    sentence, are the same construct and must resolve to the same site -- the
    opposite of the line number this table used to carry.
    """
    return re.sub(r"\s+", " ",
                  " ".join(_strip_line(ln) for ln in text.split("\n"))).strip()


def locate(root, rel, probe):
    """1-based line of the UNIQUE construct matching `probe`, else (None, why).

    A line number is not an identity. Every edit above a construct moves it,
    which is why the MEASURED table below was re-pinned by hand on 13 Sep, 6 Oct
    and 7 Oct and was STALE on all nine of its rows the first time the loop
    read this tool's exit code instead of its prose. `probe` is a slice of the
    construct itself, so it survives any amount of movement above it.

    UNIQUE is the load-bearing word: a probe that matches two sites does not
    identify one, and is reported rather than guessed at.
    """
    try:
        body = open(os.path.join(root, rel), encoding="utf-8").read()
    except OSError:
        return None, "the file is gone"
    lines = body.split("\n")
    # `_norm` is the ONE normaliser. It was duplicated inline here first, which
    # left `_norm` itself dead: the comment-stripping mutation survived the
    # battery twice because it was mutating code nothing called. The proof
    # that a helper is load-bearing is mutating it and watching a case go red.
    stripped = [_strip_line(ln) for ln in lines]
    flat = _norm(body)
    probe_n = _norm(probe)
    if not probe_n:
        return None, "the row carries no probe to look for"
    hits = flat.count(probe_n)
    if hits == 0:
        return None, "the construct is no longer in the file"
    if hits > 1:
        return None, ("the probe matches %d sites -- it does not identify one"
                      % hits)
    # Walk the flattened text to recover the 1-based line of the match.
    seen = 0
    for idx, raw in enumerate(stripped, start=1):
        piece = re.sub(r"\s+", " ", raw).strip()
        if not piece:
            continue
        if seen + len(piece) + 1 > flat.index(probe_n):
            return idx, ""
        seen += len(piece) + 1
    return None, "the construct matched but its line could not be mapped"


def resolve_measured(root, advisory):
    """Split ADVISORY rows into 'a declared number settles this' and the rest.

    Returns (settled, stale, remaining advisory). A settled row is
    (rel, line, verdict, arithmetic); a stale one is (rel, probe_head, why).

    The line is RESOLVED from the row's probe rather than stored in it, for the
    reason `locate` documents. The second half is why `suppressed` is keyed on
    the resolved line and not on the table: the MEASURED rows are the only
    ADVISORY rows this tool is allowed to drop, and a key built from stored
    coordinates silently stops matching the moment the construct moves -- which
    printed ui.dart:400 as ADVISORY while its own row sat STALE above it, one
    table disagreeing with itself in a single run.
    """
    settled, stale = [], []
    suppressed = set()
    for rel, probe, verdict, why in MEASURED:
        line, bad = locate(root, rel, probe)
        if line is None:
            head = " ".join(probe.split())[:40]
            stale.append((rel, head, bad))
            continue
        settled.append((rel, line, verdict, why))
        suppressed.add((rel, line))
    return settled, stale, [a for a in advisory if (a[0], a[1]) not in suppressed]


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


SIZE_ARGS = re.compile(
    r"minimumSize:\s*(?:const\s+)?Size(?:\.fromHeight)?\(\s*([^)]*)\)")
DIM_TOKEN = re.compile(r"AppTheme\.tapMin|\btapMin\b|([\d.]+)")


def theme_minimum(src, key):
    """Smallest dimension in the `minimumSize` of a theme key, or None.

    Reads `Size(a, b)` and `Size.fromHeight(a)`; either spelling of the
    `tapMin` token counts as 56, so the theme's own guarantee is checked with
    numbers, not with the presence of a string.
    """
    i = src.find(key)
    if i < 0:
        return None
    m = SIZE_ARGS.search(src[i:i + 900])
    if not m:
        return None
    dims = [56.0 if g is None else float(g)
            for g in (x.group(1) for x in DIM_TOKEN.finditer(m.group(1)))]
    return min(dims) if dims else None


def audit(root):
    fails, unknown, covered = [], [], []
    theme = os.path.join(root, "lib/src/core/theme/app_theme.dart")
    icon_min = text_min = None
    if os.path.exists(theme):
        tsrc = open(theme, encoding="utf-8").read()
        icon_min = theme_minimum(tsrc, "iconButtonTheme")
        text_min = theme_minimum(tsrc, "textButtonTheme")
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
            if icon_min is not None and icon_min >= MIN:
                covered.append((rel, line_no, "IconButton raised by the theme",
                                f"iconButtonTheme minimumSize {icon_min:g}"))
                continue
            fails.append((rel, line_no, "IconButton at SDK default",
                          "40x40 box, 48x48 padded hit area < 56"))

        for m in MIN_SIZE.finditer(src):
            w, h = dim(m, 1), dim(m, 2)
            if h < MIN:
                fails.append((rel, src.count("\n", 0, m.start()) + 1,
                              "minimumSize", f"{w:g}x{h:g}"))

        for m in MIN_SIZE_H.finditer(src):
            h = dim(m)
            if h < MIN:
                fails.append((rel, src.count("\n", 0, m.start()) + 1,
                              "minimumSize height", f"fromHeight {h:g} < {MIN:g}"))

        for m in CLAMP.finditer(src):
            lo = dim(m, 1)
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
                # ...and it must be open ON ITS OWN LINE. A one-line spacer is
                # balanced where it opens -- `const SizedBox(height: 16),` -- and
                # encloses nothing, which is what this rule has always claimed
                # to skip. The aggregate sum above cannot see that: it keeps
                # reading the NEXT widget's `(` on the lines below and hands the
                # spacer the credit. That is how a `FilledButton` whose own
                # `minimumSize: const Size.fromHeight(AppTheme.tapMin)` puts it
                # at 56 was reported as "button inside fixed box, height 16".
                if lines[k - 1].count("(") <= lines[k - 1].count(")"):
                    continue
                sizes = [dim(x) for x
                         in SIZED_H.finditer("".join(lines[k - 1:line_no]))]
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
            if text_min is not None and text_min >= MIN:
                covered.append((rel, line_no, "TextButton raised by the theme",
                                f"textButtonTheme minimumSize {text_min:g}"))
                continue
            fails.append((rel, line_no, "TextButton at SDK default",
                          "40 tall box, 48 hit area < 56 (textButtonTheme sets no minimumSize)"))

    rel_theme = os.path.relpath(theme, root)
    if icon_min is None:
        fails.append((rel_theme, 0, "no global IconButtonTheme",
                      "R1 therefore fires at every IconButton site"))
    elif icon_min < MIN:
        fails.append((rel_theme, 0, "IconButtonTheme under the target",
                      f"minimumSize {icon_min:g} < {MIN:g}"))
    if text_min is None or text_min < MIN:
        fails.append((rel_theme, 0, "textButtonTheme under the target",
                      f"minimumSize {text_min} -> TextButtons stay 40 tall"))

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
            hh = dim(h) if h else None
            ww = dim(w) if w else None
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
    return fails, taps, advisory, covered


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    fails, taps, advisory, covered = audit(root)
    static_fails = len(fails)
    settled, stale, advisory = resolve_measured(root, advisory)
    measured_fails = [(r, l, "measured by hand", why)
                      for r, l, v, why in settled if v == FAIL_]
    measured_pass = [(r, l, "measured pass", why)
                     for r, l, v, why in settled if v == PASS_]
    fails = fails + measured_fails
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

    fails, advisory, covered = dedupe(fails), dedupe(advisory), dedupe(covered)
    for rel, line, rule, detail in fails:
        loc = f"{rel}:{line}" if line else rel
        print(f"FAIL      {loc:66} {rule:28} {detail}")
    for rel, line, rule, detail in advisory:
        loc = f"{rel}:{line}" if line else rel
        print(f"ADVISORY  {loc:66} {rule:28} {detail}")
    for rel, line, rule, detail in measured_pass:
        print(f"MEASURED  {f'{rel}:{line}':66} {rule:28} {detail}")
    for rel, line, rule, detail in covered:
        print(f"COVERED   {f'{rel}:{line}':66} {rule:28} {detail}")
    for rel, probe_head, why in stale:
        print(f"STALE     {rel:66} {'measurement rotted':28} "
              f"probe {probe_head!r} -- {why}")

    print(f"\n{len(fails)} provable fail(s) ({static_fails} from the rules, "
          f"{len(measured_fails)} measured by hand), {len(measured_pass)} "
          f"measured pass, {len(covered)} covered by the theme, "
          f"{len(advisory)} site(s) whose size only a widget measurement can"
          " settle.")
    if stale:
        print(f"Exit 1: {len(stale)} STALE hand measurement(s) -- a construct"
              " moved and its recorded verdict no longer describes it.")
        return 1
    if fails:
        print("Exit 1: fix the provable sites (or drop them under 56 with a"
              " theme/global change) before this item can be ticked.")
        return 1
    print("Exit 0: no provably sub-56 tap target left. ADVISORY rows are not"
          " proof of anything — pin them in test/tap_target_test.dart.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
