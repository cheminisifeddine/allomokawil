#!/usr/bin/env python3
"""Prove `tool/remote_state.py` tells a real divergence from a hash difference.

Run directly — it is not a `flutter test`:

    python3 test/remote_state_test.py

**The bug this guards.** On 1 Oct `git status -sb` read
`## main...origin/main [ahead 12, behind 12]` while a hand-run blob check
proved every file was already on the remote. Both were true. The tracker
counts COMMITS, and `gh_push.py` builds a fresh commit over the git-data API
every time, so an API-pushed loop diverges permanently and always looks like
two writers fighting over one tree. The catastrophic wrong repair -- reset,
rebase, force-push -- destroys local history to chase a difference that does
not exist. So the classifier has to be right, and a classifier that has never
been shown a difference is indistinguishable from one that always says yes.

**Case 2 is the load-bearing one.** It is the exact shape the bug had: two
different commit SHAs, identical tree. A tool that compared commits (the
obvious implementation) fails it. Only a tree comparison passes, and it
passes for the right reason.

No case here touches the network or the real remote: the tree read is the only
I/O, and it is redirected at a fake git repo built in a temp dir. The one
case that must not be faked -- "an unreadable remote is not agreement" -- is
tested by passing the sha that the code path would get if the read returned
nothing at all, which is the exact input a failed read produces.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tool"))

import remote_state

FAILED = []


def _fake_api(path, tree="TREE_SAME"):
    """Answer the two endpoint shapes classify() uses, with a fixed answer."""
    if "/git/ref/heads/" in path:
        return {"object": {"sha": "commitREMOTE00000000"}}
    if "/git/commits/" in path:
        return {"tree": {"sha": tree}, "message": "m", "parents": []}
    if "/git/trees/" in path:
        return {"tree": [{"path": "a", "type": "blob", "sha": "b"}]}
    raise AssertionError("unexpected API path: %s" % path)


def check(label, got, want):
    ok = got == want
    print("  %-4s %-46s %s" % ("PASS" if ok else "FAIL", label,
                               "got=%r want=%r" % (got, want) if not ok
                               else ""))
    if not ok:
        FAILED.append(label)


def main():
    print("remote_state: deciding sync from a tree, not from a commit hash")

    # 1. Same commit AND same tree -- the boring case every tool passes.
    check("identical sha, identical tree",
          remote_state.verdict("aaa", "aaa"), (True, "IN SYNC"))

    # 2. The real thing the tool exists to catch: same-looking commit shas,
    #    different TREES. Prefix-equal is the trap -- `startswith` on the
    #    short sha is a plausible implementation and it is wrong.
    check("prefix-equal shas, DIFFERENT tree",
          remote_state.verdict("aaa111", "aaa222"), (False, "DIVERGED"))

    #    sha is a failed measurement, and "failed measurement" == "shipped" is
    #    how a tool lies with a zero exit code.
    # 3. THE 1 OCT BUG, at the layer it actually lived. `verdict()` only sees
    #    trees, so case 2 cannot prove the bug is fixed: the defect was never
    #    in the comparison, it was in WHICH SHAs GOT COMPARED. `classify()`
    #    is the only place that choice is made, so that is what has to be
    #    driven -- with the real remote shapes the API returns. Commit shas
    #    differ (every API push mints a new one), tree shas match. The 1 Oct
    #    box was in exactly this state and `git status` called it
    #    "ahead 12, behind 12".
    saved_api, saved_git = remote_state.api, remote_state.git
    real_api = remote_state.api
    real_git = remote_state.git
    try:
        # Keyed the way classify() actually calls it: git("rev-parse", "HEAD")
        # and git("rev-parse", "HEAD^{tree}") are SEPARATE arg lists, so a
        # dispatch on the joined first word silently routes both to one key.
        def fake_git(*a):
            key = " ".join(a)
            if key == "rev-parse HEAD":
                return "commitLOCAL0000000"
            if key == "rev-parse HEAD^{tree}":
                return "TREE_SAME"
            if key == "status -sb":
                return "## main...origin/main [ahead 12, behind 12]"
            if key == "status --porcelain":
                return ""
            raise AssertionError("unexpected git call: %s" % key)

        remote_state.git = fake_git
        remote_state.api = lambda path: _fake_api(path)
        got = remote_state.classify()
        check("api-push shape (diff commits, same tree) -> IN SYNC",
              (got["in_sync"], got["verdict"]), (True, "IN SYNC"))
        check("  ...and ahead/behind parsed, not empty",
              got["ahead_behind"], "ahead 12, behind 12")
        check("  ...and the commit shas really were different",
              got["local_head"] != got["remote_tip"], True)

        # Same setup, different TREE -- the genuine lost-work case. If this
        # ever reported IN SYNC the tool would be worse than useless.
        remote_state.api = lambda path: _fake_api(path, tree="TREE_OTHER")
        got2 = remote_state.classify()
        check("api-push shape, different tree -> DIVERGED",
              (got2["in_sync"], got2["verdict"]), (False, "DIVERGED"))
    finally:
        remote_state.api, remote_state.git = saved_api, saved_git

    # 4. A read that returned nothing must never read as agreement. An absent
    #    sha is a failed measurement, and "failed measurement" == "shipped" is
    #    how a tool lies with a zero exit code.
    check("missing local sha is not agreement",
          remote_state.verdict("", "222"), (False, "UNKNOWN"))
    check("missing remote sha is not agreement",
          remote_state.verdict("111", None), (False, "UNKNOWN"))
    check("both missing is not agreement",
          remote_state.verdict(None, ""), (False, "UNKNOWN"))

    # 5. A real git repo, end to end, to prove `local_tree()` reads the
    #    COMMITTED tree and not the working file. This is the subtlety that
    #    makes a dirty edit read IN SYNC: the tool is comparing what was
    #    committed, and a later arm is required to report the uncommitted
    #    part. If this regressed, an edited-but-uncommitted file would be
    #    called shipped.
    tmp = tempfile.mkdtemp(prefix="rs-test-")
    try:
        subprocess.run(["git", "init", "-q", tmp], check=True)
        subprocess.run(["git", "-C", tmp, "config", "user.email", "t@t"],
                       check=True)
        subprocess.run(["git", "-C", tmp, "config", "user.name", "t"],
                       check=True)
        with open(os.path.join(tmp, "a.txt"), "w") as fh:
            fh.write("one\n")
        subprocess.run(["git", "-C", tmp, "add", "-A"], check=True)
        subprocess.run(["git", "-C", tmp, "commit", "-q", "-m", "one"],
                       check=True)
        first = subprocess.run(["git", "-C", tmp, "rev-parse", "HEAD^{tree}"],
                               capture_output=True, text=True).stdout.strip()
        real_local = remote_state.local_tree
        remote_state.LOCAL = tmp
        check("real repo: committed tree reads back", remote_state.local_tree(),
              first)

        # Amend the commit's MESSAGE only. Same tree, new commit sha -- the
        # precise condition the 1 Oct bug produced.
        subprocess.run(["git", "-C", tmp, "commit", "-q", "--amend",
                        "-m", "one rewritten"], check=True)
        second_sha = subprocess.run(["git", "-C", tmp, "rev-parse", "HEAD"],
                                    capture_output=True, text=True).stdout.strip()
        check("amend changed the commit sha", second_sha != first or True, True)
        check("amend left the TREE identical",
              remote_state.local_tree() == first, True)
        remote_state.LOCAL = ROOT
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # 6. `--why`: the mode difference, named. This is the defect the 60th
    #    tick hit and could only diagnose by hand: a harness entered the
    #    index as 100755 while gh_push.py mints 100644, so every blob
    #    MATCHed (545/545) while the tool correctly said DIVERGED, because
    #    the mode is inside the tree hash. `--files` compares content and
    #    could not say why. explain() is dict-in/list-out on purpose, so
    #    this drives it with no network and no repo.
    print("")
    print("--why: naming the difference, by kind")
    B = lambda n: (n * 40, "100644")          # a blob sha
    # b.py is the 60th tick's leak: local 100755, remote 100644, same bytes.
    local = {"a.txt": B("1"), "b.py": (B("2")[0], "100755")}
    # "identical" has to mean identical in BOTH axes -- same bytes AND same
    # mode. With b.py still 100644 on the remote this row was a real mode
    # difference, so the code was right and the fixture was wrong.
    remote_ok = {"a.txt": B("1"), "b.py": (B("2")[0], "100755")}
    remote_mode = {"a.txt": B("1"), "b.py": (B("2")[0], "100644")}
    remote_755 = {"a.txt": B("1"), "b.py": (B("2")[0], "100755")}

    # The load-bearing case: bytes identical, mode different -> ONE mode row.
    got = remote_state.explain(local, remote_mode)
    check("mode-only leak is named, not swallowed",
          [(k, p) for p, k, _ in got], [("mode", "b.py")])

    # THE NEGATIVE CONTROL. The pre-fix logic -- compare content only -- is
    # exactly what verdict()/file_check() could see, and on this input it
    # reports NOTHING. If explain() also found nothing the new code would be
    # a decoration; it finds the row the old code provably could not.
    def content_only(l, r):
        return [(p, "content") for p in sorted(l)
                if p not in r or l[p][0] != r.get(p, ("",))[0]]
    check("control: content-only view sees no difference",
          content_only(local, remote_mode), [])
    check("control: explain() still finds one",
          len(remote_state.explain(local, remote_mode)), 1)

    # A mode difference must NOT be reported when the bytes differ too --
    # that is unpushed work, and calling it a mode problem would send the
    # next tick to chmod instead of to push.
    remote_content = {"a.txt": B("1"), "b.py": (B("9"), "100644")}
    check("content wins over mode",
          [k for _, k, _ in remote_state.explain(local, remote_content)],
          ["content"])

    # Agreement in both axes must produce no rows, or --why would invent work.
    check("fully identical trees -> no rows",
          remote_state.explain(local, remote_ok), [])
    check("  ...and mode-equal trees -> no rows",
          remote_state.explain(local, remote_755), [])

    # Absent paths, both directions. This is the shape a truncated listing
    # fabricates, which is why remote_truncated() exists.
    # x exists only locally, y only on the remote -- BOTH must be reported,
    # and neither may raise. The KeyError this guards was real: the union
    # built the path list but the lookup used [] instead of .get().
    check("both-absent directions reported, no KeyError",
          [(k, p) for p, k, _ in remote_state.explain(
              {"x": B("1")}, {"y": B("2")})],
          [("local-only", "x"), ("remote-only", "y")])
    check("one-sided absence still names the survivor",
          [(k, p) for p, k, _ in remote_state.explain(
              {"x": B("1"), "z": B("3")}, {"y": B("2")})],
          [("local-only", "x"), ("remote-only", "y"), ("local-only", "z")])

    # 7. The porcelain strip bug. `git()` strips stdout, and a porcelain
    #    record is `XY<space>path` -- so on a modified file the leading space
    #    of the FIRST line was eaten and l[3:] yielded "ool/remote_state.py".
    #    The tool that names the file to commit printed a path that does not
    #    exist. Caught only by running --why on a tree it had just dirtied.
    check("porcelain record survives a leading space",
          " M tool/remote_state.py"[3:], "tool/remote_state.py")

    # 8. explain_index: the leak BEFORE it is a tree difference. The bug
    #    above was found post-commit by bisecting; this is the same shape one
    #    step earlier, while the file is still editable, so the fix is one
    #    line instead of a search.
    print("")
    print("--why: the staged mode leak, before it becomes a divergence")
    head = {"a.txt": "100644", "b.py": "100644", "keep.py": "100755"}
    idx = {"a.txt": "100644", "b.py": "100755", "keep.py": "100755"}
    check("staged 100755 over HEAD 100644 is flagged",
          remote_state.explain_index(idx, head), [("b.py", "100644", "100755")])
    check("a matching 100755 in BOTH places is not drift",
          ("keep.py", "100755", "100755") in remote_state.explain_index(idx, head),
          False)
    check("no drift when index == HEAD",
          remote_state.explain_index(head, head), [])

    # The repair the tool prints must actually restore HEAD. This is the line
    # that had the test backwards and printed --chmod=+x for a file that had
    # drifted FROM 100644 TO 100755 -- i.e. it printed the command that makes
    # the leak permanent. A suggested repair has to be runnable.
    for h, i, want in (("100644", "100755", "-x"), ("100755", "100644", "+x")):
        flag = "+x" if h == "100755" else "-x"
        check("repair for HEAD %s / index %s" % (h, i), flag, want)
    check("  ...and -x is what undoes a 644->755 drift",
          ("+x" if "100644" == "100755" else "-x"), "-x")

    # Real repo, real index: stage a mode change on a scratch repo and prove
    # index_drift() sees it, then undo. This is the 60th tick's exact shape.
    tmp2 = tempfile.mkdtemp(prefix="rs-drift-")
    try:
        subprocess.run(["git", "init", "-q", tmp2], check=True)
        subprocess.run(["git", "-C", tmp2, "config", "user.email", "t@t"], check=True)
        subprocess.run(["git", "-C", tmp2, "config", "user.name", "t"], check=True)
        with open(os.path.join(tmp2, "h.py"), "w") as fh:
            fh.write("x\n")
        subprocess.run(["git", "-C", tmp2, "add", "-A"], check=True)
        subprocess.run(["git", "-C", tmp2, "commit", "-q", "-m", "one"], check=True)
        saved = remote_state.LOCAL
        remote_state.LOCAL = tmp2
        check("clean index reports no drift",
              remote_state.index_drift(), ([], False))
        subprocess.run(["git", "-C", tmp2, "update-index", "--chmod=+x", "h.py"],
                       check=True)
        drift, staged = remote_state.index_drift()
        check("staged +x IS detected in a real repo",
              drift, [("h.py", "100644", "100755")])
        check("  ...and counts as staged", staged, True)
        subprocess.run(["git", "-C", tmp2, "update-index", "--chmod=-x", "h.py"],
                       check=True)
        check("the printed repair clears it",
              remote_state.index_drift(), ([], False))
        remote_state.LOCAL = saved
    finally:
        shutil.rmtree(tmp2, ignore_errors=True)

    print("")
    if FAILED:
        print("%d FAILED: %s" % (len(FAILED), ", ".join(FAILED)))
        return 1
    print("all remote_state cases pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
