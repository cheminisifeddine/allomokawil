#!/usr/bin/env python3
"""Run the test suite in shards, under a wall-clock deadline, and report ONE number.

    python3 tool/run_tests.py                        # whole suite, sharded
    python3 tool/run_tests.py --deadline 120         # tighter global bound
    python3 tool/run_tests.py --shard-size 0         # disable sharding (one run)
    python3 tool/run_tests.py -- test/a_test.dart    # extra args go to flutter test

Exit codes: 0 pass, 1 fail, 2 hung/incomplete (the deadline fired),
3 BUSY (the build gate refused, so NOT ONE TEST RAN).

**Exit 2 and exit 3 are different facts and must not share a code.** Measured
9 Oct: a bare `run_tests.py` printed `BUSY — not starting a second suite on this
box` and exited 2. Two ticks read that as a hang, and one of them wrote it up as
a HUNG shard 9 that it had never run. "A shard I started stopped answering" and
"I refused to start because the box is full" are opposites to whoever reads the
exit code: the first is a tree to investigate, the second is a tick to re-run
later. 3 is now the refusal, and nothing else returns it.

**Why this file exists.** `flutter test` runs all 201 files in one process with
no deadline, so a whole-suite deadlock cannot be interrupted and cannot be
diagnosed. On 30 Sep a full run stopped at 251 tests and sat at 0.0% CPU with
every thread in `epoll_wait` and zero sockets — not slow, dead — and burned
~45 minutes of a 10-minute tick before anything noticed. The reporter's last
line was buffered mid-test-name, so the file could not be named from the
output either. Bisecting all 201 files one at a time found nothing: the hang is
an interaction between files, which is exactly what a single process produces
and exactly what a deadline can catch.

So this buys two things, and only two:

  * a **bound** — a stall costs the deadline, not the box, and the exit code
    says HUNG (2) rather than leaving a red build to be misread;
  * a **name** — the reporter tail is drained continuously and kept, so the
    file in flight when the deadline fired is printed instead of being lost to
    a half-written line. `culprit()` pulls it out of the tail.

**Why it shards.** The deadline above bounds a stall but does nothing for the
other way a run dies. On 3 Oct the 35th tick's full suite died at +1792 of 2121
with `Bad state: Cannot close sink while adding stream` from Flutter's own
`flutter_platform.dart`, at 182 MB free of 7.9 GB with no swap — the harness
lost a race with the memory floor, not an assertion. That left a truncated run
whose last line looks exactly like a suite result, so the tick had to re-run
the remaining 38 files by hand to find out whether the tree was green.

Sharding fixes the cause and the symptom together: each batch is its own
`flutter test` process, so memory is returned to the kernel between batches
instead of accumulating across 246 files, and a batch that still dies is
retried **inside its own shard** rather than ending the run. Shards are
**contiguous**, not round-robin: the 30 Sep hang is an interaction between
files, and spreading related files across batches is how a batch runner hides
the very thing it is meant to expose.

**The rule this file must never break.** A grand total is printed **only when
every shard is green**. If any shard fails, hangs, or never got its turn
because the deadline ran out, the summary says INCOMPLETE and names the shards —
because "+1792 of ~2121" read as a suite result is the exact failure this
exists to prevent. A partial run that looks complete is worse than a red one.

**What this does not do.** It does not find the 30 Sep deadlock; the bisect
already showed no single file owns it. It does not change what the suite
asserts, and it is not faster — each shard pays a fresh `flutter test` warm-up.
It makes a stall and a starved box legible and finite, and it turns evidence
that used to need two runs stitched by hand into one number.

The gate runs first. A second suite on this 7.8 GB no-swap box is the failure
this loop already has scars for, and a deadline does not make it cheaper.
"""

from __future__ import annotations

import argparse
import os
import re
import signal
import subprocess
import sys
import threading
import time
from collections import deque

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
#: Overridable so the test can point the runner at a stub that hangs. The
#: default is the real SDK on this host; the loop never sets the var.
FLUTTER = os.environ.get(
    "RUN_TESTS_FLUTTER", "/home/hatch/tools/sdk/flutter/bin/flutter")
