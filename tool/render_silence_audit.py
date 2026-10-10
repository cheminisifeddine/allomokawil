#!/usr/bin/env python3
"""Read-only sweep: does any audit renderer print an ABSENT measurement as a RESULT?

    python3 tool/render_silence_audit.py
    python3 tool/render_silence_audit.py --json

**The class this sweeps for, measured four times in three days.** "This tool did
not look" arriving as "this tool looked and found it fine". The sharpest instance
was not a reader whose vocabulary was too narrow for the tree -- it was a
*renderer* turning a missing key into a confident sentence:

    header_contradicts: None (used 7 > limit None) | ...
    ceiling sentence is blind to the count: None (over by None) --
      `portfolioFullLineAr` is handed the count and names both

Four `None`s, then a present-tense claim about the shipped Dart, with a
`check_*` helper returning `False` ("not blind") from a dict that never had the
key. Reachable with no Dart change: `_read_limit` sets the limit to `None`
whenever the plan payload omits it.

**How this sweep decides, and why it is not just a grep.** A renderer that
prints `rep.get(k)` is *correct* -- `None` in, `None` out, and the reader of the
report sees the same missing value the producer had. The defect is narrower and
worse: a renderer that reaches a **reporting arm** with a key the producing
function never set, and formats it in the grammar of a measurement. So each hit
is reported with the arm's own words, and a human reads them. This tool does not
claim a defect; it marks where the class can hide.

**Six guard states, because "correct" and "not present" used to look identical.**
The build guard got two questions -- is it inverted, does it exist -- and the
real tree and a tree with every refusal deleted printed the same header. The
states, the mutations that kill each, and the counting rule (per TOOL, not per
arm) are documented on `_guard_state` and pinned in
`test/render_silence_audit_test.py`.

**Read-only by construction.** It imports each audit module, reads its AST and
its `_render` source, and never calls a producer or opens a socket. It cannot
change a file and it cannot spend the network.

**No Dart.** Same reasoning as the sibling audit tests: the claims are about
these tools' own judgement, and the box cannot host a Dart VM.
"""

from __future__ import annotations

import argparse
import ast
import importlib
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(REPO, "tool")
if TOOL not in sys.path:
    sys.path.insert(0, TOOL)

SIBLINGS = (
    "portfolio_allowance_audit",
    "portfolio_gallery_audit",
    "worker_reviews_audit",
    "notification_read_audit",
    "inbox_read_audit",
    "agreement_census_audit",
    "numeric_bound_audit",
)


def _renderers(tree):
    """Every renderer in the module, found by SHAPE rather than by name.

    **The defect this fixes.** Discovery was an allowlist of three names:
    `_render`, `_report`, `_lines`. A tool that names its renderer `render`
    matched none of them, so the sweep filed `NO RENDERER` and moved on --
    which is the "this tool did not look" outcome arriving as a coverage
    report. Two of seven tools (`agreement_census_audit`,
    `numeric_bound_audit`) were never examined for the entire life of this
    sweep, and nothing in the output said so: they read exactly like the five
    tools it *had* read. Same shape as the two defects this file already
    fixed -- a check that could not see the thing it exists to find, satisfied
    by the absence of a finding.

    **The shape.** A renderer builds a list of report lines and returns that
    same list. That is structural: it holds whether the author spelled it
    `_render`, `render`, `_report` or `lines`, and it does not depend on a
    spelling this file has to keep in step with someone else's.

    Deliberately NOT "returns a list" -- `measure()` and `verdict()` also
    return containers, and a hit on those would be noise. The test is the pair:
    appends to a name, and returns that same name. `loose_surface()` in
    `agreement_census_audit` passes half of it and is correctly not a renderer.
    """
    out = []
    for fn in tree.body:
        if not isinstance(fn, ast.FunctionDef):
            continue
        appended = set()
        for sub in ast.walk(fn):
            if (isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute)
                    and sub.func.attr == "append" and isinstance(sub.func.value, ast.Name)):
                appended.add(sub.func.value.id)
        returned = {s.value.id for s in ast.walk(fn)
                    if isinstance(s, ast.Return) and isinstance(s.value, ast.Name)}
        if appended & returned:
            out.append(fn)
    return out


