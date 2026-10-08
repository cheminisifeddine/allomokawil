#!/usr/bin/env python3
"""Census: every file a source-scanning guard SKIPS must have a reader somewhere.

    python3 test/exemption_census_test.py

Run directly -- it is pure Python, so it answers on a box whose
`build_gate.py` refuses a Dart build, which is exactly when a guard that has
been quietly narrowing what it can see needs checking.

**The defect class this pins.** `test/line_height_token_test.dart` exempted
`app_theme.dart` *by filename*. A non-`const` `TextStyle` is a
`MethodInvocation`, not an `InstanceCreationExpression`, so the guard's
visitor structurally could not read the nine style constants it was exempting
-- and seven of the nine line-heights it held were on no rung of the ladder
that same file declares. Nine unseen writers, four of them off-ladder. The
exemption was not the bug; the exemption *with no compensating reader* was.

The rule that falls out, and the one this file enforces:

    an exemption is fine; an exemption with no compensating reader is not.

A guard that is merely narrow passes. A guard that skips a file no test ever
opens is skipping a file nobody is looking at, which is indistinguishable
from a clean tree -- the failure mode `agreement_comment_test.dart:158`
already calls a scanner that silently matches nothing.

**What counts as a compensating reader.** Some test, anywhere under `test/`,
that actually *reads the exempted file as source* -- it appears as a path in
an import, or its text is read off disk. Merely importing the symbols is not
reading it as source: forty-one Dart test files `import .../app_theme.dart`,
which is why the first draft of this census reported `app_theme.dart` as
watched and was wrong. An import proves the file compiles; this census asks
whether anyone looks at its *text*.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(REPO, "test")

# `path.endsWith('<name>.dart')` immediately guarding a `continue` -- the only
# shape that silently drops a file from a scan. A `!endsWith(...)` FILTER is a
# *narrowing* the guard states out loud and is out of scope here.
_EXEMPT = re.compile(
    r"endsWith\(\s*(?:'([^']+\.dart)'|(\w+))\s*\)"
)


def _const_filenames(src):
    """`const self = 'agreement_comment_test.dart';` -> token -> filename.

    A guard that names its exemption through a constant still exempts a file,
    and a census that only matches literals reads that guard as narrow.
    """
    consts = {}
    for m in re.finditer(
            r"""(?:const|final|String)\s+(\w+)\s*=\s*'([^']+\.dart)'""", src):
        consts[m.group(1)] = m.group(2)
    return consts


def exemptions():
    """(guard_file, line_no, exempted_basename) for every file-level skip."""
    found = []
    for name in sorted(os.listdir(TESTS)):
        if not name.endswith(".dart"):
            continue
        path = os.path.join(TESTS, name)
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        consts = _const_filenames("\n".join(lines))
        for i, line in enumerate(lines):
            if "endsWith" not in line:
                continue
            for m in _EXEMPT.finditer(line):
                tok = (m.group(1) or m.group(2)).strip()
                target = consts.get(tok, tok)
                if not target.endswith(".dart"):
                    continue
                # The skip is written two ways in this tree: a guard clause
                # (`if (...endsWith(x)) continue;`) and a negated filter in
                # a `where` chain (`!f.path.endsWith(x)`). Both drop the
                # file silently. Reading only the first is how this census
                # called a tree clean with a skip sitting in it -- found by
                # the planted proof below, not by reading the code.
                window = "\n".join(lines[i:i + 3])
                negated = "!" in line.split("endsWith")[0][-12:]
                if "continue" not in window and not negated:
                    continue
                found.append((name, i + 1, os.path.basename(target)))
    return found


def _source_texts():
    """Every `.dart` file under `test/`, as (basename, text)."""
    out = []
    for name in sorted(os.listdir(TESTS)):
        if name.endswith(".dart"):
            with open(os.path.join(TESTS, name), encoding="utf-8") as fh:
                out.append((name, fh.read()))
    return out


def readers(basename):
    """Tests that READ `basename`'s text off disk. Imports do not count.

    An import proves the file compiles. Forty-one Dart tests import
    `app_theme.dart`, which is why the first draft of this census reported it
    as watched and was wrong.

    Two things had to be tightened after the planted proof, and both were
    found by planting rather than by reading this function:

      * a **comment** is not a read. `app_source_scope_test.dart` names all
        three theme files in prose (lines 149-161) and in a backtick on 615,
        and none of it is code -- the real read of `ui.dart` is
        `tile_label_fit_test.dart:265`.
      * a **basename prefix** is not the file. Matching `category_str` counted
        `category_strip_fit_test.dart` as a reader of a file named
        `category_str.dart`, which does not exist. The match is now on the
        full basename or on a `lib/`-rooted path.
    """
    stem = basename[:-5]
    # the one file whose compensating reader is a derived source check rather
    # than another test's text read -- see motion_reader() for why it has to be
    if basename == "motion.dart":
        return ["motion_reader() (in this file)"]
    found = []
    for name, text in _source_texts():
        self_exempt = (name == basename)
        if re.search(r"""import\s+['"][^'"]*%s['"]""" % re.escape(stem), text):
            continue
        reads = ("readAsStringSync" in text or "readAsLinesSync" in text
                 or "readAsString()" in text)
        if not reads:
            continue
        # strip comments before asking whether the file is named: a guard
        # quoted inside `//` is not reading anything.
        code = _strip_comments(text)
        named = re.search(r"""%s""" % re.escape(basename), code) is not None
        lib_rooted = re.search(
            r"""['"][^'"]*/%s""" % re.escape(stem), code) is not None
        if not (named or lib_rooted):
            continue
        # The self-exemption is the one legal case a skip can take, and it is
        # legal only when the guard PINS something: `agreement_comment_test`
        # skips itself because its own doc comments quote the sentences it
        # hunts, and backs that with `expect(claims.length,
        # greaterThanOrEqualTo(6))` at line 160 -- a reader that found nothing
        # is distinguishable from a clean tree. A skip with no floor on what it
        # did read is the defect, even when it skips itself.
        if self_exempt:
            floors = ("greaterThan", "isNotEmpty", "greaterThanOrEqualTo",
                      "equals(0)")
            if not any(f in code for f in floors):
                continue
            found.append(name)
            continue
            continue
        # ...and never by the guard that skips it. A test cannot compensate for
        # its own blind spot -- it is the thing that dropped the file.
        if re.search("endsWith\\([^\\n)]*" + re.escape(basename), code):
            continue
        const_tok = re.search("endsWith\\(\\s*(\\w+)\\s*\\)", code)
        if const_tok and re.search(
                "=\\s*'[^']*" + re.escape(basename) + "'", code):
            continue
        found.append(name)
    return found


