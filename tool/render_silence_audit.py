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


def _arm_lines(fn_node):
    """The reporting arms of a function: every `if` that guards emitted text.

    An `else`-arm or an `if` that *selects* a string is where a missing key
    silently becomes a verdict. Both are returned with the literal strings that
    the branch prints, because the wording is the evidence.
    """
    out = []
    for node in ast.walk(fn_node):
        if not isinstance(node, ast.If):
            continue
        strings = []
        for sub in ast.walk(node):
            if isinstance(sub, ast.Constant) and isinstance(sub.value, str):
                # A docstring is not a claim the renderer makes.
                if len(sub.value) > 12 and not sub.value.startswith(("Read-only", "How ")):
                    strings.append(sub.value)
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

        # The polarity check that matters most: the guard's own name says "is a
        # build in flight", and its three siblings all refuse on True. An
        # inverted call site is a refusal whose printed reason is false.
        # **AST, not `src.find("if ")` -- the string scan was caught by its own
        # negative control.** It searched the raw source, so a *comment* quoting
        # the guard line (`... both read `if _another_writer_is_building():` `)
        # matched first and every tree reported "correct". A detector that reads
        # a name is the "named, never opened" shape this repo has now filed five
        # times; this one is mine, and it was found because the control asked
        # for a red tree and refused to produce one.
        polarity = "not checked"
        for fn in ast.walk(tree):
            if not isinstance(fn, ast.If):
                continue
            test = fn.test
            # The guard call can be BARE (`if _another_writer_is_building():`)
            # or WRAPPED (`if not _another_writer_is_building():`). Matching only
            # the bare shape was the second defect my own control caught: the
            # check required `test` to be a Call, so the inverted `UnaryOp` form
            # -- the only shape the sweep exists to find -- fell straight through
            # `continue` and every tree read "not checked". Unwrap first, then
            # decide, so the two shapes cannot be confused again.
            inverted = isinstance(test, ast.UnaryOp) and isinstance(test.op, ast.Not)
            inner = test.operand if inverted else test
            if not (isinstance(inner, ast.Call)
                    and isinstance(inner.func, ast.Name)
                    and inner.func.id == "_another_writer_is_building"):
                continue
            polarity = "INVERTED (refuses when NOT building)" if inverted else "correct"
            break

        for fn in renderers:
            for lineno, strings in _arm_lines(fn):
                hits.append({
                    "tool": name, "verdict": "ARM", "line": lineno,
                    "guard_polarity": polarity,
                    "detail": " / ".join(s[:90] for s in strings[:2]),
                })
    return hits


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    hits = sweep()
    inverted = [h for h in hits if h.get("guard_polarity") == "INVERTED (refuses when NOT building)"]
    if args.json:
        print(json.dumps({"swept": list(SIBLINGS), "arms": len(hits),
                          "inverted_guards": len(inverted), "hits": hits},
                         ensure_ascii=False, indent=2))
        return 0
    print("render-silence sweep: %d tools, %d reporting arms, %d inverted guards"
          % (len(SIBLINGS), len(hits), len(inverted)))
    for h in hits:
        print("  %-28s %-12s L%-5s %s" % (h["tool"], h["verdict"],
                                           h.get("line", "-"), h.get("detail", "")[:80]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
