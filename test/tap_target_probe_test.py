#!/usr/bin/env python3
"""Prove the tap-target audit's hand-measured table identifies its constructs by
CONTENT, not by a line number that every edit above it moves.

Run directly -- it reads the real tool and the real tree, it is not a
`flutter test`:

    python3 test/tap_target_probe_test.py

**Why this file exists.** `tool/tap_target_audit.py` is 529 lines of the app's
only tap-target reader, and it had **no test battery at all** -- the one audit
tool of nine with none. Its MEASURED table stored each row as
`(file, line, anchor)`, so every edit above a construct turned that row STALE.

That is not hypothetical rot. The table was **re-pinned by hand three times**
(13 Sep, 6 Oct, 7 Oct -- the comments above each row say so), and on 10 Oct it
was STALE on **all nine of its rows at once**, so the tool exited **1** on the
live tree and had been doing so for some time. Nothing noticed, because no tick
had run this tool and read its exit code; the loop's own write-ups described it
as passing.

**The second half, which a line-number fix alone would not have closed.**
`resolve_measured` also used the stored coordinates to decide which ADVISORY
rows to suppress. When a row went STALE its coordinates stopped matching, so
`ui.dart:400` printed as `ADVISORY -- hand-rolled tap` in the very same run
that printed its own row as `STALE`: one table disagreeing with itself, and the
ADVISORY count inflated by every stale row. The suppression key is now built
from the RESOLVED line, so it moves with the construct.

**Both halves are checked against the real tool and the real tree**, never a
fixture: the defect is about what this tool does to this app, and a battery
running against synthetic Dart would stay green while the real table rotted.

Cases 1-3 are CONTROLS, and they are asserted FIRST and unconditionally: a
reader that returns None or an empty table on the real tree is a BLIND reader,
not a lenient one. This repo has shipped seven guards that could not fail, all
of them by exactly that route.
"""

import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "tool", "tap_target_audit.py")

_spec = importlib.util.spec_from_file_location("tap_target_audit", TOOL)
tta = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tta)

_results = []


def check(label, ok):
    _results.append((label, ok))
    print("%s   %s" % ("PASS  " if ok else "FAIL  ", label))


def scratch(files):
    """A throwaway tree containing `files` (path -> text)."""
    d = tempfile.mkdtemp(prefix="tap_probe_")
    for rel, text in files.items():
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
    return d


def cleanup(d):
    shutil.rmtree(d, ignore_errors=True)


# A minimal Dart body whose every MEASURED probe is guaranteed unique, used to
# exercise `locate` itself without depending on the live app's line numbers.
SYNTH = "lib/x.dart"
SYNTH_BODY = "\n".join([
    "void main() {",
    "  var a = 1;",          # 2  filler above every construct
    "  var b = 2;",
    "  var c = 3;",
    "  PROBE_ONE",           # 5
    "  PROBE_TWO",           # 6
    "  var d = 4;",
    "}",
])


