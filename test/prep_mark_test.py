#!/usr/bin/env python3
"""Prove `tool/prep_mark.py` reports what it did, and never writes under `--check`.

Run directly -- it works in a temp tree and is not a `flutter test`:

    python3 test/prep_mark_test.py

**Why this file exists.** `prep_mark.py` is the tool that mutates the shipped
brand asset `assets/brand/mark.png` -- the artwork on the auth screen and the
landing screen -- and it was the last generator in `tool/` with no battery of
its own. `test/gen_icons_test.py` copies it into a temp repo as a *fixture* for
a sibling tool's two cases; it never calls its behaviour. Nothing had run this
file and read what it printed.

**The artwork it produces was measured and is good, so nothing here changes it.**
The committed mark and the one this tool writes are byte-identical: run the old
`prep_mark.py --write` on a copy and md5 the result, then run this file's and
md5 it — `f577b56a47347d89bd600111e0fb9992` both ways. The dry-run text is
unchanged line for line. Every case below is about the two things around it.

**Four defects, all the same failure this repo keeps meeting in a new costume:
something unmeasured, reported as if it had been.**

  1. **There was no way to ask "is the mark prepped?" without rewriting it.**
     The module docstring claimed *"Idempotent by construction: once centred,
     both steps are no-ops."* That is true of the RESULT and false of the RUN:
     `--write` saved unconditionally, so a second run over an already-prepped
     mark re-encoded byte-identical artwork and printed `written` — a claim of
     work, printed by a run that did none. Measured here in case 3 by pinning
     mtime across the run: the old tool moved it, the new one does not.
     `--check` now runs both steps in memory, writes nothing, and exits 1 when
     the mark is stale.

  2. **`--write` printed `written` for work it did not do.** Even a fixed
     `--check` leaves this trap open, so the no-op path is also skipped before
     the save (case 3): identical pixels mean an untouched file, and the tool
     says what is true — `already prepped`.

  3. **Every refusal was a raw traceback.** A missing mark raised a bare
     `FileNotFoundError` naming a path and nothing else; a truncated one raised
     `OSError: image file is truncated` from inside `Image.open` with no path
     in the message at all. Both are now named refusals on exit 2 (cases 4-6),
     forced to decode eagerly so a truncated file is caught at open rather than
     from inside a crop.

  4. **A mark with no visible ink was reported as a successful trim.** It hit
     `raise SystemExit("nothing visible in this image")` from inside
     `trim_to_ink`, on a string channel, mid-run — and `SystemExit` out of a
     library function aborts the whole process for every remaining file in a
     multi-file run. It is now a `Refused` that names the threshold, exits 2,
     and leaves the rest of the run to finish (case 7 runs three files with a
     blank one in the middle and requires the third to be reported).

**The threshold is pinned from both sides** (case 2): alpha 32 is invisible and
must be trimmed away, alpha 33 must be kept — the trim boundary is the one
number in this file, and a change to it silently resizes the logo everywhere.

**Cases 8-10 are the control: nothing here tests rendering, only reporting.**
A tool that could not generate would pass cases 1-7. So the real transform is
pinned too — the shipped 1024x1024 mark becomes 795x1069, and the committed
`assets/brand/mark.png` is itself checked for prepped-ness with `--check`
(case 9), which is a live assertion about the asset the app ships.
"""
from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TOOL = REPO / "tool" / "prep_mark.py"
SHIPPED_MARK = REPO / "assets" / "brand" / "mark.png"

sys.path.insert(0, str(REPO / "tool"))


