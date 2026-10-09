#!/usr/bin/env python3
"""Measure the ceiling on every numeric field: what the BOX caps, what the
PARSER bounds, and whether an over-long paste is refused or silently changed.

    python3 tool/numeric_bound_audit.py            # human summary
    python3 tool/numeric_bound_audit.py --json     # machine
    echo $?   0 = every field refuses what it cannot represent
              1 = DEFECT -- a field silently rewrites or ships an unbounded value
              2 = unreadable: the reader's vocabulary moved and this tool
                  declines to guess

**The defect this measures.** `DzNumberInputFormatter` handles two inputs it
cannot represent in two different ways:

  * a **fractional** paste (`25,5`) is REFUSED -- `formatEditUpdate` returns
    `oldValue`, the field keeps what it had, and the screen's own validation
    explains why. Correct, and explained.
  * an **over-long** paste is TRUNCATED -- `digits.substring(0, maxDigits)`,
    with no error, no message, and no marker. The field then holds a number the
    user never typed, the parser validates *that* number, finds it in range, and
    the write ships it.

So the same field, on the same keystroke, refuses one impossible input loudly
and rewrites the other quietly. The truncation is the defect: the value that
reaches the API is not the value on the screen when he pressed send.

**And the duration has no ceiling at all.** `project_detail_screen.dart` reads
the days field with `DzNumber.tryParse(rawDays, min: 1)` -- a floor and no
roof. Every other numeric field in the app has a real range (an amount is
floored at 1000, experience is capped at 70); a duration has none, so
`estimated_days` can be 999999999999 and `quoteDurationLineAr` renders it
verbatim on the quote card the customer chooses from.

**Why every number here is EXTRACTED and never carried.** A copy of
`DzNumber.maxDigits` here would be a second reader, and this backlog has spent
several items learning what that costs: two scanners of one vocabulary that
disagree is a defect graded by one and invisible to the other. So each value is
parsed out of the Dart it describes, and if a name this tool reads has moved it
exits 2 rather than answering from a remembered value. A tool that answers from
a stale vocabulary is worse than a tool that declines.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

DZ_NUMBER = "lib/src/core/text/dz_number.dart"
NUMBER_FIELD = "lib/src/widgets/number_field.dart"

# Every numeric field, with the parser call that judges it. `max` is read from
# the call itself -- a call carrying only `min:` is a field with a floor and no
# roof, which is the finding rather than an oversight.
FIELDS = [
    ("bid_amount", "lib/src/screens/project/project_detail_screen.dart",
     "_amount", "المبلغ (دج)"),
    ("bid_days", "lib/src/screens/project/project_detail_screen.dart",
     "_days", "مدة الإنجاز (أيام)"),
    ("budget_min", "lib/src/screens/project/project_new_screen.dart",
     "_budgetMin", "من (دج)"),
    ("budget_max", "lib/src/screens/project/project_new_screen.dart",
     "_budgetMax", "إلى (دج)"),
    ("profile_years", "lib/src/screens/worker/profile_edit_screen.dart",
     "_years", "سنوات الخبرة"),
    ("profile_min_price", "lib/src/screens/worker/profile_edit_screen.dart",
     "_minPrice", "من (دج)"),
    ("profile_max_price", "lib/src/screens/worker/profile_edit_screen.dart",
     "_maxPrice", "إلى (دج)"),
]

# Controller -> the `tryParse` that judges it, keyed by the CONTROLLER it reads.
#
# Each pattern matches the ARGUMENT, then the bounds are read out of whatever
# follows with a separate, bound-shape-agnostic reader. Matching only the
# uncapped shape would make the fix invisible to the tool that measures it:
# once a field gains `max:`, the strict pattern stops matching and the field
# reads as ABSENT -- so the run that finally fixed everything would report the
# exact defects it had just closed.
#   group(1) = the controller/field text
#   group(2) = the `min:` value, when the call carries one
PARSERS = [
    (r"DzNumber\.tryParse\(\s*((?:submitted\.)?amount|rawAmount)\s*(?:,\s*min:\s*(\d+)\s*)?",
     "bid_amount"),
    (r"DzNumber\.tryParse\(\s*(rawDays|_days\.text)\s*(?:,\s*min:\s*(\d+)\s*)?",
     "bid_days"),
    (r"DzNumber\.tryParse\(\s*(_budgetMin\.text)\s*(?:,\s*min:\s*(\d+)\s*)?",
     "budget_min"),
    (r"DzNumber\.tryParse\(\s*(_budgetMax\.text)\s*(?:,\s*min:\s*(\d+)\s*)?",
     "budget_max"),
    (r"DzNumber\.tryParse\(\s*(_years\.text)\s*(?:,\s*min:\s*(\d+)\s*)?",
     "profile_years"),
    (r"DzNumber\.tryParse\(\s*(_minPrice\.text)\s*(?:,\s*min:\s*(\d+)\s*)?",
     "profile_min_price"),
    (r"DzNumber\.tryParse\(\s*(_maxPrice\.text)\s*(?:,\s*min:\s*(\d+)\s*)?",
     "profile_max_price"),
]


def _call_text(src: str, m) -> str:
    """The full `DzNumber.tryParse(...)` call a match started inside.

    The bound must be read from the WHOLE call: a pattern that matches only the
    argument would stop finding the field the moment a `max:` appears, which is
    the shape of the fix.
    """
    start = m.start()
    i = src.find("(", start)
    if i < 0:
        return m.group(0)
    inner, _ = balanced(src, i)
    return src[i:] if inner is None else src[i:src.find(inner, i) + len(inner) + 1]


def read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def balanced(src: str, open_idx: int):
    """Text inside a paren opening at [open_idx]; string-aware, never runaway."""
    depth = 0
    i, n = open_idx, len(src)
    while i < n:
        c = src[i]
        if c in "'\"":
            q = c
            i += 1
            while i < n and src[i] != q:
                i += 2 if src[i] == "\\" else 1
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return src[open_idx + 1:i], i
        i += 1
    return None, None


def extract_dz_max_digits(src: str) -> int:
    m = re.search(r"static\s+const\s+int\s+maxDigits\s*=\s*(\d+)\s*;", src)
    if not m:
        raise LookupError("no `static const int maxDigits = N` in dz_number.dart")
    return int(m.group(1))


def extract_max_experience_years(src: str) -> int:
    m = re.search(r"static\s+const\s+int\s+maxExperienceYears\s*=\s*(\d+)\s*;", src)
    if not m:
        raise LookupError("no `maxExperienceYears` in dz_number.dart")
    return int(m.group(1))


def _format_edit_params(src: str):
    """The two parameter names of `formatEditUpdate`, in order.

    Derived from the signature rather than assumed to be `oldValue`/`newValue`:
    an audit that hardcodes a parameter name starts inventing defects the day
    someone renames it, which is the same failure as carrying a constant.
    """
    m = re.search(r"formatEditUpdate\s*\(([^)]*)\)\s*\{", src)
    if not m:
        raise LookupError("no `formatEditUpdate(...)` in dz_number.dart")
    names = [p.strip().split()[-1] for p in m.group(1).split(",") if p.strip()]
    if len(names) != 2:
        raise LookupError("`formatEditUpdate` does not take two parameters")
    return names[0], names[1]


def truncation_is_silent(src: str) -> bool:
    """True when the formatter TRUNCATES an over-long paste instead of refusing.

    Read rather than assumed: the refusal branch returns the OLD value, the
    truncation branch hands `substring(0, maxDigits)` straight back.
    """
    m = re.search(r"if\s*\(\s*digits\.length\s*>\s*maxDigits\s*\)\s*"
                  r"digits\s*=\s*digits\.substring\(\s*0\s*,\s*maxDigits\s*\)",
                  src)
    return bool(m)


def fraction_is_refused(src: str) -> bool:
    """True when a fractional paste returns the OLD value rather than truncating."""
    old_name, new_name = _format_edit_params(src)
    return bool(re.search(r"hasFraction\(\s*%s\.text\s*\)\s*\)\s*return\s+%s\b"
                          % (re.escape(new_name), re.escape(old_name)), src))


def number_field_cap(src: str, parser_cap: int):
    """What the BOX caps: the default, or the per-field override if one is set.

    A caller that passes nothing gets `DzNumber.maxDigits` from the widget's
    own default, so the box and the parser agree today. Measured so a tick can
    tell "inert but consistent" from "already broken".
    """
    follows = bool(re.search(r"this\.maxDigits\s*=\s*DzNumber\.maxDigits", src))
    overrides = []
    for m in re.finditer(r"NumberField\(", src):
        inner, _ = balanced(src, m.end() - 1)
        if inner is None:
            continue
        ctrl = re.search(r"controller:\s*(\w+)", inner)
        dg = re.search(r"maxDigits:\s*(\d+)", inner)
        if ctrl and dg:
            overrides.append((ctrl.group(1), int(dg.group(1))))
    return follows, sorted(set(overrides))


def measure(root: str) -> dict:
    dz_src = read(os.path.join(root, DZ_NUMBER))
    nf_src = read(os.path.join(root, NUMBER_FIELD))
    parser_cap = extract_dz_max_digits(dz_src)
    years_cap = extract_max_experience_years(dz_src)

    screens = {}
    for _, path, _, _ in FIELDS:
        if path not in screens:
            screens[path] = read(os.path.join(root, path))

    parses = {}
    for path, src in screens.items():
        for pattern, fid in PARSERS:
            if fid in parses:
                continue
            m = re.search(pattern, src)
            if not m:
                continue
            pmin = int(m.group(2)) if m.groups() and len(m.groups()) > 1 and m.group(2) else None
            whole = _call_text(src, m)
            max_in = re.search(r"max:\s*([^,)]+)", whole)
            if max_in is None:
                pmax = None
            elif "maxExperienceYears" in max_in.group(1):
                pmax = years_cap
            else:
                try:
                    pmax = int(max_in.group(1))
                except ValueError:
                    pmax = None
            parses[fid] = {"min": pmin, "max": pmax, "call": whole}

    fields = []
    for fid, path, controller, label in FIELDS:
        p = parses.get(fid)
        follows, overrides = number_field_cap(screens[path], parser_cap)
        box_cap = parser_cap
        for ctrl, digits in overrides:
            if ctrl == controller:
                box_cap = digits
        fields.append({
            "id": fid,
            "file": path,
            "controller": controller,
            "field": label,
            "box_cap": box_cap,
            "parse_min": p["min"] if p else None,
            "parse_max": p["max"] if p else None,
            "parse_found": p is not None,
            "roofed": bool(p and p["max"] is not None),
        })

    return {
        "parser_cap": parser_cap,
        "years_cap": years_cap,
        "box_default_follows_parser": number_field_cap(nf_src, parser_cap)[0],
        "box_overrides": [list(o) for o in number_field_cap(nf_src, parser_cap)[1]],
        "over_long_truncates": truncation_is_silent(dz_src),
        "fraction_refused": fraction_is_refused(dz_src),
        "fields": fields,
    }


def verdict(m: dict) -> dict:
    # A field with a floor and no roof: any value that clears the floor ships.
    unroofed = sorted(f["id"] for f in m["fields"]
                      if f["parse_found"] and not f["roofed"])
    missing = sorted(f["id"] for f in m["fields"] if not f["parse_found"])
    return {
        "unroofed": unroofed,
        "unroofed_count": len(unroofed),
        "parser_missing": missing,
        "drift": bool(unroofed or missing or m["over_long_truncates"]),
    }


def render(m: dict, v: dict) -> "list[str]":
    L = ["Numeric field bounds -- what the box caps, what the parser bounds", ""]
    L.append("  DzNumber.maxDigits (parser ceiling) ....... %d" % m["parser_cap"])
    L.append("  DzNumber.maxExperienceYears ............... %d" % m["years_cap"])
    L.append("  NumberField default follows parser ...... %s"
             % ("yes" if m["box_default_follows_parser"] else "NO"))
    L.append("")
    L.append("  %-19s %-6s %-7s %s" % ("field", "box", "min", "max"))
    for f in m["fields"]:
        if not f["parse_found"]:
            L.append("  %-19s %-6s %-7s %s" % (f["id"], f["box_cap"], "-",
                                              "PARSER NOT FOUND"))
            continue
        L.append("  %-19s %-6s %-7s %s" % (
            f["id"], f["box_cap"],
            "-" if f["parse_min"] is None else f["parse_min"],
            f["parse_max"] if f["parse_max"] is not None else "-- NO ROOF --"))
    L.append("")
    L.append("  Over-long paste: %s" % ("TRUNCATED silently"
                                        if m["over_long_truncates"] else "refused"))
    L.append("  Fractional paste: %s" % ("refused, explained"
                                         if m["fraction_refused"] else "TRUNCATED"))
    if v["unroofed"]:
        L.append("")
        L.append("DEFECT -- a floor and no roof, on %d of %d fields:"
                 % (v["unroofed_count"], len(m["fields"])))
        for f in m["fields"]:
            if f["id"] in v["unroofed"]:
                L.append("  %-19s «%s»  min=%s" % (f["id"], f["field"],
                                                   f["parse_min"]))
        L.append("")
        L.append("  Anything that clears the floor ships, up to the box's %d-digit"
                 % m["parser_cap"])
        L.append("  ceiling. `bid_days` reaches the customer: quoteDurationLineAr")
        L.append("  prints the number verbatim on the quote card. The amount on the")
        L.append("  row above it is floored at 1000 but has no roof either, so one")
        L.append("  sheet's two fields are not both bounded.")
    if v["parser_missing"]:
        L.append("")
        L.append("  Parser not found for: %s" % ", ".join(v["parser_missing"]))
    return L


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.getcwd())
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    try:
        m = measure(args.root)
    except (FileNotFoundError, LookupError) as exc:
        print("UNREADABLE -- %s" % exc)
        print("The reader's vocabulary moved and this tool declines to answer "
              "from a remembered copy. Re-measure by hand.")
        return 2

    v = verdict(m)
    if args.json:
        payload = dict(m)
        payload.update(v)
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        for line in render(m, v):
            print(line)
    return 1 if v["drift"] else 0


if __name__ == "__main__":
    sys.exit(main())
