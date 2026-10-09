#!/usr/bin/env python3
"""Prove a stashed `static const double X` can only ADD duplicates, never
carry unique work -- and that `stash pop` on one is a guaranteed red build.

Run directly -- it reads real git objects and is not a `flutter test`:

    python3 test/stash_verdict_test.py

**Why this file exists.** Two stashes sat in this repo's `refs/stash` for
five consecutive ticks, escalating on every one of them. `app_theme.dart`
carried duplicate `static const double hairline = 1.5;` declarations: the
frozen one would make the analyzer red the moment it was popped, and because
a red build is never shipped, **no tick could legally recover it and no tick
could legally drop it.** The Loop protocol says to "finish or discard", and
neither branch is executable: finishing means committing a tree with four
declarations of one name, discarding means losing work nobody had read to
find out whether it was work.

The escalation was also the wrong shape of question. Four ticks asked *"is
there a writer process?"* -- the answer was no every time, and it could not
ever be yes, because the process that wrote the stash left hours earlier.
Absence of a writer is not evidence the stash is unfinished; the question
that decides it is whether the stash contains anything the tree does not
already have.

**The question is decided by content, not by process, and it is decidable.**
A stash is a tree. Its diff against HEAD is exactly what `pop` would apply.
So the whole "finish or discard" dilemma collapses to one measurement: does
that diff contain a line the tree does not already contain?

  * every added line is already in the tree -> the stash carries nothing
    unique, `pop` duplicates, and it is safe to drop;
  * any added line is new -> it carries real work and must be finished.

Both real stashes here measured as the first case, which is why this is a
suite rather than a judgement call: the *rule* now runs without an agent,
and a future stash that IS real work gets the opposite verdict instead of
silently inheriting a five-tick-old precedent.

**Every case reads the real repo**, never a fixture. A synthetic stash would
prove the arithmetic against a tree I made up; the defect is about what these
two particular stashes contain, and a test that cannot fail on the actual
`refs/stash` would be exactly the guard-that-can't-fail this loop keeps
finding. Cases 1-4 pin the *property* (duplicates only, nothing removed,
pop is red) against real objects, and case 5 pins the *verdict* — that the
only stashes present are droppable, so the loop is not silently carrying a
second one.
"""

import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEME = "lib/src/core/theme/app_theme.dart"

# A declaration of one constant name, as Dart sees it. Anchored on the type
# so a *reference* (AppTheme.hairline) never counts as a definition.
_DECL = re.compile(r"^\s*static const double (\w+)\s*=")


def git(*args):
    return subprocess.run(
        ("git", "-C", REPO) + args,
        capture_output=True, text=True, check=True).stdout


def stashes():
    """Every stash ref, oldest-index last, as (refname, sha)."""
    out = git("stash", "list", "--format=%gd %H")
    pairs = []
    for line in out.splitlines():
        if not line.strip():
            continue
        ref, sha = line.split()
        pairs.append((ref, sha))
    return pairs


def blob_at(ref, path):
    return git("show", "%s:%s" % (ref, path))


def added_lines(ref):
    """The lines `git stash pop` would ADD, '+' stripped.

    `git diff HEAD <stash>` is the pop payload; the stash commit's own tree
    is the same content, so either works. Empty when the stash touches
    nothing this file holds.
    """
    out = subprocess.run(
        ("git", "-C", REPO, "diff", "HEAD", ref, "--", THEME),
        capture_output=True, text=True, check=True).stdout
    return [ln[1:] for ln in out.splitlines()
            if ln.startswith("+") and not ln.startswith("+++")]


def removed_lines(ref):
    out = subprocess.run(
        ("git", "-C", REPO, "diff", "HEAD", ref, "--", THEME),
        capture_output=True, text=True, check=True).stdout
    return [ln[1:] for ln in out.splitlines()
            if ln.startswith("-") and not ln.startswith("---")]


def _norm(line):
    """Whitespace-insensitive form of a source line.

    A stash is usually the same block re-indented, not new prose. Comparing
    raw lines made an indented copy read as a line "the tree lacks", which
    is the one false answer this suite must never give -- it would send a
    real, droppable stash down the "finish it" path.
    """
    return " ".join(line.split())


