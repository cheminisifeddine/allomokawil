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
count differs from the backbone, or if any commune ends up with no Arabic.

RUN:  python3 tool/gen_communes.py
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


def main():
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
    tax = {str(int(k)): v for k, v in
           re.findall(r"id: '(\d+)', name: '([^']+)'",
                      open(os.path.join(REPO, "lib/src/data/taxonomy.dart"),
                           encoding="utf-8").read())}
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
    if total != OFFICIAL_TOTAL:
        bad.append("total %d != official %d" % (total, OFFICIAL_TOTAL))
    for w in nad:
        cid = str(int(w["stateCode"]))
        want, got = len(w["cities"]), len(communes[cid])
        if want != got:
            bad.append("wilaya %s: %d communes, backbone has %d" % (cid, got, want))

    print("wilayas %d   communes %d   bytes %d"
          % (len(wilayas), total, 0))
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
    print("verified: total == 1,541 and every wilaya matches the backbone")
    return 0


if __name__ == "__main__":
    sys.exit(main())