#: Overridable for the same reason as FLUTTER: the gate is itself a behaviour
#: worth testing, and a test cannot be run by the tool it tests unless the
#: tool's dependencies can be pointed at stubs.
GATE = os.environ.get("RUN_TESTS_GATE",
                       os.path.join(REPO, "tool", "build_gate.py"))

#: A green full run is 13:13 on this box, in one process. Sharding pays a
#: `flutter test` warm-up per batch (~10-20s measured), so the global deadline
#: must NOT be cut to the old single-process number: every batch of warm-up is
#: real time, and a deadline that fires on the box being merely loaded — which
#: on 7.8 GB with no swap is the normal case, not an edge — reports INCOMPLETE
#: on a tree that is actually green.
#:
#: **It is DERIVED from the shard plan now, and that is the fix.** This was a
#: hand-picked `1800.0`, which is a number that decays every time a test file
#: is added and nothing notices. The plan it has to cover grew from 246 files /
#: 12 batches to 262 files / 11 batches, and the worst case the runner permits
#: is `n_shards x SHARD_DEADLINE x (1 + RETRIES)` = 11 x 300 x 2 = **6600s**,
#: so the global bound could SIGTERM a shard that had not come close to
#: exhausting *its own* cap. Three ticks in a row died exactly there — shard 6,
#: then 9, then 8 at `deadline 1s` — all three of which pass when run
#: properly, all three ending in `Bad state: Cannot close sink while adding
#: stream`, the signature of a killed `flutter_tester` rather than of a defect.
#: A bound that fires on the plan it is supposed to bound measures the bound,
#: not the tree.
#:
#: So the deadline is now a function of the plan rather than a constant beside
#: it. Measured clean cost is ~3.5 min/shard, so the floor is deliberately set
#: well *above* what a green run needs: the deadline's job is to catch a
#: deadlock, not to race a healthy suite, and on a loaded box the only safe
#: error is the late one.
#:
#: Files per batch. 246 files at ~13 min single-process is ~3.2s/file, so 24
#: files is ~80s of work against a ~15s warm-up: the overhead is ~18%, and the
#: resident set per process is bounded by a batch instead of by the suite.
SHARD_SIZE = 24

#: Cap on one batch. A shard that has not finished in this long is deadlocked
#: or starved, and the smaller-scope retry is the only thing left to try.
SHARD_DEADLINE = 300.0

#: One retry per shard. Two would double the worst case for a box whose
#: problem is memory, where the second attempt usually loses the same race.
RETRIES = 1

#: Slack per batch for the `flutter test` warm-up and the plan's own rounding.
#: Measured ~10-20s, and the `min()` below means a batch can never spend it all:
#: the warm-up is charged to the budget, never added on top of the cap.
SHARD_WARMUP = 20.0

#: Grace the watchdog gives a suite after SIGTERM before escalating to SIGKILL.
#: Short on purpose: the suite it reaps is, by the time the watchdog fires,
#: already dead or unwanted, and every second it holds on is a second this
#: loop's next gate is BUSY. Mirrors the grace in `_kill_group`.
WATCHDOG_GRACE = 5.0


def default_deadline(n_shards, shard_deadline=SHARD_DEADLINE, retries=RETRIES):
    """Whole-run budget for `n_shards` batches, or None when unbounded.

    Derived because a constant cannot stay right. Two things have to be true at
    once for this number to be usable:

      * it must cover every batch the runner is *allowed* to spend, which is
        `n x shard_deadline x (1 + retries)` — otherwise the global clock kills
        a shard that never broke its own cap, and the run reads INCOMPLETE on a
        green tree; and
      * it must not be so large that a real deadlock costs the whole tick.

    Taking the plan's own worst case is the only value that satisfies the
    first without a human re-tuning it every time the suite grows, and the
    per-shard cap (`SHARD_DEADLINE`) is what keeps the second honest: the
    worst case is bounded per shard *and* the deadline stops handing budget to
    a shard that has already overrun it.

    Returns None when the plan is a single unbounded batch (`n_shards < 2`),
    which is exactly the pre-sharding case: one process, and the caller's own
    `--deadline` is the whole answer.
    """
    if n_shards < 2:
        return None
    return n_shards * shard_deadline * (1 + retries) + n_shards * SHARD_WARMUP


