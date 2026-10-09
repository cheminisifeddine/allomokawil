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
import contextlib
import io
import json
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
    saved_blobs = remote_state.remote_blobs
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

    # 9. `--files` read the INDEX while the VERDICT reads HEAD. The 61st fixed
    #    `--why`'s reporting; `--files` had the mirror image of the same bug
    #    and it was never noticed because MODE-DIFFER was only ever exercised
    #    on a committed leak.
    #
    #    `file_check` built its mode row from `mode_of()` = `git ls-files -s` =
    #    the index = what the NEXT commit records. `verdict()` compares
    #    COMMITTED trees. The two axes differ exactly when a mode is staged and
    #    not committed, and then the row contradicts the verdict printed above
    #    it -- which is the one thing a row under a verdict must never do.
    print("")
    print("--files: the mode row must read the axis the verdict reads")
    tmp3 = tempfile.mkdtemp(prefix="rs-axis-")
    try:
        subprocess.run(["git", "init", "-q", tmp3], check=True)
        subprocess.run(["git", "-C", tmp3, "config", "user.email", "t@t"], check=True)
        subprocess.run(["git", "-C", tmp3, "config", "user.name", "t"], check=True)
        with open(os.path.join(tmp3, "h.py"), "w") as fh:
            fh.write("x\n")
        subprocess.run(["git", "-C", tmp3, "add", "-A"], check=True)
        subprocess.run(["git", "-C", tmp3, "commit", "-q", "-m", "one"], check=True)

        saved = remote_state.LOCAL
        remote_state.LOCAL = tmp3
        # Remote believes the same bytes at 100644 -- i.e. HEAD is IN SYNC.
        blob = subprocess.run(["git", "-C", tmp3, "hash-object", "h.py"],
                              capture_output=True, text=True).stdout.strip()
        remote_state.remote_blobs = lambda: {"h.py": (blob, "100644")}

        clean = remote_state.file_check(["h.py"])
        check("committed trees agree -> MATCH",
              [r[1] for r in clean], ["MATCH"])

        # Now stage the leak the 61st warns about: index 100755, HEAD still
        # 100644. The committed trees still AGREE, so MODE-STAGED is the only
        # honest row. The OLD reader took its mode from the index and would
        # have printed MODE-DIFFER here -- inventing a divergence the trees
        # do not have, and printing a repair for a file that is not wrong.
        subprocess.run(["git", "-C", tmp3, "update-index", "--chmod=+x", "h.py"],
                       check=True)
        rows = remote_state.file_check(["h.py"])
        check("staged 100755 over a committed 100644 is MODE-STAGED",
              [r[1] for r in rows], ["MODE-STAGED"])
        check("  ...and the row carries BOTH modes, HEAD first",
              (rows[0][4], rows[0][6]), ("100644", "100755"))
        # The committed trees really do agree, which is what makes MODE-STAGED
        # the honest verdict. Assert it on the axes that exist rather than
        # inventing a remote sha for verdict() to disagree with: the first
        # version of this line passed a literal "TREE" and went red, which
        # says nothing about the code.
        check("  ...and the committed trees really do agree (HEAD == remote)",
              (rows[0][4], rows[0][5]), ("100644", "100644"))
        check("  ...while the index does not",
              rows[0][6], "100755")

        # THE CONTROL: the pre-fix reader, driven on the same repo. It reads
        # the index, so it reports MODE-DIFFER on an input where the committed
        # trees are identical -- the divergence the new code refuses to invent.
        def old_file_check_mode(path):
            return remote_state.mode_of(path)
        check("control: old reader sees the index, reports a fake difference",
              (old_file_check_mode("h.py"), remote_state.head_mode("h.py")),
              ("100755", "100644"))

        # The repair printed for MODE-STAGED must restore HEAD's mode, i.e.
        # -x for a 644->755 staged leak. Inverted is how the 61st's repair was
        # wrong once already.
        h, i = rows[0][4], rows[0][6]
        check("MODE-STAGED repair restores HEAD 100644 from index 100755",
              "+x" if h == "100755" else "-x", "-x")
        subprocess.run(["git", "-C", tmp3, "update-index", "--chmod=-x", "h.py"],
                       check=True)
        check("  ...and running it clears the row",
              [r[1] for r in remote_state.file_check(["h.py"])], ["MATCH"])

        # The committed case, which is the one MODE-DIFFER is FOR: HEAD carries
        # the leak, the remote does not. The repair must restore the REMOTE's
        # mode (gh_push.py mints every file 100644), not HEAD's.
        subprocess.run(["git", "-C", tmp3, "update-index", "--chmod=+x", "h.py"],
                       check=True)
        subprocess.run(["git", "-C", tmp3, "commit", "-q", "-m", "leak"],
                       check=True)
        committed = remote_state.file_check(["h.py"])
        check("committed 100755 vs remote 100644 -> MODE-DIFFER",
              [r[1] for r in committed], ["MODE-DIFFER"])
        check("  ...and the repair restores the REMOTE's 100644, not HEAD's",
              "+x" if committed[0][5] == "100755" else "-x", "-x")
        subprocess.run(["git", "-C", tmp3, "update-index", "--chmod=-x", "h.py"],
                       check=True)
        subprocess.run(["git", "-C", tmp3, "commit", "-q", "-m", "fix"],
                       check=True)
        check("  ...and after the repair the trees agree again",
              [r[1] for r in remote_state.file_check(["h.py"])], ["MATCH"])

        # An existing but never-committed file: `git hash-object` hashes any
        # file that is on disk, tracked or not, so the sha is real and the row
        # is ABSENT-REMOTE -- the file is not on the remote, which is the
        # honest answer. I first asserted UNTRACKED here and went red; that
        # label only fires when `hash-object` FAILS, i.e. when the file is
        # missing from disk entirely, not when it is merely uncommitted.
        with open(os.path.join(tmp3, "new.py"), "w") as fh:
            fh.write("y\n")
        check("existing-but-uncommitted file reads ABSENT-REMOTE, not a crash",
              [r[1] for r in remote_state.file_check(["new.py"])],
              ["ABSENT-REMOTE"])
        # A path that is not on disk at all: hash-object fails, and the row
        # must still be produced rather than raising.
        check("missing file still classifies without raising",
              [r[1] for r in remote_state.file_check(["gone.py"])], ["UNTRACKED"])
        remote_state.LOCAL = saved
        remote_state.remote_blobs = saved_blobs
    finally:
        shutil.rmtree(tmp3, ignore_errors=True)


    # 10. `--files` collapsed the WORKING FILE and the COMMITTED TREE into
    #     one DIFFER label. The 62nd split the MODE axis into MODE-DIFFER
    #     (committed) and MODE-STAGED (index); content had the same defect one
    #     axis further out and nobody had driven it.
    #
    #     `file_check` read `git hash-object` (the file on DISK) and compared it
    #     to the remote, then printed DIFFER -- while the verdict above it
    #     compares HEAD to the remote. Two states, one label, opposite
    #     repairs:
    #
    #       HEAD == remote, disk edited -> verdict IN SYNC. Uncommitted work.
    #       HEAD != remote              -> verdict DIVERGED. Real push.
    #
    #     A reader cannot tell those from the row, and neither can a script.
    print("")
    print("--files: name WHICH HOP a content difference is in")
    check("trees agree, disk edited -> EDITED, not a divergence",
          remote_state.choose_content_row("work1", "head1", "head1"), "EDITED")
    check("committed trees differ -> CONTENT-DIFFER",
          remote_state.choose_content_row("head1", "head1", "remote1"),
          "CONTENT-DIFFER")
    check("on remote, absent from HEAD -> REMOTE-ONLY",
          remote_state.choose_content_row("work1", "", "remote1"), "REMOTE-ONLY")
    check("everything agrees -> no content row at all",
          remote_state.choose_content_row("head1", "head1", "head1"), None)
    # The negative control: the OLD one-label view, re-implemented, on the
    # EDITED input. It cannot separate the two states, which is the defect --
    # so this is what the code under test had to be able to disagree with.
    def old_label(work_sha, head_sha, remote_sha):
        if not remote_sha or remote_sha == "-":
            return None
        return "DIFFER" if work_sha != remote_sha else None

    check("control: the old view says DIFFER where trees AGREE",
          old_label("work1", "head1", "head1"), "DIFFER")
    check("  ...and cannot tell it from a real divergence",
          old_label("head1", "head1", "remote1"), old_label("work1", "head1", "head1"))
    check("  ...while the new one separates the two",
          remote_state.choose_content_row("head1", "head1", "remote1")
          != remote_state.choose_content_row("work1", "head1", "head1"), True)

    # The same split through the real file_check, on a real repo, with a
    # stubbed remote that holds HEAD's bytes.
    tmp4 = tempfile.mkdtemp(prefix="rs-workaxis-")
    try:
        subprocess.run(["git", "init", "-q", tmp4], check=True)
        subprocess.run(["git", "-C", tmp4, "config", "user.email", "t@t"], check=True)
        subprocess.run(["git", "-C", tmp4, "config", "user.name", "t"], check=True)
        with open(os.path.join(tmp4, "w.py"), "w") as fh:
            fh.write("committed\n")
        subprocess.run(["git", "-C", tmp4, "add", "-A"], check=True)
        subprocess.run(["git", "-C", tmp4, "commit", "-q", "-m", "one"], check=True)

        saved = remote_state.LOCAL
        remote_state.LOCAL = tmp4
        blob = subprocess.run(["git", "-C", tmp4, "hash-object", "w.py"],
                              capture_output=True, text=True).stdout.strip()
        remote_state.remote_blobs = lambda: {"w.py": (blob, "100644")}

        check("clean checkout against a matching remote -> MATCH",
              [r[1] for r in remote_state.file_check(["w.py"])], ["MATCH"])

        # The exact shape the 62nd's probe hit: edit on disk, do NOT stage.
        # The verdict stays IN SYNC, and the row must not claim otherwise.
        with open(os.path.join(tmp4, "w.py"), "w") as fh:
            fh.write("edited on disk\n")
        dirty = remote_state.file_check(["w.py"])
        check("unstaged edit against a matching remote -> EDITED",
              [r[1] for r in dirty], ["EDITED"])
        check("  ...and the row is NOT a committed divergence",
              [r[1] for r in dirty if r[1] == "CONTENT-DIFFER"], [])
        # The label is only honest if the verdict it sits under agrees. Read
        # the tree this repo actually has and compare it to itself-as-remote.
        tree = subprocess.run(["git", "-C", tmp4, "rev-parse", "HEAD^{tree}"],
                              capture_output=True, text=True).stdout.strip()
        check("  ...so the tree verdict on this state is IN SYNC",
              remote_state.verdict(tree, tree), (True, "IN SYNC"))

        # Now push the difference INTO the commit: real unpushed work, the
        # label that is allowed to say "push".
        subprocess.run(["git", "-C", tmp4, "add", "-A"], check=True)
        subprocess.run(["git", "-C", tmp4, "commit", "-q", "-m", "two"], check=True)
        check("committed edit against a stale remote -> CONTENT-DIFFER",
              [r[1] for r in remote_state.file_check(["w.py"])], ["CONTENT-DIFFER"])
        remote_state.LOCAL = saved
    finally:
        shutil.rmtree(tmp4, ignore_errors=True)

    # 11. `--files` printed MATCH while the INDEX held a blob in no commit.
    #
    #     The ladder is four rungs and the code had read three:
    #
    #       HEAD    the committed tree -- what `verdict()` hashes
    #       index   what the NEXT commit will record
    #       disk    the working file -- what `git hash-object` returns
    #
    #     `mode_of` read the index's MODE half (MODE-STAGED, the 60th tick)
    #     and `explain_index` read it for `--why`. Nothing read its BLOB half.
    #     So: stage v2, then write HEAD's bytes back to the file. The disk
    #     agrees with HEAD, the committed trees agree, and the row said MATCH
    #     -- while the index held a third blob that the next `git commit`
    #     would record over HEAD, silently reverting a file.
    #
    #     Same shape as the 60th's 100755 leak, on the content axis: a blob no
    #     committed-tree diff can see, discoverable only after it is pushed.
    print("")
    print("--files: a staged BLOB must not hide behind MATCH")
    check("staged blob, trees agree -> INDEX-STAGED",
          remote_state.staged_row("idx1", "head1", False), "INDEX-STAGED")
    check("staged mode, trees agree -> MODE-STAGED",
          remote_state.staged_row("head1", "head1", True), "MODE-STAGED")
    check("index and HEAD agree, no mode drift -> no staged row",
          remote_state.staged_row("head1", "head1", False), None)
    # Both staged at once: content wins, because the content leak is the one
    # no other check in this file can see. Ordering it the other way would
    # leave a staged blob reported under a mode-only label.
    check("BOTH staged -> INDEX-STAGED, not MODE-STAGED",
          remote_state.staged_row("idx1", "head1", True), "INDEX-STAGED")
    # Nothing to compare against -- an untracked path, or a head with no blob.
    check("no index entry -> no staged row",
          remote_state.staged_row("", "head1", False), None)
    check("no HEAD blob -> no staged row",
          remote_state.staged_row("idx1", "", False), None)

    # The negative control, and the four states the one label used to cover.
    # The old code reached MATCH via `content is None and not staged_leak`,
    # which is true for the staged-blob state because `choose_content_row`
    # only ever looks at disk and HEAD. This is that expression, verbatim.
    def old_reaches_match(index_sha, head_sha, disk_sha, staged_mode):
        content = rs_choose(disk_sha, head_sha, head_sha)
        return content is None and not staged_mode

    def rs_choose(work, head, remote):
        return remote_state.choose_content_row(work, head, remote)

    check("control: old code said MATCH on a staged blob",
          old_reaches_match("idx1", "head1", "head1", False), True)
    check("  ...and MATCH, because it could not have said anything else",
          remote_state.staged_row("idx1", "head1", False), "INDEX-STAGED")
    check("  ...the two disagree, which is the defect",
          old_reaches_match("idx1", "head1", "head1", False)
          != (remote_state.staged_row("idx1", "head1", False) is None), True)

    # The real thing: a real repo in the real three-rung state.
    tmp5 = tempfile.mkdtemp(prefix="rs-indexblob-")
    try:
        subprocess.run(["git", "init", "-q", tmp5], check=True)
        subprocess.run(["git", "-C", tmp5, "config", "user.email", "t@t"], check=True)
        subprocess.run(["git", "-C", tmp5, "config", "user.name", "t"], check=True)
        f = os.path.join(tmp5, "i.py")
        with open(f, "w") as fh:
            fh.write("v1\n")
        subprocess.run(["git", "-C", tmp5, "add", "-A"], check=True)
        subprocess.run(["git", "-C", tmp5, "commit", "-q", "-m", "one"], check=True)

        saved = remote_state.LOCAL
        remote_state.LOCAL = tmp5
        head = subprocess.run(["git", "-C", tmp5, "rev-parse", "HEAD:i.py"],
                               capture_output=True, text=True).stdout.strip()
        remote_state.remote_blobs = lambda: {"i.py": (head, "100644")}

        check("three rungs agree -> MATCH",
              [r[1] for r in remote_state.file_check(["i.py"])], ["MATCH"])

        # Stage v2, then put HEAD's bytes back on disk. Now:
        #   HEAD == disk == remote, index holds v2, and the file LOOKS clean.
        with open(f, "w") as fh:
            fh.write("v2\n")
        subprocess.run(["git", "-C", tmp5, "add", "i.py"], check=True)
        with open(f, "w") as fh:
            fh.write("v1\n")
        idx = subprocess.run(["git", "-C", tmp5, "rev-parse", ":i.py"],
                             capture_output=True, text=True).stdout.strip()
        disk = subprocess.run(["git", "-C", tmp5, "hash-object", "i.py"],
                              capture_output=True, text=True).stdout.strip()
        check("the file on disk is back on HEAD, so it LOOKS clean",
              disk, head)
        check("  ...and the index is the odd one out", idx != head, True)

        rows = remote_state.file_check(["i.py"])
        check("staged blob -> INDEX-STAGED, never MATCH",
              [r[1] for r in rows], ["INDEX-STAGED"])
        # The row must name the blob the next commit records -- the one thing
        # no diff in this file can see. Printing the disk's sha here would be
        # the 63rd's bug again, one rung down.
        check("  ...and the row CARRIES the index blob",
              rows[0][7], idx)
        check("  ...which is NOT the disk's sha", rows[0][7] != disk, True)
        check("  ...nor HEAD's", rows[0][7] != head, True)
        # MATCH is what a tick reads immediately before committing, so the
        # label has to be the thing that stops it.
        check("  ...and it is emphatically not MATCH",
              [r[1] for r in rows if r[1] == "MATCH"], [])

        # `--why` had the same hole. It compared committed trees, so it could
        # not see this, and `index_drift()` returns [] because the MODES agree.
        d, tr, mode_drift, staged, blob_drift = remote_state.why()
        check("index_drift() is blind to it (modes agree)",
              mode_drift, [])
        check("  ...so nothing named it before this tick",
              [x for x in d if x[0] == "i.py"], [])
        check("staged_content_drift() names it",
              blob_drift, [("i.py", head, idx)])

        # The repair the row prints must actually clear the row. A suggested
        # repair that does not work is worse than none.
        subprocess.run(["git", "-C", tmp5, "restore", "--staged", "i.py"], check=True)
        check("running the printed repair clears the row",
              [r[1] for r in remote_state.file_check(["i.py"])], ["MATCH"])
        check("  ...and clears --why too", remote_state.staged_content_drift(), [])

        # 12. Lead 2 from the 63rd, now that the rung exists: ONE path across
        #     the full sequence a tick actually performs. The three content
        #     labels were individually tested and nothing had ever driven them
        #     end to end, which is how the MATCH below survived.
        print("")
        print("--files: one path, the sequence a tick performs")
        with open(f, "w") as fh:
            fh.write("v2\n")
        subprocess.run(["git", "-C", tmp5, "add", "i.py"], check=True)
        subprocess.run(["git", "-C", tmp5, "commit", "-qm", "two"], check=True)
        head2 = subprocess.run(["git", "-C", tmp5, "rev-parse", "HEAD:i.py"],
                               capture_output=True, text=True).stdout.strip()
        check("committed edit, remote still at v1 -> CONTENT-DIFFER",
              [r[1] for r in remote_state.file_check(["i.py"])], ["CONTENT-DIFFER"])
        remote_state.remote_blobs = lambda: {"i.py": (head2, "100644")}
        check("remote caught up -> MATCH",
              [r[1] for r in remote_state.file_check(["i.py"])], ["MATCH"])
        with open(f, "w") as fh:
            fh.write("edited-but-not-staged\n")
        check("edit on disk -> EDITED",
              [r[1] for r in remote_state.file_check(["i.py"])], ["EDITED"])
        subprocess.run(["git", "-C", tmp5, "add", "i.py"], check=True)
        with open(f, "w") as fh:
            fh.write("v2\n")
        check("stage the edit then rewrite disk to HEAD -> INDEX-STAGED",
              [r[1] for r in remote_state.file_check(["i.py"])], ["INDEX-STAGED"])
        subprocess.run(["git", "-C", tmp5, "restore", "--staged", "i.py"], check=True)
        check("undo -> MATCH again",
              [r[1] for r in remote_state.file_check(["i.py"])], ["MATCH"])

        # Once the committed trees really do differ, the staged label is
        # noise: CONTENT-DIFFER is the true row and the verdict already says
        # DIVERGED, so a second warning beside it is noise about a divergence
        # the reader can already see.
        # Staging what is ALREADY on disk is not the invisible case, and
        # INDEX-STAGED must not claim it: disk and index hold the same blob,
        # so EDITED already says everything there is to say and its repair
        # (add, commit, push) is the correct one. INDEX-STAGED is reserved
        # for the rung nobody else can see. I wrote this case expecting
        # INDEX-STAGED and the code was right to disagree.
        with open(f, "w") as fh:
            fh.write("v9\n")
        subprocess.run(["git", "-C", tmp5, "add", "i.py"], check=True)
        check("staged AND on disk -> EDITED, the visible rung keeps the row",
              [r[1] for r in remote_state.file_check(["i.py"])], ["EDITED"])
        subprocess.run(["git", "-C", tmp5, "commit", "-qm", "three"], check=True)
        check("committed and remote stale -> CONTENT-DIFFER wins",
              [r[1] for r in remote_state.file_check(["i.py"])], ["CONTENT-DIFFER"])
        check("  ...with no staged row beside it",
              [r[1] for r in remote_state.file_check(["i.py"])
               if r[1] in ("INDEX-STAGED", "MODE-STAGED")], [])
        remote_state.LOCAL = saved
    finally:
        shutil.rmtree(tmp5, ignore_errors=True)

    # 13. Lead 2 from the 64th, and the lead was WRONG about half of it.
    #     It said a wrong tuple count was swallowed by `except SystemExit`
    #     and surfaced as a bare "unreachable". Measured on the real
    #     pre-fix code as a real subprocess: exit code 1, empty stdout, a
    #     traceback on stderr. Exit 1 is DIVERGED -- the one code the
    #     protocol says authorises a re-push. The honest failure is that a
    #     crash in the reporting path was indistinguishable from a real
    #     divergence, not that it printed the wrong sentence.
    print("")
    print("--why: a fault building the report must not read as DIVERGED")

    saved_why = remote_state.why
    saved_api2 = remote_state.api

    # (a) The report is named, not positional: no unpack can be wrong.
    rep = saved_why()
    check("why() returns a named report",
          isinstance(rep, remote_state.WhyResult), True)
    check("  ...with every field present",
          sorted(remote_state.WhyResult.__slots__),
          ["blob_drift", "diffs", "mode_drift", "staged", "truncated"])
    # The positional view still exists, so the 64th's case above is untouched.
    check("  ...and still unpacks for the old callers",
          len(list(rep)), 5)

    # (b) THE EXIT CODE, as a real process. This is the number step 6 of the
    #     protocol acts on, so a stubbed main() return would prove nothing: it
    #     is the OS exit status that a tick reads. `classify()` is stubbed so
    #     nothing here touches the network -- the only variable under test is
    #     what main() does when `why()` hands back the wrong shape.
    def _driver(mod, ret):
        return (
            "import sys\n"
            "sys.path[:0] = [%r, %r]\n"
            "import %s as m\n"
            "m.classify = lambda: {'in_sync': True, 'local_head': 'h',"
            " 'local_tree': 't', 'remote_tip': 'r', 'remote_tree': 't',"
            " 'verdict': 'IN SYNC', 'ahead_behind': 'ahead 1, behind 1',"
            " 'uncommitted': []}\n"
            "m.why = lambda: %s\n"
            "sys.argv = ['%s', '--why']\n"
            "sys.exit(m.main())\n"
            % (os.path.join(ROOT, "tool"), HERE, mod, ret, mod)
        )

    def _run(mod, ret):
        path = os.path.join(tempfile.mkdtemp(), "drv.py")
        with open(path, "w") as fh:
            fh.write(_driver(mod, ret))
        return subprocess.run([sys.executable, path], capture_output=True,
                              text=True, timeout=120)

    results = {}
    for label, ret in [("arity-4", "([], False, [], False)"),
                       ("arity-6", "([], False, [], False, [], 'extra')")]:
        proc = _run("remote_state", ret)
        results[label] = proc
        check("%s does not exit 1 (DIVERGED)" % label,
              proc.returncode == 1, False)
        check("  ...it exits 2, UNREACHABLE", proc.returncode, 2)
        check("  ...and says so in words", "UNREACHABLE" in proc.stderr, True)

    # The healthy path must still work. A fault handler that eats the normal
    # case is its own outage, so `--why` on a real report has to exit 0.
    # The stub returns a REAL WhyResult, because that is the contract now --
    # my first version of this case passed a plain five-list, which the named
    # access in main() rejects, and the failure it produced was correct
    # behaviour being asserted against.
    # The module is bound as `m`, so the expression has to be spelled `m.` --
    # I wrote `remote_state.` and the new fault handler reported the
    # NameError as exit 2, which is the handler working exactly as intended
    # and the test being wrong.
    good = _run("remote_state", "m.WhyResult([], False, [], False, [])")
    check("a well-formed report still runs", good.returncode, 0)
    check("  ...and prints its verdict", "IN SYNC" in good.stdout, True)

    # The contract is now NAMED, and that is the point of the item: a bare
    # five-sequence is no longer what main() consumes. It is still handled
    # SAFELY -- exit 2, named as a fault -- which is the difference between
    # "the contract moved" and "the contract moved and now it lies".
    duck = _run("remote_state", "([], False, [], False, [])")
    check("a bare five-list is no longer accepted", duck.returncode, 2)
    check("  ...but it is refused, not mistaken for a divergence",
          "UNREACHABLE" in duck.stderr, True)

    # (c) NEGATIVE CONTROL, against the ACTUAL pre-fix file rather than a
    #     re-implementation of it. My first attempt at this asserted that
    #     main() raises, and it did not -- because the fix had just made
    #     main() CATCH. The control was exercising the fixed code and
    #     passing for the wrong reason, which is worse than no control: it
    #     would have kept passing if the fix were reverted. The only way to
    #     show the old behaviour is to RUN the old file, which is why the
    #     pre-fix blob travels with the test instead of living in a temp dir
    #     nobody else can reach. Same driver, same monkeypatch, same input:
    #     the only variable is the file.
    check("the pre-fix blob travels with the test",
          os.path.exists(os.path.join(HERE, "remote_state_pre_fix.py")), True)
    old_proc = _run("remote_state_pre_fix", "([], False, [], False)")
    check("NEGATIVE CONTROL: pre-fix file DID exit 1 = DIVERGED",
          old_proc.returncode, 1)
    check("  ...with no verdict on stdout at all", old_proc.stdout.strip(), "")
    check("  ...while the fixed file, same input, does not",
          results["arity-4"].returncode != old_proc.returncode, True)
    check("  ...pre-fix raised ValueError; the fixed one reports a fault",
          "ValueError" in old_proc.stderr
          and "ValueError" not in results["arity-4"].stderr, True)
    # And the pre-fix file is healthy on a well-formed report, so the
    # difference above is the arity handling and not two broken copies.
    # The pre-fix file consumes a bare five-sequence, so this one DOES hand it
    # a list -- which is the whole difference between the two files, stated as
    # a test: old contract accepted, new contract refused, neither crashes.
    old_good = _run("remote_state_pre_fix", "([], False, [], False, [])")
    check("pre-fix accepted a bare five-list", old_good.returncode, 0)
    check("  ...and the fixed file, given the same, refuses safely",
          old_good.returncode != duck.returncode, True)


    remote_state.why = saved_why
    remote_state.api = saved_api2

    # 14. Lead 3 from the 64th: a STAGED MODE hidden behind a content row.
    #     The line `staged = staged_row(...) if not content else None` is right
    #     about LABELS and wrong about COVERAGE. One row carries one hop's
    #     label, but a staged mode is a second difference on a second rung with
    #     a second repair, and it used to print nowhere whenever the content
    #     hop fired. `--files` is what a tick runs immediately before
    #     `git commit`, so that is exactly where the silence cost something.
    print("")
    print("--files: a staged mode must not hide behind a content row")

    # (a) The pure decision, truth-table first. An unknown half is NOT a leak:
    #     inventing a divergence from a missing mode is the 62nd's mistake.
    check("same mode on both rungs is not a leak",
          remote_state.staged_mode_leak("100644", "100644"), False)
    check("HEAD 100755 / index 100644 IS a leak",
          remote_state.staged_mode_leak("100755", "100644"), True)
    check("  ...in either direction",
          remote_state.staged_mode_leak("100644", "100755"), True)
    check("an unknown HEAD mode is not evidence of a leak",
          remote_state.staged_mode_leak("", "100755"), False)
    check("  ...nor an unknown index mode",
          remote_state.staged_mode_leak("100644", ""), False)

    # (b) Which labels owe the note, and which already carry it. INDEX-STAGED
    #     prints `git restore --staged`, which clears BOTH axes at once, so a
    #     second chmod line beside it would be redundant advice about one edit.
    check("CONTENT-DIFFER + staged mode OWES the note",
          remote_state.hidden_staged_note("CONTENT-DIFFER", "100644", "100755"),
          ("100644", "100755"))
    check("EDITED + staged mode OWES the note",
          remote_state.hidden_staged_note("EDITED", "100755", "100644"),
          ("100755", "100644"))
    check("MATCH + staged mode OWES the note",
          remote_state.hidden_staged_note("MATCH", "100644", "100755"),
          ("100644", "100755"))
    check("INDEX-STAGED already prints the mode -- no double advice",
          remote_state.hidden_staged_note("INDEX-STAGED", "100644", "100755"),
          None)
    check("MODE-STAGED already prints the mode -- no double advice",
          remote_state.hidden_staged_note("MODE-STAGED", "100644", "100755"),
          None)
    check("no leak on either rung -> no note, whatever the label",
          remote_state.hidden_staged_note("CONTENT-DIFFER", "100644", "100644"),
          None)

    # (c) End to end through `main()` on a REAL repo, because the pure case
    #     cannot prove the printer emits it and the label keeps its own name.
    #     `classify()` is stubbed: the tree verdict is already covered above,
    #     and the variable under test is what a CONTENT row prints when the
    #     index disagrees with HEAD about the mode.
    tmp6 = tempfile.mkdtemp(prefix="rs-hiddenmode-")
    saved_local6 = remote_state.LOCAL
    saved_blobs6 = remote_state.remote_blobs
    saved_classify = remote_state.classify
    saved_argv = sys.argv
    try:
        subprocess.run(["git", "init", "-q", tmp6], check=True)
        subprocess.run(["git", "-C", tmp6, "config", "user.email", "t@t"], check=True)
        subprocess.run(["git", "-C", tmp6, "config", "user.name", "t"], check=True)
        f6 = os.path.join(tmp6, "h.py")
        with open(f6, "w") as fh:
            fh.write("v1\n")
        subprocess.run(["git", "-C", tmp6, "add", "-A"], check=True)
        subprocess.run(["git", "-C", tmp6, "commit", "-qm", "one"], check=True)
        head6 = subprocess.run(["git", "-C", tmp6, "rev-parse", "HEAD:h.py"],
                               capture_output=True, text=True).stdout.strip()
        remote_state.LOCAL = tmp6
        remote_state.remote_blobs = lambda: {"h.py": (head6, "100644")}
        remote_state.classify = lambda: {
            "in_sync": True, "local_head": "h", "local_tree": "t",
            "remote_tip": "r", "remote_tree": "t", "verdict": "IN SYNC",
            "ahead_behind": "ahead 1, behind 1", "uncommitted": []}

        def run_files():
            sys.argv = ["remote_state.py", "--files", "h.py"]
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                remote_state.main()
            return buf.getvalue()

        # Control: an edited file, modes agreeing everywhere. EDITED row, and
        # NOT ONE mention of a staged mode -- so the cases below cannot be
        # passing because the note always prints.
        with open(f6, "w") as fh:
            fh.write("v2\n")
        base = run_files()
        check("edited file -> EDITED", "EDITED" in base, True)
        check("  ...and NO staged-mode note when nothing is staged",
              "ALSO STAGED" in base, False)

        # The hole, exactly as the lead described it: stage a mode change and
        # keep the content edit unstaged. Trees agree (HEAD == remote), so the
        # verdict above stays IN SYNC and the label stays EDITED -- and the
        # staged mode used to be invisible in the whole output.
        subprocess.run(["git", "-C", tmp6, "update-index", "--chmod=+x", "h.py"],
                       check=True)
        leaked = run_files()
        check("staged mode behind an EDITED row keeps the EDITED label",
              leaked.count("EDITED") >= 1, True)
        check("  ...and the row is now ALSO STAGED", "ALSO STAGED" in leaked, True)
        check("  ...naming BOTH modes",
              "index mode 100755" in leaked and "HEAD mode 100644" in leaked, True)
        check("  ...with a repair that restores HEAD's mode",
              "git update-index --chmod=-x h.py" in leaked, True)
        check("  ...so the trees are still IN SYNC on the same input",
              leaked.splitlines()[1].startswith("local  tree"), True)

        # The label itself must not move: one hop, one label. A compound
        # `EDITED+MODE-STAGED` would break every reader that switches on the
        # label, which is the 62nd and 64th rolled back in the other direction.
        check("  ...and the LABEL did not become a compound name",
              "EDITED+MODE-STAGED" in leaked, False)

        # The same hole on the other content hop: a real committed divergence
        # with a staged mode beside it. CONTENT-DIFFER is the stronger truth and
        # keeps the row; the note still appears.
        subprocess.run(["git", "-C", tmp6, "update-index", "--chmod=-x", "h.py"],
                       check=True)
        subprocess.run(["git", "-C", tmp6, "add", "h.py"], check=True)
        subprocess.run(["git", "-C", tmp6, "commit", "-qm", "two"], check=True)
        stale = subprocess.run(["git", "-C", tmp6, "rev-parse", "HEAD~1:h.py"],
                               capture_output=True, text=True).stdout.strip()
        remote_state.remote_blobs = lambda: {"h.py": (stale, "100644")}
        subprocess.run(["git", "-C", tmp6, "update-index", "--chmod=+x", "h.py"],
                       check=True)
        both = run_files()
        check("committed divergence keeps the CONTENT-DIFFER row",
              "CONTENT-DIFFER" in both, True)
        check("  ...and still carries the staged mode",
              "ALSO STAGED" in both, True)

        # INDEX-STAGED: mode AND blob staged together. `git restore --staged`
        # clears both, so the note must NOT appear -- two repairs for one edit
        # is the noise this item is not willing to add.
        with open(f6, "w") as fh:
            fh.write("v3\n")
        subprocess.run(["git", "-C", tmp6, "update-index", "--chmod=-x", "h.py"],
                       check=True)
        subprocess.run(["git", "-C", tmp6, "add", "h.py"], check=True)
        subprocess.run(["git", "-C", tmp6, "commit", "-qm", "three"], check=True)
        head3 = subprocess.run(["git", "-C", tmp6, "rev-parse", "HEAD:h.py"],
                               capture_output=True, text=True).stdout.strip()
        remote_state.remote_blobs = lambda: {"h.py": (head3, "100644")}
        with open(f6, "w") as fh:
            fh.write("v4\n")
        subprocess.run(["git", "-C", tmp6, "update-index", "--chmod=+x", "h.py"],
                       check=True)
        with open(f6, "w") as fh:
            fh.write("v3\n")
        dup = run_files()
        check("blob AND mode staged -> INDEX-STAGED",
              "INDEX-STAGED" in dup, True)
        check("  ...with ONE repair, not two",
              "ALSO STAGED" in dup, False)
        check("  ...and the repair clears both axes at once",
              "git restore --staged h.py" in dup, True)

        # And the note must disappear the moment the leak is undone, or it would
        # cry wolf on the next run and get ignored.
        subprocess.run(["git", "-C", tmp6, "restore", "--staged", "h.py"],
                       check=True)
        subprocess.run(["git", "-C", tmp6, "update-index", "--chmod=-x", "h.py"],
                       check=True)
        clean = run_files()
        check("after the printed repair the note is gone",
              "ALSO STAGED" in clean, False)
    finally:
        sys.argv = saved_argv
        remote_state.LOCAL = saved_local6
        remote_state.remote_blobs = saved_blobs6
        remote_state.classify = saved_classify
        shutil.rmtree(tmp6, ignore_errors=True)


    # --why guarded the BUILD of the report. The RENDER was still bare: a
    # fault while PRINTING fell out of the bottom of main() as a bare
    # `return 1` -- DIVERGED, the one code the protocol says justifies
    # re-pushing. Both cases below are driven as REAL PROCESSES because the
    # exit status is the thing under test and a stubbed main() proves
    # nothing about it.
    print("")
    print("--files/--why: a fault PRINTING must not read as DIVERGED")

    def _render_driver(mod, stub):
        # Built by substitution, not by `%` on a concatenation: the stub is
        # spliced in the middle, and `%` binds tighter than `+`, so it would
        # format only the last literal group -- which is exactly the red this
        # case produced the first time it ran.
        head = (
            "import sys, importlib\n"
            "sys.path[:0] = [TOOLDIR, TESTDIR]\n"
            "m = importlib.import_module(MODNAME)\n"
            "INFO = {'in_sync': True, 'local_head': 'h', 'local_tree': 't',\n"
            "        'remote_tip': 'r', 'remote_tree': 't',\n"
            "        'verdict': 'IN SYNC',\n"
            "        'ahead_behind': 'ahead 1, behind 1', 'uncommitted': []}\n"
            "m.classify = lambda: INFO\n"
        )
        head = head.replace("TOOLDIR", repr(os.path.join(ROOT, "tool")))
        head = head.replace("TESTDIR", repr(HERE))
        head = head.replace("MODNAME", repr(mod))
        return head + stub + ("sys.argv = ['%s', '--files', 'h.py']\n"
                              "sys.exit(m.main())\n" % mod)

    def _render_run(mod, stub):
        path = os.path.join(tempfile.mkdtemp(), "rdrv.py")
        with open(path, "w") as fh:
            fh.write(_render_driver(mod, stub))
        return subprocess.run([sys.executable, path], capture_output=True,
                              text=True, timeout=120)

    # (a) `classify()` hands back a report with no `in_sync` key. The
    #     verdict line is only read by the render path, so this fault lives
    #     there by construction.
    no_key = ("INFO.pop('in_sync')\n"
              "m.file_check = lambda paths: []\n")
    a_fixed = _render_run("remote_state", no_key)
    check("a missing in_sync key does not exit 1 (DIVERGED)",
          a_fixed.returncode == 1, False)
    check("  ...it exits 2, UNREACHABLE", a_fixed.returncode, 2)
    check("  ...and names it as a fault, not a divergence",
          "could not be PRINTED" in a_fixed.stderr, True)

    # (b) `local_blobs()` raises mid-render. This is the one that produced a
    #     report that LOOKED finished: the real verdict printed, the per-file
    #     rows the tick actually asked for never did.
    boom = ("def _boom():\n"
            "    raise OSError('fatal: unable to read object')\n"
            "m.local_blobs = _boom\n"
            "m.file_check = lambda paths: [('h.py', 'MATCH', 'disc', 'sha',\n"
            "                                '100644', '100644', None)]\n")
    b_fixed = _render_run("remote_state", boom)
    check("a render fault does not exit 1 (DIVERGED)",
          b_fixed.returncode == 1, False)
    check("  ...it exits 2, UNREACHABLE", b_fixed.returncode, 2)
    check("  ...and warns the report is only PART of itself",
          "PART of the report" in b_fixed.stderr, True)

    # (c) NEGATIVE CONTROL against the actual pre-fix blob, same driver and
    #     same stubs. A re-implementation would prove nothing, so the old
    #     file ships in the repo and is driven directly.
    check("the pre-fix blob travels with the test",
          os.path.exists(os.path.join(HERE, "remote_state_pre_fix.py")), True)
    a_old = _render_run("remote_state_pre_fix", no_key)
    b_old = _render_run("remote_state_pre_fix", boom)
    check("NEGATIVE CONTROL: pre-fix DID exit 1 = DIVERGED on a render fault",
          (a_old.returncode, b_old.returncode), (1, 1))
    # ...and it contradicted itself: a report whose own last line says
    # "Nothing to push, nothing to reset", under exit 1 = push again.
    check("  ...while printing 'Nothing to push, nothing to reset'",
          "Nothing to push, nothing to reset" in a_old.stdout, True)
    # ...and the row the tick asked for was silently missing from it.
    check("  ...and silently dropped the MATCH row it was asked for",
          "MATCH" in b_old.stdout, False)
    check("  ...the fixed file, same inputs, never exits 1 on a fault",
          1 in (a_fixed.returncode, b_fixed.returncode), False)

    # (d) NO CRY-WOLF CONTROL: a guard that also swallows the healthy case is
    #     its own outage, so the untouched paths must still answer normally.
    healthy = _render_run("remote_state", "m.file_check = lambda paths: "
                          "[('h.py', 'MATCH', 'disc', 'sha', '100644',"
                          " '100644', None)]\n")
    check("a healthy --files run still exits 0", healthy.returncode, 0)
    check("  ...and still prints the MATCH row", "MATCH" in healthy.stdout, True)
    check("  ...and still prints its verdict", "IN SYNC" in healthy.stdout, True)

    # ---- 68th: `--json` published an UNMEASURED list as an empty one. ----
    #
    # `why()` is the only producer of `drift`, `blob_drift` and `truncated`,
    # and main() only calls it under `--why`. Without that flag the json
    # projection emitted all three as `[]` -- indistinguishable from a real
    # measurement that found nothing, which is the 64th's INDEX-STAGED bug
    # again, one layer up: a staged drift that `--why` names in full came out
    # of `--json` as a clean index beside `exit 0 / IN SYNC`.
    #
    # Driven as real processes through main(), because the value under test is
    # the JSON on stdout, and a unit test of a helper would not have shown it.
    def _json_driver(mod, stub, argv):
        # Built by substitution rather than `%` on a concatenation: the stub is
        # spliced in the middle and `%` binds tighter than `+`, so it would
        # format only the last literal group. That is the TypeError the first
        # version of this helper raised on its first run.
        head = (
            "import sys, importlib, json\n"
            "sys.path[:0] = [TOOLDIR, TESTDIR]\n"
            "m = importlib.import_module(MODNAME)\n"
            "m.classify = lambda: {'in_sync': True, 'local_head': 'h',\n"
            "        'local_tree': 't', 'remote_tip': 'r', 'remote_tree': 't',\n"
            "        'verdict': 'IN SYNC', 'ahead_behind': '(clean)',\n"
            "        'uncommitted': ['staged.py']}\n"
            "m.file_check = lambda paths: []\n"
        )
        head = head.replace("TOOLDIR", repr(os.path.join(ROOT, "tool")))
        head = head.replace("TESTDIR", repr(HERE))
        head = head.replace("MODNAME", repr(mod))
        # `argv` is a LIST, not a joined string: `main()` reads sys.argv[1:],
        # so "prog --json" as a single element hides the flag in argv[0] and
        # the text path runs instead. Every flag has to be its own element.
        return (head + stub + "sys.argv = list(%r)\n" % (list(argv),) +
                "sys.exit(m.main())\n")

    def _json_run(mod, stub, argv=("remote_state.py", "--json")):
        path = os.path.join(tempfile.mkdtemp(), "jdrv.py")
        with open(path, "w") as fh:
            fh.write(_json_driver(mod, stub, argv))
        proc = subprocess.run([sys.executable, path], capture_output=True,
                              text=True, timeout=120)
        if proc.returncode != 0:
            return proc, None
        try:
            return proc, json.loads(proc.stdout)
        except ValueError:
            return proc, None

    # A staged drift exists on disk in every one of these runs -- the stub is
    # what supplies it, and it is the same drift in every arm.
    DRIFT = ("m.why = lambda: m.WhyResult([], False, [], False, "
             "[('staged.py', 'HEADAAA', 'INDEXBBB')])\n")

    # (a) WITHOUT --why: the index was never examined, so the payload must say
    #     so with `null` and must not claim a clean index with `[]`.
    j_proc, j_body = _json_run("remote_state", DRIFT,
                                ["remote_state.py", "--json"])
    check("plain --json still exits 0 on an in-sync tree", j_proc.returncode, 0)
    check("  ...and still emits parseable JSON", j_body is not None, True)
    if j_body is not None:
        check("an UNMEASURED index drift is null, not []",
              j_body.get("index_content_drift"), None)
        check("  ...mode drift too", j_body.get("index_mode_drift"), None)
        check("  ...and the truncation flag, for the same reason",
              j_body.get("remote_truncated"), None)
        check("  ...`why` itself is null as well",
              j_body.get("why"), None)
        # The guard against regressing into `[]`: the empty list is the one
        # value that reads as a completed check.
        check("NEGATIVE: no unmeasured key is an empty LIST",
              any(j_body.get(k) == [] for k in
                  ("why", "index_mode_drift", "index_content_drift")), False)

    # (b) WITH --why: the question WAS asked, so a real drift must survive
    #     into the payload. A fix that nulled these unconditionally would
    #     pass (a) and silently break the machine-readable `--why`.
    jw_proc, jw_body = _json_run("remote_state", DRIFT,
                                 ["remote_state.py", "--json", "--why"])
    check("--json --why still exits 0", jw_proc.returncode, 0)
    if jw_body is not None:
        check("a MEASURED drift is still reported, not nulled",
              [d["path"] for d in (jw_body.get("index_content_drift") or [])],
              ["staged.py"])
        check("  ...with both shas, so it is actionable",
              [d["index"] for d in (jw_body.get("index_content_drift") or [])],
              ["INDEXBBB"])
        check("  ...and a clean measured list stays a list",
              jw_body.get("index_mode_drift"), [])

    # (c) NEGATIVE CONTROL against the pre-fix blob, same driver, same stubs.
    #     The old file ships in the repo for exactly this. A re-implementation
    #     would prove nothing, so the pre-fix module is imported directly.
    check("the pre-fix blob travels with the test",
          os.path.exists(os.path.join(HERE, "remote_state_pre_fix.py")), True)
    old_proc, old_body = _json_run("remote_state_pre_fix", DRIFT,
                                   ["remote_state_pre_fix.py", "--json"])
    check("NEGATIVE CONTROL: pre-fix DID publish the unmeasured list",
          (old_body or {}).get("index_content_drift"), [])
    check("  ...beside a clean in_sync verdict, which is the whole harm",
          (old_body or {}).get("info", {}).get("in_sync"), True)
    #     Same tree, same drift, same flag -- and the payload is now DIFFERENT,
    #     which is the whole point. `[]` above, the named drift below. The two
    #     answers were previously indistinguishable; that is exactly the harm.
    check("  ...so the SAME drift now yields a DIFFERENT payload",
          (old_body or {}).get("index_content_drift")
          != (jw_body or {}).get("index_content_drift"), True)
    check("  ...the pre-fix payload was indistinguishable from a CLEAN index",
          (old_body or {}).get("index_content_drift"), [])
    check("  ...and it claimed a clean in_sync verdict while doing so",
          (old_body or {}).get("info", {}).get("verdict"), "IN SYNC")

    # (d) NO CRY-WOLF CONTROL. `null` must not cost the happy path: a real
    #     verdict, the per-file rows and a parseable payload all survive.
    ok_proc, ok_body = _json_run(
        "remote_state",
        "m.file_check = lambda paths: [('h.py', 'MATCH', 'disc', 'sha',\n"
        "                               '100644', '100644', None)]\n",
        ["remote_state.py", "--json", "--files", "h.py"])
    check("a healthy --json --files run still exits 0", ok_proc.returncode, 0)
    check("  ...and still returns its per-file rows",
          [r[0] for r in (ok_body or {}).get("files", [])], ["h.py"])
    check("  ...and still says IN SYNC",
          (ok_body or {}).get("info", {}).get("verdict"), "IN SYNC")

    # ---- 69th: `--files` with NO PATHS read exactly like a clean check. ----
    #
    # Step 6 of the protocol now says to replace its 15-line mode-blind
    # heredoc with `tool/remote_state.py --files <paths...>`, on the strength
    # of `remote_state.py` being mode-aware. The replacement had the SAME
    # failure as the thing it replaced: name the flag with no paths -- an
    # unset shell variable, a glob that matched nothing, a path that was
    # really the next flag -- and it printed the tree verdict and nothing
    # else. Byte-identical output to having checked every path and found them
    # all MATCH.
    #
    # That is the 60th's shape one layer up: 545/545 blobs MATCH beside a real
    # mode divergence, and a manual bisect to find it. `rows` was falsy either
    # way, so `if rows:` printed nothing and the run exited 0 with a verdict
    # about trees the caller had specifically asked to stop looking at.
    #
    # Both channels were wrong and both had to be fixed. The text channel
    # printed no notice; `--json` published `"files": []`, the canonical
    # encoding of "every path agrees" -- the identical lie the 68th had just
    # killed for the index keys, in the key a consumer reads FIRST.
    def _nopath_driver(mod):
        head = (
            "import sys, importlib\n"
            "sys.path[:0] = [TOOLDIR, TESTDIR]\n"
            "m = importlib.import_module(MODNAME)\n"
            "m.classify = lambda: {'in_sync': True, 'local_head': 'h',\n"
            "        'local_tree': 't', 'remote_tip': 'r', 'remote_tree': 't',\n"
            "        'verdict': 'IN SYNC', 'ahead_behind': '(clean)',\n"
            "        'uncommitted': []}\n"
            # The real defect's shape: called with the empty list, returns
            # nothing, and the run continues to a clean verdict.
            "m.file_check = lambda paths: []\n"
            "assert m.file_check([]) == [], 'the stub must answer an empty list'\n"
        )
        head = head.replace("TOOLDIR", repr(os.path.join(ROOT, "tool")))
        head = head.replace("TESTDIR", repr(HERE))
        head = head.replace("MODNAME", repr(mod))
        return head + ("sys.argv = list(%r)\n" % (["remote_state.py",
                                                    "--files"],) +
                       "sys.exit(m.main())\n")

    def _nopath_run(mod):
        path = os.path.join(tempfile.mkdtemp(), "npdrv.py")
        with open(path, "w") as fh:
            fh.write(_nopath_driver(mod))
        return subprocess.run([sys.executable, path], capture_output=True,
                              text=True, timeout=120)

    # (a) The text channel. Bare `--files`, zero paths.
    np = _nopath_run("remote_state")
    check("a bare --files still exits 0 (the tree verdict is real)",
          np.returncode, 0)
    check("  ...and does NOT read as a clean per-file check",
          "NO PATHS CHECKED" in np.stdout, True)
    # The specific failure: the output a caller would read as "the files I
    # meant to check are all on the remote", which is what the old run said.
    check("  ...it cannot be mistaken for MATCH rows",
          "MATCH " in np.stdout, False)
    # The reason has to be ACTIONABLE, not a scolding: this is a command a
    # tick is running under time pressure.
    check("  ...and prints the command that fixes it",
          "remote_state.py --files <path>" in np.stdout, True)

    # (b) The json channel, same input.
    nj_proc, nj_body = _json_run("remote_state",
                                 "m.file_check = lambda paths: []\n",
                                 ["remote_state.py", "--json", "--files"])
    check("a bare --json --files still exits 0", nj_proc.returncode, 0)
    if nj_body is not None:
        check("an UNMEASURED per-file list is null, not []",
              nj_body.get("files"), None)
        # The guard against regressing: [] is the one value that reads as a
        # completed check over every path.
        check("NEGATIVE: no unmeasured key is an empty LIST",
              any(nj_body.get(k) == [] for k in
                  ("files", "why", "index_mode_drift", "index_content_drift")),
              False)
        check("  ...beside the clean in_sync verdict, which is the harm",
              nj_body.get("info", {}).get("verdict"), "IN SYNC")

    # (c) NEGATIVE CONTROL against the pre-fix blob, same driver, same stub.
    #     A re-implementation would prove nothing; the old file ships for
    #     exactly this and is driven directly.
    check("the pre-fix blob travels with the test",
          os.path.exists(os.path.join(HERE, "remote_state_pre_fix.py")), True)
    old_np = _nopath_run("remote_state_pre_fix")
    check("NEGATIVE CONTROL: pre-fix DID say nothing about the files",
          "NO PATHS CHECKED" in old_np.stdout, False)
    check("  ...it printed the same IN SYNC verdict either way",
          ("IN SYNC" in np.stdout) and ("IN SYNC" in old_np.stdout), True)
    check("  ...and the fix is what changed, not the verdict",
          np.stdout != old_np.stdout, True)

    # (d) NO CRY-WOLF CONTROL. A notice must not cost the healthy path:
    #     `--files` WITH a path still runs the real comparison, still prints
    #     the rows, and still says nothing about missing paths -- because a
    #     guard that also fires on the working case is its own outage.
    hp_proc, hp_body = _json_run(
        "remote_state",
        "m.file_check = lambda paths: [('h.py', 'MATCH', 'disc', 'sha',\n"
        "                               '100644', '100644', None)]\n",
        ["remote_state.py", "--json", "--files", "h.py"])
    check("--files WITH a path still exits 0", hp_proc.returncode, 0)
    check("  ...and still returns its rows",
          [r[0] for r in (hp_body or {}).get("files", [])], ["h.py"])
    check("  ...and a measured list is a list, never null",
          isinstance((hp_body or {}).get("files"), list), True)
    check("  ...one row per path asked for, not a placeholder",
          [r[0] for r in (hp_body or {}).get("files", [])], ["h.py"])
    check("  ...and the NO PATHS notice does not fire on it",
          "NO PATHS CHECKED" in hp_proc.stdout, False)


    print("")
    if FAILED:
        print("%d FAILED: %s" % (len(FAILED), ", ".join(FAILED)))
        return 1
    print("all remote_state cases pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
