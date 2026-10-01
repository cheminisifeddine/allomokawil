#!/usr/bin/env python3
"""Answer one question: is the local tree already on the remote, or not?

    python3 tool/remote_state.py
    python3 tool/remote_state.py --files IMPROVEMENT_BACKLOG.md tool/build_gate.py
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


def remote_tip():
    return api("/repos/%s/%s/git/ref/heads/%s" % (OWNER, REPO, BRANCH))[
        "object"]["sha"]


def remote_blobs():
    """Map path -> blob sha for the whole remote tree, via the tip sha."""
    tree = api("/repos/%s/%s/git/trees/%s?recursive=1" % (OWNER, REPO, remote_tip()))
    return {e["path"]: e["sha"] for e in tree["tree"] if e["type"] == "blob"}


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
    dirty = [l for l in git("status", "--porcelain").splitlines() if l.strip()]
    info["uncommitted"] = [l[3:] for l in dirty]
    return info


def file_check(paths):
    remote = remote_blobs()
    rows = []
    for p in paths:
        out = subprocess.run(["git", "hash-object", p], capture_output=True,
                             text=True, cwd=LOCAL)
        local = out.stdout.strip()
        want = remote.get(p)
        if not local:
            rows.append((p, "UNTRACKED", want or "-", "-"))
        elif want is None:
            rows.append((p, "ABSENT-REMOTE", local, "-"))
        elif local == want:
            rows.append((p, "MATCH", local, want))
        else:
            rows.append((p, "DIFFER", local, want))
    return rows


def main():
    args = sys.argv[1:]
    as_json = "--json" in args
    files = []
    if "--files" in args:
        rest = args[args.index("--files") + 1:]
        files = [a for a in rest if not a.startswith("--")]

    try:
        info = classify()
        rows = file_check(files) if files else []
    except urllib.error.URLError as exc:
        print("UNREACHABLE: %s" % exc, file=sys.stderr)
        return 2
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if as_json:
        print(json.dumps({"info": info, "files": rows}, indent=2))
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

    if rows:
        print("")
        for p, verdict, local, want in rows:
            print("%-11s %s" % (verdict, p))
            if verdict == "DIFFER":
                print("            local  %s" % local)
                print("            remote %s" % want)
    return 0 if info["in_sync"] else 1


if __name__ == "__main__":
    sys.exit(main())
