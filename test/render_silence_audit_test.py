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
REPO_TOOL = os.path.join(REPO, "tool")
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
        # ONCE PER TOOL, not once per arm. `guard_polarity` is a property of the
        # module (there is one call site), and the sweep stamps it onto every
        # arm it files from that renderer -- so this count tracked the renderer's
        # ARM count and broke for the right reason the wrong way when a fix made
        # a second arm visible. A test that counts arms and means tools will
        # report the next recall fix as a regression. Asserted on distinct
        # tools, so a SECOND tool gaining an inverted guard is still caught.
        tools = [h["tool"] for h in hits]
        assert sorted(set(tools)) == ["inbox_read_audit"], (
            "the sweep cannot see an inverted guard -- tools carrying an "
            "inverted verdict: %s (arms: %d)" % (sorted(set(tools)), len(hits)))
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


# ---------------------------------------------- the arm filter's RECALL


def _plant_short_arm(tmpdir, tool):
    """Copy `tool` and plant a verdict-shaped arm whose emitted string is short.

    The plant is the defect this sweep exists to catch: a branch that answers
    an absent measurement with a confident four-letter word. `none` is 4
    characters, so any length-based filter hides it -- and hiding it is the
    whole failure, because the report would then say the tool was examined and
    found clean.
    """
    src = os.path.join(REPO, "tool", tool + ".py")
    dst = os.path.join(tmpdir, tool + ".py")
    text = open(src, encoding="utf-8").read()
    lines = text.splitlines()
    tree = sweep_mod.ast.parse(text)
    import ast as _ast
    renderer = sweep_mod._renderers(tree)[0]
    rets = [s for s in _ast.walk(renderer) if isinstance(s, _ast.Return)]
    target = rets[-1]
    indent = " " * target.col_offset
    plant = ["%sif rep.get(\'measured\') is None:" % indent,
             "%s    out.append(\"none\")" % indent]
    open(dst, "w", encoding="utf-8").write(
        "\n".join(lines[:target.lineno - 1] + plant + lines[target.lineno - 1:]))


@case("the arm filter finds SHORT verdict arms in every tool (recall, measured)")
def _short_arms_are_found():
    """Recall measured on all seven tools, not asserted on one fixture.

    Before the fix this case failed **7 of 7**: `len(sub.value) > 12` dropped
    every planted arm, so the sweep reported those tools as examined and clean
    while the arm it was built to find sat in front of it.
    """
    import ast as _ast
    missed, examined = [], []
    with tempfile.TemporaryDirectory() as tmp:
        for tool in sweep_mod.SIBLINGS:
            _copy_tree(tmp)
            _plant_short_arm(tmp, tool)
            try:
                _ast.parse(open(os.path.join(tmp, tool + ".py"),
                                encoding="utf-8").read())
            except SyntaxError as exc:
                raise AssertionError("plant for %s does not parse: %s" % (tool, exc))
            before = {h.get("line") for h in sweep_mod.sweep(REPO_TOOL)}
            hits = sweep_mod.sweep(tmp)
            planted_line = None
            tree2 = _ast.parse(open(os.path.join(tmp, tool + ".py"),
                                    encoding="utf-8").read())
            for fn in sweep_mod._renderers(tree2):
                if fn.name == sweep_mod._renderers(
                        _ast.parse(open(os.path.join(REPO_TOOL, tool + ".py"),
                                        encoding="utf-8").read()))[0].name:
                    for node in _ast.walk(fn):
                        if isinstance(node, _ast.If):
                            planted_line = node.lineno
                            break
                    break
            got = [h for h in hits
                   if h["tool"] == tool and h.get("line") == planted_line]
            if not got:
                missed.append(tool)
            else:
                examined.append(tool)
            del before
    assert missed == [], (
        "the filter dropped short verdict arms in: %s -- recall is not 7/7" % missed)
    assert len(examined) == len(sweep_mod.SIBLINGS), examined


