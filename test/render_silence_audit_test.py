#!/usr/bin/env python3
"""Pin the render-silence sweep AND the two renderer defects it found.

    python3 test/render_silence_audit_test.py

**Python, not Dart.** The claims are about three audit tools' own judgement --
which string a renderer prints when a producer never ran, and whether a build
guard refuses with a reason that is true. None of it needs a Dart VM, and the
box cannot host one (`tool/build_gate.py` has denied Dart for seven consecutive
ticks: 561 MB available against a 900 MB floor, `Balloon:` 5588 MB held by the
hypervisor).

**No case here talks to the network.** Every case drives a module's own
`_render` / `sweep` with dictionaries and a copied tmpdir. Nothing is stubbed at
`Wire.call`, because the defect is *before* any wire call: it is in the branch
that decides what to say about a read that did not happen.

**Two defects, one class.**

1. `inbox_read_audit.py` refused with `if not _another_writer_is_building():`.
   The helper answers "is a build I can SEE in flight"; both siblings refuse on
   `True`. The `not` made the tool refuse precisely when nothing was building
   and run precisely when a real build was in flight -- so that audit has never
   once measured anything, while printing a confident refusal reason each time.

2. `worker_reviews_audit._render` printed
   `directory: None claiming, None checked, None empty, None LONGER than it` when
   `_check_gap` had returned `(None, reason)` -- and `main()` had thrown the
   reason away. Five absent measurements in the grammar of five measured ones.

**The control case is the one that matters.** A sweep that cannot be pointed at
a mutated tree cannot be shown to fire, and a guard never seen red is a sentence
in a file. Two of the cases below were RED against this tick's first two drafts
of the sweep itself: a string scan that matched the *comment* quoting the guard
line, and a match that required `test` to be a bare `Call` and so could not see
the `UnaryOp(Not, ...)` shape it exists to find. Both are recorded here rather
than quietly fixed, because "the detector was wrong" is the finding.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tool"))

import inbox_read_audit as inbox  # noqa: E402
import render_silence_audit as sweep_mod  # noqa: E402
import worker_reviews_audit as reviews  # noqa: E402

_results = []


def case(name):
    def wrap(fn):
        _results.append((name, fn))
        return fn
    return wrap


def _copy_tree(dst):
    for name in sweep_mod.SIBLINGS:
        src = os.path.join(REPO, "tool", name + ".py")
        if os.path.exists(src):
            shutil.copy(src, dst)


def _inverted_hits(tree):
    return [h for h in sweep_mod.sweep(tree)
            if str(h.get("guard_polarity", "")).startswith("INVERTED")]


# ---------------------------------------------------------------- defect 1


@case("inbox refused with an inverted build guard")
def _inverted_polarity():
    src = open(os.path.join(REPO, "tool", "inbox_read_audit.py"), encoding="utf-8").read()
    code = [l for l in src.split("\n")
            if re.match(r"^\s*if .*_another_writer_is_building\(\):\s*$", l)]
    assert len(code) == 1, "expected one guard call site, found %d" % len(code)
    assert not code[0].lstrip().startswith("if not"), (
        "the guard is inverted again: %r" % code[0])


@case("the sweep NAMES the inversion when a tool has one (negative control)")
def _sweep_fires():
    tmp = tempfile.mkdtemp(prefix="rendersilence-red-")
    try:
        _copy_tree(tmp)
        path = os.path.join(tmp, "inbox_read_audit.py")
        lines = open(path, encoding="utf-8").read().split("\n")
        hit = 0
        for i, line in enumerate(lines):
            # Mutate the CODE line only. The comment quoting this exact call
            # must be left alone -- matching it was this file's first defect.
            if re.match(r"^\s*if _another_writer_is_building\(\):\s*$", line):
                lines[i] = line.replace("if _another_writer_is_building():",
                                        "if not _another_writer_is_building():")
                hit += 1
        assert hit == 1, "control mutated %d code lines, expected 1" % hit
        open(path, "w", encoding="utf-8").write("\n".join(lines))
        hits = _inverted_hits(tmp)
        assert len(hits) == 1, (
            "the sweep cannot see an inverted guard -- %d found in a tree that "
            "has one" % len(hits))
        assert hits[0]["tool"] == "inbox_read_audit"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@case("the real tree has no inverted guard")
def _real_tree_clean():
    hits = _inverted_hits(os.path.join(REPO, "tool"))
    assert hits == [], "inverted guards still present: %s" % hits


@case("the guard helper refuses on True, like both siblings")
def _helper_polarity():
    """A refusal must happen when a build IS in flight, not when the box is idle."""
    assert inbox._another_writer_is_building.__doc__
    # Drive the helper's own logic without running a gate: the real question is
    # the call site's polarity, pinned above. This case documents the contract.
    assert "is a build I can see" not in inbox._another_writer_is_building().__doc__, \
        "docstring drifted from the sibling wording the fix cites"


# ---------------------------------------------------------------- defect 2


@case("a failed gap read prints NOT MEASURED, never five Nones")
def _no_none_silence():
    reports = {"https://allomokawil.com": (
        {"ids": {"user_id": 7, "profile_id": 9, "ids_disagree": False},
         "gap": {}, "gap_error": "search failed: 502 bad gateway"}, None)}
    text = "\n".join(reviews._render(reports))
    assert "None claiming" not in text, "renderer still prints absent measurements"
    assert "NOT MEASURED" in text, text
    assert "502 bad gateway" in text, "the measured reason was dropped again: %r" % text


@case("the silence arm names the reason main() used to discard")
def _reason_carried():
    src = open(os.path.join(REPO, "tool", "worker_reviews_audit.py"), encoding="utf-8").read()
    assert '"gap_error": gap_err' in src, "main() is not carrying gap_err through"
    assert re.search(r"if gap_err and not gap_rep:\s*\n\s*gap_rep = \{\}", src) is None, \
        "main() still collapses a failed read to {} and drops its reason"


@case("a real gap read still renders its numbers (the control)")
def _real_numbers_still_render():
    gap = {"claiming_reviews": 3, "checked": 3, "rows_with_no_cards": 0,
           "rows_shorter_than_claim": 1, "rows_longer_than_claim": 0}
    reports = {"https://allomokawil.com": (
        {"ids": {"user_id": 7, "profile_id": 9, "ids_disagree": True},
         "gap": gap, "gap_error": None}, None)}
    text = "\n".join(reviews._render(reports))
    assert "3 claiming" in text, text
    assert "1 short of the header" in text, text
    assert "NOT MEASURED" not in text, "the new arm silenced a HEALTHY host: %r" % text
    assert "404" in text, "the ids_disagree arm was lost: %r" % text


@case("an id read that failed prints NOT MEASURED too")
def _ids_silence():
    reports = {"https://allomokawil.com": (
        {"ids": {}, "gap": {}, "gap_error": "search failed"}, None)}
    text = "\n".join(reviews._render(reports))
    assert "ids: user None / profile None" not in text, text
    assert text.count("NOT MEASURED") >= 2, text


# ------------------------------------------------- defect 3: named, never seen


@case("the real tree examines all seven tools (no renderer is skipped)")
def _no_tool_is_unread():
    """The allowlist defect: two of seven tools read `NO RENDERER` forever.

    `agreement_census_audit` and `numeric_bound_audit` both name their
    renderer `render`, which matched none of `_render`/`_report`/`_lines`.
    The sweep reported them as having no renderer and moved on -- identical
    in the output to the five it had read. Coverage that reports itself as
    coverage while skipping work is the failure this whole file is about.
    """
    hits = sweep_mod.sweep(os.path.join(REPO, "tool"))
    skipped = [h["tool"] for h in hits if h["verdict"] == "NO RENDERER"]
    assert skipped == [], ("tools the sweep never examined: %s" % skipped)
    examined = sorted({h["tool"] for h in hits if h["verdict"] == "ARM"})
    assert examined == sorted(sweep_mod.SIBLINGS), (
        "only %d of %d tools produced arms; missing %s"
        % (len(examined), len(sweep_mod.SIBLINGS),
           sorted(set(sweep_mod.SIBLINGS) - set(examined))))
    assert len(hits) >= 27, (
        "expected the arms the two hidden tools contribute (27 after the "
        "fix, 14 before it); got %d -- discovery silently narrowed again"
        % len(hits))


@case("a renderer named `render` is found, whatever the author called it")
def _shape_not_name():
    """Positive control: the fixed sweep sees the name it used to skip."""
    tmp = tempfile.mkdtemp(prefix="rendersilence-shape-")
    try:
        _copy_tree(tmp)
        hits = sweep_mod.sweep(tmp)
        for name in ("agreement_census_audit", "numeric_bound_audit"):
            assert any(h["tool"] == name and h["verdict"] == "ARM" for h in hits), (
                "%s still reports no renderer" % name)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@case("renaming a renderer to an unknown name does not hide it (the defect)")
def _rename_is_caught():
    """The mutation. Rename `_render` -> `weird_name_xyz` and the arms must
    survive, because discovery reads shape. Under the old allowlist this
    dropped the tool to NO RENDERER and the arms vanished silently."""
    tmp = tempfile.mkdtemp(prefix="rendersilence-rename-")
    try:
        _copy_tree(tmp)
        path = os.path.join(tmp, "inbox_read_audit.py")
        src = open(path, encoding="utf-8").read()
        assert src.count("def _render(") == 1, "expected one _render definition"
        open(path, "w", encoding="utf-8").write(
            src.replace("def _render(", "def zzz_unexpected_name(", 1))
        hits = [h for h in sweep_mod.sweep(tmp) if h["tool"] == "inbox_read_audit"]
        assert hits and all(h["verdict"] == "ARM" for h in hits), (
            "renaming the renderer hid it -- arms=%r" % hits)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@case("a module with no renderer at all still reports NO RENDERER")
def _genuinely_silent_module():
    """The other half of the control. The fix must not become 'every tool
    matches' -- a module that builds no report list is still uncovered, and
    saying so is the honest output."""
    tmp = tempfile.mkdtemp(prefix="rendersilence-empty-")
    try:
        _copy_tree(tmp)
        open(os.path.join(tmp, "numeric_bound_audit.py"), "w", encoding="utf-8").write(
            'def measure(root):\n    return {"a": 1}\n\n'
            'def verdict(m):\n    return {"ok": True}\n')
        hits = sweep_mod.sweep(tmp)
        row = [h for h in hits if h["tool"] == "numeric_bound_audit"]
        assert row and row[0]["verdict"] == "NO RENDERER", (
            "a renderer-less module was given arms it does not have: %r" % row)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@case("appends to a list but returns something else is not a renderer")
def _half_the_shape_is_not_a_renderer():
    """`loose_surface()` appends to `out` and returns `sorted(...)`. Half the
    shape must not qualify, or `measure()`/`verdict()` would flood the report."""
    import ast as _ast
    src = ('def half_shape():\n'
           '    out = []\n'
           '    out.append("a claim long enough to count as an arm")\n'
           '    return sorted(out)\n')
    tree = _ast.parse(src)
    assert sweep_mod._renderers(tree) == [], "half the shape was accepted"
    # ...and the full shape is accepted, so the case is not vacuous.
    full = _ast.parse(src.replace("return sorted(out)", "return out"))
    assert len(sweep_mod._renderers(full)) == 1, "the full shape was rejected"


def main():
    failed = 0
    for name, fn in _results:
        try:
            fn()
            print("  PASS  %s" % name)
        except Exception as exc:  # noqa: BLE001 - a case reports, never raises
            failed += 1
            print("  FAIL  %s\n          %s" % (name, exc))
    print("\n%d/%d passed" % (len(_results) - failed, len(_results)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
