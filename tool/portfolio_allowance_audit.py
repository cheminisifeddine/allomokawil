#!/usr/bin/env python3
"""Measure whether the plan's photo allowance and the gallery can disagree.

`IMPROVEMENT_BACKLOG.md`, the "Next" of the portfolio-gallery tick (9 Oct),
named the sweep worth running:

    "the plan allowance against the gallery list: `MyPortfolioScreen._load`
     reads `/my/profile` for `portfolio_limit` and `/workers/:id/portfolio`
     for the rows, and `left` is computed from `used` alone."

**The premise holds and the contradiction is real — and it needs no server
bug to happen.** Measured 9 Oct 2026, live, on both hosts:

    /api/mobile/subscription -> current.portfolio_limit = 5
    /api/mobile/subscription -> NO photo-usage field at all
                                (it carries quotes_used_this_month and
                                 quotes_left, and nothing about photos)
    POST /portfolio x12      -> 12 x 200, GET -> 12 rows

So `used` can only come from the list length, the list is **uncapped** (130
posted, 130 listed, contiguous -- not the 100-row cap the notifications and
reviews routes have), and the **server enforces no limit**: twelve rows stored
against an allowance of five.

That last fact is what makes the header lie, and it is the whole finding:

    portfolioCountLineAr(count)  -> "12 صور في معرض أعمالك"
    _Header._subLine()           -> portfolioFullLineAr(5)
                                  -> "بلغت حد صور خطتك: 5 صور"

Two numbers about one set of photographs, on one card, that cannot both be
true: the gallery holds twelve and the plan stops at five. `left` floors at
zero (deliberately, and correctly -- see `PortfolioAllowance.left`), so this
is not a negative number; it is a sentence that states a ceiling the same
screen is showing twelve pictures above.

**Reachable without a bug and without cheating.** The client gate
(`_addPhoto` -> `isFull`) stops the *app* at five, so how does a contractor
reach twelve? Three ordinary ways, none of them a defect:

  * a plan **downgrade** or a lowered `portfolio_limit` under photos that
    were added on the higher tier -- the state `left` was written to floor;
  * photos registered by another surface (the desktop site, a backfill, an
    earlier build), which the app counts and never prevented;
  * the **free default** itself: `kDefaultPortfolioLimit` is 5 for a server
    that sent nothing, so a contractor who was already over five the first
    time he opened the screen reads both sentences at once.

**Why a tool, and why Python.** `tool/build_gate.py` refuses Dart whenever
the hypervisor balloon is up (340 MB available against a 900 MB floor when
this was written), and a measurement is exactly the work that must not be
dropped for that reason. Same reasoning `tool/portfolio_gallery_audit.py`
records for itself.

**It only creates throwaway accounts** and never edits a real contractor's
gallery; every write here lands on an id the tool itself just minted.
"""
import argparse
import json
import os
import re
import random
import sys
import urllib.error
import urllib.request

# The customer-facing host first, then the workers.dev fallback -- the same
# pair, in the same order, the sibling audits use, so a verdict here is about
# the hosts the shipped APK calls.
HOSTS = [
    "https://allomokawil.com",
    "https://finili.medsaidkichene.workers.dev",
]

# Cloudflare answers **403 with error code 1010** to urllib's default agent.
USER_AGENT = "AlloMokawilApp/1.0 (Android 14; Flutter)"
READ_TIMEOUT = 30

# The Dart this tool mirrors. Read, never assumed -- see
# `dart_ceiling_line_takes_count`.
DART_ALLOWANCE = "lib/src/data/portfolio_allowance.dart"

# An explicit `None` means "no file, no answer"; the default means "look in
# the repo". Distinct, because the two produce different verdicts.
_MISSING = object()


# Enough rows to pass every allowance this app can print. The largest plan sells
# 120 (`portfolio_allowance.dart`), so 130 is over the top of the range rather
# than a round number picked for luck.
OVER_LIMIT_ROWS = 130