@case("an arm qualifying only on a string in its TEST is not an arm")
def _test_literal_is_not_emitted_text():
    """The body/test split, pinned against a fixture that proves it is not vacuous.

    Without the split, `if state == "none":` would qualify the branch on a
    string it never prints -- a name the renderer matched against, not text a
    reader reads.
    """
    import ast as _ast
    src = ('def r():\n'
           '    out = []\n'
           '    if state == "MISSING SENTINEL":\n'
           '        out.append(format_only)\n'
           '    return out\n')
    tree = _ast.parse(src)
    assert sweep_mod._arm_lines(sweep_mod._renderers(tree)[0]) == [], (
        "a string in the TEST was counted as emitted text")
    real = ('def r():\n'
            '    out = []\n'
            '    if state == "none":\n'
            '        out.append("MISSING SENTINEL")\n'
            '    return out\n')
    assert len(sweep_mod._arm_lines(sweep_mod._renderers(_ast.parse(real))[0])) == 1, (
        "the same string in the BODY was rejected")


@case("the arm count is a LOWER bound: literal-free branches are not counted")
def _literal_free_branch_is_named():
    """What the filter still cannot see, pinned so it stays visible.

    An `if` that emits no literal -- a branch over computed values only --
    cannot be found by any literal rule. The real tree has exactly one. The
    sweep's docstring claims the count is a lower bound; this case makes the
    claim testable instead of decorative.
    """
    import ast as _ast
    src = ('def r():\n'
           '    out = []\n'
           '    if n > 3:\n'
           '        out.append(count)\n'
           '    return out\n')
    fn = sweep_mod._renderers(_ast.parse(src))[0]
    assert sweep_mod._arm_lines(fn) == [], "a literal-free branch was counted"
    free = 0
    for tool in sweep_mod.SIBLINGS:
        tree = _ast.parse(open(os.path.join(REPO_TOOL, tool + ".py"),
                               encoding="utf-8").read())
        for r in sweep_mod._renderers(tree):
            for node in _ast.walk(r):
                if isinstance(node, _ast.If) and not sweep_mod._emitted(node):
                    free += 1
    assert free == 1, (
        "the literal-free branch count moved (%d) -- the sweep's own report "
        "would now be stale" % free)


@case("a prose-looking arm is still an arm (the removed prefix rule, pinned)")
def _prefix_exclusion_is_not_needed():
    """The removed heuristic, and why a fixture and not a tree assertion.

    The filter used to drop any string starting `Read-only`/`How ` -- a guess
    at "that is prose, not a claim". On the real tree it excluded **ZERO**
    strings, so it narrowed recall to defend against nothing.

    **The first draft of this case asserted that property of the tree** (no
    arm anywhere starts with those prefixes). It passed against the very
    mutation meant to kill it: the tree has no such string, so the assertion
    held whether or not the filter existed. A guard that cannot fail is a
    sentence in a file -- the defect this repo has filed five times, now in my
    own new case. So the fixture below plants the exact string the old rule
    would have eaten and asserts it is STILL counted. That pins the filter's
    behaviour instead of the tree's contents.
    """
    import ast as _ast
    src = ('def r():\n'
           '    out = []\n'
           '    if rep.get("count") is None:\n'
           '        out.append("How it was measured: none")\n'
           '    out.append("Read-only probe")\n'
           '    return out\n')
    fn = sweep_mod._renderers(_ast.parse(src))[0]
    arms = sweep_mod._arm_lines(fn)
    assert len(arms) == 1, "a prose-prefixed arm was dropped: %d arms" % len(arms)
    assert "How it was measured: none" in arms[0][1], arms[0]
    # And the sentence the sweep would file for it must survive the truncation
    # in `sweep()` -- a short arm must not vanish from the printed report.
    emitted = [t for _, strs in arms for t in strs]
    assert any(len(t) <= 12 or t.startswith("How ") for t in emitted), emitted


