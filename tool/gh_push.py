#!/usr/bin/env python3
"""Push working-tree changes to GitHub via the git-database API.

Usage:
  gh_push.py OWNER REPO BRANCH ROOT -m "message" [--all | path ...] [--allow-deletes]

- Compares local files against the remote tree (git blob SHA), uploads only
  changed/new files, stages deletions, creates one commit, updates the branch.
- Uses the stored custom.github credential via authd surrogates; the raw
  token is never printed, logged, or persisted.

SAFETY (rewritten 26 Sep, after commit 782b657 deleted 5 files from main):
  1. The file set comes from `git ls-files`, so git decides what is tracked.
     A hand-rolled .gitignore matcher missed the nested android/.gitignore and
     ios/.gitignore where Flutter keeps its generated-file exclusions, and its
     `lstrip("./")` ate the leading dot of `.dart_tool`, leaking build junk.
  2. A path filter can no longer stage deletions. The "is it still there" set
     is always a full walk; the filter only narrows what gets UPLOADED.
     Previously `local` held only the filtered paths, so all 251 other remote
     files looked absent and were staged for deletion.
  3. Deletions require --allow-deletes. Without it the script prints what it
     would remove and exits 3 rather than silently emptying the branch.
  4. A branch that does not exist yet is CREATED, not an error. Reading the ref
     returned 404 (or 409 on an empty repo) and the script gave up, so the very
     first push to a new repository could never be made with this tool. The
     first commit is written as an orphan when the repo has no history and as a
     child of the default branch when it does.
"""
import sys, os, json, base64, hashlib, subprocess, urllib.request, urllib.error, urllib.parse

sys.path.insert(0, "/opt/hatch/skills/skill-creator/bin")
from dynamic_credentials import add_surrogate_to_request, read_json_response

API = "https://api.github.com"
ALLOWED = ("api.github.com",)


