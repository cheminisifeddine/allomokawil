#!/usr/bin/env python3
"""Answer one question: is the local tree already on the remote, or not?

    python3 tool/remote_state.py
    python3 tool/remote_state.py --files IMPROVEMENT_BACKLOG.md tool/build_gate.py
    python3 tool/remote_state.py --why
    python3 tool/remote_state.py --json

Step 6 of the loop protocol says to verify a push against the remote tree
rather than the exit code, and it hands the next tick a 15-line authenticated
heredoc to do it with. On 1 Oct that check was run by hand and it said the two
files MATCH -- and `git status -sb` on the same box, same second, said:

    ## main...origin/main [ahead 12, behind 12]

which is the shape of "two writers in one tree, one of them is about to lose
work". It was not. The truth is boring and worth stating precisely: the local
HEAD and the remote tip have the **same tree hash**
(`1c182ebe...`), so every file is already on the remote, and the divergence is
entirely in commit *metadata*.

**Why that happens.** `gh_push.py` pushes through the git-data API. It creates
a new commit object on GitHub from the blobs it uploads, so the remote's
commit hash can never equal the local one -- different parent, different
author timestamp, different committer. Two runs of the same loop therefore
produce two different hashes for the same bytes, and `git fetch` then makes
`ahead`/`behind` count both. `git status` cannot tell this apart from real lost
work, and neither can a human reading it quickly at the end of a tick.

That matters because the *wrong* repair for a real divergence (reset, rebase,
force-push) is catastrophic and the *right* reading of this one is "you are
done". A tick that sees "behind 12" and reaches for a reset destroys the local
history to chase a hash difference that does not exist. So this tool exists
to make the distinction a single command, and it is read-only: it never
writes a ref, never fetches, never pushes.

**The comparison is by tree hash, not by commit.** Two commits with the same
tree differ in nothing a user can see -- same files, same bytes, same modes.
That is the standard `git` notion of content equality and it is exactly the
question "did my work reach the remote". Comparing commit hashes answers a
different question ("did the same commit object survive"), which is `no` for
every API push, always, and means nothing.

Exit codes:
  0  IN SYNC    -- local tree is byte-identical to the remote tree
  1  DIVERGED   -- real difference; unpushed work exists or remote work is missing
  2  UNREACHABLE-- could not read the remote (no creds, network, bad repo)

`DIVERGED` is the only state that is allowed to make a tick re-push, and even
then the repair is `gh_push.py`, never a reset.
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
OWNER = "cheminisifeddine"
REPO = "allomokawil"
BRANCH = "main"
LOCAL = "/home/hatch/allomokawil"
CRED_BIN = "/opt/hatch/skills/skill-creator/bin"
ALLOWED = ("api.github.com",)


def _creds():
    """Import the surrogate-token helper, or explain why it is unavailable."""
    if CRED_BIN not in sys.path:
        sys.path.insert(0, CRED_BIN)
    try:
        from dynamic_credentials import add_surrogate_to_request
    except ImportError as exc:
        raise SystemExit(
            "UNREACHABLE: dynamic_credentials not importable from %s (%s)\n"
            "This is the same import step 6's heredoc performs; without it "
            "there is no token and no remote read." % (CRED_BIN, exc)
        )
    return add_surrogate_to_request


def api(path):
    add = _creds()
    req = urllib.request.Request(API + path, method="GET")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "allomokawil-remote-state")
    add(req, "custom.github", allowed_hosts=ALLOWED)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def git(*args):
    out = subprocess.run(("git", "-C", LOCAL) + args,
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit("UNREACHABLE: git %s failed: %s"
                         % (" ".join(args), out.stderr.strip()))
    return out.stdout.strip()


def git_raw(*args):
    """`git` WITHOUT stripping stdout.

    `git()` strips, which is right for a sha and wrong for
    `status --porcelain`: the record is `XY<space>path`, so on a modified
    file the first line begins with a space and the strip ate it. `l[3:]`
    then produced "ool/remote_state.py" -- the tool that tells a tick what
    to commit and push was printing a path that does not exist. Found by
    running `--why` on a tree this edit had just dirtied, i.e. only visible
    while the tool is being used, which is why it survived since 1 Oct.
    """
    out = subprocess.run(("git", "-C", LOCAL) + args,
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit("UNREACHABLE: git %s failed: %s"
                         % (" ".join(args), out.stderr.strip()))
    return out.stdout


def remote_tip():
    return api("/repos/%s/%s/git/ref/heads/%s" % (OWNER, REPO, BRANCH))[
        "object"]["sha"]


def remote_blobs():
    """Map path -> (blob sha, mode) for the whole remote tree, via the tip sha.

    The mode is here because a tree hash covers it: a file whose CONTENT is
    identical but whose executable bit differs produces a different tree, and
    that is the one difference `--files` cannot explain on its own. See
    `explain()`.
    """
    tree = api("/repos/%s/%s/git/trees/%s?recursive=1" % (OWNER, REPO, remote_tip()))
    return {e["path"]: (e["sha"], e.get("mode", "")) for e in tree["tree"]
            if e["type"] == "blob"}


def remote_truncated():
    """True if GitHub cut the recursive tree listing short.

    A truncated listing makes every absent path look like a deletion, which is
    the opposite of the truth and the most dangerous way this tool can lie:
    it would report real, shipped files as missing. The recursive trees API
    caps at 100k entries / 7 MB; this repo is far under, but the flag is the
    difference between "absent" meaning absent and meaning unknown.
    """
    return bool(api("/repos/%s/%s/git/trees/%s?recursive=1"
                    % (OWNER, REPO, remote_tip())).get("truncated"))


def local_tree():
    return git("rev-parse", "HEAD^{tree}")


def remote_tree():
    """The tree sha the remote TIP commit points at (dereferences the sha)."""
    return api("/repos/%s/%s/git/commits/%s" % (OWNER, REPO, remote_tip()))[
        "tree"]["sha"]


def verdict(local_tree_sha, remote_tree_sha):
    """Pure decision, separated so it can be tested without a network.

    Returns (in_sync, label). Everything else in this file is I/O; this is
    the part that decides whether a tick believes it shipped, so it is the
    part that gets a test.
    """
    if not local_tree_sha or not remote_tree_sha:
        # A missing sha is not "in sync". Treating an absent reading as
        # agreement is the same class of bug as a probe reporting 0 boxes
        # because it could not open the file.
        return False, "UNKNOWN"
    return (local_tree_sha == remote_tree_sha,
            "IN SYNC" if local_tree_sha == remote_tree_sha else "DIVERGED")


def classify():
    info = {
        "local_head": git("rev-parse", "HEAD"),
        "local_tree": local_tree(),
        "remote_tip": remote_tip(),
        "remote_tree": remote_tree(),
    }
    info["status"] = git("status", "-sb").splitlines()[0]
    # ahead/behind straight from git: authoritative, unlike the tracker after
    # an API push, but it counts COMMITS and so is the thing that misleads.
    # "## main...origin/main [ahead 12, behind 12]" -- the bracket can END
    # the line, so split on "[" first or the value comes back empty.
    m = re.search(r"\[([^\]]*)\]", info["status"])
    info["ahead_behind"] = m.group(1).strip() if m else "(clean)"
    info["in_sync"], info["verdict"] = verdict(info["local_tree"],
                                              info["remote_tree"])
    # The tree comparison is against the COMMITTED tree, so a file edited but
    # not yet committed reads IN SYNC above while its --files blob reads
    # DIFFER. That is not a contradiction, it is two different questions, and
    # leaving it unsaid is how a tick concludes "shipped" over an edit that
    # only ever existed on this disk. Name it.
    dirty = [l for l in git_raw("status", "--porcelain").splitlines() if l.strip()]
    # Porcelain v1 is fixed-width: two status columns, one space, then the
    # path. A rename is "R  old -> new"; keep both names rather than pretend
    # one of them is the file.
    info["uncommitted"] = [l[3:].strip() for l in dirty]
    return info


def explain(local, remote):
    """Turn a tree difference into a list of sentences, not a bisect.

    `verdict()` answers "same or not" and stops. That is enough to be safe --
    DIVERGED means go look -- but it leaves the tick that hits DIVERGED to
    reconstruct the cause by hand, which is the expensive part and the part
    done wrong under time pressure.

    The defect that forced this, found by hand in the 60th tick: a new test
    harness was created with `chmod +x` and so entered the index as `100755`,
    while `gh_push.py` mints every file as `100644`. Every blob MATCHed --
    545/545, zero differing SHAs -- and `remote_state.py` still said
    DIVERGED, correctly, because the mode is inside the tree hash. The tool
    was right and still cost a manual bisect, because `--files` compares only
    content and printed a page of MATCH next to a DIVERGED verdict.

    So the difference is reported per path, split by kind:
      mode    -- same bytes, different executable bit (the 100755 case)
      content -- same path, different blob sha (genuinely unpushed work)
      local-only  -- in the local tree, absent from the remote
      remote-only -- on the remote, absent locally (a deletion, or the
                     signature of a truncated listing -- see remote_truncated)

    PURE and dict-in/list-out: no network, no git, so it is testable, and the
    test drives it with the real 100755 shape rather than asserting it.
    """
    rows = []
    for path in sorted(set(local) | set(remote)):
        l = local.get(path)
        r = remote.get(path)
        if r is None:
            rows.append((path, "local-only", "in the local tree, not on the remote"))
            continue
        if l is None:
            rows.append((path, "remote-only", "on the remote, not in the local tree"))
            continue
        l_sha, l_mode = (l + ("",))[:2] if isinstance(l, tuple) else (l, "")
        r_sha, r_mode = (r + ("",))[:2] if isinstance(r, tuple) else (r, "")
        if l_sha != r_sha:
            rows.append((path, "content",
                         "local %s / remote %s" % (l_sha[:7], r_sha[:7])))
        elif l_mode != r_mode:
            rows.append((path, "mode", "local %s / remote %s" % (l_mode, r_mode)))
    return rows


def mode_of(path, repo=None):
    """The mode git has recorded for `path` in the index (or worktree), or ''.

    `git ls-files -s` is the index reader: it answers what the NEXT COMMIT
    will record, which is the question -- the working filesystem's permission
    bits are not git's opinion, and `chmod +x` on an already-committed file
    does not change what the index holds. That is why a leaked executable bit
    is invisible until someone re-adds the file.
    """
    out = subprocess.run(["git", "-C", repo or LOCAL, "ls-files", "-s", "--",
                          path], capture_output=True, text=True)
    if out.returncode != 0:
        return ""
    for line in out.stdout.splitlines():
        parts = line.split()
        # "<mode> <sha> <stage>	<path>"
        if len(parts) >= 3 and parts[2] in ("0", "1", "2", "3"):
            return parts[0]
    return ""


def index_blobs():
    """Map path -> (blob sha, mode) for the INDEX -- what the NEXT commit records.

    `git ls-files -s`, the same reader `mode_of()` uses, but for the whole tree
    in one call. `mode_of` reads one path and hands back the mode; the content
    half of the same index entry was never read by anything, which is the gap
    the 64th tick closed.

    The index is a rung between HEAD and the disk, and every reader in this
    file has looked either above it or below it:

        HEAD      the committed tree -- what `verdict()` hashes
        index     what the NEXT commit will record
        disk      the working file -- what `git hash-object` returns

    The index was the one rung nobody read on the CONTENT axis. `mode_of`
    covered its mode axis (MODE-STAGED, the 60th tick) and `explain_index`
    covered it for `--why`, so a staged *blob* was invisible everywhere.
    """
    out = subprocess.run(["git", "-C", LOCAL, "ls-files", "-s"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return {}
    rows = {}
    for line in out.stdout.splitlines():
        meta, _, path = line.partition("\t")
        parts = meta.split()
        # "<mode> <sha> <stage>\t<path>" -- stage must be 0; 1/2/3 are
        # conflict entries and carry no blob you can commit as-is.
        if len(parts) >= 3 and parts[2] == "0" and path:
            rows[path] = (parts[1], parts[0])
    return rows


def staged_content_drift():
    """Paths whose INDEX blob differs from the blob the last commit recorded.

    The content-axis twin of `explain_index`. `--why` compared committed trees
    and therefore could not see a staged blob, correctly -- it is not a tree
    difference yet -- but it is exactly the thing that becomes one the moment
    anyone runs `git commit`, and the whole cost of the 60th tick's mode leak
    was finding it after the fact. Catching it while the file is still being
    edited is the difference between a one-line fix and a bisect.

    PURE: index blobs in, rows out. Kept separate from `index_drift()` rather
    than folded into it so the two-tuple that six existing cases unpack stays
    exactly as it is.
    """
    head = {p: s for p, (s, _m) in local_blobs().items()}
    index = {p: s for p, (s, _m) in index_blobs().items()}
    rows = []
    for path in sorted(set(index) & set(head)):
        if index[path] != head[path]:
            rows.append((path, head[path], index[path]))
    return rows


def local_blobs():
    """Map path -> (blob sha, mode) for the committed local tree.

    `git ls-tree -r HEAD`, so this is the same object the tree hash is taken
    over -- comparing this against the remote tree compares like with like.
    """
    out = subprocess.run(["git", "-C", LOCAL, "ls-tree", "-r", "HEAD"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit("UNREACHABLE: git ls-tree failed: %s" % out.stderr.strip())
    rows = {}
    for line in out.stdout.splitlines():
        head, _, path = line.partition("\t")
        parts = head.split()
        if len(parts) >= 3:
            rows[path] = (parts[2], parts[0])
    return rows


def explain_index(index_modes, head_modes):
    """Paths whose INDEX mode differs from the mode the last commit recorded.

    This is the 60th tick's defect one step earlier than a tree diff can see
    it. `--why` compares COMMITTED trees, so a mode leak that has been staged
    but not committed is invisible there -- correctly, since it is not a tree
    difference yet. But it is precisely the thing that turns into a DIVERGED
    one commit later, and the whole cost of the original bug was finding it
    after the fact. Catching it while the file is still being edited is the
    difference between a one-line fix and a bisect.

    PURE: index modes in, rows out.
    """
    rows = []
    for path in sorted(set(index_modes) | set(head_modes)):
        i = index_modes.get(path)
        h = head_modes.get(path)
        if i is None or h is None:
            continue
        if i != h:
            rows.append((path, h, i))
    return rows


def index_drift():
    """(explain_index rows, is anything staged at all)."""
    head = {p: m for p, (_s, m) in local_blobs().items()}
    out = subprocess.run(["git", "-C", LOCAL, "ls-files", "-s"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return [], False
    index = {}
    for line in out.stdout.splitlines():
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) >= 3:
            index[path] = parts[0]
    staged = subprocess.run(["git", "-C", LOCAL, "diff", "--cached",
                             "--name-only"], capture_output=True, text=True)
    return explain_index(index, head), bool(staged.stdout.strip())


def head_mode(path, repo=None):
    """The mode the last COMMIT recorded for `path`, or ''.

    `file_check` needs this and not `mode_of`, and the difference is the whole
    point. `mode_of` reads the INDEX -- what the NEXT commit will record.
    `file_check`'s verdict is compared against `verdict()`, which compares
    COMMITTED trees. So the row was answering a question one commit ahead of
    the question the tool reports.

    The two disagree exactly when a mode was staged and not committed, in
    either direction, and then `--files` is wrong while the verdict is right:

      HEAD 100755 / index 100644 / remote 100644  ->  MATCH printed, and the
      trees DIVERGED. The reverse (HEAD 100644 / index 100755 / remote
      100644) printed MODE-DIFFER next to an IN SYNC verdict -- an invented
      divergence, the mirror of the 60th tick's defect and the same class:
      a row that disagrees with the verdict it sits under.

    A repair printed on top of either one is worse than no repair, because
    running it fixes a file whose committed tree was never wrong. `ls-tree -r
    HEAD` is what the tree hash is taken over, so this reads the same object
    `verdict()` does.
    """
    out = subprocess.run(["git", "-C", repo or LOCAL, "ls-tree", "-r", "HEAD",
                          "--", path], capture_output=True, text=True)
    if out.returncode != 0:
        return ""
    for line in out.stdout.splitlines():
        head, _, _p = line.partition("\t")
        parts = head.split()
        if len(parts) >= 3:
            return parts[0]
    return ""


def choose_content_row(work_sha, head_sha, remote_sha):
    """PURE: name the CONTENT difference, or say there is not one.

    Three objects, three hops, and the old code collapsed the first two:

      working file  --(unstaged edit)-->  HEAD  --(push)-->  remote

    `file_check` read the WORKING file's sha (`git hash-object`) and the
    remote's, and printed one label for "these differ". But the verdict above
    it compares COMMITTED trees, i.e. HEAD vs the remote. So a single DIFFER
    row covered two states that are opposites and have different repairs:

      HEAD == remote, working file edited -> verdict IN SYNC, and the work is
        uncommitted ON THIS DISK. Repair: `git add`, commit, push. Calling it
        a divergence invites a re-push of a tree that already matches, and
        the printed "local" sha is a blob that exists in NO commit.
      HEAD != remote -> a real unpushed divergence, verdict DIVERGED, and the
        repair is the push.

    A reader cannot tell those apart from the row, and neither can the label.
    So each state gets its own name and they cannot be swapped.

    This is the content-axis twin of the mode axis the 62nd tick split into
    MODE-DIFFER (committed) and MODE-STAGED (index). Same discipline: name
    WHICH HOP the difference is in, because the repair differs per hop.
    """
    if not remote_sha or remote_sha == "-":
        return None
    if not head_sha:
        # On the remote, absent from HEAD: a committed deletion.
        return "REMOTE-ONLY"
    if head_sha != remote_sha:
        # The committed trees differ. This is the real thing, and it agrees
        # with the verdict printed above it.
        return "CONTENT-DIFFER"
    if work_sha and work_sha != head_sha:
        # Trees agree; the disk does not. Verdict stays IN SYNC and it must.
        return "EDITED"
    return None


def staged_row(index_sha, head_sha, mode_staged):
    """PURE: name a staged difference, or say there is not one.

    Asked only when the committed trees already AGREE (HEAD == remote), so
    every label here means the same thing: *not a divergence yet, and the next
    commit will make it one*. That is what lets this pair sit under an IN SYNC
    verdict without contradicting it -- the opposite failure from the 62nd's,
    where a row read the index and printed MODE-DIFFER under a green verdict.

    Content is checked before mode because a staged blob is the more invisible
    of the two: no mode check, no blob check and no tree diff in this file can
    see it, so a row that names only the mode while the blob is also staged is
    the leak the 60th tick lost four days to, one axis over. When both are
    staged the row is INDEX-STAGED and the printed repair covers both.

    The three inputs, and what each is for:

      index_sha  the blob the next commit records -- the one no diff can see
      head_sha   the blob the last commit recorded -- the undo target
      mode_staged  the 62nd's finding, kept as an input so this is the single
                  place that decides the label
    """
    if not index_sha or not head_sha:
        return None
    if index_sha != head_sha:
        return "INDEX-STAGED"
    if mode_staged:
        return "MODE-STAGED"
    return None


def file_check(paths):
    """Per-file check against the COMMITTED tree, with the staged leak named.

    CONTENT and mode, both read on the axis the verdict uses: HEAD vs the
    remote commit. A mode difference is still its own row rather than hiding
    behind a green MATCH, because that is what the 60th tick tripped over --
    545/545 blobs MATCH while the tool correctly said DIVERGED.

    Two things that are NOT the committed tree get their own rows, because
    neither can be reported as a divergence:

      MODE-STAGED  the index disagrees with HEAD. Not a divergence yet; it
                   becomes one on the next commit. The repair is printed,
                   because undoing it costs one line now and a bisect later.
      EDITED       HEAD agrees with the remote; the WORKING FILE does not.
                   Uncommitted work on this disk, which `classify()` also
                   lists. The verdict is IN SYNC and it must stay there.
      CONTENT-DIFFER
                   the committed trees differ -- the real unpushed work, and
                   the label that agrees with a DIVERGED verdict.
      REMOTE-ONLY  on the remote, absent from HEAD: a committed deletion.

    The last three were one label, `DIFFER`, which is what the 63rd split.
    It is not a rename: it is one row covering two opposite states with
    different repairs, read against a verdict that could only see one of them.
    """
    remote = remote_blobs()
    # HEAD's blob and mode from ONE read of the committed tree -- the same
    # object `verdict()` hashes. `head_mode` shelled out per path before,
    # which was the 62nd's axis fix; this closes the same gap on content by
    # reading the pair together instead of mixing a worktree sha with a
    # separately-fetched mode.
    head = local_blobs()
    # The index, in one pass, for the blob as well as the mode. `mode_of`
    # shelled out per path for the mode half only, and the blob half had no
    # reader at all -- which is how a staged blob reached MATCH.
    index = index_blobs()
    rows = []
    for p in paths:
        out = subprocess.run(["git", "hash-object", p], capture_output=True,
                             text=True, cwd=LOCAL)
        work = out.stdout.strip()
        want = remote.get(p)
        r_sha, r_mode = want if want else ("-", "-")
        h = head.get(p)
        h_sha, l_mode = h if h else ("", head_mode(p))
        ent = index.get(p)
        i_sha, i_mode = ent if ent else ("", "")
        staged_leak = bool(i_mode and l_mode and i_mode != l_mode)
        content = choose_content_row(work, h_sha, r_sha)
        # Only meaningful while the committed trees agree. Once HEAD and the
        # remote differ, CONTENT-DIFFER is the true and sufficient row and a
        # staged label beside it would be noise about a divergence already
        # visible in the verdict.
        staged = staged_row(i_sha, h_sha, staged_leak) if not content else None
        if not work:
            rows.append((p, "UNTRACKED", "-", r_sha, "-", r_mode, i_mode, i_sha))
        elif want is None:
            rows.append((p, "ABSENT-REMOTE", work, "-", l_mode, "-", i_mode,
                         i_sha))
        elif content:
            rows.append((p, content, work, r_sha, l_mode, r_mode, i_mode, i_sha))
        elif staged:
            # Committed trees agree. The index does not, so the NEXT commit
            # diverges. Named here rather than silently folded into MATCH,
            # because MATCH is what a tick reads before it commits.
            rows.append((p, staged, work, r_sha, l_mode, r_mode, i_mode, i_sha))
        elif l_mode and r_mode and l_mode != r_mode:
            # Same bytes, different mode, in the trees themselves. This is
            # the real thing: `git update-index --chmod=-x`, then commit,
            # then push.
            rows.append((p, "MODE-DIFFER", work, r_sha, l_mode, r_mode, i_mode,
                         i_sha))
        else:
            rows.append((p, "MATCH", work, r_sha, l_mode, r_mode, i_mode, i_sha))
    return rows


def why():
    """The per-path difference between the two trees, as sentences."""
    local = local_blobs()
    remote = remote_blobs()
    truncated = remote_truncated()
    drift, staged = index_drift()
    return (explain(local, remote), truncated, drift, staged,
            staged_content_drift())


def main():
    args = sys.argv[1:]
    as_json = "--json" in args
    as_why = "--why" in args
    files = []
    if "--files" in args:
        rest = args[args.index("--files") + 1:]
        files = [a for a in rest if not a.startswith("--")]

    try:
        info = classify()
        rows = file_check(files) if files else []
        diffs = []
        truncated = False
        drift = []
        staged = False
        blob_drift = []
        if as_why:
            diffs, truncated, drift, staged, blob_drift = why()
    except urllib.error.URLError as exc:
        print("UNREACHABLE: %s" % exc, file=sys.stderr)
        return 2
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if as_json:
        print(json.dumps({"info": info, "files": rows,
                          "why": [{"path": p, "kind": k, "detail": d}
                                  for p, k, d in diffs],
                          "index_mode_drift": [{"path": p, "head": h,
                                                "index": i} for p, h, i in drift],
                          "index_content_drift": [{"path": p, "head": h,
                                                   "index": i}
                                                  for p, h, i in blob_drift],
                          "remote_truncated": truncated}, indent=2))
        return 0 if info["in_sync"] else 1

    print("local  HEAD  %s" % info["local_head"])
    print("local  tree  %s" % info["local_tree"])
    print("remote tip   %s" % info["remote_tip"])
    print("remote tree  %s" % info["remote_tree"])
    print("git says     %s   <- counts COMMITS, not content" % info["ahead_behind"])
    if info["verdict"] == "IN SYNC":
        print("\nIN SYNC: identical tree. Same files, same bytes.")
        print("The commit hashes differ because gh_push.py builds a new commit")
        print("over the git-data API. Nothing to push, nothing to reset.")
    else:
        print("\nDIVERGED: the trees are NOT identical. Real difference.")
        print("Inspect before touching anything -- a reset here can destroy")
        print("history to chase a difference that may be only metadata.")

    if info.get("uncommitted"):
        print("")
        print("UNCOMMITTED (on this disk only, NOT on the remote):")
        for f in info["uncommitted"]:
            print("  %s" % f)
        print("gh_push.py only uploads files git already tracks, so nothing")
        print("here has reached the remote. Commit it, then push.")

    if as_why:
        print("")
        if truncated:
            print("WARNING: the remote listing came back TRUNCATED. Paths")
            print("missing below may be an artefact of the listing cap, not a")
            print("real deletion. Do not push a deletion on this evidence.")
        if not diffs:
            print("WHY: no per-path difference between the COMMITTED trees.")
            print("They are identical file for file, mode for mode.")
        else:
            print("WHY: %d path(s) differ between the two trees:" % len(diffs))
            for p, kind, detail in diffs:
                print("  %-12s %s" % (kind, p))
                print("               %s" % detail)
            kinds = sorted({k for _, k, _ in diffs})
            print("")
            if kinds == ["mode"]:
                print("Mode only: same bytes, different executable bit.")
                print("gh_push.py mints every file 100644. A 100755 here is a")
                print("file whose index entry was written by 'chmod +x' + add.")
                print("git update-index --chmod=-x <file>, then push again.")
            elif "content" in kinds:
                print("Content differs: real unpushed work. Push the paths")
                print("above with gh_push.py. Do NOT reset.")
            if "local-only" in kinds:
                print("local-only: untracked or never committed -- 'git add' it,")
                print("because gh_push.py only uploads what git already tracks.")
            if "remote-only" in kinds:
                print("remote-only: absent locally. A real deletion, or an")
                print("artefact of the truncated-listing warning above.")

        if drift:
            print("")
            print("STAGED MODE LEAK (staged only; NOT committed, NOT on the remote):")
            for p, h, i in drift:
                print("  %-6s %s  (HEAD %s -> index %s)" % ("mode", p, h, i))
            print("The next commit carries this mode and makes the trees")
            print("diverge for a difference no blob check can see. Undo it")
            print("BEFORE committing:")
            for p, h, i in drift:
                # Restore HEAD's mode, do not flip away from it. HEAD is
                # 100644 and the index drifted to 100755, so the repair is
                # --chmod=-x; the first version of this line had the test
                # backwards and printed the command that would make the leak
                # permanent. A suggested repair must be runnable.
                print("  git update-index --chmod=%s %s"
                      % ("+x" if h == "100755" else "-x", p))
        else:
            print("")
            print("No staged MODE leak: the next commit cannot introduce a")
            print("mode difference the blob check cannot see.")
            if not blob_drift:
                print("No staged BLOB drift either -- index and HEAD record the")
                print("same content for every tracked path.")
        if blob_drift:
            print("")
            print("STAGED BLOB DRIFT (staged only; NOT committed, NOT on the remote):")
            for p, h, i in blob_drift:
                print("  %-6s %s" % ("blob", p))
                print("         HEAD  %s" % h)
                print("         index %s  <- the blob the NEXT commit records" % i)
            print("Every committed-tree check above is blind to this: no blob")
            print("comparison and no mode comparison can see it, and it becomes")
            print("a real divergence the moment anyone runs `git commit`.")
            print("Undo it BEFORE committing:")
            for p, h, i in blob_drift:
                print("  git restore --staged %s" % p)
            print("Or keep it -- if this content is the work you meant to make,")
            print("just commit it. The row is only wrong when it is a surprise.")

    if rows:
        print("")
        head = local_blobs()
        for row in rows:
            p, verdict, local, want = row[0], row[1], row[2], row[3]
            head_sha = (head.get(p) or ("",))[0]
            print("%-12s %s" % (verdict, p))
            if verdict == "CONTENT-DIFFER":
                # A real committed divergence: HEAD vs the remote. This is the
                # only content label that may say "push it", because it is the
                # only one whose verdict agrees.
                print("             COMMITTED trees differ (HEAD vs remote)")
                print("             HEAD   %s" % (head_sha or "?"))
                print("             remote %s" % want)
                print("             real unpushed work -- commit, then push")
            elif verdict == "EDITED":
                # Trees agree; the disk does not. Saying "DIFFER" here put an
                # uncommitted local edit next to an IN SYNC verdict, and the
                # sha printed was the working file's -- a blob that exists in
                # no commit at all, so it could never be matched or pushed.
                print("             COMMITTED trees AGREE; this file on disk does not")
                print("             HEAD   %s" % (head_sha or "?"))
                print("             disk   %s" % local)
                print("             uncommitted edit -- git add, commit, then push")
                print("             this is NOT a divergence; the verdict above is right")
            elif verdict == "REMOTE-ONLY":
                print("             on the remote, absent from the committed tree")
                print("             HEAD   %s" % (head_sha or "(absent)"))
                print("             a committed deletion, or a truncated listing --")
                print("             check --why before pushing it")
            elif verdict == "MODE-DIFFER":
                # The repair lead 2 asked for. Both halves now exist: the
                # reader names HEAD's mode, and the fix restores the REMOTE's,
                # which is the side gh_push.py will mint. Restoring HEAD would
                # be wrong here -- HEAD is the wrong one.
                print("             same bytes, mode HEAD %s / remote %s"
                      % (row[4], row[5]))
                print("             git update-index --chmod=%s %s"
                      % ("+x" if row[5] == "100755" else "-x", p))
                print("             then commit and push -- the trees differ")
            elif verdict == "INDEX-STAGED":
                # The 64th's row. `MATCH` here would be the worst possible
                # answer: it is what a tick reads immediately before it runs
                # `git commit`, and MATCH says "this is fine" about a blob
                # that the commit is about to record over HEAD.
                print("             COMMITTED trees AGREE; the INDEX does not")
                print("             HEAD   %s" % (head_sha or "?"))
                print("             index  %s  <- what the next commit records"
                      % (row[7] if len(row) > 7 and row[7] else "?"))
                print("             the file on DISK can agree with HEAD while the")
                print("             index holds a third blob -- which is why this is")
                print("             invisible to a reader that only looks at the file")
                print("             git restore --staged %s   (if this was a surprise)" % p)
                print("             or commit it, if this content is the work")
                print("             this is NOT a divergence; the verdict above is right")
            elif verdict == "MODE-STAGED":
                print("             trees AGREE (HEAD %s); index says %s"
                      % (row[4], row[6]))
                print("             git update-index --chmod=%s %s"
                      % ("+x" if row[4] == "100755" else "-x", p))
                print("             undo it before committing, or the next")
                print("             commit makes this a real divergence")
    return 0 if info["in_sync"] else 1


if __name__ == "__main__":
    sys.exit(main())