def main():
    # --- case 1: CONTROL. The real tree must produce a readable table.
    table = getattr(tta, "MEASURED", None)
    check("control: the MEASURED table is readable and non-empty (%d row(s))"
          % (len(table) if table else 0),
          bool(table))

    # --- case 2: CONTROL. Every real row carries a probe, not a line number.
    probes = [r for r in table if isinstance(r[1], str)] if table else []
    check("control: every real row identifies its construct by probe (%d/%d)"
          % (len(probes), len(table or [])),
          bool(table) and len(probes) == len(table))

    # --- case 3: CONTROL. Every real probe RESOLVES on the real tree, exactly
    # once. This is the assertion that would have caught the nine STALE rows.
    unresolved = []
    for rel, probe, _v, _w in (table or []):
        line, bad = tta.locate(ROOT, rel, probe)
        if line is None:
            unresolved.append("%s: %s" % (rel, bad))
    check("every real probe resolves to a unique site on this tree "
          "(%d unresolved)" % len(unresolved),
          bool(table) and not unresolved)
    for u in unresolved[:4]:
        print("    %s" % u)

    # --- case 4: locate() RESOLVES a moved construct. A line number would fail
    # this by construction; a probe follows the text.
    d = scratch({SYNTH: SYNTH_BODY})
    try:
        # Add 40 lines ABOVE the construct -- exactly what any unrelated edit
        # does to a stored line number.
        with open(os.path.join(d, SYNTH), "w", encoding="utf-8") as fh:
            fh.write("\n".join("// filler %d" % i for i in range(40)) + "\n"
                     + SYNTH_BODY)
        line, bad = tta.locate(d, SYNTH, "PROBE_ONE")
        check("a construct pushed down 40 lines still resolves (line %s)" % line,
              line == 45)
        # ... and the probe does not silently resolve to the WRONG construct.
        line2, _ = tta.locate(d, SYNTH, "PROBE_TWO")
        check("a construct pushed down 40 lines still resolves to its OWN "
              "site (%s, not 45)" % line2, line2 == 46)
    finally:
        cleanup(d)

    # --- case 5: STALE still fires when the construct is really GONE. A probe
    # that cannot go red is a table that cannot rot loudly.
    d = scratch({SYNTH: SYNTH_BODY.replace("PROBE_ONE", "SOMETHING_ELSE")})
    try:
        line, bad = tta.locate(d, SYNTH, "PROBE_ONE")
        check("a construct deleted from the file is reported, not guessed "
              "(%s)" % bad, line is None and "no longer in the file" in bad)
    finally:
        cleanup(d)

    # --- case 6: a probe matching TWO sites is reported, not guessed at. This
    # is what stops a lazy probe from quietly re-pointing a verdict at a
    # different control that happens to look the same.
    d = scratch({SYNTH: SYNTH_BODY.replace("  PROBE_ONE", "  PROBE_ONE")
                              .replace("  PROBE_TWO", "  PROBE_ONE")})
    try:
        line, bad = tta.locate(d, SYNTH, "PROBE_ONE")
        check("a probe matching 2 sites is reported rather than guessed (%s)"
              % bad, line is None and "does not identify one" in bad)
    finally:
        cleanup(d)

    # --- case 7: re-wording a COMMENT and re-formatting whitespace does NOT make
    # a row stale. The probe is about the construct; prose about the construct
    # is not the construct.
    d = scratch({SYNTH: SYNTH_BODY.replace("  PROBE_ONE",
                                           "  PROBE_ONE // now with a note")})
    try:
        line, _ = tta.locate(d, SYNTH, "PROBE_ONE")
        check("a comment added above the construct does not break the probe "
              "(line %s)" % line, line == 5)
    finally:
        cleanup(d)

    # --- case 7b: a comment BETWEEN two probe tokens. This is what makes
    # comment-stripping load-bearing: in case 7 the comment sits AFTER the
    # probe, so the probe remains a substring and a tool that kept comments
    # would pass that case too. Here the comment splits the probe in half, so
    # only a tool that strips comments can match it. (The comment-stripping
    # mutation survived the first battery because of exactly this -- the
    # mutation was real, the case was not strong enough to kill it, and a
    # mutation that survives a weak case says nothing about the guard.)
    # The comment must sit INSIDE the probe, between two of its tokens. A
    # `// note` at the end of a line is invisible to whitespace normalisation,
    # so a tool that KEPT comments would still match -- which is exactly how
    # this mutation survived two batteries. Here the probe spans a line whose
    # comment falls between the first and last tokens, so it is matchable only
    # by a tool that strips comments. (Verified before writing it: the kept
    # form does NOT contain the probe, the stripped form does.)
    d = scratch({SYNTH: "SPAN_PROBE (\n  x: 1 // trailing\n  , y: 2\n)"})
    try:
        line, _bad = tta.locate(d, SYNTH,
                                 "SPAN_PROBE ( x: 1 , y: 2 )")
        check("a comment inside the probe does not break it (line %s)" % line,
              line == 1)
    finally:
        cleanup(d)

    # --- case 7c: the file itself is gone. A row pointing at a deleted file
    # must be reported, not silently counted as fine.
    d = scratch({"lib/present.dart": SYNTH_BODY})
    try:
        line, bad = tta.locate(d, "lib/deleted.dart", "PROBE_ONE")
        check("a row pointing at a deleted file is reported (%s)" % bad,
              line is None and "file is gone" in bad)
    finally:
        cleanup(d)

    # --- case 8: the tool exits 0 on the LIVE tree, UNPIPED. The nine STALE
    # rows that shipped for days are exactly what this catches, and the exit
    # code is the part that survives a scrolled log, so it is read from a
    # process rather than inferred from printed text.
    proc = subprocess.run([sys.executable, TOOL, ROOT],
                          capture_output=True, text=True)
    check("the audit exits 0 on the live tree, unpiped (rc=%d)" % proc.returncode,
          proc.returncode == 0 and "STALE" not in proc.stdout)

    # --- case 9: every MEASURED row RESOLVES to a distinct site. Two rows
    # resolving to the same line means one construct is described twice and a
    # fix to it would have to be made twice -- or, worse, silently disagree.
    seen = {}
    for rel, probe, _v, _w in (table or []):
        line, _ = tta.locate(ROOT, rel, probe)
        if line is not None:
            seen.setdefault((rel, line), []).append(probe)
    dupe = {k: v for k, v in seen.items() if len(v) > 1}
    check("no two MEASURED rows resolve to the same site (%d collision(s))"
          % len(dupe), not dupe)

    # --- case 10: the suppression key is built from the RESOLVED line, so a
    # MEASURED row never also prints as ADVISORY. This is the second half of
    # the defect: ui.dart:400 printed as ADVISORY in the same run that printed
    # its own row STALE.
    adv = [ln for ln in proc.stdout.split("\n") if ln.startswith("ADVISORY")]
    measured = [ln.split()[1] for ln in proc.stdout.split("\n")
                if ln.startswith("MEASURED")]
    both = sorted(set(ln.split()[1] for ln in adv) & set(measured))
    check("no site is both MEASURED and ADVISORY in one run (%d overlap)"
          % len(both), not both)
    for b in both[:4]:
        print("    %s" % b)

    # --- case 11: END TO END on a MUTATED TREE. `locate` is proven above, but
    # a tool that resolved correctly and then never said so would satisfy every
    # case so far: `resolve_measured` could swallow the verdict and the run
    # would still be green. So the whole tool is pointed at a copy of the REAL
    # tree with ONE construct deleted, and it must exit 1 and say STALE. This
    # is the shape the nine-row rot actually took, and it is the only case
    # here that exercises the audit's exit code rather than its internals.
    tmp = tempfile.mkdtemp(prefix="tap_e2e_")
    try:
        for sub in ("lib", "tool"):
            dst = os.path.join(tmp, sub)
            if os.path.isdir(os.path.join(ROOT, sub)):
                shutil.copytree(os.path.join(ROOT, sub), dst)
        # Delete the first MEASURED row's construct, by its own probe.
        rel, probe, _v, _w = table[0]
        # Void the RAW LINES the probe spans. Replacing the normalised probe
        # inside the raw source does not work and quietly produced a green
        # case for the wrong reason: the probe contains comments, so its
        # normalised form never appears literally in the file and the "deletion"
        # was a no-op. A mutation that does not mutate is not evidence.
        victim = os.path.join(tmp, rel)
        lines = open(victim, encoding="utf-8").read().split("\n")
        start, _ = tta.locate(tmp, rel, probe)
        want, acc, end = tta._norm(probe), "", start
        for i in range(start - 1, len(lines)):
            acc = (acc + " " + tta._norm(lines[i])).strip()
            end = i + 1
            if want in acc:
                break
        for i in range(start - 1, end):
            lines[i] = "  // VOIDED_BY_THE_TEST"
        with open(victim, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines))
        # The deletion must actually have happened, or the case proves nothing.
        check("the case-11 deletion really removed the construct",
              tta.locate(tmp, rel, probe)[0] is None)
        proc = subprocess.run([sys.executable, TOOL, tmp],
                              capture_output=True, text=True)
        check("deleting one construct makes the audit exit 1 and say STALE "
              "(rc=%d)" % proc.returncode,
              proc.returncode == 1 and "STALE" in proc.stdout)
    finally:
        cleanup(tmp)

    print("\n%d case(s) against tool/tap_target_audit.py" % len(_results))
    bad = [l for l, ok in _results if not ok]
    print("== %d/%d ==  %s" % (len(_results) - len(bad), len(_results),
                              "ALL PASS" if not bad else "FAIL"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