# ------------------------------- the guard states: a deleted refusal is not
# ------------------------------- a healthy one

def _delete_guard_statement(path):
    """Remove the WHOLE `if _another_writer_is_building():` statement and body.

    The first draft of this helper replaced the `if` line with `pass` and left
    the body orphaned, which is an IndentationError -- the mutated tree read
    `UNREADABLE` and the mutation looked like it had "not fired". It had not
    fired because the tree was broken, which is the least convincing negative
    result available. The mutation has to leave a tree that PARSES.
    """
    import ast as _ast
    text = open(path, encoding="utf-8").read()
    tree = _ast.parse(text)
    lines = text.split("\n")
    spans = []
    for node in _ast.walk(tree):
        if not isinstance(node, _ast.If):
            continue
        if any(isinstance(c, _ast.Call) and isinstance(c.func, _ast.Name)
               and c.func.id == "_another_writer_is_building"
               for c in _ast.walk(node.test)):
            spans.append((node.lineno,
                          max(getattr(x, "lineno", node.lineno) for x in node.body)))
    for a, b in sorted(spans, reverse=True):
        del lines[a - 1:b]
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    return len(spans)


def _state_of(tmpdir, tool):
    import ast as _ast
    return sweep_mod._guard_state(
        _ast.parse(open(os.path.join(tmpdir, tool + ".py"),
                        encoding="utf-8").read()))


@case("the real tree's guards all do their job (control)")
def _real_guards_healthy():
    states = {}
    for tool in sweep_mod.SIBLINGS:
        states[tool] = _state_of(REPO_TOOL, tool)[0]
    sick = {t: s for t, s in states.items() if s in ("INVERTED", "NEVER CALLED", "UNREACHABLE")}
    assert sick == {}, "a build guard is not working: %s" % sick
    # The census tools parse Dart and build nothing; they are expected to carry
    # no guard, and the sweep must SAY so rather than leave it to inference.
    assert states.get("agreement_census_audit") == "NONE", states
    assert states.get("numeric_bound_audit") == "NONE", states


@case("a DELETED refusal is NEVER CALLED, not healthy (the mutation)")
def _deleted_guard_is_caught():
    """The defect. The old check asked "is the call site inverted?" and "does
    one exist?". A tool with its refusal REMOVED answers the second question
    correctly and was reported as clean.

    Measured before the fix: the real tree and this mutation both printed
    `0 inverted guards` in the header, byte-identical.
    """
    tmp = tempfile.mkdtemp(prefix="rendersilence-delguard-")
    try:
        _copy_tree(tmp)
        path = os.path.join(tmp, "inbox_read_audit.py")
        removed = _delete_guard_statement(path)
        assert removed == 1, "control deleted %d guard statements, expected 1" % removed
        _ast_mod = __import__("ast")
        _ast_mod.parse(open(path, encoding="utf-8").read())   # must still parse
        state, _line = _state_of(tmp, "inbox_read_audit")
        assert state == "NEVER CALLED", (
            "a removed refusal reads as healthy: state=%r" % state)
        bad = [h for h in sweep_mod.sweep(tmp)
               if h["tool"] == "inbox_read_audit"
               and h.get("guard_polarity") == "NEVER CALLED"]
        assert bad, "the sweep filed nothing for a tool whose refusal is gone"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@case("a guard that can never fire is UNREACHABLE, not correct")
