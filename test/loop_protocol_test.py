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

**3. The guard itself went blind, and it rotted twice more for the same
reason.** Case 5 read the demanded count out of a *sentence* a tick is free
to re-word. Inserting one word -- "is **now** 2605" -- put a token between
"is" and the digits and the count silently became `None`, so the case spent
weeks comparing `(None, 14)` against a real number and reporting FAIL for a
reason that had nothing to do with staleness. Prose is not a number anything
can gate on, so the demand now lives on one `# GATE BASELINE:` line inside
the fence and the prose only describes it. Re-wording the paragraph can no
longer break the guard; that is mutation-tested here.

**The vacuity trap, and the split that avoids it.** `newest_green` must not
read the demand line: if it did, `stated >= newest` would compare the demand
against itself and hold by construction -- a green guard that cannot fail.
So `main` hands the fence to `stated_baseline` and everything *outside* it to
`newest_green`, and a case asserts the two regions cannot see each other.
`newest_green` also takes the **highest** banked count rather than the last
one in the file: the backlog is append-only but tick write-ups sit out of
order, so position is not chronology (2609 was written above a 2605).

**4. The paragraph under the fence, which is what a human reads.** The fence
was moved to 2673 on 10 Oct and the sentence two lines below it kept saying
2609. Both numbers were true about *something* -- 2673 was banked and green,
2609 was the last count that gated a commit -- and the suite stayed 9/9,
because nothing compared the sentence with the marker. The machine readers
were both right, which is exactly what makes this the same defect one layer
up from #3: the guard is not blind, it is *silent about a line it does not
read*. `prose_baseline` reads only the present-tense claim directly under the
fence, so the dozens of historical "banked 2609" mentions in the file cannot
trip it.
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


# The one machine-read line inside step 4's fence. Both readers key off this
# marker, so the shape lives here once instead of in two regexes that used to
# disagree about what a green run looks like.
BASELINE_MARK = "# GATE BASELINE:"

# The present-tense claim that step 4 makes about itself, e.g.
# "**The baseline is 2609 -- the `# GATE BASELINE` line ...**". Only the
# PRESENT-tense form is matched: the same digits appear dozens of times in
# this file as history ("banked 2609", "+64 over 2609", "2609 stays on the
# books"), and a reader that swept every mention would fail on all of them.
# This is why the case below is a *contradiction* reader and not a
# "find the number" reader.
CLAIM_RE = re.compile(r"baseline\s+is\s+\**(\d+)", re.IGNORECASE)


def prose_baseline(txt, header=HEADER, fence_index=None):
    """The baseline step 4 claims in prose, or None when it claims none.

    Scans the lines that FOLLOW step 4's closing fence, and to the present
    tense only, so the dozens of historical "banked 2609" mentions in this
    file cannot be mistaken for the claim.

    **It takes the whole protocol text, not the fenced body.** The first
    version of this reader took `body` -- and `body` is only what is *inside*
    the fence, which contains no fence markers and no prose at all, so the
    reader looked for a paragraph that was never in its input and returned
    `None` on the real tree. The case then passed vacuously, reporting
    "agrees (says None)" on a file whose sentence said 2609 against a fence
    stating 2673. The same shape as the six previous guards in this file, so
    it is worth naming: **a new reader that returns `None` on the real tree
    is not a lenient reader, it is a blind one.** Hence `control` below.

    **Why this exists at all.** `stated_baseline` reads the marker line and
    `newest_green` reads the tick write-ups, so the guard had no opinion on
    the one paragraph that is what a human tick actually reads. When the fence
    moved to 2673 (`ee05f7`) the paragraph below it kept saying 2609 and the
    suite stayed 9/9: the number in the fence was right, the number in the
    sentence two lines under it was wrong, and nothing compared them.
    """
    lines = txt.split("\n")
    if fence_index is not None:
        start = fence_index
    else:
        start = next(i for i, l in enumerate(lines)
                     if l.strip().startswith(header))
    for line in lines[start:]:
        m = CLAIM_RE.search(line)
        if m:
            return int(m.group(1))
    return None


