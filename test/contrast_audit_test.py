#!/usr/bin/env python3
"""Prove the WCAG contrast audit cannot report GREEN on a palette that fails.

Run directly -- it is pure Python and is not a `flutter test`:

    python3 test/contrast_audit_test.py

**Why this file exists.** `tool/contrast_audit.py` is the app's only
contrast reader and the tool the loop cites on nearly every visual tick --
"contrast_audit 28/28" appears ~40 times in this backlog. It had **no test
battery at all**: of the app's audit tools it was the last one without one,
after the tap-target audit was given `tap_target_probe_test.py`.

Three defects were live on the real tree when this file was written. All three
are the same species: **the audit answered a question nobody asked.**

  1. **`--json` exited 0 no matter what.** The JSON branch was
     `print(...); return 0`, so a palette with three pairs under threshold
     emitted 28 rows carrying `"pass": false` and still exited **0**. Every
     consumer that pipes this audit into a script got a green verdict from a
     red palette -- and `--json` exists precisely to be consumed by a script.
  2. **A deleted token crashed the tool with the wrong error.**
     `resolve()` fell back to `token.lstrip("#").upper()` for any name missing
     from the palette, so removing `textMuted` from `app_theme.dart` returned
     the string `"textMuted"` and died two lines later with
     `ValueError: invalid literal for int() with base 16: 'TE'`. The crash
     names the arithmetic, never the cause. And the `if fg is None` guard in
     `token_report` that was written to catch it was **dead code that had
     never fired once**.
  3. **The table printed a different number than the verdict used.** The
     verdict is taken from the exact double and the row prints
     `round(ratio, 2)`. `#959595` on white is `2.995346`: it printed
     `3.00 (need 3.0)` directly above a **FAIL** marker. The number a reader
     checks against the threshold is not the number that decided the row.

Cases 1-4 are CONTROLS, asserted FIRST and unconditionally, against the real
tool and the real theme: a reader that silently drops rows or exits 0 on the
live palette is a BLIND reader, not a lenient one. This repo has shipped
seven guards that could not fail, all by exactly that route.

Every mutating case asserts **both** halves, because each defect is a verdict
that is wrong in the convenient direction: the row and the exit code. A
battery that only checks the JSON body passes the pre-fix `--json` bug.
"""

import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "tool", "contrast_audit.py")
THEME = os.path.join(ROOT, "lib", "src", "core", "theme", "app_theme.dart")

_spec = importlib.util.spec_from_file_location("contrast_audit", TOOL)
ca = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ca)

_results = []


def check(label, ok):
    _results.append((label, ok))
    print("%s   %s" % ("PASS  " if ok else "FAIL  ", label))


def run_tool(theme_path, argv):
    """Run the real tool as a SUBPROCESS against `theme_path`.

    A subprocess is the only honest way to read the exit code: calling
    `main()` in-process cannot distinguish "returned 1" from "raised", and
    the pre-fix `--json` bug lived entirely in the return value.
    """
    tmp = tempfile.mkdtemp(prefix="ca_case_")
    try:
        lib = os.path.join(tmp, "lib")
        os.makedirs(lib)
        shutil.copy(theme_path, os.path.join(lib, "app_theme.dart"))
        driver = os.path.join(tmp, "drive.py")
        with open(driver, "w", encoding="utf-8") as fh:
            fh.write(
                "import importlib.util, sys\n"
                "spec = importlib.util.spec_from_file_location('ca', %r)\n"
                "m = importlib.util.module_from_spec(spec)\n"
                "spec.loader.exec_module(m)\n"
                "m.THEME = %r\n"
                "sys.argv = %r\n"
                "sys.exit(m.main())\n"
                % (TOOL, os.path.join(lib, "app_theme.dart"), ["ca"] + argv))
        proc = subprocess.run([sys.executable, driver], cwd=tmp,
                              capture_output=True, text=True)
        return proc
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def palette_text(mutate=None):
    """The REAL theme source, optionally mutated, as a standalone file."""
    src = open(THEME, encoding="utf-8").read()
    if mutate:
        src = mutate(src)
    return src