# The DECLARATION of the ceiling line, not any mention of it.
#
# `portfolioFullLineAr` appears three more times in this very Dart file: once in
# a prose sentence and twice as a `[bracket]` doc reference. The old pattern was
# the bare name plus `(` -- it matched a CALL site in a doc comment before it
# reached the definition, so a file whose function takes two parameters could
# read as taking one. Anchoring on the return type makes a match mean "this is
# where it is defined", which is the only one of those mentions that answers
# the question.
_DECL = re.compile(
    r"^\s*(?:@\w+\s+)*"          # an annotation, if the function carries one
    r"(?:external\s+|static\s+)*"
    r"String\s+portfolioFullLineAr\s*\(",  # the return type is the anchor
    re.M)

# A parameter list, balanced across `[...]`, `{...}` and `<...>`.
#
# The old one stopped at the first `)`, so a parameter list carrying a default
# that is itself a call -- `portfolioFullLineAr(int limit, {int used =
# _fallback()})` -- was truncated mid-declaration and its own count was never
# seen. A missing bracket does not mean the parameter list ended there.
_OPENERS = "([{<"
_CLOSERS = ")]}>"
_PAIRS = {")": "(", "]": "[", "}": "{", ">": "<"}


def _param_list(src, open_paren):
    """The text between the parens at [open_paren], brackets balanced.

    Returns None when the list never closes, which is the one shape that means
    "not a parameter list after all" rather than a truncated one.
    """
    depth = 0
    for i in range(open_paren, len(src)):
        ch = src[i]
        if ch in _OPENERS:
            depth += 1
        elif ch in _CLOSERS:
            depth -= 1
            if depth == 0:
                return src[open_paren + 1:i]
    return None


def _split_params(text):
    """Top-level parameter names, ignoring nested brackets.

    A comma inside `{}`, `[]` or `<>` separates nothing -- `[int a = 1, int b =
    2]` is two parameters, not four -- so this splits on depth zero only.
    """
    depth = 0
    parts = [""]
    for ch in text:
        if ch in _OPENERS:
            depth += 1
        elif ch in _CLOSERS:
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("")
        else:
            parts[-1] += ch
    return [p.strip() for p in parts if p.strip()]


def dart_ceiling_line_takes_count(path=_MISSING):
    """Does the SHIPPED `portfolioFullLineAr` take the gallery count?

    Reads the signature out of the Dart rather than keeping a model of it.
    A mirror that hard-codes "this function takes one argument" is correct
    only until the Dart moves -- and when it moves, the mirror does not
    crash, it reports the FIXED screen as broken. That is the worst failure
    available to a tool whose whole job is judging the app: a tick reads
    `header_contradicts: True`, goes looking for a server bug, and the one
    live contradiction on both hosts had already been fixed in Dart.

    Returns True when the count is a parameter, False when it is not, and
    **None when the file cannot be read** -- an absent answer and a "no" are
    different, and collapsing them would report a verdict nobody measured.

    **Judged by ARITY, and that is the whole fix.** The old reader decided
    which parameter was the count by its SPELLING -- `used` or `count` -- so a
    field's identity was guessed from the name a developer happened to choose.
    Three wrong verdicts, all measured on this tick, none of which required a
    line of logic to change:

      String portfolioFullLineAr(int limit, int have)  -> False  (it does)
      String portfolioFullLineAr(int used)              -> True   (it does not)
      String portfolioFullLineAr(int a, int b)          -> False  (it does)

    The first is the dangerous one. Renaming a parameter is an ordinary,
    behaviour-preserving edit, and it flipped the tool to `blind=True`,
    `header_contradicts=True` -- **exit 1 against two healthy hosts**, filing a
    server defect that does not exist. That is the same defect the census
    tick shipped 1 Oct one layer over: a reader whose vocabulary is narrower
    than the tree it grades, so what it cannot recognise reads as *absent*
    rather than *unmeasured*.

    What the sentence needs is whether the count CAN reach it, and that is
    arity: one parameter means the only number this function was handed is the
    ceiling, whatever it is called. Two means a second value arrived. It does
    not matter that a two-parameter function might ignore its second argument --
    that is a different check, and this one must not pretend to be it.
    """
    if path is _MISSING:
        target = os.path.join(os.getcwd(), DART_ALLOWANCE)
    elif path is None:
        return None
    else:
        target = path
    try:
        with open(target, encoding="utf-8") as fh:
            src = fh.read()
    except OSError:
        return None
    m = _DECL.search(src)
    if not m:
        # No DECLARATION. Every mention of the name is a call site or a prose
        # reference, and a call site's arity is the caller's business.
        return None
    opener = src.index("(", m.end() - 1)
    params = _param_list(src, opener)
    if params is None:
        return None
    # An EMPTY parameter list is not an unreadable one: `portfolioFullLineAr()`
    # is a declaration that was found and read, and it takes no count. Reporting
    # None there would tell a tick "no verdict" about a file this tool could
    # read perfectly well, which is how an unreadable answer becomes an
    # absence nobody can tell apart from a measurement.
    return len(_split_params(params)) >= 2