def motion_reader():
    """The compensating reader `motion.dart` never had.

    `test/motion_test.dart:30` claims "every duration in the spec is listed in
    AppMotion.all" and then proves it against a **hand-copied set of the same
    five rungs**. A sixth rung added to `motion.dart` -- the one file the tempo
    guard at line 339 exempts, so no source scan ever sees it -- would not fail
    that test, and would then be a speed the app is allowed to use but which no
    guard can name. The ladder's own definition file was the only place it could
    hide.

    So the check is derived from the file instead of copied into a test: every
    `static const Duration` declared is listed in `AppMotion.all`, and every
    entry of `all` is declared. Both directions.
    """
    path = os.path.join(REPO, "lib", "src", "core", "theme", "motion.dart")
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    code = _strip_comments(src)
    declared = re.findall(
        r"static const Duration (\w+)\s*=\s*Duration\(", code)
    block = re.search(r"static const List<Duration> all\s*=\s*<Duration>\[(.*?)\]",
                      code, re.S)
    _assert(block is not None,
            "motion.dart: `AppMotion.all` is gone, so nothing can name a legal "
            "duration and motion_test.dart's completeness claim is stale")
    listed = [x.strip() for x in block.group(1).split(",") if x.strip()]
    orphans = [d for d in declared if d not in listed]
    ghosts = [l for l in listed if l not in declared]
    _assert(not orphans,
            "motion.dart declares a duration that `AppMotion.all` does not "
            "list -- a speed the source scan is exempt from and no guard can "
            "name: %s" % ", ".join(orphans))
    _assert(not ghosts,
            "AppMotion.all lists a duration motion.dart does not declare: %s"
            % ", ".join(ghosts))
    _assert(len(set(listed)) == len(listed),
            "AppMotion.all repeats a rung: %s" % listed)
    _assert(declared, "motion_reader read zero rungs -- this reader is "
                      "broken, not the tree")


def weight_ladder_reader():
    """The compensating reader `app_theme.dart`'s weight ladder never had.

    `test/font_weight_token_test.dart:353` asserts the ladder is "ordered,
    weakest first, and **complete**" -- and then proves completeness against a
    **hand-copy of the same five rungs**:

        expect(AppTheme.weights, <FontWeight>[
          FontWeight.w400, ... w500, ... w600, ... w700, ... w800]);

    That is the file comparing its ladder to a transcription of itself. The
    scan it depends on does not help: `_rawWeights` walks all of `lib/` and
    exempts nothing by filename, but the ladder's own `w*` declarations *are*
    raw `FontWeight.wNNN` right-hand sides -- they are the five literals the
    conversion deliberately put there. So a sixth rung declared the same way
    is invisible to the scan by construction, and the completeness test only
    checks that the five it already knows are present.

    Measured, not argued: planting `wThunder = FontWeight.w900` next to the
    real five left `font_weight_token_test`, `type_scale_test` and
    `motion_test` **all green, 32 tests** -- an off-ladder weight the tree is
    allowed to use and that no guard could name.

    So the check is derived from `app_theme.dart` instead of copied: every
    declared `static const FontWeight w*` is listed in `AppTheme.weights`, and
    every entry of `weights` is declared. Both directions. Same instrument as
    `motion_reader()`, because the defect is identical and it is in the theme
    file -- which `type_scale_test.dart:220` exempts by name.
    """
    path = os.path.join(REPO, "lib", "src", "core", "theme", "app_theme.dart")
    with open(path, encoding="utf-8") as fh:
        code = _strip_comments(fh.read())

    declared = re.findall(r"static const FontWeight (w\w+)\s*=", code)
    block = re.search(
        r"static const List<FontWeight> weights\s*=\s*<FontWeight>\[(.*?)\]",
        code, re.S)
    _assert(block is not None,
            "app_theme.dart: `AppTheme.weights` is gone, so nothing can name a "
            "legal weight and font_weight_token_test's completeness claim is "
            "stale")
    listed = [x.strip() for x in block.group(1).split(",") if x.strip()]

    orphans = [d for d in declared if d not in listed]
    ghosts = [l for l in listed if l not in declared]
    _assert(not orphans,
            "app_theme.dart declares a weight token that `AppTheme.weights` "
            "does not list -- an off-ladder weight the app may use and no "
            "guard can name: %s" % ", ".join(orphans))
    _assert(not ghosts,
            "AppTheme.weights lists a weight app_theme.dart does not "
            "declare: %s" % ", ".join(ghosts))
    _assert(len(set(listed)) == len(listed),
            "AppTheme.weights repeats a rung: %s" % listed)
    _assert(declared,
            "weight_ladder_reader read zero rungs -- this reader is broken, "
            "not the tree")


def size_ladder_reader():
    """The same defect, the other leg of the type scale -- and it is also clean.

    `type_scale_test.dart:155` guards the *size* ladder properly: it derives
    `AppTheme.scale` from the theme's own declarations (`ladderSizeNames()`)
    and asserts >= 8 steps, ordering, distinctness. That is the right shape,
    and this reader is here for the opposite reason -- to pin that it stays
    that way, and to catch the version of the weight bug where someone adds an
    `fs*` token beside the ladder rather than on it.

    Not decoration: the previous tick's `motion_test.dart:30` failure was
    exactly this shape on the tempo ladder, and two of the three type-scale
    legs were rebuilt from it.
    """
    path = os.path.join(REPO, "lib", "src", "core", "theme", "app_theme.dart")
    with open(path, encoding="utf-8") as fh:
        code = _strip_comments(fh.read())

    declared = re.findall(r"static const double (fs\w+)\s*=", code)
    block = re.search(r"static const List<double> scale\s*=\s*<double>\[(.*?)\]",
                      code, re.S)
    _assert(block is not None,
            "app_theme.dart: `AppTheme.scale` is gone, so type_scale_test's "
            "ladder is reading a ladder that does not exist")
    listed = [x.strip() for x in block.group(1).split(",") if x.strip()]

    orphans = [d for d in declared if d not in listed]
    ghosts = [l for l in listed if l not in declared]
    _assert(not orphans,
            "app_theme.dart declares an `fs*` size token that `AppTheme.scale` "
            "does not list -- a font size outside the ladder, which is the "
            "defect type_scale_test.dart exists to catch, declared in the one "
            "file it exempts: %s" % ", ".join(orphans))
    _assert(not ghosts,
            "AppTheme.scale lists a size app_theme.dart does not declare: %s"
            % ", ".join(ghosts))
    _assert(len(set(listed)) == len(listed),
            "AppTheme.scale repeats a step: %s" % listed)
    _assert(len(declared) >= 8,
            "read %d `fs*` tokens -- below the 8 steps type_scale_test.dart "
            "itself demands, so this reader is broken, not the tree"
            % len(declared))


