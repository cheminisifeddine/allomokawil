#!/usr/bin/env python3
"""Run the test suite under a wall-clock deadline, and name the file if it hangs.

    python3 tool/run_tests.py                      # whole suite, 20 min deadline
    python3 tool/run_tests.py --deadline 120        # tighter bound
    python3 tool/run_tests.py -- test/a_test.dart  # extra args go to flutter test

Exit codes: 0 pass, 1 fail, 2 hung (the deadline fired).

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

**What this does not do.** It does not find the deadlock; the bisect already
showed no single file owns it. It does not sharding-split the suite, and it
does not change what the suite asserts. It makes a stall legible and finite,
which is the part that was silently eating the loop.

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

#: A green full run is 13:13 on this box. The deadline is ~1.5x that, which is
#: deliberate in both directions: a suite slower than 20 minutes is already
#: broken (green is 11-13 min), and a deadline close to the green time would
#: fire on a merely loaded box and kill a run that was about to pass. This box
#: has 7.8 GB and no swap, so "merely loaded" is the normal case, not an edge.
#: 20 minutes still bounds a stall that used to cost 45 and unbounded after.
DEFAULT_DEADLINE = 1200.0

#: Lines kept for the post-mortem. Enough to name the file, bounded so a
#: 1715-test run cannot exhaust memory on a box that has none spare.
TAIL_LINES = 400

PASS, FAIL, HUNG = 0, 1, 2

_TEST_PATH = re.compile(r"(test/\S*?\.dart)")


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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--deadline", type=float, default=DEFAULT_DEADLINE,
                    help="wall-clock seconds before the suite is killed (default 1200)")
    ap.add_argument("--reporter", default="expanded",
                    help="flutter test reporter; expanded names the file per line")
    ap.add_argument("rest", nargs=argparse.REMAINDER,
                    help="args after -- are passed to flutter test")
    a = ap.parse_args(argv)

    deadline = a.deadline
    if deadline <= 0:
        ap.error("--deadline must be positive")

    clear, why = _gate_clear()
    if not clear:
        print("BUSY — not starting a second suite on this box.\n" + why,
              file=sys.stderr)
        return HUNG

    rest = a.rest[1:] if a.rest and a.rest[0] == "--" else list(a.rest)
    cmd = [FLUTTER, "test", "--reporter", a.reporter] + rest
    print("running: %s" % " ".join(cmd))
    print("deadline: %.0fs" % deadline)
    sys.stdout.flush()

    status, tail, secs = run(cmd, deadline)

    if status == HUNG:
        print("\nHUNG — no result after %.0fs (deadline %.0fs)." % (secs, deadline),
              file=sys.stderr)
        print("culprit (last file named by the reporter): %s"
                  % (culprit(tail) or "UNKNOWN"), file=sys.stderr)
        print("\n--- last %d reporter lines ---" % min(len(tail), 40), file=sys.stderr)
        for line in tail[-40:]:
            print(line, file=sys.stderr)
        print("---------------------------", file=sys.stderr)
        _kill_leaked_tester()
        return HUNG

    for line in tail:
        print(line)
    print("\n%s in %d:%02d" % ({0: "PASS", 1: "FAIL"}[status], int(secs // 60),
                                int(secs % 60)))
    return status


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


if __name__ == "__main__":
    sys.exit(main())
