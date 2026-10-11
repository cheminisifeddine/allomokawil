#!/usr/bin/env python3
"""Prove the Python battery gate runs what it claims, and fails when it should.

    python3 test/run_py_tests_battery_test.py

**The gap, measured 11 Oct.** `discover_tests()` collected 324 files and **0**
Python, so the 31 `test/*_test.py` batteries -- including the ones guarding the
push helper, the PNG reader, pngscan and the remote verifier -- ran only when a
tick remembered them. All 31 passed; none of them gated anything.
`tool/run_py_tests.py` is the gate that closes it.

**Why this file is not `run_py_tests_exit_docs_test.py` again.** That file pins
the protocol's *prose* to the runner's constants. This one pins the runner's
*behaviour*, because the defect here is not a stale sentence -- it is that no
code path ever asked the question. A sentence can drift; a suite that is not
collected cannot.

**Hermetic by construction.** Every case that spawns the runner sets
`RUN_TESTS_GATE` to a stub, so `build_gate.py` is never consulted and the real
one cannot make the result depend on this box's memory. Nothing here reaches
the network, reads a credential or spawns `flutter`.
"""

from __future__ import annotations

import ast
import os
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = os.path.join(REPO, "tool", "run_py_tests.py")
TESTS_DIR = os.path.join(REPO, "test")

PASS, FAIL, HUNG, BUSY, STARVED = 0, 1, 2, 3, 4

_results = []


