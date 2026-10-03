#!/usr/bin/env python3
"""Run the test suite in shards, under a wall-clock deadline, and report ONE number.

    python3 tool/run_tests.py                        # whole suite, sharded
    python3 tool/run_tests.py --deadline 120         # tighter global bound
    python3 tool/run_tests.py --shard-size 0         # disable sharding (one run)
    python3 tool/run_tests.py -- test/a_test.dart    # extra args go to flutter test

Exit codes: 0 pass, 1 fail, 2 hung/incomplete (the deadline fired).

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
#: is deliberately NOT cut to the old single-process number: 12 batches of
#: warm-up is real time, and a deadline that fires on the box being merely
#: loaded — which on 7.8 GB with no swap is the normal case, not an edge —
#: would report INCOMPLETE on a tree that is actually green.
DEFAULT_DEADLINE = 1800.0

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

#: Lines kept for the post-mortem. Enough to name the file, bounded so a
#: 1715-test run cannot exhaust memory on a box that has none spare.
TAIL_LINES = 400

#: Reporter lines printed per shard, so a green summary stays legible: a
#: 12-shard run prints 3 lines each instead of 12 x 400.
GREEN_TAIL_LINES = 3
#: What a red shard gets — enough to see the failure, bounded like TAIL_LINES.
BAD_TAIL_LINES = 40

PASS, FAIL, HUNG = 0, 1, 2

_TEST_PATH = re.compile(r"(test/\S*?\.dart)")
#: The expanded reporter's progress line: `00:04 +25: All tests passed!`.
#: The count is monotonic within a run, so the last match in the tail is the
#: shard's total. Shards are counted independently and summed, which is only
#: sound because a shard's own count comes from its own process.
_PROGRESS = re.compile(r"\+(\d+):")


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


def passed_count(tail):
    """The shard's own test count, or None if the reporter never wrote one.

    None is kept distinct from 0 on purpose: a green shard whose count cannot
    be read must not contribute a silent 0 to a total that is about to be
    presented as the suite's number.
    """
    best = None
    for line in tail:
        m = _PROGRESS.search(line)
        if m:
            best = int(m.group(1))
    return best


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

    def pump():
        try:
            for line in proc.stdout:
                tail.append(line.rstrip())
        except (ValueError, OSError):
            pass

    reader = threading.Thread(target=pump, daemon=True)
    reader.start()

    try:
        proc.wait(timeout=deadline)
    except subprocess.TimeoutExpired:
        _kill_group(proc)
        reader.join(timeout=5)
        return HUNG, list(tail), time.monotonic() - started

    reader.join(timeout=5)
    code = proc.returncode or 0
    return (PASS if code == 0 else FAIL), list(tail), time.monotonic() - started


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
    ap.add_argument("--deadline", type=float, default=DEFAULT_DEADLINE,
                    help="wall-clock seconds for the WHOLE run (default 1800)")
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

    if a.deadline <= 0:
        ap.error("--deadline must be positive")
    if a.shard_deadline <= 0:
        ap.error("--shard-deadline must be positive")
    if a.retries < 0:
        ap.error("--retries cannot be negative")

    clear, why = _gate_clear()
    if not clear:
        print("BUSY — not starting a second suite on this box.\n" + why,
              file=sys.stderr)
        return HUNG

    rest = a.rest[1:] if a.rest and a.rest[0] == "--" else list(a.rest)
    flags = [x for x in rest if x.startswith("-")]
    paths = [x for x in rest if not x.startswith("-")]
    if not paths:
        paths = discover_tests()
    shards = plan_shards(paths, a.shard_size)
    if not shards:
        print("no test files found under test/ — nothing to run.")
        return PASS

    print("runner: %s" % FLUTTER)
    print("deadline: %.0fs whole run, %.0fs per shard, %d retry/-ies"
          % (a.deadline, a.shard_deadline, a.retries))
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

        print("shard %d/%d: %s in %d:%02d (%d attempt(s), %d test(s))"
              % (i, len(shards), {0: "PASS", 1: "FAIL", 2: "HUNG"}[status],
                 int(secs // 60), int(secs % 60), attempts,
                 passed_count(tail) if passed_count(tail) is not None else "?"))
        sys.stdout.flush()
        results.append({"shard": i, "status": status, "tail": tail,
                        "secs": secs, "attempts": attempts,
                        "count": passed_count(tail), "files": len(shard)})

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
    if all(c is not None for c in counts):
        print("\nSUITE PASS — %d tests across %d shard(s), every shard green."
              % (sum(counts), len(green)))
    else:
        print("\nSUITE PASS — %d shard(s) green, but at least one shard's "
              "reporter wrote no count, so no total is claimed."
              % len(green))
    return PASS


if __name__ == "__main__":
    sys.exit(main())
