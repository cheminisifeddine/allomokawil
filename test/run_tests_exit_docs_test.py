#!/usr/bin/env python3
"""Pin the Loop protocol's exit-code table to the runner that actually defines
it.

Run directly -- it reads two real files, it is not a `flutter test`:

    python3 test/run_tests_exit_docs_test.py

**Why this file exists.** The protocol states the runner's exit codes in ONE
sentence -- *"Exit codes: 0 pass, 1 fail, **2 hung**, **3 BUSY**"* -- and that
sentence is what a tick reads when a suite returns a code it did not expect.
The runner grew a fifth status on 10 Oct (`STARVED = 4`) and the sentence was
never updated, so the one line in this file written to explain a non-zero code
is the line that had stopped explaining it.

The failure is invisible by construction. There was no contradiction to trip
over: the sentence lists 0/1/2/3, the runner defines 0/1/2/3/4, and nothing
compared the two. A tick that gets a 4 and reads the protocol finds a table
that does not contain 4 and must then go read 45 KB of source -- the exact
thing the sentence exists to avoid, on the one code whose whole purpose is to
tell a tick **do not go looking for a defect in the tree**.

**The codes are read from the runner, not hardcoded here.** That is the
difference between a guard and a snapshot: a fifth constant added to
`tool/run_tests.py` tomorrow turns this red until the sentence catches up,
where a hardcoded tuple would keep agreeing with a stale copy of itself.

**Second guard, same file.** The 10 Oct tick recorded that `/proc/loadavg`
**cannot** distinguish a starved shard from a deadlocked one -- measured, not
inferred, and the reasoning is kept in the tick write-up. An older paragraph
still recommended load average as the next item. A refuted recommendation left
in place is worse than no recommendation: it is a specific, wrong instruction
sitting in the section every tick reads. This asserts it is gone.

**Both are checked against the real files, not fixtures.** The defect is about
what these two files contain today.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKLOG = os.path.join(REPO, "IMPROVEMENT_BACKLOG.md")
RUNNER = os.path.join(REPO, "tool", "run_tests.py")

#: The statuses the protocol is expected to explain. Kept only as a *floor* --
#: it catches "a status was removed/renamed without updating this file", and
#: the real comparison is against whatever the runner defines.
KNOWN_STATUSES = {"PASS", "FAIL", "HUNG", "BUSY", "STARVED"}


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


#: The protocol ends with the honesty rule; everything after it is tick
#: write-ups appended to the same file.
PROTOCOL_END = "**Honesty rule:**"


def protocol(txt):
    """The Loop protocol's INSTRUCTION region -- ``## Loop protocol`` up to the
    honesty rule that closes it -- and deliberately nothing else.

    The region matters, and getting it wrong is the mistake this file's first
    draft made. The 10 Oct write-up *below* the honesty rule records that
    `/proc/loadavg` was proposed and then **refuted**; that is the record of a
    measurement, and it is supposed to stay. A guard scoped to the whole tail
    of the file therefore flagged the history for containing a word, and
    deleting history to satisfy it would have destroyed the measurement that
    chose the design. Instruction regions are what a tick *obeys*; write-ups
    are what it *reads about the past*. Only the first is a defect when stale.
    """
    region = txt[txt.index("## Loop protocol"):]
    return region[:region.index(PROTOCOL_END)]


def runner_codes(src):
    """The status constants the runner defines, parsed from its source.

    Handles both declaration shapes the file uses:
        `PASS, FAIL, HUNG = 0, 1, 2`      (tuple form)
        `BUSY = 3`                        (single form)

    Returns {NAME: int}. Derived from the real file on purpose -- see the
    module docstring: a hardcoded copy here would agree with a stale sentence
    forever.
    """
    codes = {}
    pattern = re.compile(
        r"^([A-Z][A-Z_]*(?:,\s*[A-Z][A-Z_]*)*)\s*=\s*"
        r"(\d+(?:,\s*\d+)*)\s*$", re.M)
    for names, values in pattern.findall(src):
        name_list = [n.strip() for n in names.split(",")]
        value_list = [int(v.strip()) for v in values.split(",")]
        if len(name_list) != len(value_list):
            continue
        for name, value in zip(name_list, value_list):
            codes[name] = value
    return codes


def runner_statuses(src):
    """The statuses the runner can REPORT, read from its own STATUS_NAME table.

    `runner_codes()` over-collects -- it also returns tuning constants like
    TAIL_LINES and SHARD_SIZE, which are not statuses and are correctly absent
    from a protocol table. So the set of things that must be documented has to
    come from the one place the runner enumerates its own statuses.

    This is also the fix for a guard that could not fail. When the "is a status
    missing?" case iterated a hardcoded set living in this file, adding a sixth
    status to `tool/run_tests.py` left it **green** -- verified by mutation,
    which is precisely the drift this file exists to catch, and it survived
    because the check asked its own question instead of the runner's. A guard
    that is right by construction is not a guard.
    """
    m = re.search(r"STATUS_NAME\s*=\s*\{(.*?)\}", src, re.S)
    if not m:
        return set()
    # Keys are the code constants (PASS, FAIL, ...); the VALUES are the words
    # the runner prints, which is exactly what the protocol table must name.
    values = re.findall(r":\s*\"([A-Z]+)\"", m.group(1))
    return set(values)


def documented_codes(stmt):
    """(code, word) pairs out of the protocol's exit-code sentence.

    Markdown emphasis is stripped first -- the sentence writes `**2 hung**`,
    not `2 hung` -- and every parenthetical is removed before the pairs are
    read.

    Removing them **all** is load-bearing, and getting it wrong is what this
    file's first draft did. The obvious `split("(")[0]` keeps only the text
    before the FIRST parenthesis, which is enough for the old table because
    the parenthetical came last (`3 BUSY` (the build gate refused...)). Add a
    fifth entry that explains itself -- `4 STARVED` (the deadline fired on...)
    -- and the same truncation silently drops everything from that point on.
    The guard then reports a status as "missing" **after it was just added to
    the file**, which reads as the fix failing and invites a second, wrong edit
    of a sentence that is already correct. A parser that cannot see the entry
    it is about must not be trusted to report one as absent.
    """
    flat = stmt.replace("*", "")
    flat = re.sub(r"\([^)]*\)", " ", flat)
    return [(int(c), w) for c, w in re.findall(r"(\d+)\s+([A-Za-z]+)", flat)]


def exit_sentence(proto_txt):
    """The sentence, with the line wrap at 80 columns rejoined.

    It is hard-wrapped mid-parenthesis across two lines, so a line-local
    search would find half a table and read it as a contradiction.
    """
    flat = " ".join(l.strip() for l in proto_txt.split("\n"))
    flat = re.sub(r"\s+", " ", flat)
    m = re.search(r"Exit codes:(.{0,400}?)\.", flat)
    return m.group(0) if m else None


def main():
    results = []

    def check(label, ok):
        results.append(bool(ok))
        print(("PASS  " if ok else "**FAIL**") + " " + label)

    proto = protocol(read(BACKLOG))
    codes = runner_codes(read(RUNNER))

    # ------------------------------------------------------------- control
    # Without this every case below could pass vacuously on a runner that no
    # longer defines statuses, or a protocol that no longer has the sentence.
    statuses = runner_statuses(read(RUNNER))
    check("control: the runner's STATUS_NAME table is readable and complete "
          "(%s)" % sorted(statuses),
          KNOWN_STATUSES.issubset(statuses))

    stmt = exit_sentence(proto)

    # ------------------------------------------------------------- 1
    check("control: the protocol still states an exit-code table%s"
          % ("" if stmt else " -- it is GONE"), stmt is not None)

    if stmt:
        pairs = documented_codes(stmt)
        check("control: that sentence parses as a table (%d pair(s))" % len(pairs),
              len(pairs) >= 4)

        # --------------------------------------------------------- 2
        # The actual defect: the sentence was 0/1/2/3, the runner is 0-4.
        missing = sorted(n for n in statuses if n not in
                         {w.upper() for _, w in pairs})
        check("the protocol's table names every status the runner defines "
              "(missing: %s)" % (missing or "none"), not missing)

        # --------------------------------------------------------- 3
        # ...and pairs each name with the number the runner uses, so a
        # renamed or renumbered status cannot hide behind a correct word.
        table = {w.upper(): c for c, w in pairs}
        wrong = sorted("%s=%d but protocol says %s"
                       % (n, v, table.get(n.upper(), "absent"))
                       for n, v in codes.items()
                       if n in table and table[n.upper()] != v)
        check("every code matches the runner (%s)"
              % ("; ".join(wrong) if wrong else "all agree"),
              not wrong)

        # --------------------------------------------------------- 4
        # And it documents nothing the runner does not define -- the other
        # direction, which catches a status invented in prose.
        invented = sorted(str(c) for c, w in pairs if w.upper() not in codes)
        check("the table documents no status the runner lacks (extra: %s)"
              % (invented or "none"), not invented)

        # --------------------------------------------------------- 5
        # The gate commands live in the same section, so a tick reading the
        # sentence is reading it next to `python3 tool/run_tests.py`.
        check("control: the sentence sits in the gate's own section",
              "tool/run_tests.py" in proto)

    # ------------------------------------------------------------- 6
    # The refuted recommendation. Load average reads HIGH for a deadlocked
    # shard when something else is busy and LOW for a starved one when nothing
    # else is -- there is no cut. Leaving the paragraph in a section every tick
    # reads keeps a specific wrong instruction alive.
    stale = [l.strip() for l in proto.split("\n") if "/proc/loadavg" in l]
    check("no refuted load-average recommendation in the protocol's own "
          "instructions (%d line(s))" % len(stale), not stale)
    for line in stale[:3]:
        print("    stale advice: %r" % line[:78])

    print("\n%d case(s) against %s + %s"
          % (len(results), os.path.relpath(BACKLOG, REPO),
             os.path.relpath(RUNNER, REPO)))
    ok = sum(results)
    print("== %d/%d ==  %s" % (ok, len(results),
                                "ALL PASS" if all(results) else "SOME FAILED"))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