class Wire:
    """One POST/GET against the API, with the outcomes kept distinct.

    Byte-for-byte the same shape `tool/portfolio_gallery_audit.py` uses,
    including the (403, 'error code: 1010') distinction: treating a WAF
    agent-string block as an application 403 files a healthy API as broken.
    """

    def __init__(self, base):
        self.base = base

    def call(self, path, data=None, token=None):
        body = json.dumps(data).encode() if data is not None else None
        req = urllib.request.Request(
            self.base + path,
            data=body,
            method="POST" if data is not None else "GET",
        )
        req.add_header("Content-Type", "application/json")
        req.add_header("User-Agent", USER_AGENT)
        if token:
            req.add_header("Authorization", "Bearer " + token)
        try:
            with urllib.request.urlopen(req, timeout=READ_TIMEOUT) as f:
                raw = f.read()
            return {"ok": True, "status": f.status,
                    "body": json.loads(raw) if raw else None, "bytes": len(raw)}
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            return {"ok": False, "status": e.code, "body": raw[:300],
                    "cf1010": "1010" in raw[:300], "bytes": len(raw)}
        except Exception as e:  # noqa: BLE001 - any transport fault is one outcome
            return {"ok": False, "status": 0, "body": str(e)[:200],
                    "cf1010": False, "bytes": 0}


def _phone(prefix):
    return "%s%02d%06d" % (prefix, random.randint(10, 99), random.randint(0, 999999))


def _photo(n):
    return "https://example.com/audit-allowance-%d.jpg" % n


def _throwaway_worker(wire):
    """A fresh contractor, so the tool never reads an id it did not mint."""
    reg = wire.call("/api/register", {
        "phone": _phone("05"), "email": "",
        "full_name": "حرفي قياس الحصة", "password": "secret123",
        "type": "worker",
    })
    if not reg["ok"] or not isinstance(reg["body"], dict) or "token" not in reg["body"]:
        return None, "register failed: %s %s" % (reg["status"], str(reg["body"])[:120])
    token = reg["body"]["token"]
    mine = wire.call("/api/mobile/my/profile", token=token)
    if not mine["ok"] or not isinstance(mine["body"], dict):
        return None, "my/profile failed: %s %s" % (mine["status"], str(mine["body"])[:120])
    return {
        "token": token,
        "user_id": (reg["body"].get("user") or {}).get("id"),
        "profile_id": mine["body"].get("id"),
    }, None


def _rows_of(resp):
    """The list inside a `Wire` response, or an empty list.

    Both a response dict and a bare body are accepted, for the reason
    `portfolio_gallery_audit._rows_of` records: the obvious reading
    `resp["body"]` raises `TypeError` when handed a body directly.
    """
    body = resp.get("body") if isinstance(resp, dict) else resp
    return body if isinstance(body, list) else []


def app_row_count(rows):
    """How many rows `repository.dart:98` would actually draw.

    The app's parse is the other half of the count, and reading the raw list
    length instead would measure a number the screen never uses:

        final url = e is Map ? e['image_url'] : e;
        return url is String ? url : '';
      }).where((s) => s.isNotEmpty).toList();

    So a row with no `image_url`, a null one, or a non-string one is dropped
    silently -- and if the server ever stored one, `used` would be lower than
    the server's own count and the header would under-report.
    """
    drawn = []
    for e in rows:
        url = e.get("image_url") if isinstance(e, dict) else e
        drawn.append(url if isinstance(url, str) else "")
    return [s for s in drawn if s]


