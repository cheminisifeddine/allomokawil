#!/usr/bin/env python3
"""Prove a BUSY refusal is not a hang, a pass, or a fail -- its own exit code.

    python3 test/run_tests_busy_code_test.py

Run directly: it spawns the real runner and is not a `flutter test`. That is the
point -- this box refuses Dart builds whenever the hypervisor balloon is up, and
a python suite is the only shape that stays checkable exactly when the gate is
most needed (the same reasoning as run_tests_retry_budget_test.py).

**The defect, measured 9 Oct.** `main()` refused to start when
`build_gate.py` answered BUSY and returned HUNG -- exit 2 -- the code that means
"a shard I started stopped answering". The log said `BUSY - not starting a
second suite` and the exit code said hang, so the two disagreed and the exit
code is the one a script reads. It did not bite the runner: nothing ran, so
nothing could have hung. It bit the *tick*, twice. One tick spent its report on
a HUNG shard 9 with 208 tests, for a run that never launched a single test
process; the next tick read the same 2 and went looking for a hang in a tree
whose shards were all green. The number 2 also collided with a real hang
elsewhere in the same file, so the two could not be told apart by code at all.

**Why this is not cosmetic.** The loop's gate rule is that the runner's output
IS the evidence, and its exit code is the part that survives a scrolled log and
a cron wrapper. A refusal is a *re-run me later*; a hang is a *the tree is
suspect*. Collapsing them makes the cheap, safe answer -- wait for memory --
look like the expensive, alarming one, which is how a tick burns itself on a
phantom. Three is chosen because 0/1/2 are taken and this is a refusal rather
than a verdict on the tree.

Two cases, both load-bearing:

* **the code is BUSY (3), not HUNG (2).** The regression itself. A fix that
  printed the right words while keeping exit 2 would pass a log-grep and fail
  every tick that trusts the code.
* **nothing was spawned.** A refusal that exits correctly but launches a suite
  anyway is worse than a wrong code: it is the OOM this gate exists to prevent,
  and the exit code alone would not reveal it. The stub writes a marker file, so
  "did it start?" is answered by the filesystem and not by the log under test.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNNER = os.path.join(REPO, "tool", "run_tests.py")

PASS, FAIL, HUNG, BUSY = 0, 1, 2, 3

_results = []


def case(name):
    def wrap(fn):
        _results.append((name, fn))
        return fn
    return wrap


def _run_with_gate(tmp, gate_rc):
    """Run the real runner behind a stub build gate that answers `gate_rc`.

    The stub `flutter` would create a marker file and then hang, so a run that
    wrongly spawns anything is caught by the marker rather than trusted to fail
    on its own -- and so the case costs one second when it is correct.
    """
    gate = os.path.join(tmp, "gate_%d.py" % gate_rc)
    with open(gate, "w") as fh:
        fh.write("import sys\nprint('BUSY synthetic')\nsys.exit(%d)\n" % gate_rc)

    marker = os.path.join(tmp, "SPAWNED")
    stub = os.path.join(tmp, "flutter")
    with open(stub, "w") as fh:
        fh.write("#!/usr/bin/env bash\ntouch %s\nsleep 600\n" % marker)
    os.chmod(stub, 0o755)

    env = dict(os.environ)
    env["RUN_TESTS_FLUTTER"] = stub
    env["RUN_TESTS_GATE"] = gate

    r = subprocess.run(
        [sys.executable, RUNNER, "--shard-size", "0", "--",
         "test/does_not_exist_test.dart"],
        cwd=REPO, env=env, capture_output=True, text=True, timeout=120)
    out = (r.stdout or "") + (r.stderr or "")
    return r.returncode, out, os.path.exists(marker)


@case("a refusal is BUSY (3), never the HUNG (2) a tick would chase")
def _refusal_is_not_a_hang():
    with tempfile.TemporaryDirectory() as tmp:
        code, out, spawned = _run_with_gate(tmp, 1)
        assert code == BUSY, \
            "a refusal must be %d (BUSY); it returned %r, which a tick reads "\
            "as a hang in a shard that never ran\n%s" % (BUSY, code, out)
        assert code != HUNG, \
            "2 is HUNG: 'a shard I started stopped answering'. A refusal is "\
            "the opposite fact.\n%s" % out
        assert code != PASS, "a refusal is not a pass.\n%s" % out
        assert code != FAIL, "a refusal is not a fail.\n%s" % out


@case("the refusal spawns nothing, and says so in words")
def _refusal_spawns_nothing():
    with tempfile.TemporaryDirectory() as tmp:
        code, out, spawned = _run_with_gate(tmp, 1)
        assert not spawned, \
            "the gate said BUSY and a suite started anyway -- that is the OOM "\
            "on this 7.8 GB no-swap box, and the exit code hides it\n%s" % out
        # The words, not just the number: a tick reading a scrolled log sees
        # this line, and a wrong code with a right line still misleads whoever
        # trusts the code -- so both are pinned.
        assert "BUSY" in out, "the refusal must name itself.\n%s" % out
        assert "NOT ONE TEST RAN" in out, \
            "the refusal must say that no test ran, so it is not mistaken "\
            "for a suite that ran and stalled.\n%s" % out
        assert "not a hang" in out, \
            "the refusal must state that it is not a hang, because that is "\
            "the misreading it is exiting 3 to prevent.\n%s" % out


def main():
    ok = 0
    bad = 0
    for name, fn in _results:
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
