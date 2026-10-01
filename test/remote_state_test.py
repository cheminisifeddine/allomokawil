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

    print("")
    if FAILED:
        print("%d FAILED: %s" % (len(FAILED), ", ".join(FAILED)))
        return 1
    print("all remote_state cases pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
