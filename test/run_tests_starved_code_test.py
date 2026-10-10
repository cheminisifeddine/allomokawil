#!/usr/bin/env python3
"""Prove a STARVED shard is not a HUNG one -- different code, different words,
different next move.

    python3 test/run_tests_starved_code_test.py

Python, not `flutter test`, for the reason `run_tests_busy_code_test.py` gives:
this box refuses Dart whenever the balloon is up, and the defect this pins is
only observable on exactly that box -- a starved shard on a loaded box. A
python suite is the shape that stays checkable when the gate is most needed.

**The defect, measured 10 Oct.** Five consecutive shards hit their 300 s cap
with zero assertion failures and printed `HUNG` -- the code `run_tests.py`
defines as "a shard I started stopped answering". `flutter_tester` was at 58 %
CPU while a foreign puppeteer Chrome burned the rest of a 2-core machine: the
shards were *starved*, not deadlocked, and the runner could not tell the two
apart. They are opposites to whoever reads the verdict. A hang says *the tree
is suspect*: bisect it, find the culprit file, ship a fix. A starve says *the
box is suspect*: nothing in the tree changed, re-run when the machine is idle.
The old code sent every starved shard down the expensive path.

**Why load average could not be the signal, measured rather than assumed.**
Load average is box-wide and 1-minute weighted, so it reads HIGH for a
deadlocked shard when something else is busy and LOW for a starved one when
nothing else is:

    shape                        own-group CPU   load1
    sleep 600 (deadlocked)            0.0 %      0.55
    busy loop (starved)              90.3 %      0.67
    deadlocked + 4 foreign hogs      0.0 %      1.85

No cut separates that table: 1.0 calls the loaded deadlock starved, anything
above it calls the real starve a hang. Load average answers "is the BOX busy";
the question is "is THIS SHARD busy". The last tick's proposal -- sample
`/proc/loadavg` and report `STARVED (load N on M cores)` -- was measured here
and would have misclassified the very case it was written for. Only the shard's
OWN process group separates them, and that is what this pins.

Six cases. The first four are the two shapes the fix exists to separate; the
last two are the ways a fix like this silently stops working.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNNER = os.path.join(REPO, "tool", "run_tests.py")

PASS, FAIL, HUNG, BUSY, STARVED = 0, 1, 2, 3, 4

_results = []

#: Long enough that a CPU-burning stub clears the 25 %-of-a-core bar, short
#: enough to leave a 10-minute tick room to run the whole file.
DEADLINE = 20

DEADLOCKED_STUB = """#!/usr/bin/env bash
echo "00:00 +0: loading test/a_test.dart"
sleep 600
"""

#: Burns real CPU and never finishes -- the shape of a starved shard, which is
#: progressing and cannot be given the time, rather than blocked on nothing.
STARVED_STUB = """#!/usr/bin/env bash
echo "00:00 +0: loading test/a_test.dart"
end=$((SECONDS + 600))
while [ $SECONDS -lt $end ]; do :; done
"""

GREEN_STUB = """#!/usr/bin/env bash
echo "00:00 +0: loading test/a_test.dart"
echo "00:02 +3: All tests passed!"
exit 0
"""


def case(name):
    def wrap(fn):
        _results.append((name, fn))
        return fn
    return wrap


def _run(stub_body, deadline=DEADLINE):
    """Run the real runner against a stub `flutter`, gate forced CLEAR."""
    tmp = tempfile.mkdtemp(prefix="starved_")
    stub = os.path.join(tmp, "flutter")
    with open(stub, "w") as fh:
        fh.write(stub_body)
    os.chmod(stub, 0o755)
    gate = os.path.join(tmp, "gate.py")
    with open(gate, "w") as fh:
        fh.write("import sys\nsys.exit(0)\n")

    env = dict(os.environ)
    env["RUN_TESTS_FLUTTER"] = stub
    env["RUN_TESTS_GATE"] = gate
    r = subprocess.run(
        [sys.executable, RUNNER, "--deadline", str(deadline),
         "--shard-size", "0", "--", "test/x_test.dart"],
        cwd=REPO, env=env, capture_output=True, text=True, timeout=180)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


@case("a deadlocked shard is HUNG (2) -- the tree is suspect")
def _deadlock_is_hung():
    code, out = _run(DEADLOCKED_STUB)
    assert code == HUNG, \
        "a shard that stopped answering must be %d (HUNG); got %r\n%s" \
        % (HUNG, code, out)
    assert "STARVED" not in out, \
        "a shard that burned 0.0 CPU-s was called STARVED: that sends a tick "\
        "to free the box when the deadlock is in the tree\n%s" % out


@case("a starved shard is STARVED (4), never the HUNG a tick would chase")
def _starve_is_not_a_hang():
    code, out = _run(STARVED_STUB)
    assert code == STARVED, \
        "a shard that was still burning CPU must be %d (STARVED); got %r, "\
        "which a tick reads as a deadlock in a tree that has none\n%s" \
        % (STARVED, code, out)
    assert code != HUNG, \
        "2 is HUNG. The 10 Oct regression: five starved shards all printed "\
        "it and the write-up described a hang.\n%s" % out
    assert code != PASS, "a starved shard is not a pass.\n%s" % out
    assert code != FAIL, "a starved shard is not a fail.\n%s" % out
    assert code != BUSY, "a starvation is not a refusal to start.\n%s" % out


@case("the starvation verdict says what to do next, in words")
def _starve_explains_itself():
    code, out = _run(STARVED_STUB)
    assert "STARVED" in out, "the shard must be named.\n%s" % out
    assert "CPU-s" in out, \
        "the evidence must be shown: the CPU the shard burned is the only "\
        "thing separating this from a hang, so it belongs in the log\n%s" % out
    assert "INCONCLUSIVE" in out, \
        "the verdict must say the run proves nothing about the tree, or a "\
        "tick reports a starved run as a red suite\n%s" % out
    assert "not red" in out, \
        "'not red' is the phrase the founder-facing report has to be able to "\
        "copy\n%s" % out
    assert "No assertion failed" in out, \
        "the report must distinguish 'slow' from 'failing'\n%s" % out


@case("a green suite stays green and is never called starved")
def _green_is_unaffected():
    code, out = _run(GREEN_STUB)
    assert code == PASS, "a green suite must stay green; got %r\n%s" % (code, out)
    assert "STARVED" not in out and "HUNG" not in out, \
        "a suite that finished on time must carry no starvation verdict\n%s" % out
    assert "SUITE PASS" in out, "and must still print its number.\n%s" % out


@case("the CPU sample is the shard's OWN group, not the box's load")
def _samples_its_own_group():
    """The sampler must read the shard, not /proc/loadavg.

    Guarding the choice of metric, not just the outcome: a future tick can make
    every case above pass again by thresholding load average instead, and the
    only thing that catches that is the source itself.
    """
    src = open(RUNNER).read()
    sampler = src[src.index("def _group_cpu_seconds"):src.index("def _is_starved")]
    assert "SC_CLK_TCK" in sampler and "/proc" in sampler, \
        "the sampler must read utime+stime out of /proc/<pid>/stat\n%s" % sampler
    assert "loadavg" not in sampler, \
        "the sampler must not read load average: measured, it reads HIGH for "\
        "a deadlocked shard when something else is busy (1.85) and LOW for a "\
        "starved one when nothing else is (0.67), so it cannot separate them\n" \
        % sampler


@case("a mixed run separates the starved shards from the hung ones")
def _mixed_is_reported_as_mixed():
    """Two shards, one shape each, in ONE run: the verdict must not merge them.

    The 10 Oct run was five starving shards and nothing else, so a fix that
    classified correctly when *every* shard agreed would never be caught here.
    This is the shape that matters in practice: one foreign process loads the
    box, some shards tip over and some finish.

    **The argv is `[test, --reporter, expanded, <file>]`, so the file is
    `$4`.** The first draft of this case branched on `$3` and matched nothing --
    every shard took the `sleep 600` branch, both printed HUNG, and the case
    passed by accident while testing nothing. The stub now prints the file it
    was handed to stderr and the assertion checks it, so a mis-keyed stub fails
    instead of going quiet.
    """
    with tempfile.TemporaryDirectory(prefix="mixed_") as tmp:
        stub = os.path.join(tmp, "flutter")
        with open(stub, "w") as fh:
            fh.write("""#!/usr/bin/env bash
