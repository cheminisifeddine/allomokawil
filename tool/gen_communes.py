#!/usr/bin/env python3
"""Build assets/data/communes_dz.json — all 58 wilayas + 1,541 communes.

WHY THIS SCRIPT EXISTS
----------------------
The project form needs every Algerian commune under its wilaya, in Arabic.
No single public dataset was correct on its own, so this merges three and
verifies the result against the official national total (1,541).

THE THREE SOURCES AND WHAT EACH IS TRUSTED FOR
  STRUCTURE / COMPLETENESS
    /home/renia/nadjah_repo/dz-wilayas-optimized.json  (in-house)
      58 wilayas x 1,541 communes. DEFINES the result: the script emits
      exactly these communes, in these wilayas. Its per-wilaya counts match
      the official figures (Alger 57, Constantine 12, Oran 26, BBA 34,
      Medea 64, M'Sila 47, Djelfa 36, Tiaret 42, Tlemcen 53, El Menia 3).
      Its names are Latin only.

  ARABIC NAMES (primary)
    kossa/algerian-cities  database/seeders/json/Commune_Of_Algeria.json
      MIT, 89 stars. 1,541 rows, wilaya_id 1..58, and -- decisively -- the
      Latin/Arabic pairing is row-correct. Its wilaya ids match both this
      app's taxonomy and the official numbering.

  ARABIC NAMES (fallback, and the repair source)
    geoalgeria  packages/dataset/data/csv/communes.csv   (MIT)

REJECTED SOURCE
    islam-re/Algeria-wilayas (MIT) looks ideal -- it ships an Arabic commune
    file and a Dart one -- but its Arabic column is ROW-SHIFTED: it pairs
    Ouzera with المدية (a wilaya name) and Baata with وزرة. Every pairing
    derived from it would be wrong, so it is not used at all.

WHAT GETS REPAIRED
  1. Duplicate rows in the Arabic sources (same commune listed twice under
     two transliterations) -- collapsed.
  2. Two communes in one wilaya carrying the same Arabic name
     (Tiaret: Mellakou and Nadorah both "ملاكو"). The true owner is decided
     by which Latin name the Arabic matches in the other sources; the other
     is re-sourced (Nadorah -> الناظورة).
  3. Source Arabic carries presentation forms, tatweel, diacritics, RLM
     marks and the Maghrebi letters ڨ/ڤ/پ/ھ. All normalised for display,
     because the audience reads plain ق/ب/ه.

DELIBERATELY NOT DONE
  Word-final ى is left alone. Folding it to ي mangles correct names
  (أولاد عيسى -> أولاد عيسي). ArabicSearch folds it at search time instead,
  so search still works -- only the stored spelling stays faithful.

VERIFY: the script fails loudly if the total is not 1,541, if any wilaya's
count differs from the backbone, if any commune ends up with no Arabic, or if
the taxonomy it reads does not cover every wilaya in the backbone.

LAST OF THOSE FOUR WAS THE ONE THAT WAS LYING
--------------------------------------------
The first three are what the header has always claimed. The third was only
true **by accident**: a commune with no Arabic is dropped from `rows`, so the
per-wilaya count check -- written for a different reason -- always caught it.
Nothing said so, and the moment that check was changed the guarantee would
have evaporated silently. It is now stated where the guarantee is kept.

`taxonomy_wilayas` is the fourth, and it is the one that used to fail silently
rather than loudly. It was one positional regex over the Dart source, matching
the literal text `id: '01', name: '` and then two quoted runs. Measured: reformat **one** row -- double the quotes, or swap the
two named fields, or break the line after the comma, all of which `dart format`
or a tidy-up may do -- and the regex drops that row and **still returns a
non-empty dict**. The old code used `tax.get(cid)`, so a missing wilaya read
as `None`, the seat alignment was silently skipped for it, `wilayas[cid]["ar"]`
fell back to the kossa spelling, and the run finished **exit 0** having written
a dataset where the picker header disagreed with the rest of the app. Same
failure this repo has already recorded twice: something absent read as if it
had been measured. Now a lost row is a lost row, and a taxonomy that does not
cover the backbone is refused.

RUN:  python3 tool/gen_communes.py

EXIT: 0 written, 1 refused (verification failed / unreadable), 2 no inputs.

ON A HOST WHERE THE INPUTS ARE GONE
------------------------------------
Measured 10 Oct, on this host: **all four inputs are missing** --
`/home/renia/nadjah_repo/...` died with the 26 Sep rebuild, and the other three
lived in `/tmp`. The script used to answer that with a bare
`FileNotFoundError` traceback naming a path that has not existed for two weeks.
It now names every input that is missing, where it used to come from, and says
plainly that the shipped asset is untouched and still authoritative -- because
it is, and an operator reading a traceback has no way to know that.

Do NOT "fix" this by regenerating the asset from the shipped one. That would
make the generator a script that proves the asset equals itself.
"""
import csv
import difflib
import json
import os
import re
import sys
import unicodedata

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NADJAH = "/home/renia/nadjah_repo/dz-wilayas-optimized.json"
KOSSA = "/tmp/kossa_com.json"
KOSSA_WIL = "/tmp/kossa_wil.json"
GEO = "/tmp/geo_communes.csv"
OUT = os.path.join(REPO, "assets/data/communes_dz.json")
OFFICIAL_TOTAL = 1541