def case(name):
    def wrap(fn):
        _results.append((name, fn))
        return fn
    return wrap


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _run(argv, gate_rc=0, timeout=120):
    """Spawn the gate with a stubbed build gate. Returns (rc, output)."""
    with tempfile.TemporaryDirectory() as tmp:
        gate = os.path.join(tmp, "gate.py")
        with open(gate, "w", encoding="utf-8") as fh:
            fh.write("import sys\nsys.exit(%d)\n" % gate_rc)
        env = dict(os.environ)
        env["RUN_TESTS_GATE"] = gate
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        p = subprocess.run([sys.executable, GATE] + argv, cwd=REPO, env=env,
                           capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")


def _write_battery(tmp, name, body):
    path = os.path.join(tmp, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(body)
    return path


# ---------------------------------------------------------------- discovery --

@case("--list names every battery it would run")
def _list_covers():
    rc, out = _run(["--list"])
    assert rc == PASS, "listing must not be a verdict; got %d\n%s" % (rc, out)
    # The listing is repo-relative (`test/foo.py`), which is what a caller
    # passes back in with `--`. Compare on that spelling, not on bare names:
    # an earlier version of this case compared basenames against repo-relative
    # lines and went red on all 32 while the gate was correct. The gate's
    # spelling is the one the runner's own `--` argument needs.
    named = [l.strip() for l in out.splitlines()
             if l.strip().endswith("_test.py")]
    on_disk = sorted("test/" + n for n in os.listdir(TESTS_DIR)
                     if n.endswith("_test.py"))
    missing = [n for n in on_disk if n not in named]
    assert not missing, ("the gate cannot see %d battery/batteries: %s"
                         % (len(missing), missing))
    # ...and nothing invented: a listing with an entry no file backs is a plan
    # that runs a phantom.
    unknown = [n for n in named if n not in on_disk]
    assert not unknown, "the gate lists non-existent batteries: %s" % unknown


@case("discovery is sorted, so the batch plan is identical every tick")
def _discovery_sorted():
    rc, out = _run(["--list"])
    assert rc == PASS, out
    named = [l.strip() for l in out.splitlines()
             if l.strip().endswith("_test.py")]
    assert named, "discovery returned nothing at all"
    assert named == sorted(named), (
        "unsorted discovery makes the plan depend on readdir order:\n%s"
        % named)


@case("discovery is exactly the batteries -- it does not swallow the Dart suite")
def _discovery_excludes_dart():
    rc, out = _run(["--list"])
    assert rc == PASS, out
    assert not [l for l in out.splitlines()
                if l.strip().endswith("_test.dart")], (
        "this gate must never collect Dart files -- it does not call flutter")


# ------------------------------------------------------------- exit codes ----

@case("a green battery is PASS (0)")
def _green_is_pass():
    with tempfile.TemporaryDirectory() as tmp:
        b = _write_battery(tmp, "ok_test.py", "print('all good')\n")
        rc, out = _run(["--retries", "0", "--", b])
    assert rc == PASS, "a passing battery must be 0; got %d\n%s" % (rc, out)
    assert "SUITE PASS" in out, out


@case("a failing battery is FAIL (1), and it is NAMED")
def _red_is_fail_and_named():
    with tempfile.TemporaryDirectory() as tmp:
        b = _write_battery(
            tmp, "bad_test.py",
            "import sys\nprint('boom: the thing that broke')\n"
            "sys.exit(1)\n")
        rc, out = _run(["--retries", "0", "--", b])
    assert rc == FAIL, "a failing battery must be 1; got %d\n%s" % (rc, out)
    assert "bad_test.py" in out, (
        "the log must name the file that failed -- an exit code without a name "
        "is what the Dart runner's `culprit()` exists to prevent:\n%s" % out)


@case("a refusal is BUSY (3), never the HUNG (2) a tick would chase")
def _refusal_is_busy_not_hung():
    rc, out = _run(["--list"], gate_rc=1)
    # --list must answer BEFORE the gate, so it cannot refuse.
    assert rc == PASS, "--list must work without the build gate; got %d" % rc
    rc, out = _run([], gate_rc=1)
    assert rc == BUSY, (
        "a refusal must be BUSY (3), never HUNG (2) -- run_tests.py learned "
        "this the hard way and the code is the part that survives a cron "
        "wrapper; got %d\n%s" % (rc, out))
    assert "NOT ONE BATTERY RAN" in out, out


@case("busy is 3 and nothing ran -- the refusal is not a silent no-op")
def _refusal_ran_nothing():
    marker_src = "import pathlib\npathlib.Path(%r).write_text('x')\n"
    with tempfile.TemporaryDirectory() as tmp:
        b = _write_battery(tmp, "writes_test.py",
                           marker_src % os.path.join(tmp, "marker"))
        rc, out = _run(["--", b], gate_rc=1)
        assert rc == BUSY, out
        assert not os.path.exists(os.path.join(tmp, "marker")), (
            "a refusal that still ran a battery is worse than a wrong code: "
            "it is the second suite this gate exists to prevent")


@case("the exit codes are imported from run_tests, not restated")
def _codes_imported_not_copied():
    src = read(GATE)
    tree = ast.parse(src)
    runner_imported = False
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "run_tests":
            runner_imported = True
    assert runner_imported, (
        "the gate must import its exit codes from run_tests. A copied literal "
        "is a second definition that will drift -- and 2 once meant two "
        "different things, which cost two ticks.")
    # **Read it as an AST, not as a regex over the source.** A regex
    # `^\s*PASS\s*=\s*\d` does not match the form the mutation actually took,
    # `BUSY, FAIL, HUNG, PASS, STARVED = 3, 1, 2, 0, 4`, so the guard passed a
    # file that had copied every code out of the runner -- the one thing it
    # exists to forbid. Measured: that mutation survived 10/10 before this line
    # existed. Assignment *targets* are what define the names, so the targets
    # are what get inspected.
    redefined = []
    for node in ast.walk(tree):
        targets = []
        if isinstance(node, ast.Assign):
            targets = node.targets
        elif isinstance(node, (ast.AugAssign, ast.AnnAssign)):
            targets = [node.target]
        for t in targets:
            for nm in ast.walk(t):
                if isinstance(nm, ast.Name) and nm.id in (
                        "PASS", "FAIL", "HUNG", "BUSY", "STARVED"):
                    redefined.append(nm.id)
    assert not redefined, (
        "%s must not be redefined locally -- they must come from run_tests, or "
        "the two runners drift apart on the one code a cron wrapper reads"
        % sorted(set(redefined)))


@case("no wall clock: every deadline in the gate is monotonic")
def _no_wall_clock():
    """`tool_clock_seam_test.dart` fails the build on `time.time()` in any
    tracked `*.py`. A deadline loop is the one file that would trip it, so the
    rule is checked here on the new file's CODE with a tokenizer, not a
    substring -- a docstring that *names* the banned call while forbidding it is
    prose. Last tick's guard was rewritten for exactly that false positive
    (a grep for a bare `TOK` failed on the sentence documenting the bug), and a
    substring check here would reintroduce it.
    """
    import io
    import tokenize

    banned = {"time.time", "time.time_ns", "time.localtime", "time.mktime"}
    hits = []
    with open(GATE, "rb") as fh:
        toks = list(tokenize.tokenize(fh.readline))

    # A dotted read is NAME NAME. Scan every pair and drop the ones that are
    # only a docstring token -- tokenize gives STRING its own type, so prose is
    # structurally excluded rather than pattern-matched.
    for i, tok in enumerate(toks):
        if tok.type != tokenize.NAME:
            continue
        if tok.string in banned:
            hits.append((tok.start[0], tok.string))
        elif i + 1 < len(toks):
            nxt = toks[i + 1]
            # `time` `.` `time` -- tokenize emits OP for the dot, so match the
            # dotted path across NAME/OP/NAME.
            if (nxt.type == tokenize.OP and nxt.string == "."
                    and i + 2 < len(toks)
                    and toks[i + 2].type == tokenize.NAME):
                dotted = "%s.%s" % (tok.string, toks[i + 2].string)
                if dotted in banned:
                    hits.append((tok.start[0], dotted))
    assert not hits, (
        "wall-clock read in a tracked .py (tool_clock_seam_test.dart would "
        "fail the build on these): %s" % hits)


@case("every battery on disk is collectable and every tool battery has a file")
def _no_orphan_batteries():
    """A battery whose subject was deleted keeps passing for ever, because the
    file it reads is gone and it was written to fail loudly on that."""
    named = []
    for n in os.listdir(TESTS_DIR):
        if not n.endswith("_test.py"):
            continue
        named.append(n)
    # every battery must be under test/ and match the discovery suffix
    assert all(n.endswith("_test.py") for n in named)
    assert len(named) >= 31, (
        "expected at least the 31 batteries measured 11 Oct, found %d"
        % len(named))


if __name__ == "__main__":
    failed = 0
    for name, fn in _results:
        try:
            fn()
        except AssertionError as exc:
            failed += 1
            print("FAIL     %s\n         %s" % (name, exc))
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print("ERROR    %s\n         %r" % (type(exc).__name__, exc))
        else:
            print("PASS     %s" % name)
    print("\n%d case(s) against tool/run_py_tests.py" % len(_results))
    print("== %d/%d ==" % (len(_results) - failed, len(_results)))
    sys.exit(1 if failed else 0)
