#!/usr/bin/env python3
"""Prove `tool/gen_communes.py` reads its inputs honestly, and says so when
it cannot.

Run directly -- it is not a `flutter test`:

    python3 test/gen_communes_test.py

**Why this file exists.** `gen_communes.py` builds
`assets/data/communes_dz.json`, the 1,541-commune picker every project form
opens, and `test/communes_test.dart` guards the *asset*. Nothing guarded the
*generator*, and this is the last load-bearing tool in `tool/` without a
battery. It was also the one that could least afford one: on this host all
four of its inputs are gone, so "the generator has never failed" and "the
generator cannot run here" were indistinguishable -- and the second is true.

**The shipped asset is NOT what is broken, and this battery proves that
separately.** Measured on it before writing a line: declared `total` 1541 =
actual rows 1541, every per-wilaya `count` matches its row list, zero
search-blind `arkey` duplicates inside a wilaya, zero strings that `clean()`
would still change, zero empty Latin names, and all 58 wilaya names agreeing
with `taxonomy.dart`. The data is right. Cases 20-24 pin that, so a future
regeneration that quietly breaks the asset fails here rather than on a phone.

**Two defects, both in how the generator reads rather than in what it writes.**

  1. **A lost taxonomy row read as a wilaya with no seat name.** The old
     reader was one positional regex over the Dart source. Reformat *one* row
     -- double the quotes, swap the two named fields, break the line after the
     comma -- and that row is simply not matched, while the regex still returns
     57 rows and no error. The caller used `tax.get(cid)`, so `None` meant both
     "no taxonomy spelling" and "my reader lost this row", and it fell back to
     the kossa spelling. The run finished **exit 0** on a dataset whose picker
     header disagreed with the rest of the app. This is the third time this
     repo has recorded that shape of bug: something absent read as if it had
     been measured (9 Oct portfolio mirror, 1 Oct census pin, now here). Cases
     1-9 pin the reader against five reformattings that the old one answered
     57/58 to, and case 10 pins the refusal that makes it loud.

  2. **The four missing inputs produced a traceback, not an answer.** Measured:
     `FileNotFoundError` naming `/home/renia/nadjah_repo/...`, a path that has
     not existed since the 26 Sep rebuild, with no hint that the asset is fine
     and the operator needs a download rather than a rebuild. Case 11 pins the
     new exit 2 and its named list.

**Cases 13-17 are the control for the whole file, and they are the ones that
make the rest meaningful.** Cases 1-12 only measure the reader and the error
paths, and a battery that never generates anything would pass against a
generator that cannot generate. So the real `main()` is run end to end against
a **synthetic backbone written to a temp file**, paired with the **real
`taxonomy.dart`**, with `OUT` repointed so the shipped asset cannot be
touched and the four missing inputs are not needed. That is the only way to
exercise the verification block and the write on a host whose inputs are gone:
  * 13-14  a well-formed run **exits 0 and writes** a dataset that keeps
           every promise the header makes (total matches the backbone, every
           wilaya keeps its taxonomy spelling, every row carries both scripts).
  * 15-16  a wilaya the taxonomy does not cover **exits 1 and writes NOTHING**
           -- the loud half of defect 1, end to end. Before the fix this
           returned 0 and wrote a file whose header disagreed with the app.
  * 17     the official total is 1,541, pinned separately because the synthetic
           run must patch it to stay small -- otherwise "the constant is right"
           would be an untested assumption inside a passing case.

`OFFICIAL_TOTAL` is patched for the synthetic runs and asserted on its own, so
the number is checked rather than assumed.

Expected: 22/22. A failure means the dataset behind every Algerian commune
picker is being rebuilt by a tool that is not being read.
"""

import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(REPO, "tool", "gen_communes.py")
ASSET = os.path.join(REPO, "assets", "data", "communes_dz.json")
TAXONOMY = os.path.join(REPO, "lib", "src", "data", "taxonomy.dart")

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("PASS  " if cond else "FAIL  ") + name +
          (("  -- " + detail) if detail and not cond else ""))