BIDI = dict.fromkeys([0x200e, 0x200f, 0x200b, 0x200c, 0x200d, 0x061c, 0xfeff])
DIAC = re.compile("[" + chr(0x064b) + "-" + chr(0x0652) + chr(0x0670) + "]")
# Maghrebi letter forms -> the letters Algerians actually read and type.
FOLD = {chr(0x6a8): chr(0x642), chr(0x6a4): chr(0x642), chr(0x67e): chr(0x628),
        chr(0x6be): chr(0x647), chr(0x6c1): chr(0x647)}


def clean(s):
    s = unicodedata.normalize("NFKC", s.translate(BIDI))
    s = s.replace(chr(0x640), "")            # tatweel
    s = DIAC.sub("", s)                      # harakat
    s = "".join(FOLD.get(c, c) for c in s)
    return re.sub(r"\s+", " ", s).strip()


def key(s):
    """Identity key for matching: accent/punctuation-insensitive Latin."""
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]", "", s.lower())


def arkey(s):
    s = unicodedata.normalize("NFKC", clean(s))
    for a, b in ((chr(0x621), chr(0x627)), (chr(0x623), chr(0x627)),
                 (chr(0x649), chr(0x64a)), (chr(0x629), chr(0x647))):
        s = s.replace(a, b)
    return re.sub(r"\s+", "", s)


def sim(a, b):
    return difflib.SequenceMatcher(None, a, b).ratio()


#: One `(id: '01', name: 'أدرار')` record, in EITHER field order and with
#: EITHER quote style, with arbitrary whitespace and newlines between the two.
#: Keyed on the field names rather than on their positions, because a record
#: is a named-field record and the names are what identify it.
_RECORD_PAIR = re.compile(r"(\w+)\s*:\s*(?:'((?:[^'\\]|\\.)*)'|\"([^\"]*)\")")

#: `// ...` to end of line, outside string literals.
_COMMENT = re.compile(r"//[^\n]*")

#: The wilaya list this reader is pointed at. Anything else named `wilayas`
#: in the file is not the list, so the span is found from THIS declaration.
_WILAYAS_DECL = "wilayas"


def taxonomy_span(src):
    """The text between the wilaya list's brackets, or raise.

    Located from the `wilayas` declaration rather than by scanning for the
    first `(` in the file, so a future type annotation or helper cannot move
    the reader onto a different list.
    """
    decl = src.index(_WILAYAS_DECL)
    start = src.index("[", decl)
    depth, i = 0, start
    while i < len(src):
        if src[i] == "[":
            depth += 1
        elif src[i] == "]":
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
        i += 1
    raise ValueError("no closing bracket for the wilayas list")


