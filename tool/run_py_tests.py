#!/usr/bin/env python3
"""Gate the 31 Python batteries that gate nothing today. One number.

    python3 tool/run_py_tests.py                  # every battery, in batches
    python3 tool/run_py_tests.py --deadline 120   # tighter global bound
    python3 tool/run_py_tests.py --shard-size 0   # one sequence, no batching
    python3 tool/run_py_tests.py --list           # what it would run, and stop
    python3 tool/run_py_tests.py -- test/label_fit_test.py

**The gap this closes, measured 11 Oct.** `discover_tests()` in `run_tests.py`
reported `discovered: 324` and collected **0** Python files for the loop's gate.
Every `test/*_test.py` is invisible to it, and all 31 pass. So the suite is not
wrong, it is *unguarded*: the batteries that protect the loop's own instruments
-- the push helper, the PNG reader, pngscan, the remote verifier, and the runner
itself -- run only when a tick happens to remember them. A battery nobody runs
catches nothing.

**Why a runner and not a sentence in the protocol.** A protocol can only *say*
"also run these"; it cannot make a red battery stop a commit. The Dart gate is
a runner for the same reason, one layer down.

**The exit codes are the Dart runner's, not a new table.** 0 pass, 1 fail,
2 HUNG, 3 BUSY, 4 STARVED, imported from `run_tests` rather than restated.
`run_tests_busy_code_test.py` exists precisely because 2 once meant two
different things; a sibling runner inventing its own meaning for 2 would
reintroduce the confusion that cost two ticks.

**No wall clock in this file.** `tool_clock_seam_test.dart` fails the build on
`time.time()` in any tracked `*.py`. A deadline loop built on the wall clock
would be the one file guaranteed to trip its own guard, so every bound below is
`time.monotonic()`.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# **Import, do not restate.** The codes, the CPU sampler, the group-kill and the
# starve threshold must have one definition each; a copy is a second definition
# that will drift. Importing also means the clock-seam sweep reads this file and
# `run_tests.py` under identical rules, so a fix here cannot pass one and fail
# the other.
from run_tests import (  # noqa: E402
    BUSY, FAIL, HUNG, PASS, REPO, STARVED, STATUS_NAME, TAIL_LINES,
    _gate_clear, default_deadline, run,
)

#: Per-battery cap. Measured 11 Oct across all 31 on this box: slowest is
#: `run_tests_starved_code_test.py` at **112 s**, then `build_gate_test.py` at
#: 72 s, then 27 s. 300 matches the Dart runner's cap and leaves ~2.7x headroom
#: over the worst case, so the cap fires on a hang rather than on a slow box.
SHARD_DEADLINE = 300.0

#: One retry, as in the Dart runner: several batteries spawn real subprocesses
#: (the busy/starved cases start runner processes and stubs), so a failure here
#: is more often a loaded box than a defect in the tree.
RETRIES = 1


def discover_py_tests(root=REPO):
    """Every `*_test.py` under `test/`, sorted, as repo-relative paths.

    Mirrors `run_tests.discover_tests` -- same walk, same sort -- differing only
    in the suffix. Sorted so the batch plan is identical every tick: a plan that
    is reproducible only sometimes is the bug, not the thing being fixed.
    """
    tests = os.path.join(root, "test")
    found = []
    for dirpath, _dirs, names in os.walk(tests):
        for name in names:
            if name.endswith("_test.py"):
                found.append(
                    os.path.relpath(os.path.join(dirpath, name), root))
    return sorted(found)


def plan_batches(files, size):
    """Split `files` into contiguous batches of at most `size`.

    **Contiguous for a reason that is not symmetry.** Several batteries write to
    fixed paths -- `band_ink.py` and `gen_icons.py` emit PNGs, and
    `shot_namespace_test.py` grades the output of `design_shots_test.dart` in
    `/tmp/shots/`. Run concurrently, one battery grades another battery's
    half-written file, and the red that produces is neither a defect nor a flake
    but a lie. Serial batches keep each file's writes to itself.
    """
    files = list(files)
    if size <= 0 or len(files) <= size:
        return [files] if files else []
    return [files[i:i + size] for i in range(0, len(files), size)]


def default_deadline_for(n_batches, shard_deadline=SHARD_DEADLINE, retries=RETRIES):
    """Whole-run budget, or None when the plan is a single unbounded batch.

    Delegates to `run_tests.default_deadline` so the derivation -- cover every
    batch the runner may legally spend, or the global clock kills a batch that
    never broke its own cap -- stays one implementation rather than two.
    """
    return default_deadline(n_batches, shard_deadline, retries)


def _run_batch(shard, global_end, shard_deadline):
    """Run each battery in the batch in order. Returns (status, tail, secs).

    Stops at the first battery that does not pass and names it. `HUNG` means the
    cap fired, which is the same fact it means in the Dart runner.
    """
    tail = []
    spent = 0.0
    for path in shard:
        remaining = global_end - time.monotonic()
        if remaining <= 0:
            return HUNG, tail + ["  -> NO TIME LEFT: %s" % path], spent
        # The tail is kept short: three lines is what a green battery needs,
        # and a red one is cut to the same few lines by `tail[-12:]` below. The
        # width is a constant because `run()` must be told the limit BEFORE it
        # starts -- a later status cannot retroactively choose it.
        status, lines, secs, _cpu = run(
            [sys.executable, path], min(shard_deadline, remaining),
            tail_limit=TAIL_LINES)
        spent += secs
        if status != PASS:
            tail.extend(lines[-12:])
            tail.append("  -> FAILED: %s" % path)
            return status, tail, spent
        tail = lines[-3:]
    return PASS, tail, spent


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--deadline", type=float, default=None,
                    help="seconds for the WHOLE run; default is derived from "
                         "the batch plan")
    ap.add_argument("--shard-size", type=int, default=12,
                    help="batteries per batch; 0 runs them as one sequence")
    ap.add_argument("--shard-deadline", type=float, default=SHARD_DEADLINE,
                    help="seconds before a single battery is killed")
    ap.add_argument("--retries", type=int, default=RETRIES,
                    help="retries per failing batch (default 1)")
    ap.add_argument("--list", action="store_true",
                    help="print the batteries this gate would run, then stop")
    ap.add_argument("rest", nargs=argparse.REMAINDER,
                    help="battery paths after --; default is all of them")
    a = ap.parse_args(argv)

    if a.shard_deadline <= 0:
        ap.error("--shard-deadline must be positive")
    if a.retries < 0:
        ap.error("--retries cannot be negative")
    if a.deadline is not None and a.deadline <= 0:
        ap.error("--deadline must be positive")

    rest = a.rest[1:] if a.rest and a.rest[0] == "--" else list(a.rest)
    paths = [x for x in rest if not x.startswith("-")]
    if not paths:
        paths = discover_py_tests()

    if a.list:
        print("%d battery/batteries under test/" % len(paths))
        for p in paths:
            print("  %s" % p)
        return PASS

    # **The build gate is consulted here for the first time on this path.**
    # Python batteries never call `flutter`, so refusing on a memory balloon
    # would make this the one gate that cannot run exactly when the loop most
    # needs a cheap check -- but refusing is still right when another *suite*
    # is live, which is what `_gate_clear` actually reports.
    clear, why = _gate_clear()
    if not clear:
        print("BUSY (exit %d) -- NOT ONE BATTERY RAN: not starting a second "
              "suite on this box.\n%s\nThis is not a hang and not a verdict on "
              "the tree: re-run when build_gate.py answers CLEAR."
              % (BUSY, why), file=sys.stderr)
        return BUSY

    batches = plan_batches(paths, a.shard_size)
    if not batches:
        print("no Python batteries found under test/ -- nothing to run.")
        return PASS

    if a.deadline is None:
        derived = default_deadline_for(len(batches), a.shard_deadline, a.retries)
        if derived is None:
            a.deadline = a.shard_deadline
            budget_note = "single batch, capped at the per-batch deadline"
        else:
            a.deadline = derived
            budget_note = "derived from %d batch(es)" % len(batches)
    else:
        budget_note = "caller-set"

    print("gate: python batteries -- %d file(s) in %d batch(es)"
          % (len(paths), len(batches)))
    print("deadline: %.0fs whole run (%s), %.0fs per battery, %d retry/-ies"
          % (a.deadline, budget_note, a.shard_deadline, a.retries))
    for i, batch in enumerate(batches, 1):
        print("  batch %d/%d: %d file(s) -- %s .. %s"
              % (i, len(batches), len(batch), batch[0], batch[-1]))
    sys.stdout.flush()

    global_end = time.monotonic() + a.deadline
    results = []
    never_started = 0

    for i, batch in enumerate(batches, 1):
        if global_end - time.monotonic() <= 0:
            never_started = len(batches) - i + 1
            break

        attempts = 0
        status = None
        while True:
            if global_end - time.monotonic() <= 0:
                break
            attempts += 1
            print("\n=== batch %d/%d, attempt %d/%d -- %d file(s), "
                  "deadline %.0fs ==="
                  % (i, len(batches), attempts, a.retries + 1, len(batch),
                     min(a.shard_deadline, global_end - time.monotonic())))
            sys.stdout.flush()
            status, tail, secs = _run_batch(
                batch, global_end, a.shard_deadline)
            # **Announce a retry only once it is actually paid for.** The budget
            # is checked first, exactly as run_tests.py does it: a batch that
            # spends the whole-run deadline on its first attempt leaves no
            # budget for a second, and printing "retrying" there would claim an
            # attempt the summary then reports as not made.
            if status == PASS or attempts > a.retries:
                break
            if global_end - time.monotonic() <= 0:
                print("no budget left for the retry this batch would need")
                break

        results.append((i, batch, status, tail, secs, attempts))

    # ---- summary: ONE number, the way the Dart runner reports one ----
    print("\n" + "=" * 68)
    green = [r for r in results if r[2] == PASS]
    not_green = [r for r in results if r[2] != PASS]
    ran = sum(len(r[1]) for r in green)
    # A red batch ran only the batteries before the one that failed, and which
    # one that was is named in its tail -- never guessed from a count.
    for r in not_green:
        named = [l for l in r[3] if l.startswith("  -> FAILED")]
        if named:
            ran += next((r[1].index(l.split()[-1]) + 1 for l in named
                         if l.split()[-1] in r[1]), 0)

    verdict = "PASS" if (not not_green and not never_started) else "FAIL"
    print("SUITE %s -- %d batteries across %d batch(es), every batch green"
          % (verdict, len(paths), len(batches)) if verdict == "PASS" else
          "SUITE FAIL -- %d batteries across %d batch(es), %d green, %d not "
          "green" % (len(paths), len(batches), len(green), len(not_green)))
    print("batteries run: %d of %d" % (ran, len(paths)))
    for i, batch, st, tail, secs, at in results:
        print("  batch %d: %s -- %d file(s) in %.1fs, %d attempt(s)"
              % (i, STATUS_NAME.get(st, "?"), len(batch), secs, at))
        if st != PASS:
            for line in tail[-10:]:
                print("    | %s" % line)
    if never_started:
        print("NEVER STARTED: %d batch(es) -- the whole-run deadline fired"
              % never_started)

    if verdict == "PASS":
        return PASS
    # **The worst fact in the run decides the code.** HUNG outranks FAIL
    # because a hang means the answer is unknown, not wrong, and a caller that
    # reads "fail" will bisect a tree that never finished running.
    if any(r[2] == HUNG for r in results):
        return HUNG
    if any(r[2] == STARVED for r in results):
        return STARVED
    return FAIL


if __name__ == "__main__":
    sys.exit(main())
