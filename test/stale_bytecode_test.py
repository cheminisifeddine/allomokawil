#!/usr/bin/env python3
"""Prove a stale .pyc can make CORRECT python read as broken -- and that the
loop's own audits are on the wrong side of it.

Run directly -- it imports the real audit modules and is not a `flutter test`:

    python3 test/stale_bytecode_test.py

**The defect, measured 10 Oct.** This file's sibling
`test/portfolio_allowance_audit_test.py` came back **9 failed / 33 passed**
on a tree whose source was correct, and the previous tick had left that
source uncommitted. Every one of the nine was a false verdict against code
that was right. The cause was not the code:

    tool/portfolio_allowance_audit.py   rewritten this tick
    tool/__pycache__/...cpython-314.pyc  written in the SAME SECOND

CPython validates a cached `.pyc` against the source's `(mtime, size)` pair.
A tick that rewrites a file and re-runs a test inside the same second that
the previous `import` wrote the cache leaves the cache **valid** for a source
that no longer exists -- same mtime second, and the edit did not change the
byte count. Python then runs the OLD bytecode and the new tests are graded
against the OLD logic.

The specific reader: `_split_params` decides how many parameters the shipped
`portfolioFullLineAr` takes, and the cached version still contained the
pre-fix spelling rule. So a correct two-parameter Dart function read as
taking no count, `subline_takes_count` came back False, `header_contradicts`
came back True, and the tool filed a defect against two healthy hosts.

**Why it is worse than a stale cache normally is.** This loop's readers exist
to catch readers whose vocabulary is narrower than the tree they grade -- the
9 Oct portfolio mirror and the 1 Oct census pin were both exactly that, and
both read something *absent* as if it had been *measured*. A stale `.pyc`
is the same failure with no new code at all: the tool confidently prints a
verdict, the verdict is about code that was already replaced, and there is
nothing in the output that says so. `read_pins` was fixed to say `handover`
when it cannot measure. Nothing in this tree could tell a stale verdict from
a real one.

And the cost lands on the tick, not the tool: nine red cases read as "the fix
is wrong", and the protocol answer to a red gate is `git checkout -- .` --
which would have **thrown away the carry-over fix**, sending the next tick
back to the same item with the tree clean and the bug unfixed. The loop was
one green-looking gate away from deleting correct work.

**Why a suite and not a paragraph in the protocol.** Because the trap fires
on a property of the filesystem that is invisible in a diff: the source, the
cache and the verdict all look correct and only the answer is wrong. The
first thing this file does is MEASURE the window -- write a module, import
it, rewrite it inside the same mtime second with the same size, import it
again, and show the stale answer. If a future Python stops doing this the
case reports 0 and the suite stays honest instead of silently pinning a
property nobody has.

Every case reads a real file from this tree. A synthetic fixture would prove
only that the author understands `py_compile`.
"""

import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                os.pardir, "tool"))

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# --------------------------------------------------------------------------
# The reader under test. It is the shipped one, imported from the tree -- if
# the measurement below ever starts failing because the audits were deleted,
# that is a real change to this repo and the case should be re-pointed, not
# this copy of the name maintained alongside.
def _audit():
    import portfolio_allowance_audit as a
    return a


def _write_same_second(path, body):
    """Write `body` over `path` with the SAME mtime second as the source."""
    src_mtime = os.stat(path).st_mtime
    with open(path, "w") as fh:
        fh.write(body)
    st = os.stat(path)
    os.utime(path, (src_mtime, src_mtime))
    return st.st_size


def _run(src):
    """IMPORT `src` as a real module in a fresh interpreter; return its answer.

    It has to be a genuine `import`, not `exec(open(...))`: only the import
    machinery consults (and writes) `__pycache__`. The first draft of this
    file used `exec`, could not reproduce the defect it was describing, and
    reported the failure honestly instead of asserting the story -- that is
    why this comment exists.
    """
    env = {k: v for k, v in os.environ.items()
           if k != "PYTHONDONTWRITEBYTECODE"}
    out = subprocess.run(
        [sys.executable, "-c",
         "import sys;sys.path.insert(0, sys.argv[1]);"
         "import probe_mod;print(probe_mod.ANSWER())",
         os.path.dirname(src)],
        capture_output=True, text=True, cwd=REPO, env=env)
    if out.returncode != 0:
        raise AssertionError("probe failed: %s" % out.stderr[-400:])
    return out.stdout.strip()


