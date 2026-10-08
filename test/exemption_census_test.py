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