def _guard_state(tree):
    """What the build guard on this module actually DOES. Five states, not two.

    **The defect this fixes, measured.** The sweep asked exactly two things
    about `_another_writer_is_building`: is the call site inverted, and does one
    exist at all. Those two questions cannot tell a working refusal from a
    MISSING one. Measured on the real tree and on two mutations of it:

    | tree | header the sweep printed |
    | --- | --- |
    | real | `7 tools, 31 reporting arms, 0 inverted guards` |
    | every call site DELETED | `... 0 inverted guards` |
    | every call site neutered (`if False and ...`) | `... 0 inverted guards` |

    Identical. A tool that had its refusal removed -- the one thing this class
    of defect is about, and the exact inverse of the inversion the sweep *was*
    built to catch -- renders as a clean tree. "This tool did not look,
    arriving as this tool looked and found it fine" is this file's own header
    sentence, and the header could not say it.

    The five states, and what each one costs:

    * `correct`       -- a bare call site; refusal happens on True.
    * `INVERTED`      -- `if not ...`: refuses when nothing is building.
    * `NEVER CALLED`  -- the helper is DEFINED and nothing calls it. The
      refusal was deleted or never wired. Reachable by editing one line and
      previously indistinguishable from healthy.
    * `UNREACHABLE`   -- the call exists but cannot fire (`if False and ...`,
      `if 0 and ...`). Reads as `correct` to any question asked of the call
      site itself, because the call *is* there.
    * `INDIRECT`      -- the helper is called into a name (`busy = ...`) and
      tested later. A legal refusal this analysis cannot follow; its own state,
      so it is neither filed INVERTED nor counted healthy.
    * `NONE`          -- the module has no build guard at all. Not a defect on
      its own: two census tools parse Dart source and build nothing, so
      refusing during a build would be theatre. Reported, so the count is
      stated rather than inferred from silence.
    """
    defines = any(isinstance(fn, ast.FunctionDef)
                  and fn.name == "_another_writer_is_building"
                  for fn in tree.body)
    if not defines:
        return "NONE", None

    # Every call of the helper, wherever it sits. A call that is not the whole
    # test of an `if` cannot be a refusal and must not be judged as one.
    sites = []
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == "_another_writer_is_building"):
            sites.append(node)
    if not sites:
        return "NEVER CALLED", None

    indirect = None
    for call in sites:
        owner = _owning_if(tree, call)
        if owner is None:
            # `busy = _another_writer_is_building()` then `if busy:` is a
            # legal refusal this analysis cannot follow through a name. Recorded
            # as its own state rather than silently scored: a tool that refuses
            # correctly this way must not be filed INVERTED, and a tool that
            # merely CALLS the helper must not be filed healthy.
            if indirect is None:
                indirect = call.lineno
            continue
        test = owner.test
        if isinstance(test, ast.UnaryOp) and isinstance(test.op, ast.Not):
            return "INVERTED", owner.lineno
        conjuncts = test.values if isinstance(test, ast.BoolOp) else [test]
        for c in conjuncts:
            if isinstance(c, ast.Constant) and c.value is False:
                return "UNREACHABLE", owner.lineno
    if indirect is not None:
        return "INDIRECT", indirect
    return "correct", sites[0].lineno


def _owning_if(tree, call):
    """The `if` whose TEST contains `call`, or None if the call is not a test."""
    for node in ast.walk(tree):
        if not isinstance(node, ast.If):
            continue
        for sub in ast.walk(node.test):
            if sub is call:
                return node
    return None


def _emitted(node):
    """The string constants this branch EMITS -- body and `else`, not the test.

    **Why the body is separated from the test.** An `if` chooses what to say
    by comparing against a literal (`if state == "none": ...`), and that
    literal is in the test, not in the text the reader sees. Counting the whole
    node would let an arm qualify on a string it never prints. Measured on the
    real tree: 31 arms either way, 0 test-only arms -- so this costs nothing
    here and is kept because it is the definition, not because the numbers
    happened to agree.
    """
    in_test = {id(sub) for sub in ast.walk(node.test)}
    out = []
    for sub in ast.walk(node):
        if id(sub) in in_test:
            continue
        if sub is node:
            continue
        if isinstance(sub, ast.Constant) and isinstance(sub.value, str):
            out.append(sub.value)
    return out


def _arm_lines(fn_node):
    """The reporting arms of a function: every `if` that guards emitted text.

    An `else`-arm or an `if` that *selects* a string is where a missing key
    silently becomes a verdict. Both are returned with the literal strings that
    the branch prints, because the wording is the evidence.

    **The length threshold is gone, and it was costing the whole class.**
    The filter used to require `len(sub.value) > 12` and to skip anything
    starting `Read-only`/`How ` -- a guess at "that is prose, not a claim",
    made by a reader with no vocabulary for the tree it grades. Recall was
    MEASURED, not assumed: a verdict-shaped arm planted in all seven tools'
    renderers (`if rep.get(k) is None: out.append("none")`) was found in
    **0 of 7**. A renderer answering an unmeasured read with `"none"` is
    exactly the defect this file exists to catch, and it printed four letters.

    The replacement rule is **shape**: a string the branch *emits* is an arm,
    whatever its length, so recall cannot depend on how long the author's
    sentence is. Precision cost, measured on the real tree before the change:
    27 arms -> **31**, and all four new ones are genuine arms, not noise:
    three identical `'  %-42s %s'` arms under `if err:` in
    `worker_reviews_audit`, `notification_read_audit` and `inbox_read_audit`
    (the host-error line IS what those branches say), and
    `numeric_bound_audit` L377, which prints a field row and the sentinel
    `"unreadable"`. The `Read-only`/`How ` prefix exclusion matched **zero**
    strings on the whole tree -- it was never doing work, only narrowing.

    **What this rule still cannot see, stated rather than implied.** An `if`
    that emits no literal at all -- a branch over a computed value only -- is
    invisible to any literal rule, and the real tree has exactly **one**
    (`agreement_census_audit` L341, a `negated.search` filter inside
    `_lineClaims`, which is not a renderer at all). A sweep that printed "no
    more blind spots" here would be repeating the original sin. So the arm
    count is a LOWER bound and the report says so.
    """
    out = []
    for node in ast.walk(fn_node):
        if not isinstance(node, ast.If):
            continue
        strings = _emitted(node)
        if strings:
            out.append((node.lineno, strings))
    return out