def line_height_ladder_reader():
    """The third type-scale leg, and the one the census predicted worst.

    `test/line_height_token_test.dart:353` asserts the ladder is "ordered,
    tightest first, and **complete**" -- and then builds its `ascending` list
    out of a **hand-transcription of the same ten rungs**:

        final ascending = <double>[
          AppTheme.lhTightest, ... AppTheme.lhReading,
        ];

    That is the weight ladder's shape one level down, and the census's guess
    that this file would be the copy rather than the derive was right. The
    difference from the weight leg is that there is **no `AppTheme.lhHeights`
    list to derive from at all** -- `app_theme.dart` has `scale` for sizes and
    `weights`, but the line-height ladder has no collection, so the test had
    nowhere to read from and transcribed the declarations instead.

    Measured, not argued: planting `lhThunder = 0.93` next to the real ten
    left `line_height_token_test.dart` and `type_scale_test.dart` **all green,
    12 tests** -- including the assertion that claims completeness -- and the
    Python census green too (7 passed). An off-ladder line-height the app may
    inherit through `copyWith`, that no guard could name.

    So the transcription is checked against the declarations from here, both
    directions: every `static const double lh*` declared in the theme must
    appear in the test's ladder, and every rung the test lists must be
    declared. Ordering is deliberately NOT re-checked -- that leg already
    works and it is the test's job to keep owning; this reader only refuses to
    let the list become a closed copy that drifts from the source of truth.
    """
    theme = os.path.join(REPO, "lib", "src", "core", "theme", "app_theme.dart")
    with open(theme, encoding="utf-8") as fh:
        code = _strip_comments(fh.read())
    declared = re.findall(r"static const double (lh\w+)\s*=", code)

    test_path = os.path.join(REPO, "test", "line_height_token_test.dart")
    with open(test_path, encoding="utf-8") as fh:
        test_src = fh.read()
    listed = re.findall(r"AppTheme\.(lh\w+)", test_src)
    # The value-pinning test above the ordering test names every rung too, so
    # the listing is the union of both -- either place is a place the next rung
    # has to be added, and a rung in neither is exactly the orphan we hunt.
    _assert(declared,
            "line_height_ladder_reader read zero rungs -- this reader is "
            "broken, not the tree")
    _assert(len(declared) >= 10,
            "read %d `lh*` tokens, expected at least 10 -- if the theme was "
            "genuinely trimmed, raise this floor deliberately rather than "
            "letting the reader quietly shrink with it" % len(declared))

    orphans = [d for d in declared if d not in listed]
    ghosts = [l for l in set(listed) if l not in declared]
    _assert(not orphans,
            "app_theme.dart declares a line-height token the ladder test "
            "never names -- an off-ladder `height:` the tree may inherit "
            "through copyWith and that no guard can name: %s"
            % ", ".join(sorted(orphans)))
    _assert(not ghosts,
            "line_height_token_test.dart walks line-heights app_theme.dart "
            "does not declare -- a rung that cannot exist, which means the "
            "test is reading a stale copy: %s" % ", ".join(sorted(ghosts)))


def radius_ladder_reader():
    """The radius leg -- `rXs..rXl` plus the `rPill` sentinel -- and the
    question the tracking tick left as the next one: is the radius ladder
    derived by any guard, or is it a hand-copy the way weight and line-height
    were?

    Answer, measured before this reader existed: **a hand-copy, and a
    narrower rule than R1 looks.**

    `test/card_recipe_test.dart:265-270` pins all six values:

        expect(AppTheme.rXs, 6);   expect(AppTheme.rSm, 12);
        expect(AppTheme.rMd, 16);  expect(AppTheme.rLg, 20);
        expect(AppTheme.rXl, 28);  expect(AppTheme.rPill, 999);

    which is the file transcribing the thing it claims to check -- the same
    defect `font_weight_token_test.dart` had. What made it invisible is that
    R1 *looks* like it covers the family: "a radius is named, never typed"
    scans every `BorderRadius.circular(digit)`. So the guard enforces the
    **shape** of a radius (it is named) and never **which** name, and a new
    named radius satisfies it perfectly.

    Measured: planted `rWild = 13` beside the real six, declared with no
    measurement behind it, and applied for real from `lib/`
    (`BorderRadius.circular(AppTheme.rWild)` in `review_screen.dart`, over a
    screen that was using `rSm`). `card_recipe_test.dart` -> **all green, 16
    tests**; `home_location_pill_test.dart` + `project_card_budget_strip_test
    .dart` -> **green**; this census -> **9 passed, 0 failed**. A 7 dp radius
    that is not on the ladder, carrying a design decision nobody made, and the
    whole radius guard family calls it clean.

    So the check is derived from `app_theme.dart` and runs in five directions:

      * **orphan** -- a radius declared in the theme that
        `card_recipe_test.dart` never names. This is the plant above.
      * **ghost** -- a radius the guard names that the theme does not
        declare, so `expect(AppTheme.<token>, 6)` pins nothing.
      * **unapplied** -- a radius nothing in `lib/` ever applies, which is the
        other half of "one owner": a corner-shape decision that exists only in
        the theme is the shape the next caller finds and assumes was drawn.
      * **ordering + distinctness** -- the four rungs `rXs < rSm < rMd < rLg <
        rXl`, strictly. This is the direction the other three ladders had and
        tracking did not; radius has a real ladder, so it gets the claim.
      * **sentinel** -- `rPill` is deliberately NOT a rung. `999` is "as round
        as the platform will let you be", so putting it through an ascending
        order check would either pass for the wrong reason or force a
        fudge factor into the rule. It is named explicitly and asserted to sit
        above every rung and to be distinct from them, which is the property
        that actually matters: the pill radius must not collide with a real
        corner.

    Floor: 5 rungs and 1 sentinel, the counts measured at HEAD, so the reader
    cannot pass on a theme it failed to read.
    """
    theme = os.path.join(REPO, "lib", "src", "core", "theme", "app_theme.dart")
    with open(theme, encoding="utf-8") as fh:
        code = _strip_comments(fh.read())
    declared = re.findall(r"static const double (r[A-Z]\w*)\s*=", code)
    _assert(declared,
            "radius_ladder_reader read zero tokens -- this reader is broken, "
            "not the tree")

    # `rPill` is a sentinel, not a rung: 999 means "fully rounded", so it is
    # excluded from the ordering claim rather than fudged into it.
    sentinels = [d for d in declared if d == "rPill"]
    rungs = [d for d in declared if d not in sentinels]

    guard_path = os.path.join(REPO, "test", "card_recipe_test.dart")
    with open(guard_path, encoding="utf-8") as fh:
        guard_src = fh.read()
    named = set(re.findall(r"AppTheme\.(r[A-Z]\w*)", guard_src))

    applied = set()
    for root, _dirs, files in os.walk(os.path.join(REPO, "lib")):
        for fname in files:
            if not fname.endswith(".dart"):
                continue
            if fname == "app_theme.dart":
                continue  # the declaration is not a use
            with open(os.path.join(root, fname), encoding="utf-8") as fh:
                applied |= set(re.findall(r"AppTheme\.(r[A-Z]\w*)", fh.read()))

    orphans = [d for d in declared if d not in named]
    ghosts = [g for g in sorted(named) if g not in declared]
    unapplied = [d for d in declared if d not in applied]

    _assert(not orphans,
            "app_theme.dart declares a radius token that card_recipe_test.dart "
            "never names -- R1 only insists a radius is NAMED, never which "
            "name, so an invented token satisfies it perfectly and arrives off "
            "the ladder with no measurement and no owner: %s"
            % ", ".join(orphans))
    _assert(not ghosts,
            "card_recipe_test.dart names a radius token app_theme.dart does "
            "not declare -- the guard is pinning a value that does not exist, "
            "so its expect() asserts nothing: %s" % ", ".join(ghosts))
    _assert(not unapplied,
            "app_theme.dart declares a radius token nothing in lib/ ever "
            "applies -- a corner-shape decision that exists only in the theme, "
            "which is the shape the next caller will find and assume was "
            "drawn: %s" % ", ".join(unapplied))

    values = dict(re.findall(r"static const double (r[A-Z]\w*)\s*=\s*([0-9.]+)",
                             code))
    _assert(all(r in values for r in rungs),
            "could not read a numeric value for every rung (%s) -- the ladder "
            "cannot be ordered from a token whose right-hand side is not a "
            "literal" % ", ".join(r for r in rungs if r not in values))
    ladder = [float(values[r]) for r in rungs]
    ordered = sorted(set(ladder))
    _assert(ladder == ordered,
            "the radius ladder is not strictly ascending, weakest first: %s "
            "= %s. A card drawn at the wrong rung is not a taste call -- it is "
            "the design ladder skipped."
            % (", ".join(rungs), ", ".join("%g" % v for v in ladder)))
    _assert(len(set(ladder)) == len(ladder),
            "the radius ladder repeats a value: %s"
            % ", ".join("%s=%g" % (r, float(values[r])) for r in rungs))

    _assert(sentinels,
            "app_theme.dart declares no `rPill` sentinel -- the fully-rounded "
            "radius lost its name, so every pill is being drawn at whatever "
            "corner happens to be free")
    for s_name in sentinels:
        _assert(float(values[s_name]) > max(ladder),
                "%s (%g) must sit above every rung (%g) -- it means 'as round "
                "as the platform allows', and if it lands inside the ladder a "
                "pill and a card corner draw the same shape by accident"
                % (s_name, float(values[s_name]), max(ladder)))
        _assert(float(values[s_name]) not in ladder,
                "%s (%g) collides with a rung -- the pill radius and a card "
                "corner are the same number, so one of them is a lie"
                % (s_name, float(values[s_name])))

    _assert(len(rungs) >= 5,
            "read %d radius rungs; HEAD has 5 (rXs..rXl), so fewer means the "
            "reader read nothing" % len(rungs))