#: Lines kept for the post-mortem. Enough to name the file, bounded so a
#: 1715-test run cannot exhaust memory on a box that has none spare.
TAIL_LINES = 400

#: Reporter lines printed per shard, so a green summary stays legible: a
#: 12-shard run prints 3 lines each instead of 12 x 400.
GREEN_TAIL_LINES = 3
#: What a red shard gets — enough to see the failure, bounded like TAIL_LINES.
BAD_TAIL_LINES = 40

PASS, FAIL, HUNG = 0, 1, 2
#: **Refused to start** — the build gate said no, so zero tests ran. This is
#: deliberately NOT 2: "a shard I started stopped answering" and "I would not
#: begin" are opposite facts, and a tick that reads 2 as a hang hunts a stall
#: that never existed. 9 Oct, bare run: BUSY printed, exit 2, and the write-up
#: described a HUNG shard. Three, because 0/1/2 are taken and this is a refusal
#: rather than a verdict on the tree.
BUSY = 3

_TEST_PATH = re.compile(r"(test/\S*?\.dart)")
#: The expanded reporter's progress line: `00:04 +25: All tests passed!`.
#: The count is monotonic within a run, so the last match in the tail is the
#: shard's total. Shards are counted independently and summed, which is only
#: sound because a shard's own count comes from its own process.
#: **The optional ` -N` group is the fix, and it recovers a number this file was
#: throwing away.** When a shard fails, the expanded reporter stops printing the
#: clean `+NNN:` form and prints `+169 -6:` instead — and `\+(\d+):` cannot match
#: that, because a colon never follows the pass count on a red line. So
#: `passed_count` returned None for **every red shard**: the one run the loop most
#: needs a number from was the only one that could not produce one. Two visible
#: consequences, both paid for on 4 Oct: the summary line crashed on the `"?"`
#: fallback (see the `%s` note below) and a failing shard reported no size at
#: all. `+169 -6:` now yields 169, which is the count that actually ran.
#: The expanded reporter's progress line, as the reporter actually builds it.
#:
#: `test_core/lib/src/runner/reporter/compact.dart::_progressLine` writes, in
#: this exact order: `\r` + `MM:SS` + ` ` + `+` + passed, then -- each
#: **optionally**, only when non-empty -- ` ~` + skipped and ` -` + failed,
#: then `:` and the message. Captured from this box on 8 Oct rather than
#: assumed, because the order is a property of the reporter and the whole
#: defect below is about a shape that was never looked at:
#:
#:     00:00 +3: All tests passed!            (green, nothing skipped)
#:     00:00 +2 ~3: All tests passed!         (green, 3 skipped)
#:     00:00 +3 -1: Some tests failed.        (red, nothing skipped)
#:     00:00 +2 ~1 -1: Some tests failed.     (red, both)
#:
#: **The skip group is the fix, and it is the group this file was missing.**
#: The previous pattern taught the regex the *failure* form (` -N`), which is
#: the one run the loop most needs a number from, and left the skip form
#: (` ~N`) unreadable -- because the optional group covered only ` -N`.
#: Measured here, on the two captured shapes:
#:
#:     '+2 ~3: All tests passed!'  -> None
#:     '+3 -1: Some tests failed.' -> 3
#:
#: Two things were wrong with that, and the second is the worse one. The
#: backlog recorded the symptom as `0`/`None` per shard; what the function
#: actually returns is the last progress line written **before** the first
#: skip -- a partial, plausible-looking count. A 5-test file reported 1.
#: A shard whose skips begin early returns `None`; a shard whose skips begin
#: late returns a number that is confidently wrong. A gate that reads a
#: confident number is harder to distrust than one that reads a zero.
#:
#: All three groups are captured, not just skipped, because the runner
#: reports a shard that ran tests regardless of how they came out, and a
#: number that silently dropped the failures would under-report a red shard
#: by exactly the number the loop most needs to see.
_PROGRESS = re.compile(r"\+(\d+)(?: ~(\d+))?(?: -(\d+))?:")