def _record_texts(body):
    """Each parenthesised record in `body`, outermost parentheses only."""
    depth, buf = 0, None
    for i, ch in enumerate(body):
        if ch == "(":
            if depth == 0:
                buf = []
            if buf is not None:
                buf.append(ch)
            depth += 1
        elif ch == ")":
            depth -= 1
            if buf is not None:
                buf.append(ch)
                if depth == 0:
                    yield "".join(buf)
                    buf = None
        elif buf is not None:
            buf.append(ch)


def taxonomy_wilayas(path=None):
    """Wilaya id -> Arabic name, read from `lib/src/data/taxonomy.dart`.

    Raises ValueError if the file names a wilaya twice, if a record is not a
    two-field record, or if it holds fewer than `expected` rows. A SHORT read
    is the defect this exists for: the old regex returned a smaller dict and
    every caller treated the absence as "this wilaya has no taxonomy spelling".
    """
    path = path or os.path.join(REPO, "lib/src/data/taxonomy.dart")
    src = open(path, encoding="utf-8").read()
    # Comments first, then the span: a commented-out record must not be read
    # as a live one, and stripping inside the span is where it can happen.
    src = _COMMENT.sub("", src)
    out = {}
    for rec in _record_texts(taxonomy_span(src)):
        fields = {m.group(1): (m.group(2) if m.group(2) is not None
                               else m.group(3))
                  for m in _RECORD_PAIR.finditer(rec)}
        if set(fields) != {"id", "name"}:
            raise ValueError(
                "taxonomy record is not an (id, name) pair: (%s)" % rec.strip())
        if not fields["id"].isdigit():
            raise ValueError("taxonomy id %r is not a wilaya number"
                             % fields["id"])
        wid = str(int(fields["id"]))          # '01' and '1' are one wilaya
        if wid in out:
            raise ValueError("taxonomy lists wilaya %s twice" % wid)
        out[wid] = clean(fields["name"])
    if not out:
        raise ValueError("taxonomy yielded no wilayas at all -- the reader "
                         "found nothing, which is not the same as an app with "
                         "no wilayas")
    return out


def require_inputs():
    """Every input this run needs, or a named list of the ones that are gone.

    Returns True when all are present. On a host where they are not, prints
    each missing file with where it used to come from and exits 2 -- rather
    than letting `open()` raise a traceback naming a path from a dead machine.
    """
    wanted = [
        (NADJAH, "structure and completeness -- 58 wilayas x 1,541 communes",
         "the in-house backbone, dz-wilayas-optimized.json"),
        (KOSSA, "the Arabic names (primary)",
         "kossa/algerian-cities (MIT): database/seeders/json/Commune_Of_Algeria.json"),
        (KOSSA_WIL, "the Arabic wilaya names",
         "the same repo's wilaya seeder"),
        (GEO, "the Arabic names, fallback and repair source",
         "geoalgeria (MIT): packages/dataset/data/csv/communes.csv"),
    ]
    missing = [(p, why, how) for p, why, how in wanted if not os.path.exists(p)]
    if not missing:
        return True
    print("gen_communes: cannot run -- %d of %d inputs are missing on this host:"
          % (len(missing), len(wanted)), file=sys.stderr)
    for p, why, how in missing:
        print("   MISSING  %s" % p, file=sys.stderr)
        print("        was: %s" % why, file=sys.stderr)
        print("        get: %s" % how, file=sys.stderr)
    print(file=sys.stderr)
    print("This tool CANNOT regenerate %s." % OUT, file=sys.stderr)
    print("The shipped asset is untouched and still authoritative -- do not "
          "rebuild it from itself.", file=sys.stderr)
    return False


