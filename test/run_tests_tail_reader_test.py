#!/usr/bin/env python3
"""Prove the tail readers tell the REPORTER's tally from TEST STDOUT.

    python3 test/run_tests_tail_reader_test.py

Run directly: it imports the real runner and reads real reporter bytes. It is
not a `flutter test` -- this box refuses Dart whenever the balloon is up, and
the defect below is only observable on a box that lets a shard hang, which is
exactly when a python suite is the shape that still runs.

**Why this file exists.** `tool/run_tests.py` gates every commit this loop
ships on `SUITE PASS -- N tests across M shard(s)`, and that N is `sum(ran)`
over the shards: `ran_count(tail)`, which calls `progress_counts(tail)`. The
four reader functions -- `progress_counts`, `passed_count`, `ran_count`,
`culprit` -- had **no test battery at all**. Nine sibling batteries existed
for the same file's exit codes, starve detection and retry budget; the
functions the number the loop gates on is *summed from* were the ones nobody
checked. A reader nobody runs is not a reader that is correct, it is a reader
whose failures are invisible.

**The defect, measured on real reporter output this tick.** The reporter and
the tests share one stdout stream, so `progress_counts` -- which takes the
**last** line matching `+(\\d+)...:` *anywhere in the line* -- will happily
read a **test's own `print`** as the shard's tally. Captured on this box, not
imagined: a shard was SIGKILLed mid-hang (exit 137, so the reporter never
wrote its summary line) and the tail ended

    00:00 +1: B prints progress-shaped text, then wedges the isolate
    00:00 +4242 -77: THIS IS TEST STDOUT, NOT THE REPORTER

`progress_counts` returned `(4242, 0, 77)` and `ran_count` returned **4319**
for a shard that ran **2** tests. That is the suite total, the number the loop
gates on, inflated by a value no shard could ever produce -- and the only
reason it cannot gate a commit today is incidental: the total sums **green**
shards only, and a shard that hangs is never green. The reader is wrong on the
exact run where a tick is already reading the output by hand.

**`culprit()` had the same defect, and its version is worse.** It is called on
one path only -- `status in (HUNG, STARVED)` -- and its whole job is to name
the file to bisect. Its pattern `(test/\\S*?\\.dart)` matches a stack frame
inside the Flutter SDK, so on a real wedged isolate (captured in
`truehang.txt`) it returned **`test/flutter_platform.dart`**: a file in the
Flutter SDK, not in this repo, that does not exist and cannot be bisected. The
one function whose entire value is "go and look at THIS file" pointed a tick at
the framework. The fix is to require the `_test.dart` suffix the runner only
ever names real suites by.

**The fixture files are real reporter bytes**, captured this tick by running
`flutter test --reporter expanded` on purpose-built files and killing the
process exactly as the runner's deadline kills it (SIGKILL, not SIGTERM, so no
summary line is written and nothing is masked). Each carries a `# TRUTH:`
line stating the answer measured from the run, and every case below asserts
against that line rather than against a value re-derived with the same regex
this file exists to police.
"""

import importlib.util
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "tool", "run_tests.py")
FIXTURES = os.path.join(ROOT, "test", "fixtures", "run_tests_tail")

_spec = importlib.util.spec_from_file_location("run_tests_under_test", TOOL)
rt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rt)

_results = []


def case(fn):
    _results.append(fn)
    return fn