def culprit(tail):
    """The last test file named in the reporter tail, or None.

    The expanded reporter prefixes every line with the file, and marks the one
    in flight with `loading <path>` and failures with a trailing `[E]`, so the
    path is recoverable from a line that was cut off mid-name.
    """
    for line in reversed(tail):
        m = _TEST_PATH.search(line)
        if m:
            return m.group(1)
    return None


def progress_counts(tail):
    """The last progress line's `(passed, skipped, failed)`, or None.

    The counts are monotonic within a run, so the last line the reporter wrote
    is the shard's own tally -- on any of the four real shapes above.

    None means the reporter never wrote a progress line this reader could
    parse, which is kept distinct from `(0, 0, 0)`: a shard whose count cannot
    be read must not contribute a silent 0 to a total that is about to be
    presented as the suite's number.
    """
    best = None
    for line in tail:
        m = _PROGRESS.search(line)
        if m:
            best = (int(m.group(1)),
                    int(m.group(2) or 0),
                    int(m.group(3) or 0))
    return best


def passed_count(tail):
    """The shard's own **passed** count, or None if the reporter wrote none."""
    counts = progress_counts(tail)
    return None if counts is None else counts[0]


def ran_count(tail):
    """Every test the shard accounted for: passed + skipped + failed.

    This is the number the suite summary is built from, and it is deliberately
    not `passed_count`. A shard that lost 163 tests and a shard that ran
    nothing are both invisible to a passed-only total once skips and failures
    are dropped: the first reports fewer passes, the second reports zero, and
    a suite total cannot tell "smaller" from "did not run". Summing what each
    shard *ran* is the only figure that falls when guards stop running.
    """
    counts = progress_counts(tail)
    return None if counts is None else sum(counts)


def discover_tests(root=REPO):
    """Every `*_test.dart` under `test/`, sorted, as repo-relative paths.

    Sorted so the shard plan is the same on every tick: a run that is
    reproducible only sometimes is the bug, not the thing being fixed.
    """
    tests = os.path.join(root, "test")
    found = []
    for dirpath, _dirs, names in os.walk(tests):
        for name in names:
            if name.endswith("_test.dart"):
                found.append(
                    os.path.relpath(os.path.join(dirpath, name), root))
    return sorted(found)


def plan_shards(files, size):
    """Split `files` into contiguous batches of at most `size`.

    Contiguous, deliberately. A round-robin split would put every batch in a
    similar position in the alphabet, which is how a batch runner ends up
    reporting green while never once running two interacting files together.
    """
    files = list(files)
    if size <= 0 or len(files) <= size:
        return [files] if files else []
    return [files[i:i + size] for i in range(0, len(files), size)]