def api(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Accept", "application/vnd.github+json")
    if data:
        req.add_header("Content-Type", "application/json")
    add_surrogate_to_request(req, "custom.github", allowed_hosts=ALLOWED)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, read_json_response(resp)
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode()[:500]
        except Exception:
            body = ""
        return e.code, {"error": body}


def blob_sha(content: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(content) + content).hexdigest()


def git_modes(root):
    """Map path -> git mode (100644 / 100755) for every tracked file.

    FIX (11 Oct): the tree was built with a HARDCODED "100644" for every
    uploaded file, so an executable file went to the remote as 100644 while
    git had it as 100755 -- and because `git hash-object` covers CONTENT
    only, every content check said MATCH. The exec bit was the one axis
    the push could neither carry nor notice.

    Read from `git ls-files -s`, the same reader `tool/remote_state.py`
    uses, so the helper and the verifier cannot drift apart. git is the
    source of truth: an unknown path falls back to 100644, which is the
    mode git uses for a plain file.
    """
    try:
        out = subprocess.check_output(
            ["git", "-C", root, "ls-files", "-s", "-z"], stderr=subprocess.DEVNULL
        )
    except Exception:
        return {}
    modes = {}
    for rec in out.decode("utf-8", "replace").split("\0"):
        if not rec:
            continue
        head, _, path = rec.partition("\t")
        parts = head.split()
        # "<mode> <sha> <stage>"; stage 0 only -- a conflicted index has
        # stages 1/2/3 and is not something to push.
        if len(parts) == 3 and parts[2] == "0" and path:
            modes[path] = parts[0]
    return modes


def git_tracked_set(root):
    """Ask git for the authoritative tracked file list.

    Git is the source of truth for what belongs in the tree. Re-implementing
    .gitignore in Python got this wrong twice already (root-only patterns miss
    android/.gitignore and ios/.gitignore, which are where Flutter actually
    keeps the build-generated exclusions). Falls back to an empty set if git is
    unavailable, in which case the caller keeps the legacy walk.
    """
    try:
        out = subprocess.check_output(
            ["git", "-C", root, "ls-files", "-z"], stderr=subprocess.DEVNULL
        )
        return {p for p in out.decode("utf-8", "replace").split("\0") if p}
    except Exception:
        return set()


def resolve_base(owner, repo, branch):
    """Return (base_sha, ref_exists, note) for the commit this push builds on.

    base_sha is the branch tip when the branch exists, the default branch's tip
    when the branch is new but the repo has history (so the new branch is a
    real child of main, exactly as `git push origin main:BRANCH` would make it),
    and None when the repository is completely empty and the first commit has to
    be an orphan.

    ref_exists is separate from base_sha and must not be derived from it: a NEW
    branch off main has a perfectly good base but no ref to PATCH, and treating
    "has a base" as "has a ref" sends the commit to a 422 ("Reference does not
    exist") after the blobs are already uploaded. Only a branch that was there
    at the start of the push is patched; anything else is created.

    GitHub answers a ref read on a missing branch with 404, and on an empty
    repository with 409 ("Git Repository is empty"). Both mean "no such ref",
    neither means "stop" -- refusing there is what made the first push to a new
    repo impossible.
    """
    status, ref = api("GET", f"/repos/{owner}/{repo}/git/refs/heads/{branch}")
    if status == 200:
        return ref["object"]["sha"], True, f"existing branch '{branch}'"
    if status not in (404, 409):
        raise SystemExit(f"Failed to read ref: {status} {ref}")

    # The branch does not exist. An empty repo reports a default_branch name
    # that points at nothing, so it is only a real base if it actually reads.
    status, meta = api("GET", f"/repos/{owner}/{repo}")
    default = meta.get("default_branch") if status == 200 else None
    if default and default != branch:
        status, dref = api("GET", f"/repos/{owner}/{repo}/git/refs/heads/{default}")
        if status == 200:
            return dref["object"]["sha"], False, f"new branch '{branch}' off '{default}'"
    return None, False, f"new branch '{branch}' in an empty repository (orphan commit)"


def seed_empty_repo(owner, repo, branch, files, msg):
    """Create the very first commit in a repository that has no history.

    GitHub's git-data API cannot initialise an empty repository: creating a blob
    answers 409 "Git Repository is empty", so the blob -> tree -> commit -> ref
    chain this script normally walks can never start. The Contents API is the
    documented way in -- its first PUT creates the branch and the commit
    together -- so the orphan case goes through it instead of pretending the
    data API will work.

    Only the first file goes through here. It carries the branch's first
    commit; the rest of the files are then pushed by the normal path on the
    next run, which now finds a real base to diff against.
    """
    first = sorted(files)[0]
    status, body = api(
        "PUT", f"/repos/{owner}/{repo}/contents/{urllib.parse.quote(first)}",
        {"message": msg, "content": base64.b64encode(files[first]).decode(),
         "branch": branch})
    if status not in (200, 201):
        raise SystemExit(f"Cannot seed empty repository: {status} {body}")
    print(f"  seeded empty repo via Contents API: {first}")
    return body.get("content", {}).get("sha")


def walk_local(root, only=None, use_all=True):
    """Return {relpath: bytes} for every file git tracks under ROOT.

    Driven by `git ls-files`, so build output, generated registrants and nested
    .gitignore rules are handled by git itself rather than by a hand-rolled
    matcher. The walk is ALWAYS complete even when the upload set is filtered:
    absence of a file is the signal used to stage deletions, so it must never be
    confused with "not selected for upload". That confusion is what deleted 5
    files from main in commit 782b657.
    """
    tracked = git_tracked_set(root)
    if not tracked:
        raise SystemExit(
            "git ls-files returned nothing for " + root +
            " - refusing to guess. The tree is deleted, or not a git checkout."
        )
    out = {}
    for rel in sorted(tracked):
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            continue  # deleted locally; the caller stages the removal
        with open(full, "rb") as f:
            out[rel] = f.read()
    if not use_all and only is not None:
        return {p: c for p, c in out.items() if selects(only, p)}
    return out


def selects(only, path):
    """True when a path ARGUMENT covers this tracked file.


    A filter argument is a file path OR a directory. The old code did an exact
    set membership test (`p in only`), so passing the directories every caller
    actually passes -- `-- lib test` -- matched ZERO files, printed
    "No changes to push" and exited 0. On 26 Sep 2026 that swallowed a green,
    fully-tested commit for four hours: the filter selected 1 of 195 files, and
    that one file was already identical to the remote, so the near-empty match
    read as a clean success. A directory now covers everything beneath it,
    which is what every invocation in this repo's history meant.
    """
    if path in only:
        return True
    return any(path.startswith(arg.rstrip("/") + "/") for arg in only)


# NOTE, 27 Sep 2026: fixing this function alone was not enough. `walk_local`
# was given `selects()`, but the UPLOAD SET below was still built with
# `p in only` -- the exact-match test this function exists to replace. So the
# directory arguments every caller passes (`-- lib test`) walked all 306 files
# and then selected 0 of them for upload, and the guard fired with
# "selected 0 of 306 tracked files". One call site in two places: the same class
# of bug as the 26 Sep one, and the reason a green helper fix could still
# refuse a real commit. Both call sites must use `selects`.


def verify_push(owner, repo, branch, changed, modes, deleted):
    """Re-read the pushed tree and confirm every claimed path landed.

    FIX (11 Oct), for the defect the founder named: the helper printed a
    green line while leaving files unpushed, three calls in a row.

    What this checks, and why each axis:

      * content -- the blob sha the API now reports for the path must equal
        the sha of the bytes we uploaded. Catches a blob that was created
        but not actually wired into the tree we committed.
      * mode   -- `git hash-object` covers CONTENT only, so a file whose
        executable bit changed is invisible to every content check. The
        mode is inside the tree hash, so it has to be compared separately.
        This is the axis that was structurally unreachable before.

    A MISMATCH is a hard failure: exit 5, a distinct code that cannot be
    confused with 2 (bad args), 3 (refused deletions) or a hung shard. The
    push HAS happened -- the commit is on the remote -- so this reports
    what is missing and how to finish, rather than pretending it did not.

    Truncated tree listings are treated as failure, not success: GitHub
    caps a recursive listing, and "I could not see the rest" must never be
    printed as "everything is there".
    """
    if not changed and not deleted:
        return True

    print("Verifying the push against the remote tree...")
    status, tree = api(
        "GET", f"/repos/{owner}/{repo}/git/trees/{branch}?recursive=1")
    if status != 200:
        print(f"VERIFY FAILED: could not read the pushed tree: {status} {tree}")
        return False
    if tree.get("truncated"):
        print("VERIFY FAILED: the remote tree listing is TRUNCATED, so this "
              "check measured nothing. Re-run with --files, or push fewer "
              "files so the whole tree fits in one listing.")
        return False

    remote = {e["path"]: (e["sha"], e.get("mode", ""))
              for e in tree.get("tree", []) if e.get("type") == "blob"}

    problems = []
    for path, content in sorted(changed.items()):
        want_sha = blob_sha(content)
        want_mode = modes.get(path, "100644")
        got = remote.get(path)
        if got is None:
            problems.append(f"  MISSING   {path}  (absent from the pushed tree)")
            continue
        got_sha, got_mode = got
        if got_sha != want_sha:
            problems.append(
                f"  CONTENT   {path}  pushed {got_sha[:12]} "
                f"but the local bytes are {want_sha[:12]}")
        if got_mode and got_mode != want_mode:
            problems.append(
                f"  MODE      {path}  pushed {got_mode}, git has {want_mode}")

    for path in deleted:
        if path in remote:
            problems.append(
                f"  DELETED   {path}  staged for deletion but still on the remote")

    if problems:
        print("\nVERIFY FAILED -- the commit is on the remote but it does not "
              "contain what this run claimed to push:")
        for line in problems:
            print(line)
        print(f"\n{len(problems)} path(s) did not land. Do NOT re-push blindly: "
              "run the repo's verifier, which prints the divergence per file:\n"
              "  python3 tool/remote_state.py --why")
        return False

    print(f"VERIFIED: {len(changed)} file(s) match the remote on CONTENT and "
          f"MODE, {len(deleted)} deletion(s) confirmed.")
    return True


def main():
    args = sys.argv[1:]
    if len(args) < 5 or "-m" not in args:
        print(__doc__)
        sys.exit(2)
    owner, repo, branch, root = args[0], args[1], args[2], args[3]
    msg = args[args.index("-m") + 1]
    rest = [a for a in args[4:] if a not in ("-m", msg)]
    allow_deletes = "--allow-deletes" in rest
    # Flags are not path filters. "--allow-deletes" used to stay in `rest`,
    # which made `use_all` False and `only` empty, so invoking the helper with
    # that flag alone uploaded NOTHING: it staged the deletions, reported
    # "Pushed 0 changed, 4 deleted" and exited 0, leaving a commit on main
    # whose message described code that was never uploaded. Strip flags first
    # so the decision is made on the path arguments alone.
    paths = [a for a in rest if a not in ("--all", "--allow-deletes")]
    use_all = (not paths) or ("--all" in rest)
    only = set(paths)
    if not use_all and not only:
        raise SystemExit("refusing to upload an empty path set")

    # 1. what does this push build on: the branch, the default branch, or
    #    nothing at all in an empty repo.
    base_sha, ref_exists, base_note = resolve_base(owner, repo, branch)
    print(f"base: {base_note}")

    # 2. remote tree (recursive). A brand-new branch starts from the tree it is
    #    forked from, so the diff stays honest instead of reporting every file
    #    as new.
    if base_sha is not None:
        status, tree = api("GET", f"/repos/{owner}/{repo}/git/trees/{base_sha}?recursive=1")
        if status != 200:
            print(f"Failed to read tree: {status} {tree}")
            sys.exit(1)
        remote = {t["path"]: t["sha"] for t in tree.get("tree", []) if t["type"] == "blob"}
    else:
        remote = {}

    # 3. walk local files. ALWAYS a full walk: the upload set may be filtered,
    #    but the "is it still there" set must not be, or every excluded path
    #    reads as deleted. (This is what broke main in 782b657.)
    local_all = walk_local(root, only=None, use_all=True)
    if use_all:
        to_upload = local_all
    elif not ref_exists:
        # A filter narrows what is uploaded. On a branch that does not exist
        # yet that would quietly create a branch holding only the filtered
        # files and nothing else -- a half-written branch that looks pushed.
        # Uploading the whole tree is the only honest reading of the request,
        # so say so loudly instead of narrowing.
        print(f"NOTE: branch '{branch}' is new, so the path filter is ignored "
              f"and the full tree ({len(local_all)} files) is pushed.")
        to_upload = local_all
    else:
        to_upload = {p: c for p, c in local_all.items() if selects(only, p)}

    if not use_all and not to_upload:
        raise SystemExit(
            "REFUSING to push: the path filter selected 0 of "
            f"{len(local_all)} tracked files, so there is nothing to upload.\n"
            f"  filter: {' '.join(sorted(only))}\n"
            "A filter that matches nothing used to print 'No changes to push' and\n"
            "exit 0, which is how a directory argument like '-- lib test' silently\n"
            "discarded a whole cycle of work. Check the paths, or pass no filter at\n"
            "all to push the entire tree."
        )

    changed = {p: c for p, c in to_upload.items() if remote.get(p) != blob_sha(c)}
    deleted = sorted(p for p in remote if p not in local_all)

    if deleted and not allow_deletes:
        print("REFUSING to push: these remote files are gone locally:")
        for p in deleted:
            print(f"  - {p}")
        print("If that is intended, re-run with --allow-deletes.")
        print("If not, restore the files (e.g. `git checkout -- <path>`).")
        sys.exit(3)

    if not changed and not deleted and ref_exists:
        print("No changes to push.")
        return

    if not changed and not deleted and not ref_exists:
        # The branch does not exist and its content already matches the base.
        # There is no file to upload, so the only honest thing to do is create
        # the branch AT the base commit -- which is exactly what
        # `git push origin main:BRANCH` does, and it leaves no junk commit on
        # the new branch. (An "empty commit" is not an option here: GitHub
        # answers 422 "Invalid tree info" for a tree with no entries, so an
        # empty commit cannot be built through the git-data API at all.)
        status, body = api("POST", f"/repos/{owner}/{repo}/git/refs",
                           {"ref": f"refs/heads/{branch}", "sha": base_sha})
        if status != 201:
            print(f"Branch creation failed: {status} {body}")
            sys.exit(1)
        print(f"Created branch '{branch}' at {base_sha} (no changes to commit).")
        print(f"FULL_SHA={base_sha}")
        return

    # 4. an empty repository cannot be seeded through the git-data API at all
    #    (creating a blob returns 409 "Git Repository is empty"), so the first
    #    commit goes in through the Contents API and the caller re-runs to
    #    upload whatever is left. Bailing out here with a clear message beats
    #    a 409 halfway through the upload.
    if base_sha is None:
        first = min(to_upload)
        seed_empty_repo(owner, repo, branch, to_upload, msg)
        rest = sorted(p for p in to_upload if p != first)
        if rest:
            print(f"  {len(rest)} more file(s) queued; re-run the same command "
                  f"to push them (the branch now exists).")
        return

    # 5. upload blobs
    tree_items = []
    modes = git_modes(root)
    for path, content in changed.items():
        mode = modes.get(path, "100644")
        print(f"  uploading {path} ({len(content)} bytes, {mode})")
        status, blob = api("POST", f"/repos/{owner}/{repo}/git/blobs",
                           {"content": base64.b64encode(content).decode(), "encoding": "base64"})
        if status != 201:
            print(f"Blob upload failed for {path}: {status} {blob}")
            sys.exit(1)
        tree_items.append({"path": path, "mode": mode, "type": "blob", "sha": blob["sha"]})
    for path in deleted:
        print(f"  deleting {path}")
        tree_items.append({"path": path, "mode": "100644", "type": "blob", "sha": None})

    # 6. create tree to diff against.
    tree_body = {"tree": tree_items}
    if base_sha is not None:
        tree_body["base_tree"] = base_sha

    status, new_tree = api("POST", f"/repos/{owner}/{repo}/git/trees", tree_body)
    if status != 201:
        print(f"Tree creation failed: {status} {new_tree}")
        sys.exit(1)

    # 7. create commit
    commit_body = {"message": msg, "tree": new_tree["sha"]}
    if base_sha is not None:
        commit_body["parents"] = [base_sha]
    status, commit = api("POST", f"/repos/{owner}/{repo}/git/commits", commit_body)
    if status != 201:
        print(f"Commit creation failed: {status} {commit}")
        sys.exit(1)

    # 8. point the branch at the new commit. A branch that did not exist is
    #    created here (POST) rather than patched; 422 then means someone else
    #    created it in between, which is a real conflict worth stopping on.
    if ref_exists:
        status, body = api("PATCH", f"/repos/{owner}/{repo}/git/refs/heads/{branch}",
                           {"sha": commit["sha"]})
        if status != 200:
            print(f"Ref update failed: {status} {body}")
            sys.exit(1)
    else:
        status, body = api("POST", f"/repos/{owner}/{repo}/git/refs",
                           {"ref": f"refs/heads/{branch}", "sha": commit["sha"]})
        if status != 201:
            print(f"Ref creation failed: {status} {body}")
            print("If the branch already exists, re-run: it will update it.")
            sys.exit(1)

    # 9. VERIFY, do not trust. The founder's own complaint (10 Oct): three
    #    calls printed a green line, and the first two left 5 of 10 files
    #    unpushed. Every step above reported SUCCESS -- 201 on every blob,
    #    201 on the tree, 201 on the commit, 200 on the ref -- and the push
    #    was still incomplete. A helper that cannot catch its own failure
    #    forces every caller to write a second verifier by hand, and that
    #    is exactly what `tool/remote_state.py` is.
    #
    #    So the helper reads the tree it just moved the branch to, and
    #    checks BOTH axes on every path it claims to have pushed: content
    #    and mode. Re-reading from the API -- not from the local dict of
    #    what we meant to send -- is the whole point: a diff against
    #    `changed` can only ever confirm our own intent, and the defect is
    #    that intent was never achieved.
    # A verification failure must NOT leave a green success line and exit 0
    # on stdout -- that is the exact shape the founder reported (a green line
    # over an incomplete push). Exit 5 is distinct from 2 (bad args) and
    # 3 (refused deletions), so a caller can tell "I refused" from "I pushed
    # and it did not land". The FULL_SHA line is NOT printed on failure: it
    # is what a scraper greps to decide the push worked.
    if not verify_push(owner, repo, branch, changed, modes, deleted):
        print("REFUSING to report success: the push is INCOMPLETE.")
        sys.exit(5)

    print(f"Pushed {len(changed)} changed, {len(deleted)} deleted -> "
          f"{owner}/{repo}@{branch} commit {commit['sha']}")
    print(f"FULL_SHA={commit['sha']}")


if __name__ == "__main__":
    main()