def spacing_ladder_reader():
    """The spacing leg -- `s4..s32` on the theme's "one 4 dp grid" -- and the
    shape the previous tick predicted, measured here rather than assumed.

    Answer, measured before this reader existed: **a ratchet, not a ladder.**

    `test/card_recipe_test.dart:288-295` transcribes all eight values by hand
    and then asserts `v % 4 == 0` for each. So the spacing guard enforces the
    **form** of a spacing value (it is a multiple of 4) and never **which
    token** holds it -- the same defect `radius_ladder_reader` just found one
    file over, and the reason the "Next" note called `s*` the likelier find:
    eight rungs behind a value-shaped check reads as covered.

    Measured: planted `sWild = 6` beside the real eight and applied it for
    real from `lib/` (`auth_gate.dart`, over a gap that was `AppTheme.s8`).
    `card_recipe_test.dart` -> **all green**; R4, the off-grid ratchet, stayed
    green and said nothing, because `_literals()` skips identifiers by design
    -- a token is off the guard's map entirely. That blind spot is documented
    in R4's own header. A 6 dp gap, 2 dp off the grid it claims every gap comes
    from, and the whole spacing guard family called the tree clean.

    So the check is derived from `app_theme.dart` and runs in five directions:

      * **orphan** -- a rung the card-recipe guard never names. This is the
        plant above.
      * **ghost** -- a rung the guard names that the theme does not declare,
        so its `expect()` asserts nothing.
      * **unapplied** -- a rung nothing in `lib/` ever applies, which is the
        other half of "one owner".
      * **grid** -- every rung is a positive multiple of 4. The theme says
        "one 4 dp grid" in prose; this makes the prose a claim. Note this is
        deliberately NOT the ratchet: R4 counts off-grid *literals* and may
        only go down, whereas this constrains the rungs themselves.
      * **ordering + distinctness** -- `s4 < s8 < ... < s32`, strictly. Eight
        named rungs are a ladder and the ladder gets the claim; a duplicated
        value means two names for one step and the next caller picks either.

    Floor: 8 rungs, the count measured at HEAD, so the reader cannot pass on a
    theme it failed to read.
    """
    theme = os.path.join(REPO, "lib", "src", "core", "theme", "app_theme.dart")
    with open(theme, encoding="utf-8") as fh:
        code = _strip_comments(fh.read())

    # The rungs are numeric-named (`s4`..`s32`), so the family is
    # `s\d+\w*` and NOT `s[A-Z]\w*` -- the first version of this reader used
    # the radius reader's alphabet-only shape, matched zero tokens on the real
    # theme, and failed green-until-reverted with "read zero tokens". What the
    # radius reader's lesson actually transfers is the *shared prefix*: the
    # strip-card metrics (`stripCardW`, `stripH`, `stripInnerH`) carry the
    # same leading `s` and are card geometry, not spacing rungs, so neither
    # `s\w*` nor `s[A-Z]\w*` may be used. A named rogue (`sWild`) is still in
    # the family -- that is the plant this reader exists to catch.
    declared = re.findall(r"static const double (s(?:\d+|[A-Z]\w*))\s*=", code)
    _assert(declared,
            "spacing_ladder_reader read zero tokens -- this reader is broken, "
            "not the tree")

    guard_path = os.path.join(REPO, "test", "card_recipe_test.dart")
    with open(guard_path, encoding="utf-8") as fh:
        guard_src = fh.read()
    named = set(re.findall(r"AppTheme\.(s(?:\d+|[A-Z]\w*))", guard_src))

    applied = set()
    for root, _dirs, files in os.walk(os.path.join(REPO, "lib")):
        for fname in files:
            if not fname.endswith(".dart"):
                continue
            if fname == "app_theme.dart":
                continue  # the declaration is not a use
            with open(os.path.join(root, fname), encoding="utf-8") as fh:
                applied |= set(re.findall(r"AppTheme\.(s(?:\d+|[A-Z]\w*))", fh.read()))

    orphans = [d for d in declared if d not in named]
    ghosts = [g for g in sorted(named) if g not in declared]
    unapplied = [d for d in declared if d not in applied]

    _assert(not orphans,
            "app_theme.dart declares a spacing rung card_recipe_test.dart "
            "never names -- the guard asserts `v %% 4 == 0`, which constrains "
            "the SHAPE of a value and never which token holds it, so an "
            "invented rung satisfies it perfectly and arrives off the grid "
            "with no measurement and no owner: %s" % ", ".join(orphans))
    _assert(not ghosts,
            "card_recipe_test.dart names a spacing rung app_theme.dart does "
            "not declare -- the guard is pinning a value that does not exist, "
            "so its expect() asserts nothing: %s" % ", ".join(ghosts))
    _assert(not unapplied,
            "app_theme.dart declares a spacing rung nothing in lib/ ever "
            "applies -- a gap decision that exists only in the theme, which "
            "is the rung the next caller will find and assume was drawn: %s"
            % ", ".join(unapplied))

    values = dict(re.findall(r"static const double (s(?:\d+|[A-Z]\w*))\s*=\s*([0-9.]+)",
                             code))
    _assert(all(r in values for r in declared),
            "could not read a numeric value for every rung (%s) -- the ladder "
            "cannot be ordered from a token whose right-hand side is not a "
            "literal" % ", ".join(r for r in declared if r not in values))

    off_grid = [r for r in declared
                if float(values[r]) <= 0 or float(values[r]) % 4 != 0]
    _assert(not off_grid,
            "the spacing ladder claims one 4 dp grid and these rungs are off "
            "it: %s. R4 counts off-grid LITERALS and may only go down; it "
            "cannot see a named token, which is how a 6 dp gap reached a "
            "screen while the ratchet read zero."
            % ", ".join("%s=%g" % (r, float(values[r])) for r in off_grid))

    ladder = [float(values[r]) for r in declared]
    ordered = sorted(set(ladder))
    _assert(ladder == ordered,
            "the spacing ladder is not strictly ascending, weakest first: %s "
            "= %s. A gap drawn at the wrong rung is not a taste call -- it is "
            "the design ladder skipped."
            % (", ".join(declared), ", ".join("%g" % v for v in ladder)))
    _assert(len(set(ladder)) == len(ladder),
            "the spacing ladder repeats a value: %s"
            % ", ".join("%s=%g" % (r, float(values[r])) for r in declared))

    _assert(len(declared) >= 8,
            "read %d spacing rungs; HEAD has 8 (s4..s32), so fewer means the "
            "reader read nothing" % len(declared))