def stated_baseline(body):
    """The demand the fence states, read from the canonical line only.

    Reads `body` -- the fenced block itself -- and NOT the prose around it.
    The old reader scanned the whole protocol for a hand-worded sentence
    (a regex on "**The baseline is <digits>"), which then broke twice: the
    word *now* was inserted between "is" and the digits and the count went to
    None. A sentence a tick can re-word is not a number anything can gate on;
    the marker line is the demand, and prose describes it.
    """
    for line in body:
        if BASELINE_MARK in line:
            m = re.search(r"SUITE PASS\s*[—\-]+\s*(\d+) tests across (\d+) shard",
                          line)
            if m:
                return int(m.group(1)), int(m.group(2))
    return None, None


def newest_green(txt):
    """The highest-counted banked green run in the tick write-ups.

    `txt` is the whole protocol MINUS step 4's fenced block, so this can never
    read the demand line back and satisfy itself. See the note in `main`.
    """
    hits = re.findall(r"SUITE PASS\s*[—\-]+\s*(\d+) tests(?:,| across)"
                      r"\s*(?:(\d+) shard|(\d+)/\d+ shards)", txt)
    runs = []
    for tests, across, frac in hits:
        shards = across or frac
        if shards is not None:
            runs.append((int(tests), int(shards)))
    return max(runs) if runs else (None, None)


def main():
    results = []

    def check(label, ok):
        results.append(bool(ok))
        print(("PASS  " if ok else "**FAIL**") + " " + label)

    txt = read()
    proto = protocol_lines(txt)
    start, _open_i, body = fenced_block_after(proto, HEADER)

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
    #
    # `writeups` is the protocol with step 4's fenced block REMOVED, and the
    # demand is read out of that block. That split is load-bearing: when both
    # numbers came out of one string, the guard compared the demand against a
    # match that could be the demand, so `stated >= newest` held by
    # construction and the case could not fail no matter how wrong the prose
    # was. `writeups` cannot see the marker line, and `stated_baseline` is
    # only ever handed the fence, so neither can borrow the other's number.
    # `fenced_block_after` returned (header_i, open_fence_i, body); the fence
    # closes immediately after the body, so both cut points are already known
    # and neither needs a second scan for fences.
    plines = proto.split("\n")
    close_i = _open_i + 1 + len(body)
    assert plines[close_i].strip().startswith("```"), repr(plines[close_i])
    writeups = "\n".join(plines[:_open_i] + plines[close_i + 1:])

    stated = stated_baseline(body)
    newest = newest_green(writeups)
    check("the fenced baseline is not stale (states %s, newest green %s)"
          % (stated, newest),
          stated[0] is not None
          and newest[0] is not None
          and stated[0] >= newest[0])

    # The demand must live on the marker line, not only in prose. Without this
    # a tick could delete the line, the prose would still read "The baseline is
    # 2609", and case 5 would pass on a block no longer stating anything.
    check("the fence states the demand on the %r line (%d found)"
          % (BASELINE_MARK, sum(BASELINE_MARK in l for l in body)),
          any(BASELINE_MARK in l for l in body))

    # The paragraph under the fence must not contradict the fence. This is
    # the half of step 4 that is *prose*, and prose is what a tick reads --
    # the fence is what a tick copies. When the two disagreed by 64 the
    # suite was 9/9, so this is the case that would have caught it.
    # Control, and it comes FIRST on purpose. A reader that finds nothing on
    # the real tree would make every agreement assertion below it vacuously
    # true, so it has to be proven able to see the sentence before its
    # verdict is allowed to mean anything.
    claimed = prose_baseline(proto, fence_index=close_i + 1)
    check("control: the prose reader finds step 4's baseline sentence (%s)"
          % claimed, claimed is not None)
    check("the prose below the fence agrees with it (says %s, fence states %s)"
          % (claimed, stated[0]),
          claimed is not None and stated[0] is not None
          and claimed == stated[0])

    # And the two readers must not overlap: if the marker line ever leaked
    # into the region case 5 scans, the demand would be able to vouch for
    # itself. This is the check that fails if someone "simplifies" the split.
    check("the write-ups cannot see the demand line",
          all(BASELINE_MARK not in l for l in writeups.split("\n")))

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
