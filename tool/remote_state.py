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


def file_check(paths):
    """Per-file content check. CONTENT only -- mode is a separate axis.

    That split is deliberate and it is what the 60th tick tripped over: a
    file can MATCH here and still be why the tool says DIVERGED, because
    `hash-object` reads bytes and says nothing about the executable bit. So
    every MATCH row now carries the mode next to it, and a mode difference
    gets its own verdict rather than hiding behind a green MATCH.
    """
    remote = remote_blobs()
    rows = []
    for p in paths:
        out = subprocess.run(["git", "hash-object", p], capture_output=True,
                             text=True, cwd=LOCAL)
        local = out.stdout.strip()
        want = remote.get(p)
        r_sha, r_mode = want if want else ("-", "-")
        l_mode = mode_of(p)
        if not local:
            rows.append((p, "UNTRACKED", "-", r_sha, "-", r_mode))
        elif want is None:
            rows.append((p, "ABSENT-REMOTE", local, "-", l_mode, "-"))
        elif local != r_sha:
            rows.append((p, "DIFFER", local, r_sha, l_mode, r_mode))
        elif l_mode and r_mode and l_mode != r_mode:
            # Same bytes, different mode. This is the row the old version
            # could not produce, and its absence is why a 100755 leak printed
            # MATCH next to DIVERGED.
            rows.append((p, "MODE-DIFFER", local, r_sha, l_mode, r_mode))
        else:
            rows.append((p, "MATCH", local, r_sha, l_mode, r_mode))
    return rows


def why():
    """The per-path difference between the two trees, as sentences."""
    local = local_blobs()
    remote = remote_blobs()
    truncated = remote_truncated()
    drift, staged = index_drift()
    return explain(local, remote), truncated, drift, staged


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
        if as_why:
            diffs, truncated, drift, staged = why()
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
        elif staged:
            print("")
            print("Staged changes carry no mode drift: the next commit cannot")
            print("introduce a difference the blob check cannot see.")

    if rows:
        print("")
        for row in rows:
            p, verdict, local, want = row[0], row[1], row[2], row[3]
            print("%-12s %s" % (verdict, p))
            if verdict == "DIFFER":
                print("             local  %s" % local)
                print("             remote %s" % want)
            elif verdict == "MODE-DIFFER":
                print("             same bytes, mode local %s / remote %s"
                      % (row[4], row[5]))
    return 0 if info["in_sync"] else 1


if __name__ == "__main__":
    sys.exit(main())