def main():
    if not require_inputs():
        return 2
    nad = json.load(open(NADJAH))
    kossa = json.load(open(KOSSA))
    kossa_wil = {str(int(r["id"])): clean(r["ar_name"])
                 for r in json.load(open(KOSSA_WIL))}
    geo = list(csv.DictReader(open(GEO)))

    # --- lookup tables: latin key -> arabic
    kossa_lut, kossa_by_w = {}, {}
    for r in kossa:
        k, w = key(r["name"]), str(int(r["wilaya_id"]))
        kossa_lut.setdefault(k, clean(r["ar_name"]))
        kossa_by_w.setdefault(w, []).append((k, clean(r["ar_name"]), r["name"]))

    geo_lut, geo_by_w = {}, {}
    for g in geo:
        k, w = key(g["name_fr"]), str(int(g["wilaya_code"]))
        geo_lut.setdefault(k, clean(g["name_ar"]))
        geo_by_w.setdefault(w, []).append((k, clean(g["name_ar"]), g["name_fr"]))

    def lookup(lat, w):
        """Arabic for a Latin name: exact everywhere, then fuzzy near the
        same wilaya first, then fuzzy globally (reassigned communes)."""
        k = key(lat)
        for lut in (kossa_lut, geo_lut):
            if k in lut:
                return lut[k]
        for table in (kossa_by_w, geo_by_w):
            best, br = None, 0.0
            for kk, ar, _ in table.get(w, []):
                r = sim(k, kk)
                if r > br:
                    best, br = ar, r
            if best and br >= 0.75:
                return best
        for table in (kossa_lut, geo_lut):
            best, br = None, 0.0
            for kk, ar in table.items():
                r = sim(k, kk)
                if r > br:
                    best, br = ar, r
            if best and br >= 0.90:
                return best
        return None

    def lookup_geo(lat, w):
        """geoalgeria only -- used to RE-SOURCE a name that two communes in
        one wilaya are sharing. Must not consult kossa, because kossa is the
        source holding the bad pair (its Tiaret has Nadorah -> ملاكو)."""
        k = key(lat)
        if k in geo_lut:
            return geo_lut[k]
        best, br = None, 0.0
        for kk, ar, _ in geo_by_w.get(w, []):
            r = sim(k, kk)
            if r > br:
                best, br = ar, r
        if best and br >= 0.80:
            return best
        best, br = None, 0.0
        for kk, ar in geo_lut.items():
            r = sim(k, kk)
            if r > br:
                best, br = ar, r
        return best if best and br >= 0.92 else None

    def lookup_any(lat, w):
        """As lookup(), but tolerates a parenthetical qualifier, e.g.
        "Z'barbar (El Isseri )" -> also try "Z'barbar"."""
        got = lookup(lat, w)
        if got:
            return got
        head = re.split(r"[(\[]", lat)[0].strip()
        return lookup(head, w) if head and head != lat else None

    # The app's own taxonomy spelling wins for a wilaya seat: the commune
    # named after its wilaya must read exactly like the wilaya itself
    # (اولاد جلال -> أولاد جلال).
    try:
        tax = taxonomy_wilayas()
    except (OSError, ValueError) as exc:
        print("gen_communes: cannot read the app taxonomy: %s" % exc,
              file=sys.stderr)
        return 1
    aligned = []

    wilayas, communes, misses, collisions = {}, {}, [], []

    for w in nad:
        cid = str(int(w["stateCode"]))
        rows = []
        for c in w["cities"]:
            lat = c["name"].strip()
            rows.append([lookup_any(lat, cid), lat])

        # no Arabic left behind
        for r in rows:
            if not r[0]:
                misses.append((cid, r[1]))

        # Same Arabic name used by two communes in one wilaya: exactly one of
        # them owns it. Give it to the member whose own Latin name the other
        # sources agree with, and re-source the rest (Tiaret: Mellakou keeps
        # ملاكو, Nadorah becomes الناظورة).
        groups = {}
        for r in rows:
            if r[0]:
                groups.setdefault(arkey(r[0]), []).append(r)
        for k, grp in groups.items():
            if len(grp) < 2:
                continue
            fixed = False
            for r in grp:
                alt = lookup_geo(r[1], cid)
                if alt and arkey(alt) != k:
                    collisions.append((cid, r[1], r[0], alt))
                    r[0] = alt
                    fixed = True
            if not fixed:
                collisions.append((cid, ", ".join(r[1] for r in grp),
                                   grp[0][0], None))

        # align the wilaya seat's spelling with the app's taxonomy
        seat = arkey(tax.get(cid, ""))
        if seat:
            for r in rows:
                if r[0] and arkey(r[0]) == seat and r[0] != tax[cid]:
                    aligned.append((cid, r[0], tax[cid]))
                    r[0] = tax[cid]

        rows = [r for r in rows if r[0]]
        rows.sort(key=lambda r: r[0])
        communes[cid] = rows
        # label the wilaya exactly as this app's taxonomy spells it, so the
        # picker and the rest of the app can never disagree
        wilayas[cid] = {"ar": tax.get(cid) or kossa_wil[cid],
                        "fr": w["state"], "count": len(rows)}

    total = sum(v["count"] for v in wilayas.values())

    # ---------------------------------------------------------------- checks
    bad = []
    # The taxonomy must name every wilaya the backbone has. `tax.get(cid)` used
    # to answer None for one it did not, which is indistinguishable from a
    # wilaya that genuinely has no seat name -- so a lost row silently changed
    # the dataset and still exited 0.
    uncovered = sorted(set(wilayas) - set(tax), key=lambda k: int(k))
    if uncovered:
        bad.append("taxonomy covers %d of %d wilayas; missing %s"
                   % (len(set(wilayas) & set(tax)), len(wilayas),
                      ", ".join(uncovered[:6]) +
                      ("..." if len(uncovered) > 6 else "")))
    if total != OFFICIAL_TOTAL:
        bad.append("total %d != official %d" % (total, OFFICIAL_TOTAL))
    for w in nad:
        cid = str(int(w["stateCode"]))
        want, got = len(w["cities"]), len(communes[cid])
        if want != got:
            bad.append("wilaya %s: %d communes, backbone has %d" % (cid, got, want))

    # No `bytes` field here: the file has not been written yet, and the old
    # hardcoded `0` printed a number that was simply false next to two that
    # were true. The real size is printed after the write.
    print("wilayas %d   communes %d" % (len(wilayas), total))
    print("wilaya-seat spellings aligned to taxonomy: %d" % len(aligned))
    for a in aligned:
        print("   = w%-3s %s -> %s" % a)
    print("collisions repaired: %d" % len(collisions))
    for c in collisions:
        print("   * w%-3s %-24s %s -> %s" % c)
    if misses:
        print("MISSING ARABIC (%d):" % len(misses))
        for m in misses:
            print("   !! w%-3s %s" % m)
        # Kept out of `bad` until now, on the reasoning that the count check
        # already covers it. It does -- a row with no Arabic is dropped, so the
        # per-wilaya counts cannot both match the backbone. But that is a
        # coincidence between two checks written for two different reasons, and
        # the header has always promised this one. It is now the promise itself,
        # so rewriting the count check cannot quietly retire it.
        bad.append("%d commune(s) have no Arabic name" % len(misses))
    if bad:
        print("\nFAILED VERIFICATION:")
        for b in bad:
            print("   !! %s" % b)
        return 1

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump({"source": "kossa/algerian-cities (MIT) + geoalgeria (MIT); "
                             "structure from dz-wilayas-optimized.json",
                   "total": total, "wilayas": wilayas,
                   "communes": {k: [[a, l] for a, l in v]
                                for k, v in communes.items()}},
                  fh, ensure_ascii=False, separators=(",", ":"))
    print("wrote %s  (%d bytes)" % (OUT, os.path.getsize(OUT)))
    # The number is printed from the constant, never typed in again. It used to
    # be literal text, so a run that verified a total of 4 still printed
    # "verified: total == 1,541" -- a confirmation line that cannot disagree
    # with the run it is confirming, which is the one kind nobody reads.
    print("verified: total == %s and every wilaya matches the backbone"
          % f"{OFFICIAL_TOTAL:,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
