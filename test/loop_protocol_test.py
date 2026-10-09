#!/usr/bin/env python3
"""Prove the Loop protocol's gate block is copy-pasteable and gates on a
number the tree can still pass.

Run directly -- it reads the real protocol, it is not a `flutter test`:

    python3 test/loop_protocol_test.py

**Why this file exists.** Step 4 of the Loop protocol is what every tick
runs before it commits anything. It is the single instruction in this file
with no other copy to check it against, so when it rots nothing catches it.

It had rotted twice, in ways a tick reading it carefully would not catch.

**1. The fence does not close where it should.** The block opens at
"4. Gate before committing:" and its closing ``` was pushed to line 847 --
fourteen lines late. Everything between is prose (*"The baseline is 2528..."*,
the 2297/2459 history, the "do not gate lower" rule), so the two gate
commands and fourteen lines of Markdown render as **one code block**. A tick
that copies that block gets 15 lines of shell with a `(` in line 6:
`bash -n` on it is a syntax error. The commands themselves are correct and
were still runnable by eye; the defect is that the instruction cannot be
copied, and a tick under time pressure copies.

**2. The baseline inside it is stale, and the fence hid the contradiction.**
It states **2528 across 13 shard(s)**. The newest green run in the same
file states **2603 across 14** -- and this file's own text, five lines
later, forbids gating below the last green run. A tick reading only the
fenced block gates on 2528, which is 75 tests below the tree it is about to
measure: a legitimate +75 would be indistinguishable from a regression, and
the 13/13 vs 14/14 shard split makes the verdict unreadable.

**Both are checked against the real file, not a fixture.** The defect is
about what line 831 of *this* protocol contains; a test run against a
synthetic markdown could stay green while the real block rots further.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKLOG = os.path.join(REPO, "IMPROVEMENT_BACKLOG.md")

HEADER = "4. Gate before committing:"


def read():
    with open(BACKLOG, encoding="utf-8") as fh:
        return fh.read()


def protocol_lines(txt):
    """The Loop protocol's own text, so a tick section is not mistaken for
    the prose back in step 1 that quotes these same numbers."""
    return txt[txt.index("## Loop protocol"):]


def fenced_block_after(txt, header):
    """The first ``` fence opened by the numbered step `header`.

    Returns (start_line, end_line, body_lines) where end_line is the *next*
    closing fence, or None when the block is never closed.
    """
    lines = txt.split("\n")
    start = next(i for i, l in enumerate(lines) if l.strip().startswith(header))
    open_at = None
    for i in range(start, len(lines)):
        if not lines[i].strip().startswith("```"):
            continue
        if open_at is None:
            open_at = i
        else:
            return start, open_at, lines[open_at + 1:i]
    return open_at, None, lines[open_at + 1:]


def shell_syntax_ok(body):
    """Is this block valid shell? -n parses without executing anything."""
    p = subprocess.run(["bash", "-n"], input="\n".join(body) + "\n",
                       capture_output=True, text=True)
    return p.returncode == 0, (p.stderr or "").strip()


def gate_commands(body):
    return [l.strip() for l in body
            if l.strip().startswith(("python3 ", "/home/"))]


def newest_green(txt):
    """The last SUITE PASS count in the file, which is the last green run."""
    hits = re.findall(r"SUITE PASS\s*[—\-]+\s*(\d+) tests across (\d+) shard", txt)
    return (int(hits[-1][0]), int(hits[-1][1])) if hits else (None, None)


def stated_baseline(txt):
    m = re.search(r"\*\*The baseline is (\d+)", txt)
    s = re.search(r"across (\d+) shard", txt)
    return (int(m.group(1)) if m else None,
            int(s.group(1)) if s else None)


def main():
    results = []

    def check(label, ok):
        results.append(bool(ok))
        print(("PASS  " if ok else "**FAIL**") + " " + label)

    txt = read()
    proto = protocol_lines(txt)
    start, end, body = fenced_block_after(proto, HEADER)

    # ---------------------------------------------------------------- 1
    # The block a tick copies must hold the gate commands and nothing else.
    # Asserting only "a closing fence exists" cannot fail here -- the broken
    # file *does* close, thirteen lines late -- so this counts prose instead.
    prose = [l for l in body
             if l.strip()
             and not l.strip().startswith(("python3 ", "/home/", "#"))]
    check("the gate fence holds commands only, no prose (%d prose line(s))"
          % len(prose), not prose)
    for line in prose[:3]:
        print("    leaked prose: %r" % line.strip()[:72])

    # ---------------------------------------------------------------- 2
    # And what it contains must survive being handed to a shell. This is the
    # failure a copy-paste actually hits; the first version of this check
    # only counted commands and so could not see it.
    ok, err = shell_syntax_ok(body)
    check("the gate block is valid shell to paste (%d lines)%s"
          % (len(body), "" if ok else ": " + err.splitlines()[-1]), ok)

    # ---------------------------------------------------------------- 3
    # Both commands, and only them, are in the block. Prose that leaks in is
    # the symptom of 1; a gate command that leaks out means the fence is
    # too tight and the tick has nothing to run.
    cmds = gate_commands(body)
    check("both gate commands are inside the fence (%d found)" % len(cmds),
          len(cmds) == 2
          and any("flutter" in c and "analyze" in c for c in cmds)
          and any("run_tests.py" in c for c in cmds))

    # ---------------------------------------------------------------- 4
    # Control: the reader can actually find the block. Without this, cases
    # 1-3 pass vacuously on a protocol that no longer contains step 4.
    check("control: step 4 is present and non-trivial (%d body lines)"
          % len(body), len(body) >= 2)

    # ---------------------------------------------------------------- 5
    # The number the gate demands must be one this tree can still meet, and
    # must agree with the newest green run recorded in the same file.
    stated = stated_baseline(proto)
    newest = newest_green(proto)
    check("the fenced baseline is not stale (states %s, newest green %s)"
          % (stated, newest),
          stated[0] is not None
          and newest[0] is not None
          and stated[0] >= newest[0])

    # ---------------------------------------------------------------- 6
    # ...and the shard count must agree too, or "13/13 green" reads as a
    # pass on a 14-shard run.
    check("the fenced shard count matches the newest green run (%s vs %s)"
          % (stated[1], newest[1]), stated[1] == newest[1])

    # ---------------------------------------------------------------- 6
    # Every fence in the protocol must balance. Fixing step 4 by moving its
    # paragraph out of the block left the paragraph's original closing fence
    # orphaned, and that one stray ``` swallowed the rest of the file --
    # ~28,600 lines of protocol rendered as one code block. The suite was
    # 6/6 green while that was true: it read step 4 and never counted fences
    # outside it. This is the check that would have caught it.
    depth = 0
    opens = []
    for line in proto.split("\n"):
        if not line.strip().startswith("```"):
            continue
        if depth == 0:
            depth = 1
            opens.append(line)
        else:
            depth = 0
            opens.pop()
    check("every fence in the protocol balances (%d open at end)"
          % len(opens), depth == 0)
    for line in opens[:2]:
        print("    unbalanced fence: %r" % line.strip()[:60])

    print("\n%d case(s) against %s" % (len(results), os.path.relpath(BACKLOG, REPO)))
    ok = sum(results)
    print("== %d/%d ==  %s" % (ok, len(results),
                                "ALL PASS" if all(results) else "SOME FAILED"))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