def tracking_token_reader():
    """The tracking leg -- the one type-scale family with a **single** rung,
    and the question the last tick left open: is a single-value family guarded
    at all, or merely absent from the census because there is nothing to
    derive from?

    Answer, measured before this reader existed: **not guarded at all.**

    Planted `lsWild = 0.4` beside the real `lsDigits`, declared with no
    measurement behind it, and used for real by a widget in `lib/` --
    `const p = TextStyle(letterSpacing: AppTheme.lsWild)`. That is precisely
    the defect `letter_spacing_token_test.dart` was written to prevent: the
    file's own header says tracking "was the last unwritten leg of the type
    scale" and that tracking on Arabic widened a word 15 % for the same
    letters, and the rule it enforces is "every `letterSpacing:` names an
    `AppTheme.ls*` token". A second token satisfies that rule perfectly --
    it *is* an `ls*` token. The rule constrains the **shape** of the value,
    never **which** token, so a new tracking value arrives with no
    measurement, no owner and no guard.

    Measured: `letter_spacing_token_test.dart` + `type_scale_test.dart` ->
    **all green, 21 tests**, and this census -> **8 passed, 0 failed**. Same
    blind spot as the weight and line-height ladders, one level along: not a
    transcription but a **missing collection**. `scale` and `weights` have
    lists; `lsDigits` never got one, so there was nothing for a completeness
    claim to be written against, and no claim was made.

    So the check is derived from `app_theme.dart` instead of copied, and it
    runs in all three directions that can actually fail:

      * **orphan** -- a tracking token declared in the theme that
        `letter_spacing_token_test.dart` never names. This is the plant above:
        a value in the tree with no owner and no measurement.
      * **ghost** -- a token the guard names that the theme does not declare,
        i.e. the guard pinned a value that no longer exists and its
        `expect(AppTheme.<token>, 1.1)` is pinning nothing.
      * **unapplied** -- a token nothing in `lib/` ever applies, which is the
        other half of "one owner": a tracking value that exists purely in the
        theme is a letter-spacing decision nobody has made yet, and the next
        person to find it will use it and assume it was measured.

    No `ls*` ladder exists to be ordered or checked for distinctness, so
    unlike the other three readers this one asserts no ordering -- there is
    nothing to order. The floor is `>= 1`, deliberately the weakest of the
    four, because this family is deliberately one value wide; the floor
    exists only so the reader cannot pass on a theme it failed to read.
    """
    theme = os.path.join(REPO, "lib", "src", "core", "theme", "app_theme.dart")
    with open(theme, encoding="utf-8") as fh:
        code = _strip_comments(fh.read())
    declared = re.findall(r"static const double (ls\w+)\s*=", code)
    _assert(declared,
            "tracking_token_reader read zero tokens -- this reader is broken, "
            "not the tree")

    guard_path = os.path.join(REPO, "test", "letter_spacing_token_test.dart")
    with open(guard_path, encoding="utf-8") as fh:
        guard_src = fh.read()
    # the guard's own `_kToken` constant is its subject; naming it in prose or
    # in a plant counts, exactly as the line-height reader unions its two
    # lists -- either place is a place the next token has to be added.
    named = set(re.findall(r"AppTheme\.(ls\w+)", guard_src))

    applied = set()
    for root, _dirs, files in os.walk(os.path.join(REPO, "lib")):
        for fname in files:
            if not fname.endswith(".dart"):
                continue
            if fname == "app_theme.dart":
                continue  # the declaration is not a use
            with open(os.path.join(root, fname), encoding="utf-8") as fh:
                applied |= set(re.findall(r"AppTheme\.(ls\w+)", fh.read()))

    orphans = [d for d in declared if d not in named]
    ghosts = [g for g in sorted(named) if g not in declared]
    unapplied = [d for d in declared if d not in applied]

    _assert(not orphans,
            "app_theme.dart declares a tracking token that "
            "letter_spacing_token_test.dart never names -- a second tracking "
            "value the rule 'every letterSpacing names an ls* token' cannot "
            "refuse, because the invented token satisfies it perfectly, so it "
            "arrives with no measurement and no owner: %s"
            % ", ".join(orphans))
    _assert(not ghosts,
            "letter_spacing_token_test.dart names a tracking token "
            "app_theme.dart does not declare -- the guard is pinning a value "
            "that does not exist, so its expect() asserts nothing: %s"
            % ", ".join(ghosts))
    _assert(not unapplied,
            "app_theme.dart declares a tracking token nothing in lib/ ever "
            "applies -- a letter-spacing decision that exists only in the "
            "theme, which is the shape the next caller will find and assume "
            "was measured: %s" % ", ".join(unapplied))
    _assert(len(declared) >= 1,
            "read %d tracking tokens; this family is deliberately one value "
            "wide, so 1 is the floor and anything below it means the reader "
            "read nothing" % len(declared))