def write_theme(text):
    fd, path = tempfile.mkstemp(prefix="ca_theme_", suffix=".dart")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def main():
    # ── CONTROLS on the real theme (cases 1-4) ───────────────────────────
    pal = ca.parse_palette(THEME)
    check("control: the real theme parses into >=20 tokens (got %d)" % len(pal),
          len(pal) >= 20)
    rows = ca.token_report(pal)
    check("control: every declared pair produces a row -- none dropped "
          "(%d rows, %d pairs declared)"
          % (len(rows), len(ca.PAIRS)),
          len(rows) == len(ca.PAIRS))
    check("control: no row on the real theme is unresolved",
          not [r for r in rows if r.get("unresolved")])
    judged = [r for r in rows if r["kind"] != "decor"]
    proc = run_tool(THEME, ["token"])
    check("control: the real palette exits 0 (rc=%d, %d judged)"
          % (proc.returncode, len(judged)),
          proc.returncode == 0)

    # ── 1. `--json` on a RED palette exits 1, not 0 ────────────────────────
    # Pre-fix this was the headline bug: the JSON body carried three
    # `"pass": false` rows and the process still returned 0.
    bad = write_theme(palette_text(lambda s: s.replace(
        "Color(0xFF6C707A)", "Color(0xFFD8D8D8)")))
    try:
        p = run_tool(bad, ["token", "--json"])
        payload = json.loads(p.stdout)
        failing = [r for r in payload["pairs"]
                   if not r["pass"] and r["kind"] != "decor"]
        check("a red palette really is red in the JSON body (%d failing)"
              % len(failing), len(failing) > 0)
        check("case 1: `--json` EXITS 1 on that palette (rc=%d) -- pre-fix "
              "this was 0 with the same body" % p.returncode,
              p.returncode == 1)
        p2 = run_tool(bad, ["token"])
        check("case 1b: the text branch exits 1 on the same palette "
              "(rc=%d), so both branches agree" % p2.returncode,
              p2.returncode == 1)
    finally:
        os.unlink(bad)

    # ── 2. a deleted token is UNRESOLVED, not a ValueError ────────────────
    # The regression that made the guard dead code: the tool used to die with
    # `invalid literal for int() with base 16: 'TE'`.
    gone = write_theme(palette_text(
        lambda s: s.replace(
            "static const Color textMuted = Color(0xFF6C707A);", "")))
    try:
        p = run_tool(gone, ["token"])
        check("case 2: deleting a token does NOT crash with a ValueError "
              "(stderr=%r)" % p.stderr.strip()[-60:],
              "ValueError" not in p.stderr and "ValueError" not in p.stdout)
        check("case 2b: the deleted token is reported MISS/unresolved",
              "MISS" in p.stdout and "unresolved" in p.stdout)
        check("case 2c: an UNRESOLVED pair exits 1 -- a palette that cannot "
              "answer is not a passing palette (rc=%d)" % p.returncode,
              p.returncode == 1)
        pj = json.loads(run_tool(gone, ["token", "--json"]).stdout)
        check("case 2d: `--json` keeps the unresolved row instead of "
              "silently dropping it (%d rows)" % len(pj["pairs"]),
              len(pj["pairs"]) == len(ca.PAIRS))
    finally:
        os.unlink(gone)

    # ── 3. the printed number IS the number the verdict used ───────────────
    # Pre-fix the row printed round(r, 2) while PASS was decided on the exact
    # double, so `#959595` on white (2.995346) printed `3.00 (need 3.0)` above
    # a FAIL marker. The fix is a FLOOR, not more decimals: over all 16.7M
    # sRGB colours the largest value still within one ulp *below* a threshold
    # is 2.999999768 (`#989A30` on white), which prints `3.0` at 3dp too.
    # Raising precision moves the hole, it does not close it.
    hexc = "959595"
    raw = ca.ratio(hexc, "FFFFFF")
    check("case 3: the witness really does round UP to its threshold at 2dp "
          "(raw=%.6f, round2=%r)" % (raw, round(raw, 2)),
          raw < 3.0 <= round(raw, 2))
    check("case 3a: but the tool FLOORS it, so it prints below -- "
          "printed=%r" % ca.printed_ratio(raw),
          ca.printed_ratio(raw) < 3.0)
    pal2 = dict(pal)
    pal2["starEmpty"] = hexc
    row = [r for r in ca.token_report(pal2)
           if r["fg"] == "starEmpty" and r["bg"] == "bg"][0]
    check("case 3b: a row judged FAIL never prints a number at or above its "
          "threshold (printed %.3f, need %.1f)" % (row["ratio"], row["need"]),
          row["pass"] or row["ratio"] < row["need"])
    check("case 3c: the printed value never exceeds the exact ratio",
          row["ratio"] <= row["raw"])

    # ── 4. the floor is a HARD invariant, on the real witnesses ────────────
    # Measured by brute force over every sRGB foreground on white and on the
    # two washes the palette actually uses; these are the values that sit
    # within one ulp below each threshold and used to print as it.
    for hexc, need in (("9A6C5A", 4.5), ("989A30", 3.0)):
        raw = ca.ratio(hexc, "FFFFFF")
        check("case 4: #%s is %.9f, under %s, yet round()s up to %r -- the "
              "floor keeps it at %r" % (hexc, raw, need, round(raw, 3),
                                        ca.printed_ratio(raw)),
              raw < need and ca.printed_ratio(raw) < need)
    # And the invariant itself, over the whole near-boundary band.
    # 101 steps of 0.0001 across the band, EXCLUSIVE of the threshold itself:
    # the endpoint is exactly 4.5, and `printed_ratio(4.5) == 4.5` is correct,
    # so including it tested nothing about the floor.
    band = [4.5 - 0.01 + 0.0001 * i for i in range(100)]
    check("case 4b: across the whole %s band below 4.5 the printed value "
          "never reaches 4.5" % ca.EDGE_BAND,
          all(ca.printed_ratio(v) < 4.5 for v in band))
    check("case 4c: and the error is one-sided -- the floor never reads HIGH",
          all(ca.printed_ratio(v) <= v for v in band))

    # ── 5. a row sitting on the line is NAMED, not rounded through ─────────
    # Flooring is one-sided, so a passing row can print a hair under its
    # threshold. EDGE exists so that is visible instead of silent.
    pal3 = dict(pal)
    pal3["textMuted"] = "8A8A91"          # 3.428 on white -- near the 3:1 line
    rows3 = ca.token_report(pal3)
    edgy = [r for r in rows3 if r["edge"]]
    check("case 5: a ratio within %s of its threshold is flagged EDGE "
          "(%d row(s))" % (ca.EDGE_BAND, len(edgy)), len(edgy) > 0)
    # This one is a FINDING, not a control. On 10 Oct the shipped palette had
    # `success on successWash` at 4.507919 against a 4.5 floor -- a margin of
    # +0.0079, which is one nudge of that hex away from failing. The audit
    # printed it as a comfortable PASS with no sign it was that close. Pinned
    # as an exact witness so a future theme change cannot quietly move it.
    real_edge = [(r["fg"], r["bg"], round(r["raw"], 6))
                 for r in rows if r["edge"]]
    check("case 5b: the real theme's only EDGE row is still "
          "`success on successWash` at 4.507919 (got %r)" % (real_edge,),
          real_edge == [("success", "successWash", 4.507919)])
    check("case 5b2: it PASSES -- EDGE names a thin margin, it is not a "
          "failure (exit %d)" % proc.returncode,
          [r for r in rows if r["edge"]][0]["pass"] and proc.returncode == 0)
    # Asserted against the REAL theme, not a synthetic colour: the shipped
    # palette already carries an EDGE row, and a test that manufactured one
    # would prove nothing about the tool the loop actually runs. (I tried:
    # no sRGB grey lands in (4.5, 4.51] on white -- the grid is too coarse --
    # so the synthetic route needed an invented colour anyway.)
    preal = run_tool(THEME, ["token"])
    line = [l for l in preal.stdout.splitlines()
            if "success on successWash" in l]
    check("case 5c: the real `success on successWash` row prints as EDGE (%r)"
          % (line[0].strip() if line else None),
          bool(line) and line[0].strip().startswith("EDGE"))
    check("case 5d: and the table SAYS why -- the reader is told the margin is "
          "thin rather than left to trust a bare number (%r)"
          % ("within" in line[0] if line else False),
          bool(line) and "within" in line[0])
    check("case 5e: an EDGE row does not change the verdict -- the run still "
          "exits 0 (rc=%d)" % preal.returncode, preal.returncode == 0)

    print("\n%d case(s) against tool/contrast_audit.py" % len(_results))
    bad_ = [l for l, ok in _results if not ok]
    print("== %d/%d ==  %s" % (len(_results) - len(bad_), len(_results),
                               "ALL PASS" if not bad_ else "FAIL"))
    return 1 if bad_ else 0


if __name__ == "__main__":
    sys.exit(main())