def _kill_group(proc, grace=5.0):
    """Kill the child *and everything it started*.

    `start_new_session=True` gives the child its own process group, so a hung
    test that spawned a helper takes the helper with it. Killing only the
    leader is how a `flutter_tester` ends up orphaned at PPID 1 burning
    ~170 MB of a box with no swap — the leak `tool/build_gate.py` already has
    to special-case.
    """
    try:
        pgid = os.getpgid(proc.pid)
    except (ProcessLookupError, PermissionError):
        pgid = None
    if pgid is not None:
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(pgid, sig)
            except (ProcessLookupError, PermissionError):
                break
            if sig is signal.SIGTERM:
                end = time.monotonic() + grace
                while time.monotonic() < end and proc.poll() is None:
                    time.sleep(0.1)
                if proc.poll() is not None:
                    break
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def _watchdog(pgid):
    """Tear down `pgid` as soon as the runner stops holding the pipe open.

    This is the arm for the one death `_kill_group` cannot cover. `_kill_group`
    runs on the runner's own deadline and on a shard that fails — both of which
    require the runner to be alive to call it. When the runner is killed from
    *outside* (the agent harness kills a foreground command that overruns, or
    the box OOM-kills it) every child it made is reparented to init and keeps
    running, and the engine is the part that costs: `flutter_tester` at ~170 MB
    on a 7.8 GB no-swap box. `build_gate.py` can then only answer BUSY forever,
    so every later tick skips its gate. That happened for real on 5 Oct: pid
    21434 sat at PPID 1 in process group 21236 after the 68th's suite was cut at
    shard 47/66, and the 69th could not run a single build.

    **`prctl(PR_SET_PDEATHSIG)` is the obvious fix and it does not work here.**
    It signals the *direct child* only. The process that leaks is a
    *grandchild* — `flutter_tester`, spawned by `flutter test` — so killing
    `flutter test` would orphan the engine anyway, reproducing the bug in a new
    shape. The signal has to reach the group, and the only thing that knows to
    send it is a process that outlives the runner.

    So the runner hands this one job to a second process and watches a pipe. The
    runner holds the write end; the watchdog holds the read end. When the runner
    dies for *any* reason — SIGTERM, SIGKILL, OOM — the kernel closes the write
    end because the runner was the last holder, the watchdog's `read` returns
    EOF, and it kills the group. No polling, no timer, no dependence on the
    runner being alive to notice anything.

    stdin is that pipe, so this doubles as the argv the gate inspects: it is
    launched with a bare pid and carries no flutter path, because a watchdog
    whose command line contained `bin/flutter` would read as a live tool to
    `build_gate.py` and make the box look BUSY after the run was over.
    """
    try:
        while os.read(0, 4096):
            pass
    except (OSError, ValueError):
        pass
    try:
        pgid = int(pgid)
    except (TypeError, ValueError):
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pgid, sig)
        except (ProcessLookupError, PermissionError, OSError):
            return
        # SIGTERM gets a short grace so a healthy engine can exit on its own;
        # SIGKILL is the floor that guarantees the memory comes back.
        end = time.monotonic() + WATCHDOG_GRACE
        while time.monotonic() < end:
            try:
                os.killpg(pgid, 0)
            except (ProcessLookupError, OSError):
                return
            time.sleep(0.05)


def _spawn_watchdog(pgid):
    """Start `_watchdog` on `pgid`. Returns (write_end, process).

    The caller must keep `write_end` open for the whole run and close it when
    the suite is done: closing it is how a *clean* run tells the watchdog to
    clean up after itself. If the watchdog cannot be started the run still
    proceeds — a missing safety net is not a reason to refuse to test.
    """
    try:
        read_fd, write_fd = os.pipe()
    except OSError:
        return None, None
    try:
        proc = subprocess.Popen(
            [sys.executable, os.path.abspath(__file__),
             "--watchdog-pgid", str(pgid)],
            stdin=read_fd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=REPO,
            # Its own session, so the watchdog is not in the runner's process
            # group. A group-wide SIGTERM at the runner — which is how a shell
            # kills an overrunning foreground job — would otherwise take the
            # reaper down with the thing it exists to reap, and the suite would
            # be orphaned exactly as before.
            start_new_session=True,
        )
    except (OSError, ValueError):
        os.close(read_fd)
        os.close(write_fd)
        return None, None
    os.close(read_fd)
    return write_fd, proc


def run(argv, deadline, cwd=REPO, tail_limit=TAIL_LINES):
    """Run `argv` to completion or to the deadline. Returns (status, tail, secs)."""
    started = time.monotonic()
    tail = deque(maxlen=tail_limit)
    proc = subprocess.Popen(
        argv,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )

    # `start_new_session=True` above put the suite in its OWN process group,
    # which is why a group-kill aimed at the runner cannot reach it — and why
    # the group to reap is the child's, whose pgid equals its pid. The watchdog
    # holds the group's fate to a pipe the runner keeps open, so this file can
    # now be killed without taking its suite with it.
    write_fd, watchdog = _spawn_watchdog(proc.pid)

    def pump():
        try:
            for line in proc.stdout:
                tail.append(line.rstrip())
        except (ValueError, OSError):
            pass

    reader = threading.Thread(target=pump, daemon=True)
    reader.start()

    def _finish(status):
        """Release the watchdog and report, on every path out of `run`.

        Closing the write end is the clean-run signal: the watchdog sees EOF,
        kills the group (which by then is empty if the suite exited cleanly) and
        exits, so no watchdog is ever left behind either. Leaking *those* would
        hand the next tick a second orphan to trip over.
        """
        if write_fd is not None:
            try:
                os.close(write_fd)
            except OSError:
                pass
        if watchdog is not None:
            try:
                watchdog.wait(timeout=WATCHDOG_GRACE + 1.0)
            except (subprocess.TimeoutExpired, OSError):
                pass
        reader.join(timeout=5)
        return status, list(tail), time.monotonic() - started

    try:
        proc.wait(timeout=deadline)
    except subprocess.TimeoutExpired:
        _kill_group(proc)
        return _finish(HUNG)

    code = proc.returncode or 0
    return _finish(PASS if code == 0 else FAIL)