def decls(text):
    return [m.group(1) for m in
            (_DECL.match(ln) for ln in text.splitlines()) if m]


def main():
    results = []

    head = blob_at("HEAD", THEME)
    head_decls = decls(head)

    def check(label, ok):
        results.append(bool(ok))
        print(("PASS  " if ok else "**FAIL**") + " " + label)

    # ---------------------------------------------------------------- 1
    # The decisive property: every line a stash ADDS is already in the tree.
    # This is what makes the stash droppable, and it is checked against the
    # real refs/stash, so it fails if a future stash is real work.
    live = stashes()
    dup_only = True
    detail = []
    for ref, _sha in live:
        head_set = {_norm(ln) for ln in head.splitlines()}
        novel = [ln for ln in added_lines(ref)
                 if _norm(ln) and _norm(ln) not in head_set]
        detail.append("%s: +%d line(s), %d new"
                       % (ref, len(added_lines(ref)), len(novel)))
        if novel:
            dup_only = False
            print("    %s carries lines the tree lacks: %r"
                  % (ref, novel[:3]))
    check("every stashed line is already in the tree (%s)"
          % "; ".join(detail) if detail else "no stash present",
          dup_only)

    # ---------------------------------------------------------------- 2
    # A stash that only duplicates cannot be "finished" -- finishing it is
    # the red build. Popping must ADD a second declaration of a name the
    # tree already declares. One duplicate is already an analyzer error.
    for ref, _sha in live:
        after = decls(blob_at(ref, THEME))
        counts = {}
        for d in after:
            counts[d] = counts.get(d, 0) + 1
        dupes = sorted(n for n, c in counts.items() if c > 1)
        check("popping %s duplicates a declared name (would be red): %s"
              % (ref, dupes or "NONE"),
              bool(dupes))

    # ---------------------------------------------------------------- 3
    # Nothing is removed. A stash that deletes a line carries real work and
    # must not be dropped; if any stash here deleted something, the verdict
    # above is wrong and this fails loudly instead of quietly dropping it.
    removes = [(ref, len(removed_lines(ref))) for ref, _ in live
               if removed_lines(ref)]
    check("no stash removes a line (%s)" % (removes or "none"),
          not removes)

    # ---------------------------------------------------------------- 4
    # Control: the reader must be able to see a real declaration, or every
    # case above is vacuously true on a broken regex. `hairline` is declared
    # at HEAD; if the regex stopped matching, case 2 would pass by finding
    # no duplicates at all.
    check("control: reader finds the committed declaration %r"
          % head_decls[:1],
          "hairline" in head_decls and head_decls.count("hairline") == 1)

    # ---------------------------------------------------------------- 5
    # The verdict the loop actually needs. It fails the moment a stash lands
    # that is NOT droppable, so the five-tick escalation cannot restart on
    # real work that somebody would have to notice by hand.
    #
    # `all([])` is True, so with no stash present this case would have
    # printed a green line for a repo it never examined. The count it
    # reports is the number of stashes judged unresolvable, and it is
    # derived from the same predicate the case asserts -- when they
    # disagree, which they did once, the label was a lie.
    unresolvable = [ref for ref, _ in live
                    if [ln for ln in added_lines(ref)
                        if _norm(ln) and _norm(ln) not in
                        {_norm(l) for l in head.splitlines()}]]
    check("every live stash is droppable (%d unresolvable of %d)"
          % (len(unresolvable), len(live)),
          not unresolvable)

    # ---------------------------------------------------------------- 6
    # A repo with no stash is a clean repo, not a verified one. Saying so
    # is what stops the next tick from treating "6/6" as a measurement.
    check("suite examined at least one stash (%d present)"
          % len(live), bool(live))

    print("\n%d stash(es) examined: %s"
          % (len(live), ", ".join(r for r, _ in live) or "none"))
    ok = sum(results)
    print("== %d/%d ==  %s"
          % (ok, len(results),
             "ALL PASS" if all(results) else "SOME FAILED"))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