def _read_limit(wire, acct):
    """Claim 1: the plan states a photo ceiling, and states nothing about usage.

    The absence is half the finding. The quote side of the same payload carries
    `quotes_used_this_month` and `quotes_left`; if photos had a usage field the
    screen could cross-check the two, and the header contradiction below would
    be caught before it reached a user.
    """
    rep = {"profile_id": acct["profile_id"]}
    sub = wire.call("/api/mobile/subscription", token=acct["token"])
    rep["subscription_status"] = sub["status"]
    body = sub["body"] if isinstance(sub["body"], dict) else {}
    current = body.get("current") if isinstance(body.get("current"), dict) else {}
    rep["subscription_keys"] = sorted(body.keys())
    rep["current_keys"] = sorted(current.keys())

    limit = current.get("portfolio_limit")
    rep["portfolio_limit"] = limit if isinstance(limit, int) else None
    # The decisive absence: no numeric field about photos already in use.
    # **`portfolio_limit` is excluded by name**, and that is the whole point of
    # the key: it *is* about photos and it *is* an integer, so a substring match
    # counts it, and the tool would report a usage field where the server sends
    # only the ceiling. The test that caught this asserted `== []` against a
    # payload carrying `portfolio_limit: 5` and got `['portfolio_limit']`.
    usage = sorted(
        k for k in current
        if k != "portfolio_limit"
        and isinstance(current.get(k), int)
        and any(t in k.lower() for t in ("photo", "portfolio", "image"))
    )
    rep["photo_usage_fields"] = usage
    # `0` is what `models/plan.dart`'s `_int` hands back for an absent field,
    # which `PortfolioAllowance.fromLimit` reads as the free plan's 5. A server
    # that sends nothing therefore produces the *same* number as a real free
    # plan, and the screen cannot tell them apart.
    rep["limit_absent_reads_as_zero"] = limit is None or limit == 0
    return rep, None


def _fill_past_the_limit(wire, acct, rows=OVER_LIMIT_ROWS):
    """Claim 2: the gallery is uncapped and the server enforces no ceiling.

    Two separate facts, and the second is the dangerous one. A capped list would
    make `used` an under-count (a header that under-reports); an unenforced
    limit is what makes `used` **exceed** the ceiling, which is the state the
    header cannot render.
    """
    rep = {"rows_asked": rows}
    pid = acct["profile_id"]
    statuses = {}
    stored = 0
    for i in range(1, rows + 1):
        r = wire.call("/api/mobile/workers/%d/portfolio" % pid,
                      {"image_url": _photo(i)}, token=acct["token"])
        statuses[str(r["status"])] = statuses.get(str(r["status"]), 0) + 1
        if r["status"] == 200:
            stored += 1
    rep["post_status_histogram"] = statuses
    rep["posted_200"] = stored

    gal = wire.call("/api/mobile/workers/%d/portfolio" % pid, token=acct["token"])
    listed = _rows_of(gal)
    rep["gallery_status"] = gal["status"]
    rep["server_rows"] = len(listed)
    rep["app_rows"] = len(app_row_count(listed))
    # Contiguity, so "uncapped" cannot be confused with "capped but shuffled":
    # every requested index must come back. A cap would drop the tail, and a
    # cap that dropped the *first* rows instead would still leave a full count.
    urls = set(app_row_count(listed))
    missing = [i for i in range(1, rows + 1) if _photo(i) not in urls]
    rep["missing_from_list"] = len(missing)
    rep["list_is_complete"] = not missing
    # The app's parse silently drops a row it cannot read a URL out of; if the
    # server ever sends one, `used` and the server's count part company.
    rep["rows_dropped_by_app_parse"] = len(listed) - rep["app_rows"]
    return rep, None