def _gate_clear():
    r = subprocess.run([sys.executable, GATE, "--quiet"],
                       capture_output=True, text=True, cwd=REPO)
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def _kill_leaked_tester():
    """Report — never kill — testers the deadline could not reap.

    Deliberately read-only. This process did not start them, and `flutter test`
    may still be tearing its own children down; a second SIGKILL here is how a
    concurrent run loses its engine. The gate will report them on the next tick.
    """
    r = subprocess.run(["pgrep", "-a", "flutter_tester"], capture_output=True,
                       text=True)
    if r.stdout.strip():
        print("note: flutter_tester still present after the deadline:\n"
              + r.stdout.strip(), file=sys.stderr)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--deadline", type=float, default=None,
                    help="wall-clock seconds for the WHOLE run; default is "
                         "derived from the shard plan (see default_deadline)")
    ap.add_argument("--shard-size", type=int, default=SHARD_SIZE,
                    help="files per batch; 0 runs the suite in one process")
    ap.add_argument("--shard-deadline", type=float, default=SHARD_DEADLINE,
                    help="seconds before a single batch is killed (default 300)")
    ap.add_argument("--retries", type=int, default=RETRIES,
                    help="retries per failing batch (default 1)")
    ap.add_argument("--reporter", default="expanded",
                    help="flutter test reporter; expanded names the file per line")
    ap.add_argument("rest", nargs=argparse.REMAINDER,
                    help="args after -- are passed to flutter test")
    a = ap.parse_args(argv)

    if a.shard_deadline <= 0:
        ap.error("--shard-deadline must be positive")
    if a.retries < 0:
        ap.error("--retries cannot be negative")
    if a.deadline is not None and a.deadline <= 0:
        ap.error("--deadline must be positive")

    clear, why = _gate_clear()
    if not clear:
        # 9 Oct: this returned HUNG (2), which is the code for "a shard I started
        # stopped answering". Two consecutive ticks read the refusal as a hang.
        # BUSY is its own code; see BUSY above.
        print("BUSY (exit %d) — NOT ONE TEST RAN: not starting a second suite"
              " on this box.\n%s\nThis is not a hang and not a verdict on the"
              " tree: re-run when build_gate.py answers CLEAR."
              % (BUSY, why),
              file=sys.stderr)
        return BUSY

    rest = a.rest[1:] if a.rest and a.rest[0] == "--" else list(a.rest)
    flags = [x for x in rest if x.startswith("-")]
    paths = [x for x in rest if not x.startswith("-")]
    if not paths:
        paths = discover_tests()
    shards = plan_shards(paths, a.shard_size)
    if not shards:
        print("no test files found under test/ — nothing to run.")
        return PASS

    # **The plan exists before the budget is decided.** This is the ordering the
    # old constant got wrong: `DEFAULT_DEADLINE` was read by argparse before a
    # single file had been discovered, so it could not know how many batches it
    # was paying for and decayed silently every time the suite grew. Deriving
    # it here means the bound is a property of the plan, not a guess about it.
    if a.deadline is None:
        derived = default_deadline(len(shards), a.shard_deadline, a.retries)
        if derived is None:
            # A single batch has no plan to multiply, so the budget falls back to
            # the per-batch cap and says *that*, rather than claiming a
            # derivation it did not perform. The log is how a tick tells a
            # derived budget from a fallback one; a note that lies about its own
            # number is worse than no note.
            a.deadline = a.shard_deadline
            budget_note = "single shard, capped at the per-batch deadline"
        else:
            a.deadline = derived
            budget_note = "derived from %d shard(s)" % len(shards)
    else:
        budget_note = "caller-set"

    print("runner: %s" % FLUTTER)
    print("deadline: %.0fs whole run (%s), %.0fs per shard, %d retry/-ies"
          % (a.deadline, budget_note, a.shard_deadline, a.retries))
    print("suite: %d file(s) in %d shard(s)"
          % (len(paths), len(shards)))
    for i, shard in enumerate(shards, 1):
        print("  shard %d/%d: %d file(s) — %s .. %s"
              % (i, len(shards), len(shard), shard[0], shard[-1]))
    sys.stdout.flush()

    global_end = time.monotonic() + a.deadline
    results = []
    not_run = 0

    for i, shard in enumerate(shards, 1):
        remaining = global_end - time.monotonic()
        if remaining <= 0:
            not_run = len(shards) - i + 1
            break

        status, tail, secs, attempts = None, [], 0.0, 0
        while True:
            remaining = global_end - time.monotonic()
            if remaining <= 0:
                break
            attempts += 1
            cmd = ([FLUTTER, "test", "--reporter", a.reporter] + flags + shard)
            print("\n=== shard %d/%d, attempt %d/%d — %d file(s), "
                  "deadline %.0fs ==="
                  % (i, len(shards), attempts, a.retries + 1, len(shard),
                     min(a.shard_deadline, remaining)))
            sys.stdout.flush()
            status, tail, secs = run(cmd, min(a.shard_deadline, remaining))
            if status == PASS or attempts > a.retries:
                break
            if status == HUNG:
                _kill_leaked_tester()
            # **The retry must be announced only if it is actually paid for.**
            # A HUNG attempt spends its shard's whole cap, so on a plan whose
            # remaining budget is smaller than one more attempt -- the single
            # shard case, where the whole-run budget *is* the per-batch cap, or
            # any caller who set --deadline tight -- the loop below exits on
            # `remaining <= 0` without running anything. The message used to be
            # printed unconditionally, one line above that exit, so the log read
            # "retrying inside its own shard" and then the shard summary
            # reported "1 attempt(s)": the runner claimed an attempt it had
            # never made. Two logs in one run contradicted each other, and the
            # one a tick reads to decide whether the suite was retried was the
            # false one. Measured on both shapes before the fix: a 1-shard run
            # at `deadline 3s` and a 2-shard run at `--deadline 3s` each printed
            # the retry line and reported a single attempt. Now the budget is
            # checked first and an unpaid retry is named as what it is.
            if global_end - time.monotonic() <= 0:
                print("--- shard %d/%d failed (%s); no whole-run budget left "
                      "for the retry (%d of %d spent) ---"
                      % (i, len(shards), "HUNG" if status == HUNG else "FAIL",
                         attempts, a.retries + 1))
                sys.stdout.flush()
                break
            print("--- shard %d/%d failed (%s); retrying inside its own shard ---"
                  % (i, len(shards), "HUNG" if status == HUNG else "FAIL"))
            sys.stdout.flush()

        if status is None:
            not_run = len(shards) - i + 1
            break

        if status == PASS:
            for line in tail[-GREEN_TAIL_LINES:]:
                print(line)
        else:
            print("--- shard %d/%d did not pass; last %d reporter lines ---"
                  % (i, len(shards), min(len(tail), BAD_TAIL_LINES)),
                  file=sys.stderr)
            for line in tail[-BAD_TAIL_LINES:]:
                print(line, file=sys.stderr)
            print("----------------------------------------------", file=sys.stderr)
            if status == HUNG:
                print("culprit (last file named by the reporter): %s"
                      % (culprit(tail) or "UNKNOWN"), file=sys.stderr)
                _kill_leaked_tester()

        # **The count is `%s`, not `%d`, and that is the fix.** The fallback is
        # the string "?" and a failing shard is the *only* common way to get it:
        # `passed_count` reads the reporter's progress lines, and a shard that
        # dies mid-file ends on a `+169 -6:` line the regex does not match, so
        # the shard the loop most needs a number for is the one that returns
        # None. `%d` then raised `TypeError: %d format: a real number is
        # required, not str` — inside the per-shard print, so the run died
        # *before* writing `results.append`, before the totals, and before the
        # final verdict: six red tests, and all the runner said was a Python
        # traceback. A gate whose failure mode is "lose the evidence" cannot be
        # the thing that reports the evidence, and it cost this tick a second
        # 13-minute run to re-establish that the suite was red.
        count = passed_count(tail)
        print("shard %d/%d: %s in %d:%02d (%d attempt(s), %s test(s))"
              % (i, len(shards), {0: "PASS", 1: "FAIL", 2: "HUNG"}[status],
                 int(secs // 60), int(secs % 60), attempts,
                 count if count is not None else "?"))
        sys.stdout.flush()
        results.append({"shard": i, "status": status, "tail": tail,
                        "secs": secs, "attempts": attempts,
                        "count": passed_count(tail), "ran": ran_count(tail),
                        "skipped": (progress_counts(tail) or (0, 0, 0))[1],
                        "files": len(shard)})

    total_secs = sum(r["secs"] for r in results)
    green = [r for r in results if r["status"] == PASS]
    bad = [r for r in results if r["status"] != PASS]

    print("\n" + "=" * 62)
    print("shards: %d run, %d green, %d not green, %d never started"
          % (len(results), len(green), len(bad), not_run))
    print("elapsed: %d:%02d" % (int(total_secs // 60), int(total_secs % 60)))
    print("=" * 62)

    if not_run or bad:
        # The whole point of this file. No grand total is printed here, because
        # a total over a partial run is the one number that reads exactly like
        # a suite result — which is how the 35th tick's "+1792" became an open
        # question instead of an answer.
        if not_run:
            print("\nINCOMPLETE — %d shard(s) never started: the %.0fs deadline "
                  "ran out." % (not_run, a.deadline), file=sys.stderr)
        for r in bad:
            print("shard %d not green: %s after %d attempt(s), %d file(s)"
                  % (r["shard"], {1: "FAIL", 2: "HUNG"}[r["status"]],
                     r["attempts"], r["files"]), file=sys.stderr)
        print("\nThis is NOT a suite result. The tree is unverified: fix the "
              "shard(s) above, or re-run with a larger --deadline.",
              file=sys.stderr)
        return HUNG if (not_run or any(r["status"] == HUNG for r in bad)) else FAIL

    counts = [r["count"] for r in green]
    ran = [r["ran"] for r in green]
    if all(c is not None for c in counts) and all(v is not None for v in ran):
        # The total is what the shards RAN, and the split is printed whenever
        # anything was skipped -- so the number can never be read as "every
        # test in here passed" when it did not. This is the line the loop
        # gates on, and it is the line that used to omit whole shards.
        skipped = sum(r["skipped"] for r in green)
        print("\nSUITE PASS — %d tests across %d shard(s), every shard green."
              % (sum(ran), len(green)))
        if skipped:
            print("  %d passed, %d skipped (skipped tests are inside the "
                  "total and are not claimed as passing)." % (sum(counts), skipped))
    else:
        print("\nSUITE PASS — %d shard(s) green, but at least one shard's "
              "reporter wrote no count, so no total is claimed."
              % len(green))
    return PASS


def _watchdog_main(argv):
    """The reaper mode of this file: `_watchdog` on argv's pgid.

    A separate entry point rather than a flag checked deep inside `main`, so
    the watchdog can never be talked into running a suite, and so re-execing
    this file with a pid is the only way to start one.
    """
    if len(argv) != 2 or argv[0] != "--watchdog-pgid":
        print("usage: run_tests.py --watchdog-pgid PGID", file=sys.stderr)
        return 2
    _watchdog(argv[1])
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--watchdog-pgid":
        sys.exit(_watchdog_main(sys.argv[1:]))
    sys.exit(main())