echo "STUB-SAW $4" >&2
if [ "$4" = "test/a_test.dart" ]; then
  echo "00:00 +0: loading test/a_test.dart"
  end=$((SECONDS + 600))
  while [ $SECONDS -lt $end ]; do :; done
  exit 0
fi
echo "00:00 +0: loading test/b_test.dart"
sleep 600
""")
        os.chmod(stub, 0o755)
        gate = os.path.join(tmp, "gate.py")
        with open(gate, "w") as fh:
            fh.write("import sys\nsys.exit(0)\n")
        env = dict(os.environ)
        env["RUN_TESTS_FLUTTER"] = stub
        env["RUN_TESTS_GATE"] = gate
        r = subprocess.run(
            [sys.executable, RUNNER, "--deadline", "70", "--shard-size", "1",
             "--shard-deadline", "25", "--retries", "0", "--",
             "test/a_test.dart", "test/b_test.dart"],
            cwd=REPO, env=env, capture_output=True, text=True, timeout=220)
        out = (r.stdout or "") + (r.stderr or "")

    assert code_is_sane(r.returncode, out), \
        "the runner crashed or exited outside its own code set: %r\n%s" \
        % (r.returncode, out)
    # The stub must really have been handed each file, or the case is void.
    assert "STUB-SAW test/a_test.dart" in out, \
        "the stub never received the starved shard's file -- argv shape "\
        "changed and this case would be testing nothing\n%s" % out
    assert "STUB-SAW test/b_test.dart" in out, \
        "the stub never received the hung shard's file\n%s" % out
    assert "shard 1/2: STARVED" in out, \
        "the burning shard must be STARVED\n%s" % out
    assert "shard 2/2: HUNG" in out, \
        "the sleeping shard must still be HUNG -- if it is not, one verdict "\
        "is being applied to both shapes\n%s" % out
    assert "MIXED" in out, \
        "a run with both shapes must say so rather than report one verdict "\
        "twice\n%s" % out
    assert "SUITE PASS" not in out, \
        "a shard that died must never be counted into a suite total\n%s" % out
    # A mixed run still names the tree-suspect shard, because that is the one
    # worth bisecting.
    assert "HUNG" in out.split("MIXED")[1], \
        "the MIXED verdict must carry the hung shard's verdict with it\n%s" % out


def code_is_sane(code, out):
    return code in (PASS, FAIL, HUNG, BUSY, STARVED) and "Traceback" not in out


def main():
    failures = 0
    for name, fn in _results:
        try:
            fn()
            print("ok   - %s" % name)
        except AssertionError as exc:
            failures += 1
            print("FAIL - %s\n%s" % (name, exc))
        except Exception as exc:                       # noqa: BLE001
            failures += 1
            print("ERROR- %s: %r" % (name, exc))
    print("\n%d passed, %d failed" % (len(_results) - failures, failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