def _check_header(wire, acct, rep):
    """Claim 3: the two sentences the header draws, on the measured numbers.

    This is the app's logic, reproduced in Python and **marked as a mirror**.
    The Dart side is `portfolio_allowance.dart` +
    `my_portfolio_screen.dart::_Header._subLine`; the audit cannot import them
    (no Dart VM on a memory-denied box), so the rule is spelled out here.

    What is asserted is the *shape* -- does the screen print a count and a
    ceiling that contradict each other -- not the Arabic. `isFull` is
    `limit - used <= 0`, and `left` floors at zero.

    **The ceiling sentence is read from the Dart, not modelled.** The whole
    verdict turns on whether `portfolioFullLineAr` is told the gallery count,
    and that function is the Dart's, not this tool's: a mirror that assumed
    the old one-argument signature reported the FIXED screen as broken, and
    called both live hosts a server contradiction. `takes_count` is read by
    `dart_ceiling_line_takes_count` on every call, so a future signature
    change is measured rather than remembered.
    """
    used = rep["gallery"]["app_rows"]
    limit = rep["plan"].get("portfolio_limit")
    takes_count = dart_ceiling_line_takes_count()
    out = {"used": used, "limit": limit, "subline_takes_count": takes_count}
    if not isinstance(limit, int):
        out["verdict"] = "NO_LIMIT_STATED"
        return out, None
    out["left"] = max(limit - used, 0)
    out["is_full"] = limit - used <= 0
    out["count_line"] = "%d photos in your gallery" % used

    if not out["is_full"]:
        out["subline"] = "%d left of %d" % (out["left"], limit)
        out["over_ceiling_line"] = False
        out["over_ceiling_by"] = 0
        out["count_exceeds_limit"] = used > limit
        out["header_contradicts"] = False
        return out, None

    # At or over the ceiling the Dart picks between two sentences, and WHICH one
    # is the whole question:
    #   not told the count -> "full at limit: N", naming only the ceiling, so
    #                        it cannot tell 5-of-5 from 130-against-5;
    #   told the count     -> both numbers, which is what stops the card
    #                        contradicting the count line printed above it.
    if takes_count:
        # «تجاوز معرض أعمالك حد صور خطتك: 130 صورة في 5 صور» -- has and ceiling.
        out["subline"] = ("over your plan's limit: %d against %d"
                          % (used, limit))
        out["count_exceeds_limit"] = used > limit
        out["over_ceiling_line"] = False
        out["header_contradicts"] = False
    else:
        out["subline"] = "full at limit: %d" % limit
        out["count_exceeds_limit"] = used > limit
        out["over_ceiling_line"] = True
        out["header_contradicts"] = bool(used > limit)

    # Reported on every path, including `NO_LIMIT_STATED`: how far past the
    # ceiling the gallery is, so a report can state the size of the gap and not
    # merely that there is one. 0 while inside the ceiling.
    out["over_ceiling_by"] = max(used - limit, 0)
    return out, None


def check_ceiling_line(head):
    """Is the ceiling sentence the screen prints still blind to the count?

    One predicate, so the report, the test and the eventual Dart fix are all
    judged by the same question. The defect is a property of the *sentence*,
    not of the numbers: `portfolioFullLineAr(limit)` receives only the ceiling
    and therefore builds the same string whether the gallery holds five
    photographs or a hundred and thirty.

    Kept separate from `header_contradicts` on purpose. That one asks whether
    the two sentences on the card disagree with each other, and a fix that
    re-words the subline would silence it while leaving the ceiling sentence
    unable to tell a full gallery from an overfull one -- which is the half-fix
    `test/portfolio_allowance_audit_test.py` refuses by name.

    A header that took the count into the ceiling line (`subline_takes_count`)
    is, by construction, not blind to it.
    """
    if not isinstance(head, dict):
        return False
    if head.get("subline_takes_count"):
        return False
    return bool(head.get("over_ceiling_line"))


def _another_writer_is_building():
    """True only when the gate names a build it can see. Never guesses.

    Same contract as `portfolio_gallery_audit._another_writer_is_building`:
    not `--quiet`, because that suppresses the very sentence tested here and
    would invent a reason on every memory-denied box.
    """
    try:
        import subprocess
        out = subprocess.run(
            [sys.executable, "tool/build_gate.py"],
            capture_output=True, text=True, timeout=60,
        )
        text = (out.stdout or "") + (out.stderr or "")
        return "another writer is building" in text.lower()
    except Exception:  # noqa: BLE001 - a gate that cannot answer must not block
        return False


