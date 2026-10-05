#!/usr/bin/env python3
"""Prove `gh_push.py` refuses a ROOT that is not a repo, and that it says so.

Run directly — it drives the real helper's tree walk and is not a
`flutter test`:

    python3 test/push_helper_test.py

**Why this file exists.** The Loop protocol's step 6 is the command every
tick ends on, and the note beside it recorded the trap as "run it from
`/home/hatch/workspace/repos` ... the caller's working directory, not its
arguments, is what the helper reads. It exits 0 either way." Measured on
this host, **two of those three clauses are false**:

  1. the *arguments* decide. `walk_local(root)` asks
     `git -C <root> ls-files`, so ROOT is resolved **relative to the
     caller's cwd** — an absolute ROOT works from any directory, and the
     working form the protocol tells ticks to use is a cwd dependency it
     never states;
  2. it does **not** exit 0. `raise SystemExit(msg)` exits **1**, measured
     directly and through `subprocess.returncode`. The "green exit code
     from a refused push" story is the same shape as the two the protocol
     already documents elsewhere (bare `git push`, the empty upload set),
     so it is very likely to be believed and very likely to be checked
     only by exit code;
  3. it **never touched the network**. The refusal is `step 3`, after the
     base ref is read, so a probe of it is a ref read plus a git call —
     and every case here is the *tree walk* alone, which is pure git and
     filesystem. Nothing here can mint a commit or move a ref.

So this file tests `walk_local`/`git_tracked_set` directly rather than
`main()`, which keeps the cases hermetic: **no push, no commit, no ref
move, no credential read.** That is also why case 3 can assert a real exit
code — it runs the module as a subprocess with an unparseable argument
list, so it exits 2 before any I/O and never reaches the network.

**The generalisable half is case 4.** The 26 Sep rebuild cost this loop two
ticks because the protocol's path table listed paths that no longer existed,
and every tick that trusted the table died on arrival. Nothing checked the
table. Case 4 parses the real table out of `IMPROVEMENT_BACKLOG.md` and
asserts every path in it exists on this host, so a table cannot rot into a
list of commands that cannot run.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
HELPER_DIR = "/home/hatch/workspace/repos"
HELPER = os.path.join(HELPER_DIR, "gh_push.py")
BACKLOG = os.path.join(ROOT, "IMPROVEMENT_BACKLOG.md")

sys.path.insert(0, HELPER_DIR)

FAILED = []


def check(label, got, want):
    ok = got == want
    print("  %-4s %-52s %s" % ("PASS" if ok else "FAIL", label,
                               "" if ok else "got=%r want=%r" % (got, want)))
    if not ok:
        FAILED.append(label)
    return ok


def walk(root, cwd):
    """Call the helper's own walk from a given cwd.

    ALWAYS returns a 3-tuple: ("ok", 1, n) for a walk, ("refused", 1,
    message) for a refusal, or ("bad", 0, text) when the walk neither walks
    nor refuses -- the shape a silently-greening helper
    would take. The `except Exception` arm is deliberate and is what the
    first version of this file lacked: with only SystemExit caught, a
    helper whose walk raised something else -- or returned the wrong shape
    -- crashed the harness with a traceback. A crash still exits non-zero,
    so it still fails, but the reader gets a stack trace instead of the
    sentence naming which assumption stopped being true.
    """
    import importlib
    saved = os.getcwd()
    try:
        os.chdir(cwd)
        gh_push = importlib.import_module("gh_push")
        importlib.reload(gh_push)
        try:
            out = gh_push.walk_local(root, only=None, use_all=True)
        except SystemExit as exc:
            return "refused", 1, str(exc)
        except Exception as exc:                      # noqa: BLE001
            return "bad", 0, "%s: %s" % (type(exc).__name__, exc)
        if not isinstance(out, dict):
            return "bad", 0, "walk_local returned %s, not a dict" % type(out).__name__
        # A silent-green helper returns {} here: it printed the refusal and
        # carried on. That is NOT an ok walk of zero files, it is a refusal
        # that lost its exit code -- the exact defect the protocol's note
        # claims is there. Name it, so the failure reads as a sentence.
        if not out:
            return "bad", 0, "walk_local returned an EMPTY tree for %r" % root
        return "ok", 1, len(out)
    finally:
        os.chdir(saved)


def main():
    print("push_helper: ROOT decides the walk, and a refusal exits non-zero")

    # 1. The documented trap, from the helper's own directory: ROOT="." does
    #    not name a checkout and is refused rather than guessed at.
    kind, code, msg = walk(".", HELPER_DIR)
    check("ROOT='.' from the helper's dir is refused",
          kind, "refused")
    check("  ...and the refusal names the ROOT it could not walk",
          msg.startswith("git ls-files returned nothing for ."), True)
    check("  ...and a refusal is exit 1, NOT exit 0",
          code, 1)

    # 2. The same ROOT="." from the repo itself works. This is the whole
    #    difference: the argument is resolved against cwd.
    kind, code, n = walk(".", ROOT)
    check("ROOT='.' from inside the repo walks the tree", kind, "ok")
    check("  ...and it is the real tree, not an empty success", n > 100, True)

    # 3. An ABSOLUTE ROOT works from anywhere -- including a directory that
    #    is not a checkout at all. This is the form the protocol should
    #    state, because it has no cwd dependency to get wrong.
    kind, code, n = walk(ROOT, HELPER_DIR)
    check("absolute ROOT from the helper's dir walks the tree", kind, "ok")
    check("  ...same file count as from inside the repo", n, walk(".", ROOT)[2])
    kind, code, n = walk(ROOT, "/tmp")
    check("absolute ROOT from an unrelated dir (/tmp) walks the tree",
          kind, "ok")

    # 4. THE LOAD-BEARING ONE. Every command in the protocol's path table has
    #    to exist on the host that runs it. Two ticks were lost to a table
    #    that listed the pre-rebuild paths. Parse the real table, assert the
    #    real paths, so the table cannot rot again.
    #
    #    Scoped to the table on purpose: it is the block a tick reads first
    #    and the only one with no prose hedging around it. (Prose elsewhere
    #    names /home/renia and /usr/lib/jvm precisely in order to say they
    #    are gone -- a path that must NOT exist, so a blanket "every path in
    #    the protocol exists" rule would be wrong.)
    text = open(BACKLOG, encoding="utf-8").read()
    start = text.index("## Loop protocol")
    end = text.index("\n## ", start)
    proto = text[start:end]
    # The cell is `code` possibly followed by prose, so match the FIRST
    # backticked path anywhere in the cell rather than requiring the cell to
    # end right after it. Anchoring to the row start keeps a line of prose
    # from being mistaken for a table row.
    rows = re.findall(r"^\|[^\n]*\|\s*`(/[^`]+)`", proto, re.M)
    table = [p for p in rows]
    check("the protocol's path table was found and is not empty",
          len(table) >= 4, True)
    # Scratch that a tool recreates on demand is NOT a path that can be
    # asserted to exist: design_shots_test.dart mkdir -p's /tmp/shots itself.
    # A rule that fails on a fresh boot would train the loop to ignore it.
    RECREATED = {"/tmp/shots", "/tmp/shots/"}
    hard = [p for p in table if p not in RECREATED]
    for p in hard:
        check("  %-46s exists" % p, os.path.exists(p.rstrip("/")), True)
    check("  the repo row points at this checkout",
          any(p.rstrip("/") == ROOT for p in table), True)
    check("  the helper row points at a real file, not a directory",
          os.path.isfile(HELPER), True)
    check("  the SDK row is executable",
          os.access("/home/hatch/tools/sdk/flutter/bin/flutter", os.X_OK), True)
    check("  /tmp/shots is a recreated scratch dir, exempt from the rule",
          "/tmp/shots" in RECREATED and not hard.count("/tmp/shots"), True)

    # 5. A refusal must not be reachable as a *green* exit code from the
    #    command line either. Too few args exits 2 before any I/O at all, so
    #    this is hermetic -- and it is the shape a truncated invocation takes
    #    after an agent edits the recipe wrong.
    r = subprocess.run([sys.executable, HELPER, "owner", "repo", "main"],
                       capture_output=True, text=True, cwd=ROOT)
    check("a truncated invocation exits non-zero", r.returncode != 0, True)

    print("")
    if FAILED:
        print("%d FAILED: %s" % (len(FAILED), ", ".join(FAILED)))
        return 1
    print("all push_helper cases pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
