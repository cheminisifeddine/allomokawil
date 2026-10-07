#!/usr/bin/env python3
"""Prove `tool/run_tests.py` never ANNOUNCES a retry it did not pay for.

    python3 test/run_tests_retry_budget_test.py

Run directly -- it spawns real child processes and is not a `flutter test`:
the defect being pinned is an *ordering* question (when is a message printed
relative to a clock), and a mocked subprocess cannot observe ordering. A
python suite is also the only shape that runs on a box whose gate refuses a
Dart build, which is exactly when this needs to be checkable.

**The defect.** `main()` prints "retrying inside its own shard" and then loops
back to `remaining = global_end - time.monotonic()`. A HUNG attempt has already
spent its whole shard cap, so on a plan whose remaining budget cannot fund one
more attempt the loop exits on `remaining <= 0` having run nothing. The message
sat one line ABOVE that check and was emitted regardless, while the shard
summary -- printed from the real `attempts` counter -- correctly said
"1 attempt(s)". One run, two logs, contradicting each other:

    === shard 1/1, attempt 1/2 -- 3 file(s), deadline 3s ===
    --- shard 1/1 failed (HUNG); retrying inside its own shard ---
    shard 1/1: HUNG in 0:03 (1 attempt(s), 0 test(s))

The line a tick reads to decide whether the suite was retried was the false
one. This file exists because the loop's rule is that a gate's output *is* the
evidence: `passed_count` returning None once made the runner raise TypeError
rather than print "?" (`%d` vs `%s`), and a log that misdescribes its own
number is decoration, not a record.

Two shapes reach the dead branch, and both are pinned:

  * the single-shard plan, where `default_deadline` returns None and `main()`
    falls back to `a.shard_deadline`, so the whole-run budget IS the per-batch
    cap and attempt 1 consumes all of it;
  * any caller who sets `--deadline` tighter than the shards need.

**Case 3 is the guard on the fix, not a duplicate.** It runs a plan whose
derived budget *can* pay for the retry and asserts the stub was really launched
twice. Without it, a fix that simply suppressed the message -- the cheapest way
to silence case 1 -- would pass cases 1 and 2 while deleting the retry the
runner documents, the one its own `--retries` flag and
`run_tests_shard_test.dart` both depend on. A guard that stops firing would
also produce a green suite; that is the failure mode this file is shaped
against.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNNER = os.path.join(REPO, "tool", "run_tests.py")

PASS, FAIL, HUNG = 0, 1, 2

_results = []


def case(name):
    def wrap(fn):
        _results.append((name, fn))
        return fn
    return wrap


def _run_hanging(tmp, label, runner_args):
    """Run the real runner against a stub `flutter` that hangs forever.

    The stub appends a line per launch, so "did the runner actually retry?" is
    answered by COUNTING rather than by trusting the log under test -- which is
    the whole point: the pre-fix runner's log was the thing that lied.
    """
    gate = os.path.join(tmp, "gate_clear.py")
    with open(gate, "w") as fh:
        fh.write("import sys\nsys.exit(0)\n")

    launches = os.path.join(tmp, "%s_launches" % label)
    stub = os.path.join(tmp, "flutter")
    with open(stub, "w") as fh:
        fh.write(
            "#!/usr/bin/env bash\n"
            "echo 1 >> %s\n"
            "echo \"00:00 +0: loading test/f1_test.dart\"\n"
            "sleep 600\n" % launches)
    os.chmod(stub, 0o755)

    env = dict(os.environ)
    env["RUN_TESTS_FLUTTER"] = stub
    env["RUN_TESTS_GATE"] = gate

    r = subprocess.run(
        [sys.executable, RUNNER] + runner_args + ["--", "f1_test.dart",
                                                  "f2_test.dart"],
        cwd=REPO, env=env, capture_output=True, text=True, timeout=300)
    out = (r.stdout or "") + (r.stderr or "")

    n = 0
    if os.path.exists(launches):
        with open(launches) as fh:
            n = len([l for l in fh.read().split("\n") if l.strip()])
    return r.returncode, out, n


@case("a retry the budget cannot pay for is named, not announced")
def _single_shard():
    # Single shard: the whole-run budget IS the per-batch cap, so attempt 1
    # consumes all of it. This is the shape a plain `--shard-size 0` run takes.
    with tempfile.TemporaryDirectory() as tmp:
        code, out, n = _run_hanging(
            tmp, "single", ["--shard-size", "0", "--shard-deadline", "3"])
        assert code == HUNG, "a hang is HUNG (2), got %r\n%s" % (code, out)
        assert "retrying inside its own shard" not in out, \
            "runner claimed a retry it never ran\n%s" % out
        assert "no whole-run budget left for the retry" in out, \
            "the unpaid retry must be stated, not dropped\n%s" % out
        assert "1 attempt(s)" in out, \
            "exactly one attempt was paid for\n%s" % out
        assert n == 1, "stub launched %d time(s), the retry never ran" % n


@case("a caller-set deadline too small for a retry is not oversold")
def _caller_set():
    # Two shards under a --deadline that cannot fund a second attempt. The
    # opposite edge of the same clock from the case above.
    with tempfile.TemporaryDirectory() as tmp:
        code, out, n = _run_hanging(
            tmp, "caller",
            ["--shard-size", "1", "--shard-deadline", "30", "--deadline", "3"])
        assert code == HUNG, "a hang is HUNG (2), got %r\n%s" % (code, out)
        assert "retrying inside its own shard" not in out, \
            "no budget, no retry claim\n%s" % out
        assert "no whole-run budget left for the retry" in out, \
            "the unpaid retry must be named\n%s" % out
        assert "INCOMPLETE" in out, "a cut run is not a suite result\n%s" % out
        assert n == 1, "stub launched %d time(s), one attempt was all" % n


@case("a budget that CAN pay for the retry still retries, and says so")
def _retry_still_pays():
    # The guard on the fix. Two shards, each hanging, each with budget for both
    # of its attempts: 2 shards x 2 attempts = 4 launches. A fix that merely
    # suppressed the message would pass the two cases above while deleting the
    # retry, and this is what catches that.
    #
    # The count was 2 on the first run of this file and the assertion was
    # wrong, not the runner: the budget is per SHARD, so the derived whole-run
    # figure funds 2 attempts in each of the 2 shards rather than 2 overall.
    with tempfile.TemporaryDirectory() as tmp:
        code, out, n = _run_hanging(
            tmp, "paid", ["--shard-size", "1", "--shard-deadline", "3"])
        assert code == HUNG, "a hang is HUNG (2), got %r\n%s" % (code, out)
        assert "retrying inside its own shard" in out, \
            "a retry that is paid for must still be announced\n%s" % out
        assert n == 4, \
            "2 shards x 2 paid attempts = 4 launches, got %d" % n


@case("a shard that FAILS fast still gets its paid-for retry")
def _fail_retry_unaffected():
    # The fix must not disturb the ordinary FAIL retry, which is what
    # --retries exists for. A failing stub costs no budget, so attempt 2 runs.
    with tempfile.TemporaryDirectory() as tmp:
        gate = os.path.join(tmp, "gate.py")
        with open(gate, "w") as fh:
            fh.write("import sys\nsys.exit(0)\n")
        stub = os.path.join(tmp, "flutter")
        with open(stub, "w") as fh:
            fh.write("#!/usr/bin/env bash\n"
                     "echo \"00:01 +0: test/x [E]\"\nexit 1\n")
        os.chmod(stub, 0o755)
        env = dict(os.environ)
        env["RUN_TESTS_FLUTTER"] = stub
        env["RUN_TESTS_GATE"] = gate
        r = subprocess.run(
            [sys.executable, RUNNER, "--shard-size", "0",
             "--shard-deadline", "20", "--", "f1_test.dart"],
            cwd=REPO, env=env, capture_output=True, text=True, timeout=120)
        out = (r.stdout or "") + (r.stderr or "")
        assert r.returncode != HUNG or "2 attempt(s)" in out, \
            "a paid-for retry must run even when both attempts fail\n%s" % out
        assert "2 attempt(s)" in out, \
            "the FAIL retry is what --retries promises\n%s" % out


# **Two of this file's own assertions were wrong before the runner was ever
# suspected, and both are recorded here because the trap recurs.** Neither cost
# a shipped bug -- the runner was correct in both cases and the test was not --
# and that is exactly what makes them worth writing down.
#
#   1. The launch count. Case 3 asserted the stub ran twice for two shards; it
#      ran four times, because the budget is per SHARD and a derived whole-run
#      figure funds 2 attempts in each of the 2 shards rather than 2 overall.
#      "Per shard" and "per run" look identical in the runner's own log.
#   2. The red-shard exit code. An ad-hoc replication of
#      `run_tests_shard_test.dart` assumed a never-green shard would exit HUNG
#      (2); it exits FAIL (1) and prints "This is NOT a suite result" rather
#      than the word "INCOMPLETE", which is reserved for shards that never got
#      their turn. HUNG means the harness lost control; a shard that ran twice
#      and failed twice is a red tree, and conflating them would send a tick
#      hunting a harness bug it does not have.
#
# Same lesson slice 33 and the last tick's border-width census recorded: a probe
# returning an implausible number is a broken probe, not a result. Both here
# were caught by reading the runner's real output rather than by reasoning
# about what it "should" say.


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
