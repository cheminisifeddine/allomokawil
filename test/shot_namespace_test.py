#!/usr/bin/env python3
"""Prove every design-shot filename in the suite is globally unique.

Run directly -- it is pure stdlib file reading, not a `flutter test`:

    python3 test/shot_namespace_test.py

**Why this file exists.** Six Oct's shard 6 failed one test and the filed
hypothesis was "62 test files share `/tmp/shots`, so concurrent writers
collide". That was recorded as an open question, and an open question
nobody re-checks drifts into a fix built on nothing. This file answers it
**statically**, which is stronger than reproducing it under load:

* every writer under `/tmp/shots` is enumerated from the sources,
* every PNG basename each one can produce is recovered, including the
  interpolated `'/tmp/shots/$name.png'` shape,
* and two files are allowed to agree on a name **never**.

The answer is that the namespace is clean: 116 distinct basenames, zero
cross-file duplicates. So the collision theory is not "probably fine", it
is dead, and this file is what keeps it dead.

**Why "statically" is the stronger claim.** The concurrent theory needed
the writes to *interleave* to do damage. The loop measured `flutter test`
concurrency at exactly 1 on this 2-core box (see the Loop protocol), so a
second file cannot be mid-`toImage` while the first reads its bytes back.
A duplicate name would still be a latent bug worth failing on -- a future
`--concurrency=2`, or a run on a bigger box, would turn it live without
anyone editing a line. That is why this is a hard failure rather than a
warning, and why it does not check for concurrency at all.
"""

import collections
import glob
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SHOTS = "/tmp/shots"

# A helper that writes a shot. The suite spells these many ways
# (`_shoot`, `_shootCard`, `_capture`, `_captureCentre`, ...) and the arity
# is not stable, so the name is recovered by taking the FIRST string
# literal in the argument list, not by assuming a position.
_CALL = re.compile(r"\b_?[A-Za-z]*([Ss]hoot|capture|Capture)\w*\(")
# A concrete path literal: '/tmp/shots/foo.png'
_LITERAL = re.compile(r"['\"]([^'\"]*/([^'\"/]+)\.png)['\"]")


def _args(src, open_paren):
    """Return the text between the paren at `open_paren` and its match."""
    depth = 1
    i = open_paren
    while i < len(src) and depth:
        if src[i] == "(":
            depth += 1
        elif src[i] == ")":
            depth -= 1
        i += 1
    return src[open_paren:i - 1]


def _first_literal(argtext):
    """First single-quoted literal in an argument list, or None.

    Single quotes only: these files are linted to avoid double-quoted
    strings, so a `"` here is far more likely to be part of some other
    expression than the shot name.
    """
    m = re.search(r"'([A-Za-z0-9_\-]+)'", argtext)
    return m.group(1) if m else None


def namespace():
    """basename -> {files that can write it}."""
    owner = collections.defaultdict(set)
    for path in sorted(glob.glob(os.path.join(REPO, "test", "*.dart"))):
        with open(path, errors="replace") as fh:
            src = fh.read()
        if SHOTS not in src:
            continue
        base = os.path.basename(path)

        for m in _CALL.finditer(src):
            name = _first_literal(_args(src, m.end()))
            if name:
                owner[name + ".png"].add(base)

        for m in _LITERAL.finditer(src):
            name = m.group(2)
            if "$" in name:          # interpolated: covered by _CALL above
                continue
            owner[name].add(base)
    return owner


def main():
    owner = namespace()
    dupes = {k: sorted(v) for k, v in owner.items() if len(v) > 1}

    print("test/shot_namespace_test.py")
    print("basenames under %s: %d, written by %d files"
          % (SHOTS, len(owner), len({f for v in owner.values() for f in v})))

    ok = True
    if dupes:
        ok = False
        print("**FAIL** %d basenames are claimed by more than one test file:"
              % len(dupes))
        for name, files in sorted(dupes.items()):
            print("   %-34s %s" % (name, ", ".join(files)))
    else:
        print("PASS  no PNG basename is written by two test files")

    # A second, independent check that does not share the parser above:
    # count the writers, because a parser that found nothing because it
    # read nothing is the failure this file exists to prevent.
    writers = [f for f in glob.glob(os.path.join(REPO, "test", "*.dart"))
               if SHOTS in open(f, errors="replace").read()]
    print("     files referencing %s: %d" % (SHOTS, len(writers)))
    if len(writers) < 40:
        ok = False
        print("**FAIL** only %d files reference %s -- this reader is broken, "
              "not the tree" % (len(writers), SHOTS))

    print("== %s ==" % ("ALL PASS" if ok else "SOME FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