def load_tool():
    """Import the tool without running its `main`."""
    spec = importlib.util.spec_from_file_location("gen_communes_under_test",
                                                  TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def reads(fn, *args):
    """Call `fn`, grading a refusal as a FAILED read rather than a crash.

    A battery that dies on a tool is not a battery against that tool: the run
    reports a traceback, prints no score, and the reader cannot tell a killed
    defect from a test file with a bug in it. Mutation M2 (a reader that only
    parses single-quoted rows) was genuinely killed by this file, but it killed
    it the unreadable way -- one uncaught ValueError and no verdict at all.
    """
    try:
        return fn(*args), None
    except Exception as exc:                       # noqa: BLE001
        return None, "%s: %s" % (type(exc).__name__, exc)


def needs(mod, *names):
    """Report the cases that cannot run against this tool, as failures.

    Without this the battery CRASHES against the pre-fix tool with an
    AttributeError, and a crash is not a verdict: it fails the run for a
    reason that has nothing to do with the assertions, prints no score, and
    cannot tell the reader which of the 25 cases were actually answered. A
    battery that grades a broken tool one case at a time is what makes "9/17
    against the unfixed tool" a claim about the DEFECTS rather than about the
    first line that happened to touch the missing name.
    """
    missing = [n for n in names if not hasattr(mod, n)]
    if not missing:
        return True
    check("the tool exposes %s" % ", ".join(names), False,
          "absent: %s -- the reader cases below cannot be graded" % missing)
    return False


# --- The real taxonomy, under reformattings that are all legal Dart --------
_REAL = open(TAXONOMY, encoding="utf-8").read()
_ROW = "(id: '01', name: 'أدرار'),"

VARIANTS = {
    "as shipped": _REAL,
    "double quotes": _REAL.replace(_ROW, '(id: "01", name: "أدرار"),'),
    "named fields swapped": _REAL.replace(_ROW, "(name: 'أدرار', id: '01'),"),
    "line broken after the comma":
        _REAL.replace(_ROW, "(id: '01',\n         name: 'أدرار'),"),
    "trailing comma": _REAL.replace(_ROW, "(id: '01', name: 'أدرار',),"),
}


def run_generator(tool, tmp, out, wilayas, capture=False, unsourceable=None):
    """Run the tool's real `main()` over synthetic inputs, writing to `out`.

    The module globals are repointed rather than the files on disk: `OUT` so a
    refused run cannot touch the shipped asset, the four input paths so the
    missing ones are supplied, and `OFFICIAL_TOTAL` so a two-wilaya backbone
    can pass its own verification. `REPO` is deliberately NOT repointed -- the
    run reads the app's REAL taxonomy, which is the point of the control.
    """
    nad = os.path.join(tmp, "nad.json")
    kc = os.path.join(tmp, "kossa_com.json")
    kw = os.path.join(tmp, "kossa_wil.json")
    geo = os.path.join(tmp, "geo.csv")

    cities = {w: ["Adrar", "Reggana"] for w in wilayas}
    with open(nad, "w", encoding="utf-8") as fh:
        json.dump([{"stateCode": int(w), "state": "Test-%s" % w,
                    "cities": [{"name": c} for c in cities[w]]}
                   for w in wilayas], fh)
    ar_by_latin = {"Adrar": "أدرار", "Reggana": "رقان"}
    if unsourceable:
        # and out of kossa too
        pass
    with open(kc, "w", encoding="utf-8") as fh:
        json.dump([{"id": i + 1, "wilaya_id": int(w), "name": c,
                    "ar_name": ar_by_latin[c]}
                   for w in wilayas
                   for i, c in enumerate(cities[w])
                   if c != unsourceable], fh)
    with open(kw, "w", encoding="utf-8") as fh:
        json.dump([{"id": int(w), "ar_name": "Test-%s" % w} for w in wilayas],
                  fh)
    # `unsourceable` names a commune the two Arabic sources deliberately do
    # NOT carry, so the generator has to drop the row and say so.
    with open(geo, "w", encoding="utf-8") as fh:
        fh.write("name_fr,name_ar,wilaya_code\n")
        for w in wilayas:
            for c in cities[w]:
                if c != unsourceable:
                    fh.write("%s,%s,%s\n" % (c, ar_by_latin[c], w))

    saved = {k: getattr(tool, k) for k in
             ("NADJAH", "KOSSA", "KOSSA_WIL", "GEO", "OUT", "OFFICIAL_TOTAL")}
    tool.NADJAH, tool.KOSSA = nad, kc
    tool.KOSSA_WIL, tool.GEO, tool.OUT = kw, geo, out
    tool.OFFICIAL_TOTAL = sum(len(v) for v in cities.values())
    try:
        if os.path.exists(out):
            os.remove(out)
        if not capture:
            return tool.main()
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = tool.main()
        return rc, buf.getvalue()
    finally:
        for k, v in saved.items():
            setattr(tool, k, v)


def temp_taxonomy(tmp, text):
    p = os.path.join(tmp, "taxonomy.dart")
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(text)
    return p


def main():
    tool = load_tool()
    tmp = tempfile.mkdtemp(prefix="gen_communes_test_")

    try:
        # Every case below that needs the new reader or the new input check is
        # graded as a failure when the tool does not have them, so the battery
        # reports a score against a broken tool instead of dying on it.
        has_reader = needs(tool, "taxonomy_wilayas")
        needs(tool, "require_inputs")

        # ================= cases 1-5: the reader survives a reformat ========
        for i, (label, src) in enumerate(VARIANTS.items(), start=1):
            if not has_reader:
                check(f"case {i}: the taxonomy reader reads all 58 wilayas "
                      f"when the rows are {label}", False,
                      "tool has no taxonomy_wilayas()")
                continue
            got, err = reads(tool.taxonomy_wilayas,
                             temp_taxonomy(tmp, src))
            check(f"case {i}: the taxonomy reader reads all 58 wilayas when "
                  f"the rows are {label}",
                  err is None and len(got) == 58 and got.get("1") == "أدرار",
                  err or f"read {len(got)}, wilaya 1 -> {got.get('1')!r}")

        # ================= case 6: it agrees with what it read ==============
        got = {}
        if has_reader:
            got, _e = reads(tool.taxonomy_wilayas, temp_taxonomy(tmp, _REAL))
        got = got or {}
        check("case 6: every id is normalised, so '01' and '1' are one wilaya",
              "01" not in got and "1" in got and "58" in got,
              f"keys sample {sorted(got)[:3]}")

        # ================= cases 7-9: it refuses rather than truncates =====
        g7, e7 = (reads(tool.taxonomy_wilayas,
                        temp_taxonomy(tmp, "class X { int y = 1; }"))
                  if has_reader else (None, "no reader"))
        check("case 7: a taxonomy with no wilaya list is refused, not read as "
              "an app with no wilayas",
              e7 is not None and g7 is None, e7 or "accepted a file with no "
              "wilaya list in it")

        g8, e8 = (reads(tool.taxonomy_wilayas, temp_taxonomy(
            tmp, "class X { static const wilayas = [(id: '01', n: 'أ')]; }"))
            if has_reader else (None, "no reader"))
        check("case 8: a record that is not an (id, name) pair is refused",
              e8 is not None and g8 is None,
              e8 or "accepted a record that is not an (id, name) pair")

        # ---- case 8b-8d: a record must be EXACTLY (id, name) --------------
        # Mutation M10 (loosening the field-set test to `if not fields:`)
        # SURVIVED this battery. It survives because a strict test and a loose
        # one agree on every well-formed record, and no case fed the reader a
        # MALFORMED one that a loose reader would still accept. Three do, and
        # all three are records a maintainer can write by accident:
        for label, src, why in (
            ("missing its name", "(id: '01')",
             "a wilaya with no name at all"),
            ("with a misspelt field", "(id: '01', naam: 'أدرار')",
             "an Arabic name under a field the reader does not know, so the "
             "record carries no name"),
            ("with an extra field", "(id: '01', name: 'أدرار', slug: 'adrar')",
             "a record that grew a field the reader must not silently ignore"),
        ):
            gr, er = reads(tool.taxonomy_wilayas, temp_taxonomy(
                tmp, "class T { static const List<Object> wilayas = [%s]; }\n"
                     % src))
            check(f"case 8x: a record {label} is refused, not read as {why}",
                  er is not None and gr is None,
                  er or f"accepted as {gr}")

        g9, e9 = (reads(tool.taxonomy_wilayas, temp_taxonomy(
            tmp, "class X { static const wilayas = [(id: '01', name: 'أ'), "
                 "(id: '1', name: 'ب')]; }"))
            if has_reader else (None, "no reader"))
        check("case 9: the same wilaya listed twice under both id spellings is "
              "refused",
              e9 is not None and g9 is None,
              e9 or "accepted wilaya 01 and 1 as two different wilayas")

        # ---- case 9b: a well-formed list with no rows in it --------------
        # This is the guard mutation M5 deleted and the battery SURVIVED, so
        # it had no case at all. It matters because an empty taxonomy and an
        # app with no wilayas are different worlds, and only the first is
        # possible: the suite has 58 wilayas and `communes_test.dart` loads
        # all 1,541 communes against them.
        if has_reader:
            empty, err9b = reads(tool.taxonomy_wilayas, temp_taxonomy(
                tmp, "class Taxonomy { static const List<Object> wilayas = "
                     "[]; }\n"))
            check("case 9b: a taxonomy that parses to ZERO wilayas is "
                  "refused, not accepted as an app with no wilayas",
                  err9b is not None and (empty is None),
                  err9b or f"accepted an empty read ({len(empty or {})} rows)")
        else:
            check("case 9b: a taxonomy that parses to ZERO wilayas is "
                  "refused, not accepted as an app with no wilayas", False,
                  "tool has no taxonomy_wilayas()")

        # ================= case 10: a commented-out row is not a live one ==
        commented = _REAL.replace(_ROW, "// (id: '01', name: 'أدرار'),\n")
        commented = commented.replace(
            "(id: '02', name: 'الشلف'),", "(id: '02', name: 'الشلف'),")
        cgot = {}
        if has_reader:
            cgot, e10 = reads(tool.taxonomy_wilayas,
                              temp_taxonomy(tmp, commented))
        cgot = cgot or {}
        check("case 10: a commented-out wilaya row is not counted as a live "
              "one (and the file is still readable, not refused)",
              e10 is None and "1" not in cgot and len(cgot) == 57,
              e10 or f"read {len(cgot)} rows")

        # ================= case 11: the missing-input answer ===============
        rr = subprocess.run([sys.executable, TOOL], capture_output=True,
                            text=True)
        out = rr.stdout + rr.stderr
        check("case 11: on this host -- where the inputs are gone -- the tool "
              "exits 2 and names every missing input, never a traceback",
              rr.returncode == 2 and "Traceback" not in out
              and "MISSING" in out and "FileNotFoundError" not in out,
              f"rc={rr.returncode}")

        # ================= case 12: it says the asset is safe ===============
        check("case 12: the refusal says the shipped asset is untouched, so an "
              "operator does not rebuild it from itself",
              "untouched" in out and "do not" in out.lower(), "")

        # ================= case 17: the constant itself ===================
        check("case 17: the official national total the generator verifies "
              "against is 1,541 communes", tool.OFFICIAL_TOTAL == 1541,
              f"got {tool.OFFICIAL_TOTAL}")

        # ================= cases 13-16: the real main(), end to end ========
        out = os.path.join(tmp, "out.json")
        rc = run_generator(tool, tmp, out, wilayas=["01", "02"])
        check("case 13: a well-formed run exits 0", rc == 0, f"rc={rc}")
        if rc == 0 and os.path.exists(out):
            d = json.load(open(out, encoding="utf-8"))
            check("case 14a: it wrote a dataset whose total equals the "
                  "backbone it was given",
                  d["total"] == 4 and len(d["communes"]) == 2,
                  f"total {d.get('total')}, {len(d.get('communes', {}))} wl")
            check("case 14b: every wilaya kept the SPELLING the app's taxonomy "
                  "uses, not the dataset's fallback",
                  d["wilayas"]["1"]["ar"] == "أدرار",
                  f"got {d['wilayas']['1']['ar']!r}")
            check("case 14c: every commune carries both an Arabic and a Latin "
                  "spelling",
                  all(a.strip() and l.strip() for v in d["communes"].values()
                      for a, l in v), "")
        else:
            check("case 14a: it wrote a dataset", False,
                  f"rc={rc}, file written={os.path.exists(out)}")
            check("case 14b: taxonomy spelling preserved", False, "no file")
            check("case 14c: both scripts present", False, "no file")

        rc3, txt3 = run_generator(tool, tmp, os.path.join(tmp, "out2.json"),
                                  wilayas=["01", "02"], capture=True)
        # The run above verified a total of 4 against a patched constant. The
        # old line printed "total == 1,541" regardless, so the confirmation
        # agreed with a run it had nothing to do with.
        check("case 14d: the confirmation line prints the total the run "
              "actually verified, not a number typed into the script",
              rc3 == 0 and "total == 4" in txt3 and "1,541" not in txt3,
              f"rc={rc3}")

        # ---- case 15a: a commune with no Arabic must FAIL the run ---------
        # Mutation M7 (dropping the missing-Arabic refusal) SURVIVED this
        # battery, and it survived for a reason worth keeping: every synthetic
        # run above gives each commune an Arabic name, so the guard had no case
        # that could ever trip it. A name present in NEITHER Arabic source is
        # the situation the header's third promise is about, so it gets one
        # here -- built by pointing both Arabic sources at a different
        # commune, leaving the backbone's own name unsourced.
        #
        # It also proves the claim in the tool's comment is load-bearing rather
        # than decorative: the per-wilaya count check catches the dropped row
        # too, which is why this case must assert on WHICH failure is named --
        # otherwise it passes for the wrong reason and M7 survives again.
        rc4, txt4 = run_generator(tool, tmp, os.path.join(tmp, "out3.json"),
                                  wilayas=["01"], unsourceable="Reggana",
                                  capture=True)
        check("case 15a: a commune no Arabic source can name exits 1",
              rc4 == 1, f"rc={rc4}")
        check("case 15b: and the refusal NAMES the missing Arabic, so an "
              "operator knows which commune to fix",
              "no Arabic" in txt4 and "Reggana" in txt4,
              f"output did not name it: {txt4[-200:]!r}")

        # 99 is a real wilaya number shape the taxonomy does not carry.
        rc2 = run_generator(tool, tmp, out, wilayas=["01", "99"])
        check("case 15: a wilaya the taxonomy does not cover exits 1, not 0",
              rc2 == 1, f"rc={rc2}")
        check("case 16: and that refusal writes NO file, so the shipped asset "
              "cannot be replaced by a broken run",
              not os.path.exists(out),
              "the output file from the refused run is still on disk")

        # ================= cases 18-22: the SHIPPED asset is correct ======
        data = json.load(open(ASSET, encoding="utf-8"))
        rows = sum(len(v) for v in data["communes"].values())
        check("case 18: the shipped asset holds the official 1,541 communes, "
              "and its declared total is the truth",
              data["total"] == 1541 and rows == 1541,
              f"declared {data['total']}, rows {rows}")

        mism = [k for k, v in data["communes"].items()
                if data["wilayas"][k]["count"] != len(v)]
        check("case 19: every wilaya's declared count equals its own row list",
              not mism, f"{len(mism)} wilaya(s) disagree")

        dup = []
        for wid, lst in data["communes"].items():
            seen = set()
            for ar, _lat in lst:
                a = tool.arkey(ar)
                if a in seen:
                    dup.append((wid, ar))
                seen.add(a)
        check("case 20: no wilaya holds two communes the search cannot tell "
              "apart", not dup, f"{len(dup)} collision(s)")

        unnormalised = [ar for lst in data["communes"].values()
                        for ar, _l in lst if tool.clean(ar) != ar]
        check("case 21: every shipped Arabic name is already normalised "
              "(no bidi marks, no harakat, no Maghrebi letter forms)",
              not unnormalised, f"{len(unnormalised)} unnormalised")

        empty = [(wid, lat) for wid, lst in data["communes"].items()
                 for _ar, lat in lst if not lat.strip()]
        check("case 22: no commune has an empty Latin spelling, so a Latin "
              "keyboard still finds it", not empty, f"{len(empty)} empty")

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    bad = [n for n, ok in results if not ok]
    print()
    print(f"{len(results) - len(bad)}/{len(results)} cases passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