def _render(reports):
    lines = []
    for host, (rep, err) in reports.items():
        lines.append("  %s" % host)
        if err:
            lines.append("    ERROR: %s" % err)
            continue
        plan, gal, head = rep.get("plan", {}), rep.get("gallery", {}), rep.get("header", {})
        lines.append("    portfolio_limit %s | photo usage fields on payload: %s"
                     % (plan.get("portfolio_limit"), plan.get("photo_usage_fields")))
        lines.append("    posted %s/%s (statuses %s) -> server rows %s, app draws %s, "
                     "list complete: %s"
                     % (gal.get("posted_200"), gal.get("rows_asked"),
                        gal.get("post_status_histogram"), gal.get("server_rows"),
                        gal.get("app_rows"), gal.get("list_is_complete")))
        lines.append("    header: %s" % head.get("count_line"))
        lines.append("            %s" % head.get("subline"))
        lines.append("    header_contradicts: %s (used %s > limit %s) | "
                     "rows dropped by app parse: %s"
                     % (head.get("header_contradicts"), head.get("used"),
                        head.get("limit"),
                        gal.get("rows_dropped_by_app_parse")))
        # The line the pending Dart copy fix has to change, and how far past it
        # the gallery is. Printed on its own row because it is the check that
        # survives the fix: `header_contradicts` goes False once the two
        # sentences stop disagreeing, this goes False only when the ceiling
        # sentence itself can name the count.
        # The explanation has to follow the boolean. A row that printed
        # "still takes only a limit" beside `False` would be a report
        # contradicting itself one line under its own verdict -- the exact
        # failure this tool exists to catch, caught in the tool.
        blind = bool(head.get("over_ceiling_line"))
        if head.get("subline_takes_count") is None:
            why = "`portfolioFullLineAr` NOT READ -- no verdict"
        elif blind:
            why = "`portfolioFullLineAr` still takes only a limit"
        else:
            why = "`portfolioFullLineAr` is handed the count and names both"
        lines.append("    ceiling sentence is blind to the count: %s "
                     "(over by %s) -- %s"
                     % (head.get("over_ceiling_line"),
                        head.get("over_ceiling_by"), why))
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--hosts", default=",".join(HOSTS))
    ap.add_argument("--rows", type=int, default=OVER_LIMIT_ROWS)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if _another_writer_is_building():
        sys.stderr.write("REFUSED - another writer is building on this box\n")
        return 3

    reports = {}
    for host in [h.strip() for h in args.hosts.split(",") if h.strip()]:
        wire = Wire(host.rstrip("/"))
        acct, err = _throwaway_worker(wire)
        if acct is None:
            reports[host] = ({"plan": {}, "gallery": {}, "header": {}}, err)
            continue
        plan, _ = _read_limit(wire, acct)
        gal, _ = _fill_past_the_limit(wire, acct, rows=args.rows)
        head, _ = _check_header(wire, acct, {"plan": plan, "gallery": gal})
        reports[host] = ({"plan": plan, "gallery": gal, "header": head}, None)

    unreachable = [h for h, (r, e) in reports.items()
                   if e and "1010" not in str(e)]
    cf_blocked = [h for h, (r, e) in reports.items() if e and "1010" in str(e)]

    if args.json:
        print(json.dumps({
            "hosts": {h: {"report": r, "error": e} for h, (r, e) in reports.items()},
            "unreachable": unreachable,
            "cloudflare_1010": cf_blocked,
        }, indent=2, ensure_ascii=False))
    else:
        print("Portfolio allowance vs gallery -- can the header print two "
              "true-looking numbers that disagree?")
        for line in _render(reports):
            print(line)
        if cf_blocked:
            print("\n  %d host(s) answered 403/1010 (Cloudflare WAF on the agent "
                  "string), not an API fault." % len(cf_blocked))
        if unreachable:
            print("\n  UNREACHABLE: %s -- no verdict either way." % ", ".join(unreachable))

    if unreachable and len(unreachable) == len(reports):
        return 2
    for rep, err in reports.values():
        if err:
            continue
        head = rep.get("header", {}) or {}
        # `over_ceiling_line` is deliberately NOT part of this verdict. It is
        # True on a healthy host today -- the copy is the defect, and the copy
        # is fixed in Dart, not here -- so letting it drive the exit code would
        # make this tool permanently red and the founder would stop reading it.
        # It is reported, and pinned by `test/portfolio_allowance_audit_test.py`,
        # so the moment the Dart fix lands the boolean flips and the test says
        # so out loud. Exit 1 stays reserved for a contradiction that is the
        # SERVER's to fix, which is the one a tick can act on today.
        if head.get("header_contradicts"):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