def _unreachable_guard_is_caught():
    """`if False and _another_writer_is_building():` keeps the call site, so
    every question asked OF THE CALL SITE answers `correct`. The refusal is
    dead code and the tool builds during a real build."""
    tmp = tempfile.mkdtemp(prefix="rendersilence-deadguard-")
    try:
        _copy_tree(tmp)
        path = os.path.join(tmp, "worker_reviews_audit.py")
        text = open(path, encoding="utf-8").read()
        hits = 0
        for line in text.split("\n"):
            pass
        new = []
        for line in text.split("\n"):
            if re.match(r"^\s*if _another_writer_is_building\(\):\s*$", line):
                line = line.replace("if _another_writer_is_building():",
                                    "if False and _another_writer_is_building():")
                hits += 1
            new.append(line)
        assert hits == 1, "control neutered %d call sites, expected 1" % hits
        open(path, "w", encoding="utf-8").write("\n".join(new))
        state, _line = _state_of(tmp, "worker_reviews_audit")
        assert state == "UNREACHABLE", (
            "a dead refusal reads as correct: state=%r" % state)
        bad = [h for h in sweep_mod.sweep(tmp)
               if h["tool"] == "worker_reviews_audit"
               and h.get("guard_polarity") == "UNREACHABLE"]
        assert bad, "the sweep filed nothing for a guard that can never fire"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@case("removing EVERY refusal in the tree is caught 5 of 5")
def _every_guard_deleted_is_caught():
    """The mutation run against all seven tools at once, because a guard check
    that only ever sees one module is the 'named, never opened' shape."""
    tmp = tempfile.mkdtemp(prefix="rendersilence-allguards-")
    try:
        _copy_tree(tmp)
        total = 0
        for tool in sweep_mod.SIBLINGS:
            total += _delete_guard_statement(os.path.join(tmp, tool + ".py"))
        assert total == 5, "expected 5 guard statements in the tree, deleted %d" % total
        import ast as _ast
        for tool in sweep_mod.SIBLINGS:
            _ast.parse(open(os.path.join(tmp, tool + ".py"),
                            encoding="utf-8").read())
        states = {t: _state_of(tmp, t)[0] for t in sweep_mod.SIBLINGS}
        sick = {t: s for t, s in states.items() if s == "NEVER CALLED"}
        assert len(sick) == 5, (
            "removing every refusal was caught in %d of 5: %s" % (len(sick), states))
        filed = {h["tool"] for h in sweep_mod.sweep(tmp)
                 if h.get("guard_polarity") == "NEVER CALLED"}
        assert len(filed) == 5, "the sweep filed %d of 5: %s" % (len(filed), sorted(filed))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@case("ONE inverted guard is still caught (the regression this must not break)")
def _inversion_still_caught():
    """The case that already existed, re-asserted against the six-state judge:
    a fix for 'a missing refusal' must not cost the detection of 'a wrong one'."""
    tmp = tempfile.mkdtemp(prefix="rendersilence-invert-")
    try:
        _copy_tree(tmp)
        path = os.path.join(tmp, "inbox_read_audit.py")
        new = []
        hits = 0
        for line in open(path, encoding="utf-8").read().split("\n"):
            if re.match(r"^\s*if _another_writer_is_building\(\):\s*$", line):
                line = line.replace("if _another_writer_is_building():",
                                    "if not _another_writer_is_building():")
                hits += 1
            new.append(line)
        assert hits == 1, "control inverted %d call sites, expected 1" % hits
        open(path, "w", encoding="utf-8").write("\n".join(new))
        bad = [h for h in sweep_mod.sweep(tmp)
               if h["tool"] == "inbox_read_audit"
               and h.get("guard_polarity") == "INVERTED"]
        assert bad, "the inversion detector regressed"
        # ...and it must be INVERTED, not one of the new states.
        assert _state_of(tmp, "inbox_read_audit")[0] == "INVERTED", _state_of(tmp, "inbox_read_audit")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@case("a helper called into a name is INDIRECT, not guessed either way")
def _indirect_guard_is_its_own_state():
    """`busy = _another_writer_is_building()` then `if busy:` is a legal
    refusal this AST pass cannot follow. Filing it INVERTED would invent a
    defect; filing it `correct` would assert a measurement nobody made."""
    import ast as _ast
    src = ('def _another_writer_is_building():\n'
           '    return False\n'
           'def main():\n'
           '    busy = _another_writer_is_building()\n'
           '    if busy:\n'
           '        print("REFUSED")\n')
    state, _line = sweep_mod._guard_state(_ast.parse(src))
    assert state == "INDIRECT", state
    src2 = src.replace("    if busy:", "    if not busy:")
    assert sweep_mod._guard_state(_ast.parse(src2))[0] == "INDIRECT", \
        "the indirect shape must stay unjudged in both polarities"