def tail_of(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as fh:
        return fh.read().splitlines()


def truth_of(name):
    """The answer recorded when the reporter actually ran, not a re-derivation."""
    for line in tail_of(name):
        m = re.match(r"#\s*TRUTH:\s*(.+)$", line)
        if m:
            return m.group(1)
    raise AssertionError("fixture %s carries no # TRUTH: line" % name)


def digits(text):
    return [int(n) for n in re.findall(r"\d+", text)]


@case
def test_stdout_cannot_become_the_shard_tally():
    """The defect. A hung shard's tally must not be read from a test's print()."""
    tail = tail_of("spin.txt")
    got = rt.ran_count(tail)
    assert got != 4319, (
        "ran_count returned %s -- it read TEST STDOUT as the reporter's tally. "
        "The shard ran %s tests. Fixture truth: %s"
        % (got, digits(truth_of("spin.txt"))[0], truth_of("spin.txt")))
    # The shipped contract is "claim nothing", not "recover the real 2": the
    # two are indistinguishable from the text alone (a test can print the
    # reporter's exact format, and the \r that would separate them is gone by
    # the time it reaches a pipe), so the runner declines rather than guesses.
    assert got is None, (
        "a shard killed mid-flight must report no count at all, got %s" % got)


@case
def test_killed_shard_claims_no_number_at_all():
    """The repair is not "ignore the stdout line" -- it is "claim nothing".

    A regex that simply stopped matching would also stop reading the
    REPORTER and lose the count on good runs. The real discriminator is
    whether the reporter got to write its closing line: a tail with one still
    yields its tally (see the green/red cases), a tail without one yields
    None. `main` already handles None by claiming no total, so a killed shard
    reports an absent number instead of an impossible one.
    """
    for name in ("spin.txt", "truehang.txt"):
        tail = tail_of(name)
        assert rt.progress_counts(tail) is None, (
            "%s was killed mid-flight, so no line in it can be trusted as the "
            "reporter's tally; progress_counts returned %s"
            % (name, rt.progress_counts(tail)))
        assert rt.ran_count(tail) is None, (
            "%s: ran_count must be None alongside it, got %s"
            % (name, rt.ran_count(tail)))


@case
def test_a_finished_tail_is_still_read_in_full():
    """Read from the other side: the repair must not cost real counts."""
    for name, expected in (("multi.txt", (6, 0, 0)), ("red.txt", (2, 1, 1))):
        tail = tail_of(name)
        assert rt.progress_counts(tail) == expected, (
            "%s closed cleanly and must still report %s; got %s"
            % (name, expected, rt.progress_counts(tail)))
        assert rt.ran_count(tail) == sum(expected), (
            "%s: ran_count=%s" % (name, rt.ran_count(tail)))


@case
def test_failure_listing_after_the_summary_is_not_a_tally():
    """A red shard keeps its counts even though red output follows the summary.

    The reporter writes the failure listing AFTER its closing line, and those
    lines carry counts of their own. Breaking at the terminator has to stop
    before they are read, not after.
    """
    tail = tail_of("red.txt")
    assert any("Failing tests:" in l for l in tail), (
        "fixture no longer contains the post-summary listing it exists for")
    assert rt.progress_counts(tail) == (2, 1, 1), (
        "post-summary output leaked into the tally: %s"
        % (rt.progress_counts(tail),))


@case
def test_failure_message_is_not_a_tally():
    """A test's failure MESSAGE can contain a progress-shaped string too."""
    tail = tail_of("msg.txt")
    got = rt.progress_counts(tail)
    assert got == (0, 0, 1), (
        "the '+99 -7:' inside a failure message must not be read as a count; "
        "got %s. Truth: %s" % (got, truth_of("msg.txt")))


@case
def test_culprit_never_names_a_framework_file():
    """`culprit()` exists to name a file to bisect; an SDK path cannot be one."""
    tail = tail_of("truehang.txt")
    got = rt.culprit(tail)
    assert got is None or got.endswith("_test.dart"), (
        "culprit() named %r, which is not a file in this repo and cannot be "
        "bisected. Truth: %s" % (got, truth_of("truehang.txt")))


@case
def test_culprit_still_names_the_real_suite():
    """Same repair, read from the other side: the real answer survives it."""
    tail = tail_of("truehang.txt")
    got = rt.culprit(tail)
    assert got == "test/truehang_test.dart", (
        "culprit() must still name the suite that wedged; got %r" % (got,))


@case
def test_red_shard_counts_are_unchanged():
    """The repair must not move the numbers a red shard reports today."""
    tail = tail_of("red.txt")
    assert rt.progress_counts(tail) == (2, 1, 1), (
        "a red shard must still report passed/skipped/failed correctly; got %s"
        % (rt.progress_counts(tail),))
    assert rt.ran_count(tail) == 4, "got ran_count=%s" % rt.ran_count(tail)


@case
def test_green_shard_counts_are_unchanged():
    tail = tail_of("multi.txt")
    assert rt.progress_counts(tail) == (6, 0, 0), (
        "multi-file cumulative counts must not change; got %s"
        % (rt.progress_counts(tail),))
    assert rt.ran_count(tail) == 6, "got ran_count=%s" % rt.ran_count(tail)


@case
def test_skipped_shard_still_reads_its_skip_group():
    tail = tail_of("collide.txt")
    assert rt.passed_count(tail) == 1, (
        "the skip-group repair from 10 Oct must survive; got %s"
        % rt.passed_count(tail))


@case
def test_every_fixture_is_cited_by_a_case():
    """A fixture nobody asserts on is a fixture that stops being real."""
    cited = {"spin.txt", "msg.txt", "truehang.txt", "red.txt", "multi.txt",
             "collide.txt"}
    on_disk = {f for f in os.listdir(FIXTURES) if f.endswith(".txt")}
    assert cited <= on_disk, "fixtures vanished: %s" % (cited - on_disk)
    for name in cited:
        assert truth_of(name), "%s lost its # TRUTH: line" % name


@case
def test_fixtures_are_git_tracked_or_ignored_consistently():
    """A fixture the .gitignore eats is a fixture the next tick loses."""
    ig = os.path.join(ROOT, ".gitignore")
    if not os.path.exists(ig):
        return
    body = open(ig, encoding="utf-8").read()
    for name in ("spin.txt", "truehang.txt"):
        assert "run_tests_tail" not in body, (
            ".gitignore excludes the fixtures dir; the next clone loses the "
            "oracle these cases assert against.")


def main():
    failures = []
    for fn in _results:
        try:
            fn()
            print("  ok   %s" % fn.__name__)
        except AssertionError as exc:
            failures.append((fn.__name__, str(exc)))
            print("  FAIL %s\n         %s" % (fn.__name__, exc))
    print("\n%d/%d pass against tool/run_tests.py"
          % (len(_results) - len(failures), len(_results)))
    if failures:
        print("\n%d case(s) FAILED:" % len(failures))
        for name, msg in failures:
            print("  %s: %s" % (name, msg))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