def outline_width_reader():
    """The outline leg -- `hairline`, `hairlineSelected`, `hairlineFocus`,
    `hairlineResting`, `ring` -- and the shape the previous tick predicted as
    the last one left: **a family that is mostly aliases of each other**.

    The other four readers all assume a ladder: named rungs, distinct values,
    strictly ordered. This family is the opposite. At HEAD:

        hairline         = 1.5
        hairlineSelected = 2
        hairlineFocus    = 2
        hairlineResting  = hairline     <- an IDENTIFIER, not a literal
        ring             = 3

    Four facts, each of which a strict-ordering reader gets wrong:

      * **Two of the five collide on a value** (`hairlineSelected` and
        `hairlineFocus` are both 2) -- and that is *deliberate*, documented in
        `app_theme.dart` and now asserted in `hairline_token_test.dart`. A
        distinctness claim would fire on correct code.
      * **One resolves to another token** (`hairlineResting = hairline`). The
        spacing/radius readers regex a NUMBER off the right-hand side and
        would read that as "could not read a value", failing green-until-
        reverted on the real tree -- the same bug this file already records
        twice.
      * **The family is not ascending.** `ring` (3) is thicker than
        `hairlineSelected` (2), but `ring` is not "more hairline than
        selected" -- it is a different job (framing an avatar inside a box,
        not marking a control). An ordering claim would assert a relationship
        the theme explicitly denies.
      * **`ring` is off the 4 dp grid by design** (`worker_profile_column_test
        .dart:296` asserts `ring % 4 != 0`), so the spacing reader's grid rule
        would fire on a token its own guard says is correct.

    So there is no ladder to order, and pretending otherwise is how a reader
    becomes a guard that fails on the tree it was written for. What IS true,
    and what this reader claims instead:

      * **orphan** -- an outline token the theme declares that no test names
        by name. This is not hypothetical: measured at HEAD, `hairlineFocus`
        had **zero** uses in `test/`, so the theme's "highest-stakes input"
        focus ring -- the phone field, the number an Algerian customer types
        first -- was asserted nowhere by name. It is owned now, by a test in
        `hairline_token_test.dart` that names the whole family.
      * **ghost** -- a name a test uses that the theme does not declare.
      * **unapplied** -- a token nothing in `lib/` ever applies. One owner and
        one user, same as every other family here.
      * **resolution** -- every token resolves to a concrete double, following
        an identifier right-hand side to its literal. The other four readers
        structurally cannot make this one: they regex a NUMBER off the
        right-hand side, so `hairlineResting = hairline` reads to them as "no
        value" and they would fail green-until-reverted on a clean tree.
        *MEASURED, AND IT IS NOT THE CLAIM I EXPECTED.* A sixth token arriving
        COMPLETE -- declared, named by a test, and applied for real from
        `lib/` -- satisfies orphan, ghost, unapplied and resolution together.
        This reader passed it at 12/0 with a 1.2 dp control outline drawn on the
        app's primary button. So resolution is kept for what it genuinely
        protects (a family member whose value cannot be resolved is a family
        member with no meaning) and the sixth-name case is caught by the
        membership claim below and by `hairline_token_test.dart`, NOT here.
      * **alias integrity** -- a token defined AS another token must stay equal
        to it. `hairlineResting` exists precisely so a change to `hairline`
        moves it; re-typed as the literal `1.5` it becomes a second
        independent number that agrees today and drifts silently tomorrow, and
        no other direction here would notice.

    Measured, not argued: `hairlineWild = 1.2` planted beside the real five
    and applied for real from `lib/` (`ui.dart`, over an outline that was
    `hairlineResting`) left `hairline_token_test.dart` at **5 green**,
    `card_recipe_test.dart` at **16 green** and this census at **11 passed,
    0 failed**. A 1.2 dp control outline, a quarter dp under the token it
    replaced, and every hairline guard in the tree called it clean -- because
    `_classify` judges a width by its DIGITS, which constrains the shape of a
    value and never which token holds it.

    The grid/order/distinctness claims are deliberately ABSENT, and that is
    the finding rather than an omission: `ring` breaks the grid, the family
    breaks the order, and two tokens break distinctness, each with a test
    saying so. A reader that added them would have to allowlist the whole
    family -- the "net that closes behind itself" the radius reader refused.
    """
    theme = os.path.join(REPO, "lib", "src", "core", "theme", "app_theme.dart")
    with open(theme, encoding="utf-8") as fh:
        code = _strip_comments(fh.read())

    # The family is the `hairline*` prefix plus the one named ring. `ring` is
    # listed explicitly rather than matched by a bare `ring` pattern, because
    # a future `ringGap` would be a gap and not an outline -- and what makes
    # this family different from the spacing ladder is precisely that these
    # widths are NOT on the spacing grid.
    declared = re.findall(r"static const double (hairline\w*|ring)\s*=", code)
    _assert(declared,
            "outline_width_reader read zero tokens -- this reader is broken, "
            "not the tree")

    raw = dict(re.findall(
        r"static const double (hairline\w*|ring)\s*=\s*([^;]+);", code))
    _assert(all(d in raw for d in declared),
            "could not read a right-hand side for every outline token (%s) -- "
            "the family cannot be resolved from a token this reader cannot see"
            % ", ".join(d for d in declared if d not in raw))

    # A right-hand side is either a literal or ANOTHER outline token
    # (`hairlineResting = hairline`). Insisting the alias target is in the
    # family is what lets this reader say something the other four cannot: at
    # HEAD one of the five is not a number at all, and the spacing/radius
    # readers regex a NUMBER out of the right-hand side, so they would read
    # that as "no value" and fail green-until-reverted on a clean tree.
    for name in declared:
        rhs = raw[name].strip()
        _assert(re.fullmatch(r"[0-9.]+", rhs) or rhs in declared,
                "%s = %s, which is neither a literal nor another outline "
                "token -- the value cannot be resolved, so every claim this "
                "reader makes about it would be vacuous" % (name, rhs))

    # Literals first, then chase aliases (`a = b; b = c; c = 2`) with a
    # visited set so a cycle is reported rather than hung on.
    values = {}
    for name in declared:
        rhs = raw[name].strip()
        if re.fullmatch(r"[0-9.]+", rhs):
            values[name] = float(rhs)
    for name in declared:
        if name in values:
            continue
        seen, cur = {name}, raw[name].strip()
        while not re.fullmatch(r"[0-9.]+", cur):
            _assert(cur not in seen,
                    "the outline aliases form a cycle (%s) -- no token in it "
                    "has a value" % " -> ".join(sorted(seen)))
            seen.add(cur)
            cur = raw[cur].strip()
        values[name] = float(cur)

    _assert(len(values) >= 5,
            "read %d outline tokens; HEAD has 5 (hairline, hairlineSelected, "
            "hairlineFocus, hairlineResting, ring), so fewer means the reader "
            "read nothing" % len(values))
    bad = ["%s=%g" % (k, v) for k, v in values.items() if v <= 0]
    _assert(not bad,
            "an outline token is zero or negative -- a border that draws "
            "nothing: %s" % ", ".join(bad))

    named = set()
    for fname in os.listdir(TESTS):
        if not fname.endswith(".dart"):
            continue
        with open(os.path.join(TESTS, fname), encoding="utf-8") as fh:
            named |= set(re.findall(r"AppTheme\.(hairline\w*|ring)\b",
                                    fh.read()))

    orphans = [d for d in declared if d not in named]
    _assert(not orphans,
            "app_theme.dart declares an outline token no test names by name -- "
            "hairline_token_test.dart judges a width by its DIGITS, which "
            "constrains the shape of a width and never which token holds it, "
            "so a sixth name walks in the same door tracking walked through: %s"
            % ", ".join(orphans))
    ghosts = [g for g in sorted(named) if g not in declared]
    _assert(not ghosts,
            "a test names an outline token app_theme.dart does not declare -- "
            "its expect() is pinning a value that does not exist: %s"
            % ", ".join(ghosts))

    applied = set()
    for root, _dirs, files in os.walk(os.path.join(REPO, "lib")):
        for fname in files:
            if not fname.endswith(".dart") or fname == "app_theme.dart":
                continue
            with open(os.path.join(root, fname), encoding="utf-8") as fh:
                applied |= set(re.findall(r"AppTheme\.(hairline\w*|ring)\b",
                                         fh.read()))
    unapplied = [d for d in declared if d not in applied]
    _assert(not unapplied,
            "app_theme.dart declares an outline token nothing in lib/ ever "
            "applies -- an outline weight that exists only in the theme is the "
            "one the next caller will find and assume was measured: %s"
            % ", ".join(unapplied))

    # MEMBERSHIP -- the claim the four relations above cannot make, and the one
    # this reader was rewritten around after the plant below proved they could
    # not. A sixth name arriving COMPLETE (declared, named by a test, applied
    # from `lib/`) satisfies orphan, ghost, unapplied AND resolution together,
    # so every relation this reader had passed it: `hairlineWild = 1.2` drew a
    # 1.2 dp outline on the app's primary button and this reader said the tree
    # was clean. Nothing above can see it, because each asks "is this token
    # well-formed and used", never "is this token PERMITTED".
    #
    # So the reviewed set is pinned here, and a token outside it is reported.
    # This is the opposite of the "net that closes behind itself" the radius
    # reader refused: `known` is a constant, never derived from the theme, so it
    # cannot accept itself and cannot be widened by the very edit it catches.
    # Editing `known` is a deliberate act -- a new outline weight is a design
    # decision and belongs in the backlog, not in a guard that shrugs.
    known = {"hairline": 1.5, "hairlineSelected": 2, "hairlineFocus": 2,
             "hairlineResting": 1.5, "ring": 3}
    extra = ["%s=%g (not in the reviewed set)" % (k, v)
             for k, v in values.items() if k not in known]
    _assert(not extra,
            "app_theme.dart exposes an outline width that was never reviewed -- "
            "a sixth name arrived complete (declared, named by a test, applied "
            "from lib/) and every other relation in this reader passed it: %s. "
            "A new outline weight is a design decision: add it to `known` here "
            "and to hairline_token_test.dart deliberately, with the reason."
            % ", ".join(extra))
    missing = [k for k in known if k not in values]
    _assert(not missing,
            "an outline width that was reviewed no longer exists in the theme: "
            "%s -- callers name it, or a token was dropped and its callers are "
            "now reading a different one" % ", ".join(missing))
    _assert(all(abs(values[k] - v) < 1e-9 for k, v in known.items()
                if k in values),
            "an outline width the theme declares is NOT the value this reader "
            "reviewed -- a re-value (hairlineSelected 2 -> 1.5, say) satisfies "
            "every shape relation here while quietly thinning the app's "
            "outlines: %s"
            % ", ".join("%s=%g (reviewed %g)" % (k, values[k], v)
                        for k, v in known.items()
                        if k in values and abs(values[k] - v) >= 1e-9))

    # The alias claim, in two halves, and the split is load-bearing.
    #
    # HALF 1 -- the alias structure must still EXIST. A token whose
    # right-hand side names another token is what makes this family a family
    # of aliases instead of five unrelated numbers, and the equality below can
    # only check the edges that are still there: re-typing `hairlineResting =
    # hairline` as `= 1.5` leaves a plain literal, so the alias branch simply
    # never runs and the re-type is invisible. Measured, not reasoned -- this
    # reader passed a tree carrying exactly that edit, which is why the claim
    # is that the edge is present rather than only that it agrees.
    aliases = [n for n in declared if raw[n].strip() in declared]
    _assert(aliases,
            "no outline token is defined AS another outline token -- the "
            "family has lost its alias structure. At HEAD hairlineResting is "
            "defined as hairline, and the point of that is that moving "
            "`hairline` moves it; re-typed as a literal it becomes a second "
            "independent number that agrees today and drifts silently "
            "tomorrow, and nothing else in the tree would notice.")
    for name in aliases:
        rhs = raw[name].strip()
        _assert(values[name] == values[rhs],
                "%s is defined as %s but resolves to %g against %s's %g -- the "
                "alias no longer agrees with the token it points at"
                % (name, rhs, values[name], rhs, values[rhs]))