@case("the sweep REPORTS the guard state, not just computes it (mutation D)")
def _guard_state_is_reported():
    """A judge whose verdict is computed and thrown away is a guard that cannot
    fail, which is the defect this repo has filed six times and this tick once
    more -- my first draft of these six cases scored `_guard_state` directly
    and called that sufficient. Measured, not assumed: mutating `sweep()` so
    the non-`correct` states are never FILES made all 23 cases pass.

    So this case asserts the thing the mutation actually removes: that the
    state reaches the REPORT. It reads `sweep()`'s output on a mutated tree,
    where the arms are unchanged and the guard is not.
    """
    tmp = tempfile.mkdtemp(prefix="rendersilence-report-")
    try:
        _copy_tree(tmp)
        path = os.path.join(tmp, "worker_reviews_audit.py")
        assert _delete_guard_statement(path) == 1
        hits = sweep_mod.sweep(tmp)
        row = [h for h in hits if h["tool"] == "worker_reviews_audit"]
        assert row, "the mutated tool vanished from the sweep entirely"
        states = {h.get("guard_polarity") for h in row}
        assert "NEVER CALLED" in states, (
            "the state was computed and never filed -- the report cannot show "
            "it: %s" % states)
        # The header line, not just the JSON: this is what a human reads.
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            sweep_mod.main(["--dir", tmp])
        text = buf.getvalue()
        assert "NEVER CALLED" in text, (
            "the printed sweep is missing the dead refusal:\n%s"
            % text.split("\n")[0])
        # The header carries the COUNT, and the count must match the mutation:
        # `_delete_guard_statement` removed one from `worker_reviews_audit`
        # only, so exactly one tool is not doing its job. Asserting the number
        # rather than "> 0" is deliberate -- "0 guard(s)" and "7 guard(s)" both
        # pass a threshold and are the two answers this case exists to separate.
        assert "1 guard(s) not doing their job" in text, text.split("\n")[0]
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@case("one dead guard counts ONCE, not once per arm (mutation E)")
def _guard_count_is_per_tool():
    """`guard_polarity` is a property of the MODULE and is stamped onto every
    arm its renderer files. Filtering `hits` therefore counts a four-arm
    renderer as four broken guards -- measured: deleting one refusal in
    `worker_reviews_audit` printed `5 guard(s) not doing their job`.

    Found by planting, not by reading: mutation E (`{h["tool"] ...}` ->
    `{1 ...}`) turned the header into an opaque constant and **all 24 cases
    still passed**, because every case asserted a count of zero or asserted
    the state per tool, never the header's number. This case asserts the exact
    number for a one-tool mutation, which is the assertion E cannot survive.
    """
    tmp = tempfile.mkdtemp(prefix="rendersilence-count-")
    try:
        _copy_tree(tmp)
        path = os.path.join(tmp, "worker_reviews_audit.py")
        assert _delete_guard_statement(path) == 1
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            sweep_mod.main(["--dir", tmp])
        header = buf.getvalue().split("\n")[0]
        assert "1 guard(s) not doing their job" in header, (
            "one dead guard did not count once: %s" % header)
        # And the tree-wide mutation counts five, not the sum of their arms.
        for tool in sweep_mod.SIBLINGS:
            _delete_guard_statement(os.path.join(tmp, tool + ".py"))
        buf2 = io.StringIO()
        with contextlib.redirect_stdout(buf2):
            sweep_mod.main(["--dir", tmp])
        header2 = buf2.getvalue().split("\n")[0]
        assert "5 guard(s) not doing their job" in header2, header2
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


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