def run(*args, cwd=None):
    p = subprocess.run([sys.executable, str(TOOL), *[str(a) for a in args]],
                       cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def write_png(path, pixels, size):
    from PIL import Image
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    for x, y, a in pixels:
        im.putpixel((x, y), (10, 10, 10, a))
    im.save(path)
    return Path(path)


def fresh(tmp, name="m.png"):
    dst = tmp / name
    shutil.copy(SHIPPED_MARK, dst)
    return dst


def md5(path):
    return hashlib.md5(Path(path).read_bytes()).hexdigest()


CASES = []


def case(fn):
    CASES.append(fn)
    return fn


@case
def c01_check_does_not_write(tmp):
    """`--check` on a stale mark answers 1 and leaves the file untouched."""
    m = fresh(tmp)
    before = md5(m)
    rc, out, _ = run(m, "--check")
    assert rc == 1, "expected 1 on an unprepared mark, got %d" % rc
    assert md5(m) == before, "--check rewrote the mark it claimed to only check"
    assert "STALE" in out, "the staleness must be named, not implied: %r" % out
    assert "1024x1024" in out and "795x1069" in out, \
        "must say what it would become: %r" % out


@case
def c02_trim_threshold_pinned_from_both_sides(tmp):
    """alpha 32 is halo and is trimmed; alpha 33 is art and is kept."""
    halo = write_png(tmp / "halo.png", [(5, 5, 32)], (20, 20))
    art = write_png(tmp / "art.png", [(5, 5, 33)], (20, 20))
    rc, out, _ = run(halo, "--write")
    assert rc == 2, "a 32-alpha pixel is invisible: it must be refused, got %d" % rc
    from PIL import Image
    assert Image.open(halo).size == (20, 20), "a refused mark must not be written"
    rc, out, _ = run(art, "--write")
    assert rc == 0, "a 33-alpha pixel is visible art: %r%s" % (out, rc)
    # Trim takes it to 1x1; centring then pads it to 2x2 by the documented
    # `p == 2 * (w/2 - cx)` rule, so 2x2 -- not 1x1 -- is the correct answer.
    assert Image.open(art).size == (2, 2), \
        "a lone visible pixel must trim to 1x1 and centre-pad to 2x2"
    assert "trim   20x20 -> 1x1" in out, "the trim boundary must be visible: %r" % out


@case
def c03_write_is_a_no_op_on_a_prepped_mark(tmp):
    """`--write` twice: the second run must not touch the file, and must say so."""
    m = fresh(tmp)
    rc, _, _ = run(m, "--write")
    assert rc == 0, "first write failed"
    after_first = md5(m)
    os.utime(m, (0, 0))            # epoch mtime: any save will move it
    rc, out, _ = run(m, "--write")
    assert rc == 0, "second write failed: %d" % rc
    assert os.stat(m).st_mtime == 0, \
        "--write re-encoded an unchanged mark; idempotence is about the result, not the run"
    assert md5(m) == after_first, "bytes changed on a no-op write"
    assert "already prepped" in out, \
        "must not claim work it did not do: %r" % out
    assert "written" not in out, "'written' must mean work was done: %r" % out


@case
def c04_missing_file_is_named_not_a_traceback(tmp):
    rc, out, err = run(tmp / "nope.png", "--write")
    assert rc == 2, "a missing mark must be refused on exit 2, got %d" % rc
    assert "no such file" in err, "must name the reason: %r" % err
    assert "nope.png" in err, "must name the file: %r" % err
    assert "Traceback" not in err and "FileNotFoundError" not in err, \
        "an operator should read a reason, not a stack: %r" % err


@case
def c05_truncated_file_is_named(tmp):
    data = SHIPPED_MARK.read_bytes()
    bad = tmp / "trunc.png"
    bad.write_bytes(data[:900])
    rc, _, err = run(bad, "--write")
    assert rc == 2, "a truncated mark must be refused, got %d" % rc
    assert "cannot read" in err and "trunc.png" in err, \
        "must name the file and the reason: %r" % err
    assert "Traceback" not in err, "no stack for an unreadable file: %r" % err


@case
def c06_write_and_check_together_are_refused(tmp):
    m = fresh(tmp)            # NEVER the shipped asset: a tool that ignores
    rc, _, err = run(m, "--write", "--check")   # --check would rewrite it
    assert rc == 2, "opposite flags must not be silently resolved, got %d" % rc
    assert "opposites" in err, "must say why: %r" % err


@case
def c07_a_blank_mark_does_not_abort_the_rest_of_the_run(tmp):
    """The old code raised SystemExit from inside a library function."""
    from PIL import Image
    Image.new("RGBA", (30, 30), (0, 0, 0, 0)).save(tmp / "blank.png")
    a, b = fresh(tmp, "a.png"), fresh(tmp, "b.png")
    rc, out, err = run(tmp / "blank.png", a, b, "--write")
    assert rc == 2, "the blank mark must make the run fail, got %d" % rc
    assert "a.png" in out and "b.png" in out, \
        "files after the blank one must still be prepared: %r" % out
    assert Image.open(a).size == (795, 1069), "a.png must have been written"
    assert Image.open(b).size == (795, 1069), "b.png must have been written"


@case
def c08_the_transform_is_the_shipped_transform(tmp):
    """The control: the tool still actually generates the real artwork."""
    m = fresh(tmp)
    rc, out, _ = run(m, "--write")
    assert rc == 0, "the real mark must still prepare: %d" % rc
    from PIL import Image
    assert Image.open(m).size == (795, 1069), \
        "the shipped mark must become 795x1069, not something new"
    assert "written" in out, "a real change must still be reported as written"


@case
def c09_the_shipped_mark_is_raw_and_would_desync_the_icons(tmp):
    """The coupling `prep_mark --check` now exists to warn about.

    This case was written as "the shipped mark is prepped" and **failed**, which
    is the finding: `assets/brand/mark.png` ships as the RAW 1024x1024 artwork,
    halo and all. That is correct here and must not be "fixed" -- the shipped
    launcher icons were generated from that raw mark, and `gen_icons.py --check`
    answers 0 against it today. Prepping the asset in place would move the
    adaptive foreground's ink by **+4.4%** (25.08 -> 26.17 px of radius at
    `ADAPTIVE_INK_RADIUS`) and every icon would go stale.

    So the tool's job on the shipped asset is to REPORT the coupling, not to
    silently reconcile it. Case 1 already proves `--check` exits 1 and names the
    change without writing; this pins which mark is in the tree and that the
    answer is stable, so a tick that decides to actually write the shipped file
    has to meet this case first.
    """
    from PIL import Image
    assert Image.open(SHIPPED_MARK).size == (1024, 1024), \
        "the shipped mark is no longer the raw 1024x1024 the icons were built " \
        "from -- re-measure the icon coupling before changing this"
    rc, out, _ = run(SHIPPED_MARK, "--check")
    assert rc == 1, \
        "the shipped mark is un-prepped, and --check must say so (exit %d)" % rc
    assert "STALE" in out, "must name the coupling: %r" % out
    assert "1024x1024" in out and "795x1069" in out, \
        "must state both sizes so the blast radius is visible: %r" % out
    # and it is only a report: the shipped asset is byte-identical afterwards
    before = md5(SHIPPED_MARK)
    run(SHIPPED_MARK, "--check")
    assert md5(SHIPPED_MARK) == before, "--check must never write the shipped mark"


@case
def c10_check_is_read_only_on_a_prepped_mark(tmp):
    m = fresh(tmp)
    run(m, "--write")
    before = md5(m)
    os.utime(m, (0, 0))
    rc, out, _ = run(m, "--check")
    assert rc == 0, "a prepped mark must answer 0, got %d" % rc
    assert os.stat(m).st_mtime == 0, "--check touched an already-prepped mark"
    assert md5(m) == before, "--check changed bytes on an already-prepped mark"
    assert "STALE" not in out, "must not call a prepped mark stale: %r" % out


def main() -> int:
    passed = failed = 0
    # The shipped mark is the one file in this repo a case must never damage.
    # Grading this battery against the OLD tool did damage it: c06 passed
    # --write --check at the real path, the old tool ignores --check and saves,
    # and assets/brand/mark.png went 1024x1024 -> 795x1069 in the worktree.
    # c09's assertion caught it, but detection does not undo it -- so the hash
    # is taken up front and the file is RESTORED on every exit path, and the
    # run fails loudly if it ever had to.
    shipped_before = SHIPPED_MARK.read_bytes()
    try:
        for fn in CASES:
            tmp = Path(tempfile.mkdtemp(prefix="prep_mark_test_"))
            try:
                fn(tmp)
                print("  ok   %s" % fn.__name__)
                passed += 1
            except AssertionError as exc:
                print("  FAIL %s: %s" % (fn.__name__, exc))
                failed += 1
            except Exception as exc:
                print("  FAIL %s: %s: %s" % (fn.__name__, type(exc).__name__, exc))
                failed += 1
            finally:
                shutil.rmtree(tmp, ignore_errors=True)
    finally:
        if SHIPPED_MARK.read_bytes() != shipped_before:
            SHIPPED_MARK.write_bytes(shipped_before)
            print("  FAIL run_restored_shipped_mark: a case rewrote "
                  "assets/brand/mark.png; it has been restored from the hash "
                  "taken at the start of the run")
            failed += 1
    print("%d passed / %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