def _strip_comments(text):
    """Dart text with `//` and block comments removed, newlines kept."""
    out = []
    in_block = False
    for line in text.split("\n"):
        res, i = [], 0
        if not in_block:
            while i < len(line):
                if line.startswith("/*", i):
                    in_block = True
                    i += 2
                    break
                if line.startswith("//", i):
                    break
                res.append(line[i])
                i += 1
        while in_block:
            end = line.find("*/", i)
            if end < 0:
                i = len(line)
                break
            in_block = False
            i = end + 2
        out.append("".join(res))
    return "\n".join(out)


def _results():
    # 1. the census finds something at all -- a scanner that matches nothing
    #    reports a clean tree, which is the exact failure this file exists for
    found = exemptions()
    yield ("the census reads the guards it was written to read", lambda: (
        _assert(len(found) >= 8,
                "only %d file-level exemption(s) found; expected >= 8 -- this "
                "reader is broken, not the tree" % len(found))))

    def no_unwatched_exemption():
        unwatched = []
        for guard, line, target in found:
            if not readers(target):
                unwatched.append(
                    "  %s:%d exempts %s and NO test reads it as source"
                    % (guard, line, target))
        _assert(not unwatched,
                "an exemption with no compensating reader -- these files are "
                "invisible to every guard in the tree:\n%s" % "\n".join(
                    unwatched))

    yield ("no exemption is left without a compensating reader",
           no_unwatched_exemption)

    # 2. the control: an exemption the census MUST fail on. Without it, the
    #    census could be a rule that always passes -- and a guard that cannot
    #    fail is not a guard.
    def control_fails():
        fake = ("never_real_guard_test.dart", 1, "lib/src/screens/gone.dart")
        _assert(not readers(fake[2]),
                "the control file is 'watched'; the census cannot fail")
    yield ("CONTROL -- an exempt file nobody reads is reported",
           control_fails)

    # 3. the derived reader for `motion.dart` runs on every pass. A census
    #    that reports a compensating reader which then silently fails to
    #    execute is the same defect one level up.
    yield ("motion.dart's derived reader actually reads the ladder",
           motion_reader)

    # 4. the two type-scale ladders, same defect class as motion.dart: a test
    #    that asserts against a copy of the thing it claims to check. The
    #    weight one WAS the copy; the size one is checked here so it cannot
    #    become one.
    yield ("app_theme.dart's weight ladder is derived, not transcribed",
           weight_ladder_reader)
    yield ("app_theme.dart's size ladder stays complete", size_ladder_reader)
    yield ("app_theme.dart's line-height ladder is not a stale copy",
           line_height_ladder_reader)
    # 4b. the tracking leg. Deliberately ONE value wide, so unlike the three
    #     ladders there is no collection to derive completeness from -- which
    #     is why it was unguarded rather than misguarded. See
    #     tracking_token_reader() for the plant that proved it.
    yield ("app_theme.dart's tracking token has one owner and one user",
           tracking_token_reader)
    # 4c. the radius leg -- `rXs..rXl` plus the `rPill` sentinel. R1 in
    #     card_recipe_test.dart looks like it covers this family ("a radius is
    #     named, never typed") but it constrains the SHAPE of the value, never
    #     which token, so a seventh radius walks in the same door tracking did.
    #     See radius_ladder_reader() for the plant that proved it.
    yield ("app_theme.dart's radius ladder is derived, not transcribed",
           radius_ladder_reader)
    # 4d. the spacing leg -- `s4..s32` on the theme's "one 4 dp grid". The
    #     off-grid ratchet R4 looks like it covers this family, but it counts
    #     LITERALS and `_literals()` skips identifiers by design, so a named
    #     rung is off its map entirely and a 9th token walks in the same door.
    #     See spacing_ladder_reader() for the plant that proved it.
    yield ("app_theme.dart's spacing ladder is derived, not transcribed",
           spacing_ladder_reader)
    # 4e. the outline leg -- `hairline*` plus `ring`. The LAST family that is
    #     neither a type scale nor a spacing ladder: four of the five are
    #     ALIASES of each other by value, a shape none of the four readers
    #     above can express, since each assumes rungs are distinct and ordered.
    #     `ring` is off the 4 dp grid by design and a test asserts it, so the
    #     spacing reader's grid rule would fire on correct code. See
    #     outline_width_reader() for the plant that proved the gap.
    yield ("app_theme.dart's outline widths have one owner and one user",
           outline_width_reader)

    # 5. the control for THIS reader: the planted sixth rung the tree does not
    #    have. A reader that cannot fail on a known-bad input is not a reader,
    #    and the weight reader is new code in a file whose whole argument is
    #    that hand-copied assertions do not fail.
    def ladder_control_fails():
        for declared, listed, label in (
            (["wBody", "wThunder"], ["wBody"], "weight"),
            (["fsBody", "fsGhost"], ["fsBody"], "size"),
            (["lhBody", "lhThunder"], ["lhBody"], "line-height"),
            (["lsDigits", "lsWild"], ["lsDigits"], "tracking"),
            (["rXs", "rWild"], ["rXs"], "radius"),
            (["s4", "sWild"], ["s4"], "spacing"),
            # The outline family is NOT a ladder, so this control covers the
            # orphan relation only -- the shared part. Its distinctness is
            # measured by the membership claim inside outline_width_reader().
            (["hairline", "hairlineWild"], ["hairline"], "outline"),
        ):
            orphans = [d for d in declared if d not in listed]
            _assert(orphans,
                    "the %s ladder control found no orphan -- the readers "
                    "cannot fail, which is the defect class this file is "
                    "about" % label)
    yield ("CONTROL -- a declared rung missing from the ladder is reported",
           ladder_control_fails)


def _assert(cond, msg):
    if not cond:
        raise AssertionError(msg)


def main():
    ok = 0
    bad = 0
    for name, fn in _results():
        try:
            fn()
        except AssertionError as exc:
            bad += 1
            print("FAIL  %s\n      %s" % (name, exc))
        except Exception as exc:  # a crash is a failure, not a skip
            bad += 1
            print("ERROR %s\n      %r" % (name, exc))
        else:
            ok += 1
            print("ok    %s" % name)
    print("\n%d passed, %d failed" % (ok, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
