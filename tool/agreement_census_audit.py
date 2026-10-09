#!/usr/bin/env python3
"""Measure the two pinned census numbers in `agreement_comment_test.dart`.

The 9 Oct tick left this pair red for four ticks running and asked for a full
look. This is that look, as far as a host with no room for a Dart VM can take
it: **the two pins are STALE, both drifted by exactly the amount two later
features explain, and one of them is not falsifiable for the mutation its own
comment names.** The pins themselves are Dart, so they cannot be fixed on a
boxed-out host -- but the numbers they assert can be measured here, in Python,
and the file's OWN finding is that a number which lives only in prose drifts.

    python3 tool/agreement_census_audit.py            # human summary
    python3 tool/agreement_census_audit.py --json     # machine
    echo $?   0 = pins agree with the tree
              1 = DRIFT -- a pin disagrees with what the tree holds
              2 = unreadable: the reader's vocabulary moved and this tool
                  declines to guess

**Why this reads the regexes out of the Dart file instead of carrying copies.**
A copy of `_probeLoose` here would be a second reader, and this backlog has
already spent three items learning what a second reader costs: two scanners of
one vocabulary that disagree about what a sentence says is a defect graded by
one and invisible to the other -- graded by nobody, in practice
(`agreement_comment_test.dart::_lineClaims`, written for exactly this). So the
patterns are EXTRACTED from `test/agreement_comment_test.dart` and compiled as
they are written. Every pattern this tool uses is Dart regex syntax that is
also valid Python, so no translation happens and none can be wrong. If an
extraction finds no pattern by that name the tool exits 2 rather than falling
back to a remembered copy: a tool that answers from a stale vocabulary is
worse than a tool that declines.

**And the pins are read, not assumed.** The two numbers live in the tree as
`expect(census.direct.length, 20, ...)` and `expect(census.surface.length,
25, ...)`. Parsing them is what keeps THIS tool from going stale the way the
pins did -- it has no constant of its own to rot.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

DART = "test/agreement_comment_test.dart"
ROOTS = ("lib", "test")

# The pins, by the expression that carries them. `expect(census.direct.length,
# 20, ...)` -- the value is whatever integer follows.
# A pin is `expect(census.<field>.length, <int>,` -- the trailing comma is what
# distinguishes a PIN from the FLOOR beside it (`greaterThanOrEqualTo(20),`),
# which is a bound and not a value. Both `,` and `;` terminate it, because
# `dart format` closes a wrapped expectation with whichever the line allows and
# a reformatted pin that stopped being read would report as agreement.
# Measured: the battery widened this to `[,;]` and the suite stayed green, so
# nothing pinned the COMMA itself until `test/agreement_census_audit_test.py`
# grew both halves of the rule.
PIN_RE = re.compile(
    r"expect\(\s*census\.(\w+)\.length\s*,\s*(\d+)\s*[,;]")


# --------------------------------------------------------------------------
# Reading the Dart reader's own vocabulary
# --------------------------------------------------------------------------
def dart_source(root: str) -> str:
    path = os.path.join(root, DART)
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _arg_list(src: str, start: int):
    """The text between the `(` at [start] and its match, STRING-AWARE.

    Measured on why: the first version counted parens blindly, and the very
    pattern this tool exists to read -- the `calls` RegExp -- has
    two unbalanced parens INSIDE a raw string, so the scanner ran off the end
    of the pattern and reported «RegExp( is unclosed» for a file whose every
    RegExp is closed. A reader that has to be right about balanced parens
    before it can be right about quotes is a reader that fails on precisely
    the patterns worth reading.

    So string literals are skipped wholesale: Dart strings here are '...' or
    "... " with a backslash escape and nothing else, which is
    enough to step over one.
    """
    depth, i = 1, start
    while i < len(src) and depth:
        ch = src[i]
        if ch in "'\"":
            quote = ch
            i += 1
            while i < len(src) and src[i] != quote:
                i += 2 if src[i] == "\\" else 1
            i += 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        i += 1
    if depth:
        raise LookupError("a RegExp( opened in %s is unclosed" % DART)
    return src[start:i - 1], i


def extract_regex(src: str, name: str) -> "re.Pattern[str]":
    """The compiled pattern of `<final|var> <name> = RegExp(...)` in [src].

    Dart's `RegExp` takes one or two arguments -- a plain string or a RAW
    string (`r'...'`, which is what every pattern this tool needs uses) and an
    optional named `caseSensitive:`. Both are assembled here.

    Two things this has to get right, and both are ways a tool like this
    silently grades something nobody wrote:

      * **the argument boundary.** `RegExp(` opens a paren that can itself
        contain the raw string, so the arguments are found by SCANNING to the
        matching close rather than by a regex up to the first `)`. The patterns
        in this file are written both ways -- `final _negated = RegExp(r'…')`
        at top level and `final calls = RegExp(r'…')` as a LOCAL inside
        `_routingCensus` -- so the declaration kind is matched loosely on
        purpose: a tool that only reads top-level finals finds two of the
        three patterns it needs and answers confidently about one.
      * **the raw string.** Dart has no escapes inside `r'...'`, so the body is
        taken verbatim; `plain` strings are unescaped, which is what
        `RegExp('import' r'…')` -- adjacent literals, as this file writes
        it -- needs in order to become one pattern.
    """
    decl = re.search(r"(?:final|var)\s+" + re.escape(name) + r"\s*=\s*RegExp\(",
                     src)
    if not decl:
        raise LookupError("no RegExp named %r in %s" % (name, DART))
    start = decl.end()
    args, i = _arg_list(src, start)

    parts = re.findall(r"r'((?:[^'\\]|\\.)*)'|'((?:[^'\\]|\\.)*)'", args)
    if not parts:
        raise LookupError("%r has no string literal to compile" % name)
    body = "".join(raw or dart_unescape(plain) for raw, plain in parts)
    flags = re.I if "caseSensitive: false" in args else 0
    return re.compile(body, flags)


def read_pins(src: str):
    """`{field: value}` for every pinned `expect(census.<field>.length, N, ...)`.

    A pin this cannot find is a pin that has been deleted, renamed or
    re-pointed -- so the caller compares the SET of pins it found against the
    set it was asked about, and a missing one is reported rather than ignored.
    Silence about a pin that no longer exists is how a guard stops guarding.
    """
    return {field: int(value) for field, value in PIN_RE.findall(src)}


# --------------------------------------------------------------------------
# The tree
# --------------------------------------------------------------------------
def dart_files(root: str):
    """Every `.dart` file the reader walks, in a stable order.

    **The `build/` exclusion is DELIBERATE rather than defensive, and that is
    a measured decision.** It is unreachable in the shape this walk has: the
    roots are `lib` and `test`, and a repo puts its build output at
    `<root>/build`, so no directory under either root can have a `build`
    component -- verified on this tree, where **zero** directories under
    `lib/` or `test/` contain one.

    So it is kept anyway, and the reason it is kept is worth stating: the
    guard this file exists to model is the reader's own, and a reader that is
    a *faithful copy* is one whose behaviour cannot drift from the original.
    If the roots ever change -- a vendored dependency under `lib/`, a
    generated tree -- the copy must not silently start counting a second copy
    of every Dart file in the repository.

    It is dead code on this tree, and it is the only dead code here. Everything
    else in this file is load-bearing against the test suite's mutation run,
    which is where a guard earns the right to exist unexercised: a cheap guard
    that cannot fire is worth keeping precisely because firing it is
    catastrophic and forgetting it is trivial.
    """
    for top in ROOTS:
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            # `build/` holds a copy of the tree that no edit can reach.
            #
            # ONE exclusion, not two. The first version both skipped the
            # directory when its own path carried a `build` component AND
            # pruned `build` out of the subdirectory list, and the mutation
            # battery proved the pair **indistinguishable**: deleting either
            # one left the suite GREEN, because the other covered it. Two
            # mechanisms for one rule is a mechanism nobody can test, and a
            # rule with two untestable mechanisms is one rule implemented
            # zero times.
            if "build" in dirpath.split(os.sep):
                continue
            for name in sorted(filenames):
                if name.endswith(".dart"):
                    yield os.path.join(dirpath, name)


def code_of(path: str) -> str:
    """The file with its COMMENT lines removed -- the reader's own rule.

    Mirrors `_routingCensus.codeOf`. It is deliberately a comment filter and
    nothing more: it does not blank string literals, because a mention inside a
    string in real code is a mention, and `tool/agreement_census_audit.py`
    measures the reader as written rather than the reader as one would write
    it. (That gap is reported separately, below, as `inside_string_only`.)
    """
    with open(path, encoding="utf-8") as fh:
        return "\n".join(
            l for l in fh.read().split("\n") if not l.lstrip().startswith("//"))


def is_comment(line: str) -> bool:
    return line.lstrip().startswith("//")


def direct_call_sites(root: str, calls: "re.Pattern[str]"):
    """`{basename: path}` for every file whose CODE calls the helper."""
    out = {}
    for path in dart_files(root):
        if calls.search(code_of(path)):
            out[os.path.basename(path)] = path
    return out


def direct_ignoring_comments(root: str, calls: "re.Pattern[str]"):
    """The same count with the comment filter REMOVED -- the mutation.

    This is the number the `census.direct.length` pin was written to police: a
    census that cannot tell a call site from a worked EXAMPLE would grow here
    and not there. A pin on a COUNT can only see this if the delta is
    non-zero, which is what `--why` reports.
    """
    out = {}
    for path in dart_files(root):
        with open(path, encoding="utf-8") as fh:
            body = fh.read()
        if calls.search(body):
            out[os.path.basename(path)] = path
    return out


def comment_lines(root: str):
    """`(basename, lineno, text)` for every comment line in the tree."""
    for path in dart_files(root):
        with open(path, encoding="utf-8") as fh:
            for i, line in enumerate(fh.read().split("\n"), 1):
                if is_comment(line):
                    yield os.path.basename(path), i, line.lstrip()


def dart_unescape(text: str) -> str:
    """Dart plain-string escapes. Raw strings (r'...') never reach this.

    Dart has no `\x27` inside a plain string that is itself inside a Python
    single-quoted literal; the one pattern this file writes that way is
    `RegExp('import' r'...')`, and its plain part carries no escapes at all.
    So the four that matter are covered and anything else is passed through
    rather than guessed at.
    """
    return (text.replace("\\n", "\n").replace("\\t", "\t")
                .replace("\\r", "\r"))


def blank_quoted(text: str) -> str:
    """Quoted spans blanked to spaces, offsets preserved.

    The reader's `_blankQuotedSpans`. Backticks, guillemets and straight
    double quotes are all blanked because this tree uses all three, and a
    quoted span is SHOWN rather than stated.
    """
    for pattern in (r"`[^`]*`", "«[^»]*»", r'"[^"]*"'):
        text = re.sub(pattern, lambda m: " " * len(m.group(0)), text)
    return text


def loose_surface(root: str, probe: "re.Pattern[str]",
                  negated: "re.Pattern[str]"):
    """`(basename, lineno, matched_text)` for every claim-shaped sentence.

    The LOOSE probe on purpose: it accepts a bare article or none, so it
    over-matches. A census built from the reader's own patterns would report
    the reader's reach as if it were the problem's size, which is the one thing
    this number must not do.
    """
    out = []
    for name, lineno, raw in comment_lines(root):
        text = blank_quoted(raw)
        for m in probe.finditer(text):
            if negated.search(text[:m.start()]):
                continue
            out.append((name, lineno, m.group(0).strip()))
    return out


# --------------------------------------------------------------------------
# The judgement
# --------------------------------------------------------------------------
def measure(root: str) -> dict:
    src = dart_source(root)
    # The reader's own patterns, extracted -- never copied.
    calls = extract_regex(src, "calls")
    probe = extract_regex(src, "_probeLoose")
    negated = extract_regex(src, "_negated")

    pins = read_pins(src)
    direct = direct_call_sites(root, calls)
    unfiltered = direct_ignoring_comments(root, calls)

    # The mutation the `census.direct.length` pin NAMES: `calls` widened to the
    # bare name, no parenthesis demanded. See the report for why this is the
    # interesting one.
    bare = re.compile(calls.pattern.replace(r"\(", ""))

    surface = loose_surface(root, probe, negated)

    # The membership assertion, read out of the same file the pins come from.
    membership = read_membership(src)
    prose_only = prose_only_files(root, calls)

    return {
        "pins": pins,
        "membership": membership,
        "membership_present": membership["present"],
        "membership_guarded": membership["guarded"],
        "membership_exempt": membership["exempt"],
        "prose_only": sorted(prose_only),
        "prose_only_count": len(prose_only),
        "direct": len(direct),
        "direct_files": sorted(direct),
        # Can the pin on the COUNT see a census that reads prose as calls?
        "comment_filter_delta": len(unfiltered) - len(direct),
        "comment_filter_files": sorted(set(unfiltered) - set(direct)),
        # Can it see `calls` widened to the bare name?
        "bare_name_delta": len(direct_call_sites(root, bare)) - len(direct),
        "bare_name_files": sorted(
            set(direct_call_sites(root, bare)) - set(direct)),
        "surface": surface,
        "surface_count": len(surface),
    }


# The membership assertion the count pin was ordered to become. Extracted,
# like the patterns -- never copied -- so this tool reports on the assertion
# the tree ACTUALLY holds rather than the one a previous tick proposed.
#
# Its shape, as written in the Dart:
#
#     final directClaimFiles =
#         census.direct.intersection(claimFiles).difference({
#       'arabic_agreement.dart',
#       'arabic_agreement_test.dart',
#       'quote_duration_copy.dart'
#     });
#     expect(directClaimFiles, isEmpty,
#
# Three literals, one intersection, one difference, one `isEmpty`. All four
# have to be found or this reports the assertion as ABSENT rather than as
# vacuous -- and "absent" and "present but cannot fail" are different faults
# with different fixes.
MEMBERSHIP_RE = re.compile(
    r"census\.direct\s*\.intersection\(claimFiles\)\s*\.difference\(\{"
    r"(?P<exempt>[^}]*)\}\)")
MEMBERSHIP_EMPTY_RE = re.compile(
    r"expect\(\s*directClaimFiles\s*,\s*isEmpty\s*[,;]")


def read_membership(src: str) -> dict:
    """The membership assertion as written, or `present: False`.

    Returns `{"present", "exempt", "guarded"}` -- `guarded` says the collected
    set is actually asserted empty, which is the half that makes it a guard
    rather than a computation nobody checks.
    """
    m = MEMBERSHIP_RE.search(src)
    if not m:
        return {"present": False, "exempt": [], "guarded": False}
    exempt = re.findall(r"'([^']+)'", m.group("exempt"))
    return {"present": True, "exempt": exempt,
            "guarded": bool(MEMBERSHIP_EMPTY_RE.search(src))}


def prose_only_files(root: str, calls: "re.Pattern[str]") -> dict:
    """`{basename: path}` for files that MENTION the helper but never CALL it.

    This is the negative shape the plant in the Dart file writes to disk: a file
    whose only `arabicCounted(` sits inside a comment. The count pin cannot see
    it because the set it counts is unchanged; a membership assertion CAN,
    because the file lands in `direct` -- so whether the real tree can supply
    the case decides which guard is load-bearing here, and that is a fact about
    the tree rather than about either assertion.
    """
    out = {}
    for path in dart_files(root):
        with open(path, encoding="utf-8") as fh:
            body = fh.read()
        if calls.search(body) and not calls.search(code_of(path)):
            out[os.path.basename(path)] = path
    return out


# The Dart field a pin names, and the key its measurement lands under here.
# `census.direct.length` is measured by walking the tree; `census.surface
# .length` is the size of a list. Kept as a table so a THIRD pin -- the file
# may well grow one -- reads as a missing entry rather than as a wrong answer.
MEASURED_AS = {"direct": "direct", "surface": "surface_count"}


def verdict(m: dict) -> dict:
    pins = m["pins"]
    drift = []
    for field, pinned in sorted(pins.items()):
        # A pin this tool cannot measure is ONE fault, not two. The first
        # version branched twice -- an unknown field, then an absent
        # measurement -- and the mutation battery proved the branches
        # indistinguishable: deleting either one left the suite green, because
        # the other produced the same verdict with a different sentence. So
        # there is one branch now, and the note says what to do about it.
        actual = m.get(MEASURED_AS.get(field, ""))
        if actual is None:
            drift.append({"pin": field, "pinned": pinned, "measured": None,
                          "note": "the pin names a field this tool does not "
                                  "measure -- re-measure by hand"})
            continue
        if actual != pinned:
            drift.append({"pin": field, "pinned": pinned, "measured": actual,
                          "delta": actual - pinned})
    return {
        "drift": drift,
        # A count pin is only falsifiable for a mutation that MOVES the count.
        "direct_pin_falsifiable_for_comment_filter":
            m["comment_filter_delta"] != 0,
        "direct_pin_falsifiable_for_bare_name":
            m["bare_name_delta"] != 0,
        # ...and the membership assertion the last tick ordered INSTEAD of it.
        # It is the stronger guard only if the real tree can supply the case it
        # is sensitive to. Zero prose-only files means the tree cannot, so on
        # THIS tree it is vacuous in exactly the way the count pin is -- and
        # swapping one for the other would trade a pin that sees drift for one
        # that cannot see the defect, without adding a second thing that can.
        "membership_present": m.get("membership_present", False),
        # An absent assertion is never guarded: reporting `guarded: True`
        # beside `present: False` is how a deleted guard reads as a working
        # one. The battery caught exactly this on its first run.
        "membership_guarded": (m.get("membership_present", False)
                              and m.get("membership_guarded", False)),
        "membership_falsifiable_here": m.get("prose_only_count", 0) != 0,
        # The plant is the answer, and it is not a suggestion: the Dart file
        # already writes the case to disk and deletes it, which is the only
        # reason the shape is exercised at all on a tree that has no instance.
        "plant_is_the_only_coverage": (m.get("prose_only_count", 0) == 0
                                       and m.get("membership_present", False)),
        "prose_only": m.get("prose_only", []),
        "prose_only_count": m.get("prose_only_count", 0),
    }


def render(m: dict, v: dict) -> "list[str]":
    out = ["Agreement census pins -- the numbers test/agreement_comment_test.dart "
           "asserts, measured on the tree"]
    out.append("")
    out.append("  pins found in the Dart file: %s" % (", ".join(
        "%s=%d" % kv for kv in sorted(m["pins"].items())) or "NONE"))
    out.append("  files that CALL the helper in code : %d" % m["direct"])
    out.append("  loose claim-shaped sentences      : %d" % len(m["surface"]))
    out.append("")
    if v["drift"]:
        out.append("  DRIFT -- a pin no longer describes this tree:")
        for d in v["drift"]:
            out.append("    %-8s pinned %-4s measured %-4s (%+d)"
                       % (d["pin"], d["pinned"], d["measured"],
                          d.get("delta", 0)))
            # The WHY, and it is the part a human actally needs: a pin this
            # tool cannot measure is a different fault from one that has
            # drifted, and printing both as a number mismatch is how a reader
            # re-measures a pin that did not move.
            if d.get("note"):
                out.append("             -> %s" % d["note"])
    else:
        out.append("  every pin agrees with the tree.")
    out.append("")
    out.append("  Is the pin on `census.direct.length` falsifiable for the "
               "mutations its own comment names?")
    out.append("    comment filter removed (prose counted as calls): "
               "delta %+d  -> %s"
               % (m["comment_filter_delta"],
                  "pin CAN see it" if v["direct_pin_falsifiable_for_comment_filter"]
                  else "PIN CANNOT SEE IT"))
    out.append("    `calls` widened to the bare name               : "
               "delta %+d  -> %s"
               % (m["bare_name_delta"],
                  "pin CAN see it" if v["direct_pin_falsifiable_for_bare_name"]
                  else "PIN CANNOT SEE IT"))
    if m["comment_filter_files"]:
        out.append("      files only the comment filter hides: %s"
                   % ", ".join(m["comment_filter_files"]))
    if m["bare_name_files"]:
        out.append("      files only the bare name adds: %s"
                   % ", ".join(m["bare_name_files"]))
    out.append("")
    out.append("  The membership assertion the count pin was ordered to become.")
    if not v["membership_present"]:
        out.append("    ABSENT -- no `direct.intersection(claimFiles)"
                   ".difference({...})` in the Dart file.")
    else:
        out.append("    present, exempting %d file(s): %s"
                   % (len(m["membership_exempt"]),
                      ", ".join(m["membership_exempt"]) or "none"))
        out.append("    asserted empty        : %s"
                   % ("yes" if v["membership_guarded"] else
                      "NO -- collected and never checked"))
        out.append("    files in this tree that are prose-only : %d"
                   % m["prose_only_count"])
        if v["membership_falsifiable_here"]:
            out.append("    -> it IS falsifiable here: those %d file(s) would "
                       "enter the set:" % m["prose_only_count"])
            for f in v["prose_only"]:
                out.append("         %s" % f)
        else:
            out.append("    -> VACUOUS HERE, exactly like the count pin. The "
                       "real tree has no prose-only file, so nothing enters "
                       "the set and nothing can make it non-empty.")
        if v["plant_is_the_only_coverage"]:
            out.append("    -> the ONLY thing exercising the shape is the "
                       "plant in the Dart file, which writes the case to disk "
                       "and deletes it again.")
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.getcwd())
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    try:
        m = measure(args.root)
    except (FileNotFoundError, LookupError) as exc:
        print("UNREADABLE -- %s" % exc)
        print("The reader's vocabulary moved and this tool declines to answer "
              "from a remembered copy. Re-measure by hand.")
        return 2

    v = verdict(m)
    if args.json:
        payload = {k: val for k, val in m.items() if k != "surface"}
        payload["surface_count"] = len(m["surface"])
        payload["surface"] = m["surface"]
        payload.update(v)
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        for line in render(m, v):
            print(line)
    return 1 if v["drift"] else 0


if __name__ == "__main__":
    sys.exit(main())