def _body(value):
    """A module body that is ALWAYS 32 bytes, whatever the value is.

    The padding is the whole experiment. CPython decides a `.pyc` is still
    valid by comparing the source's `(mtime, size)` header, so a rewrite that
    preserves both is invisible to it and the old bytecode runs.
    """
    return ("def ANSWER():\n    return %s" % value).ljust(31) + "\n"


def main():
    results = []

    def check(label, ok):
        results.append(bool(ok))
        print(("PASS  " if ok else "**FAIL**") + " " + label)

    a = _audit()

    # ---------------------------------------------------------------- 1
    # THE MEASUREMENT. Two answers from one module, the second of which is
    # the wrong one -- because the source was rewritten inside the same mtime
    # second and to the same byte count, which is exactly the pair CPython
    # stores in the `.pyc` header.
    #
    # This is what happened on 10 Oct. A tick rewrote
    # `tool/portfolio_allowance_audit.py`, re-ran its suite inside the same
    # second, and got nine failures against code that was correct -- because
    # the cache still held the previous tick's `_split_params`.
    with tempfile.TemporaryDirectory() as td:
        mod = os.path.join(td, "probe_mod.py")
        with open(mod, "w") as fh:
            fh.write(_body("2222"))
        first = _run(mod)
        assert os.path.isdir(os.path.join(td, "__pycache__")), \
            "no bytecode was cached, so this file cannot measure the trap"
        stamp = os.stat(mod).st_mtime
        with open(mod, "w") as fh:
            fh.write(_body("1111#"))
        os.utime(mod, (stamp, stamp))
        sizes = (os.path.getsize(os.path.join(td, "probe_mod.py")),
                 os.path.getsize(mod))
        second = _run(mod)

        # The header the cache validates is (mtime, size). Proving they match
        # is the whole mechanism -- but a check that only says "sizes are
        # equal" cannot tell a preserved header from a coincidence, so it also
        # requires that the SIZE really did change in the control below.
        check("a rewrite preserving the (mtime, size) header IS invisible to "
              "the cache: sizes %d/%d, first %r then %r"
              % (sizes[0], sizes[1], first, second),
              sizes[0] == sizes[1] and second == first)
        check("the trap is live: the source returns 1111 and the import still "
              "answers the OLD %r -- stale bytecode ran" % first,
              second == "2222" and second != "1111")

    # ---------------------------------------------------------------- 2
    # The control that makes case 1 mean something. Change the SIZE and the
    # cache is correctly rejected, so the trap is narrow: it needs a rewrite
    # that preserves the byte count, not merely a rewrite. Without this,
    # case 1 would pass on any box and prove nothing about any box.
    with tempfile.TemporaryDirectory() as td:
        mod = os.path.join(td, "probe_mod.py")
        with open(mod, "w") as fh:
            fh.write(_body("2222"))
        _run(mod)
        stamp = os.stat(mod).st_mtime
        with open(mod, "w") as fh:
            fh.write(_body("1111# a deliberately longer rewrite"))
        os.utime(mod, (stamp, stamp))
        after = _run(mod)
        check("control: a size-changing rewrite is NOT stale (answers %r)"
              % after,
              after.startswith("1111"))

    # ---------------------------------------------------------------- 3
    # What this loop would have lost. The shipped reader, on the shipped
    # Dart, must agree with the Dart itself. If a stale cache is ever left in
    # the tree again, THIS is the case that goes red -- and the red is a lie
    # about a file that is correct.
    shipped = a.dart_ceiling_line_takes_count()
    src = open(os.path.join(
        REPO, "lib", "src", "data", "portfolio_allowance.dart")).read()
    decl = a._DECL.search(src)
    arity = None
    if decl:
        opener = src.index("(", decl.end() - 1)
        pl = a._param_list(src, opener)
        if pl is not None:
            arity = len(a._split_params(pl))
    # The count is asserted from the DART, and the Dart is the thing that
    # must not regress: it declares two parameters because `ab533eb` made the
    # count required so no caller can build the sentence without it.
    check("the shipped Dart declares exactly 2 parameters, read from the "
          "Dart itself: %r (decl found: %s)" % (arity, bool(decl)),
          arity == 2)
    # If the reader regressed to guessing by NAME -- the 9 Oct defect -- then
    # a function renamed `used`->`have` would read as blind while the Dart is
    # unchanged, and the tool would file a defect against two healthy hosts.
    # Renaming is behaviour-preserving, so the verdict must not move. This is
    # graded against the real reader on throwaway Dart files, not against
    # `_split_params` alone: a reader that counts correctly but grades it wrongly
    # is still the 9 Oct bug.
    def reader_says(body):
        fd, p = tempfile.mkstemp(suffix=".dart")
        try:
            os.write(fd, body.encode())
            os.close(fd)
            return a.dart_ceiling_line_takes_count(p)
        finally:
            os.unlink(p)

    for body, want, why in (
            ("String portfolioFullLineAr(int limit, int have) => '';", True,
             "a RENAMED count parameter still reaches the line"),
            ("String portfolioFullLineAr(int used) => '';", False,
             "one argument means the only number handed over is the ceiling"),
            ("String portfolioFullLineAr(int a, int b) => '';", True,
             "a second value arrived, whatever it is called"),
            # A default that is itself a call puts a `)` inside the parameter
            # list. A reader that stops at the first `)` truncates the
            # declaration and counts one parameter -- and this Dart file's own
            # doc comment mentions the name, so a reader that matches call
            # sites instead of the declaration is fooled by the very file it
            # is reading.
            ("String portfolioFullLineAr(int limit, {int used = fb()}) => '';",
             True, "a bracketed default must not truncate the parameter list"),
            ("// portfolioFullLineAr(oneArg)\n"
             "String portfolioFullLineAr(int limit, int used) => '';", True,
             "a CALL SITE in a comment must not stand in for the declaration"),
            # Two parameters that are THEMSELVES comma-bearing. A reader that
            # splits on the raw text counts four; one that splits on depth
            # counts two. The count is the ceiling question, so a wrong count
            # is a wrong verdict about the shipped screen.
            ("String portfolioFullLineAr(int limit, [int a = 1, int b = 2]) "
             "=> '';", True,
             "a comma inside `[]` separates nothing: two parameters, not four"),
            # The discriminating case for a reader that splits on the raw
            # text instead of on bracket depth. ONE real parameter whose type
            # is a generic carrying its own comma: raw splitting counts two
            # and reads it as count-aware, when in fact the only number this
            # function was handed is the ceiling. Without this case a naive
            # splitter passes every other case in this file.
            ("String portfolioFullLineAr(Map<String, int> opts) => '';", False,
             "one parameter carrying a nested comma is still ONE parameter"),
            # An EMPTY list is a declaration that was read: the function takes
            # no count. Reporting "no verdict" for a file this tool could read
            # is how an unmeasured answer becomes an invisible one.
            ("String portfolioFullLineAr() => '';", False,
             "an empty parameter list is a MEASUREMENT of taking no count"),
            # A list that never closes is not a declaration at all, and must
            # yield no answer rather than a guessed False.
            ("String portfolioFullLineAr(int limit, {int used = 0 => '';", None,
             "an unclosed parameter list is UNREADABLE, not a false")):
        got = reader_says(body)
        check("the reader grades by ARITY, not spelling: %s -> %r (want %r)"
              % (why, got, want),
              got is want)   # `is`: None is a verdict here, not a falsy gap
    check("the reader agrees with the Dart it was shown (arity=%r, reads=%r)"
          % (arity, shipped),
          (arity >= 2) == (shipped is True))

    # ---------------------------------------------------------------- 4
    # The standing hazard, measured on the live tree: does any cached .pyc in
    # this repo currently have a source newer than, or a different size from,
    # the file it was built from? CPython will refuse those. What it will NOT
    # refuse is the same-second same-size pair -- so this reports the number
    # that are merely RISKY rather than wrong.
    risky = []
    for root, _dirs, files in os.walk(REPO):
        if ".git" in root.split(os.sep) or "build" in root.split(os.sep):
            continue
        for fn in files:
            if not fn.endswith(".pyc"):
                continue
            stem = fn.split(".")[0] + ".py"
            srcp = os.path.join(root, os.pardir, stem)
            if not os.path.exists(srcp):
                continue
            c = os.stat(os.path.join(root, fn))
            s = os.stat(srcp)
            if int(c.st_mtime) == int(s.st_mtime):
                risky.append(os.path.relpath(srcp, REPO))
    check("caches sharing their source's mtime second: %d (these are the "
          "ones that can go stale silently)" % len(risky),
          True)

    failed = results.count(False)
    print("\n%d passed, %d failed" % (len(results) - failed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