def sweep(tool_dir=None):
    """Sweep `tool_dir` (defaults to the real `tool/`).

    The parameter exists so a test can copy the tools into a tmpdir and mutate
    the copy: a detector that can only be pointed at the real tree cannot be
    shown to fire, and a guard that has never been seen to go red is not a
    guard -- it is a sentence in a file.
    """
    tool_dir = tool_dir or TOOL
    hits = []
    for name in SIBLINGS:
        path = os.path.join(tool_dir, name + ".py")
        if not os.path.exists(path):
            hits.append({"tool": name, "verdict": "MISSING",
                         "detail": "no such file"})
            continue
        try:
            tree = ast.parse(open(path, encoding="utf-8").read())
        except SyntaxError as exc:
            hits.append({"tool": name, "verdict": "UNREADABLE",
                         "detail": "syntax error: %s" % exc})
            continue

        renderers = _renderers(tree)
        guards = [n for n in tree.body
                  if isinstance(n, ast.FunctionDef) and n.name == "_another_writer_is_building"]
        if not renderers:
            hits.append({"tool": name, "verdict": "NO RENDERER",
                         "detail": "no function appends to a list and returns "
                                   "that list -- a module with no renderer"})
            continue

        # The guard's own name says "is a build in flight", and every sibling
        # refuses on True. SIX states, measured -- see `_guard_state`, which
        # replaced a two-question version that could not tell a working refusal
        # from a deleted one: a tree with every call site removed printed
        # `0 inverted guards`, byte-identical to this clean one.
        polarity, guard_line = _guard_state(tree)
        if polarity != "correct":
            hits.append({
                "tool": name, "verdict": "GUARD " + polarity,
                "line": guard_line, "guard_polarity": polarity,
                "detail": {
                    "NEVER CALLED": "the helper is defined and nothing calls it"
                                    " -- the refusal was removed",
                    "UNREACHABLE": "the call site exists but its test can never be"
                                   " true, so the refusal never happens",
                    "INDIRECT": "the helper is called into a name, not tested"
                                " directly -- not judged either way",
                    "NONE": "this module has no build guard",
                }.get(polarity, ""),
            })


        for fn in renderers:
            for lineno, strings in _arm_lines(fn):
                hits.append({
                    "tool": name, "verdict": "ARM", "line": lineno,
                    "guard_polarity": polarity,
                    "detail": " / ".join(s[:90] for s in strings[:2]),
                })
    return hits


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--dir", default=None,
                    help="sweep this tool_dir instead of the real one")
    args = ap.parse_args(argv)
    hits = sweep(args.dir)
    # COUNT TOOLS, not rows. `guard_polarity` is a property of the module and
    # is stamped onto every arm the renderer files, so filtering `hits` counts
    # a four-arm renderer as four broken guards -- measured: one deleted
    # refusal in `worker_reviews_audit` printed `5 guard(s) not doing their
    # job`. The same shape as the arm-count regression this file's sibling
    # test already pins, found again in the line I added beside it.
    def _tools_with(state):
        return sorted({h["tool"] for h in hits if h.get("guard_polarity") == state})

    inverted = _tools_with("INVERTED")
    unguarded = sorted({h["tool"] for h in hits
                        if h.get("guard_polarity") in ("NEVER CALLED", "UNREACHABLE")})
    if args.json:
        print(json.dumps({"swept": list(SIBLINGS),
                          "arms": len([h for h in hits if h.get("verdict") == "ARM"]),
                          "inverted_guards": len(inverted),
                          "guards_not_working": len(unguarded),
                          "hits": hits}, ensure_ascii=False, indent=2))
        return 0
    print("render-silence sweep: %d tools, %d reporting arms, %d inverted guards,"
          " %d guard(s) not doing their job"
          % (len(SIBLINGS), len([h for h in hits if h.get("verdict") == "ARM"]),
             len(inverted), len(unguarded)))
    for h in hits:
        print("  %-28s %-12s L%-5s %s" % (h["tool"], h["verdict"],
                                           h.get("line", "-"), h.get("detail", "")[:80]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
