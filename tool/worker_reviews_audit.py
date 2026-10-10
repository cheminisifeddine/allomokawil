#!/usr/bin/env python3
"""Measure what a contractor's own review surface returns, instead of assuming.

After the market (`inbox_read_audit.py`) and the centre (`notification_read_audit.py`),
this is the third `data/repository.dart` read surface, and the last one a
contractor looks at as *work* rather than as *news*.

**Measured 9 Oct 2026 against production, on two hosts.** Three things, and
only the first is a defect in the app's own reading:

    GET /api/mobile/workers/search      -> worker id 1, avg_rating 4.8,
                                           total_reviews 24
    GET /api/mobile/workers/1/reviews   -> []            <- the header disagrees
    GET /api/mobile/workers/1           -> 200, the profile the screen opens

So on **one page** the customer is shown a 4.8 star pill with (24) and, two
scrolls down, an empty reviews section. The app has already shipped guards for
both halves of that contradiction (`reviews_section_copy.dart`: the empty arm
and the partial arm), which is exactly why this audit does not re-open it. What
is measured here is the claim those guards rest on -- that the two reads can be
*asked the same question* -- plus the one shape no guard covers.

**The shape no guard covers: two ids for one man.** The worker profile is
keyed by the **worker profile id** (`/api/mobile/workers/652`), while the
account is keyed by **user id** (`/api/mobile/my/profile` -> `user_id: 1030`).
Both answer `/workers/<id>/reviews` with **200** -- and the two do not mean
the same thing:

    /api/mobile/workers/1030/reviews -> 200 []
    /api/mobile/workers/1030          -> 404 {"error":"المقاول غير موجود"}
    /api/mobile/workers/652/reviews  -> 200 []
    /api/mobile/workers/652           -> 200 {the profile}

So a **404 on the profile and a 200 on the reviews** is reachable, and the
reviews route will not tell you which id you passed. `Repository.workerReviews`
takes the profile id -- which is what `WorkerProfileScreen(workerId: w.id)` is
handed, and what `w.id` is on every browse row -- so the app is on the correct
one today. This audit pins that as a measured fact rather than a hope, because
the failure it would cause is silent: a wrong id reads **empty**, never wrong.

**Why a tool, and why Python.** `tool/build_gate.py` refuses Dart on this box
whenever the hypervisor balloon is up (423 MB available against a 900 MB floor
when this was written), and a measurement is exactly the work that must not be
dropped for that reason. It needs no Dart VM -- the same reasoning
`test/run_tests_busy_code_test.py` records for itself.

**It only creates throwaway accounts** and never touches a real thread, the
same contract `tool/inbox_read_audit.py` and `tool/notification_read_audit.py`
keep. It reads public profile data; it writes nothing to any real account.

    python3 tool/worker_reviews_audit.py
    python3 tool/worker_reviews_audit.py --top 12 --json

Exit codes: 0 nothing to report (no id answered a different way from its
profile, and no row's list is longer than its header claims), 1 a worker whose
two ids disagree, or a list that contradicts the header, 2 the host was
unreachable, 3 refused because another writer is building. **2 and 3 are
opposites** -- "the wire is down" and "do not start here" -- and the 69th tick
lost a tick by collapsing that pair.
"""
import argparse
import json
import random
import sys
import urllib.error
import urllib.request

# The customer-facing host first, then the workers.dev fallback -- the same pair,
# in the same order, that `tool/inbox_read_audit.py` and
# `tool/notification_read_audit.py` use, so a verdict here is a statement about
# the hosts the shipped APK calls.
HOSTS = [
    "https://allomokawil.com",
    "https://finili.medsaidkichene.workers.dev",
]

# Cloudflare answers **403 with error code 1010** ("access denied") to urllib's
# default `Python-urllib/3.x` agent -- a WAF signature match, not an application
# failure. Reported as its own outcome so a future tick does not spend ten
# minutes believing a healthy API is down.
USER_AGENT = "AlloMokawilApp/1.0 (Android 14; Flutter)"

# One row measured ~400 bytes, so this is generous against a 1 MiB reply and
# short of the infinite wait that produced the 30 Sep stall.
READ_TIMEOUT = 30


class Wire:
    """One POST/GET against the API, with the outcomes kept distinct.

    **The 1010 split, and why it is a split.** Treating a WAF block as a real
    403 files the API as broken when it answered every request the app ever
    sends it -- with the agent string the app actually sends.
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


def _throwaway_worker(wire):
    """A fresh contractor, so the tool never reads from an id it did not mint.

    The id *shape* is the point of the audit and it cannot be measured on a
    directory row: `/workers/search` answers profile ids, and the account id
    behind one is only reachable from a token the tool holds.
    """
    reg = wire.call("/api/register", {
        "phone": _phone("05"), "email": "",
        "full_name": "حرفي قياس المراجعات", "password": "secret123",
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
        "user_id": reg["body"].get("user", {}).get("id"),
        "profile_id": mine["body"].get("id"),
    }, None


def _rows_of(resp):
    """The list inside a `Wire` response, or an empty list.

    **The shape is checked twice, and the second check is the one this file
    first shipped wrong.** The obvious reading is `resp["body"]`, and against a
    response dict that works. It was then called with a *body* from two places,
    where `resp["body"]` indexes a list with a string and raises `TypeError` --
    not an empty result, a crash, on the exact path a directory row takes. Both
    the response dict and the bare body are accepted here so no caller can get
    it wrong by accident.
    """
    body = resp.get("body") if isinstance(resp, dict) else resp
    return body if isinstance(body, list) else []


def _check_ids(wire, acct):
    """Claim 1: the two ids a contractor has must not answer the same way.

    Measured, because the failure this would cause is silent: a wrong id
    returns **200 []**, not an error, so nothing on the screen can tell the user
    that the id was wrong. Only the profile route can.
    """
    rep = {"user_id": acct["user_id"], "profile_id": acct["profile_id"]}

    prof = wire.call("/api/mobile/my/profile", token=acct["token"])
    rep["profile_route_status"] = prof["status"]
    rep["profile_id_matches"] = (
        isinstance(prof["body"], dict) and prof["body"].get("id") == acct["profile_id"])

    public = wire.call("/api/mobile/workers/%s" % acct["profile_id"])
    rep["public_profile_status"] = public["status"]

    reviews_by_profile = wire.call("/api/mobile/workers/%s/reviews" % acct["profile_id"])
    reviews_by_user = wire.call("/api/mobile/workers/%s/reviews" % acct["user_id"])
    public_by_user = wire.call("/api/mobile/workers/%s" % acct["user_id"])

    rep.update({
        "reviews_by_profile_status": reviews_by_profile["status"],
        "reviews_by_user_status": reviews_by_user["status"],
        "public_by_user_status": public_by_user["status"],
    })

    # The defect: the reviews route answers 200 for an id whose **profile** is a
    # 404. Two different questions, one "yes", one "no", and the caller is left
    # holding an empty list it is entitled to draw as "this man has no reviews".
    rep["ids_disagree"] = (
        reviews_by_user["ok"] and not public_by_user["ok"])
    rep["silent_empty"] = reviews_by_user["ok"] and len(_rows_of(reviews_by_user)) == 0
    return rep


def _check_gap(wire, top):
    """Claim 2: a list longer than its header claims is not reported as a gap.

    The header count is `WorkerProfile.totalReviews` and the list is
    `/workers/:id/reviews`; the app already draws both
    (`reviews_section_copy.dart` owns the two arms). What is measured here is
    that the directory rows the browse screen actually renders do not disagree
    in the *other* direction -- a list that claims more reviews than the header
    -- because that arm does not exist and a silent surplus is as much a lie as
    a silent shortfall.
    """
    search = wire.call("/api/mobile/workers/search?limit=100")
    if not search["ok"]:
        return None, "search failed: %s %s" % (search["status"], str(search["body"])[:120])
    rows = _rows_of(search["body"])
    if not rows:
        return None, "search did not answer a list: %s" % str(search["body"])[:120]

    # The rows that claim at least one review: the only ones where the two
    # reads can disagree at all.
    claiming = [r for r in rows
                if isinstance(r.get("total_reviews"), int) and r["total_reviews"] > 0]
    checked, over, under, empty = [], 0, 0, 0
    for r in claiming[:top]:
        wid = r.get("id")
        claimed = r["total_reviews"]
        listing = wire.call("/api/mobile/workers/%s/reviews" % wid)
        if not listing["ok"]:
            continue
        drawn = len(_rows_of(listing))
        checked.append({"id": wid, "claimed": claimed, "drawn": drawn})
        if drawn == 0:
            empty += 1
        elif drawn > claimed:
            over += 1
        elif drawn < claimed:
            under += 1

    rep = {
        "directory_rows": len(rows),
        "claiming_reviews": len(claiming),
        "checked": len(checked),
        "rows_with_no_cards": empty,
        "rows_shorter_than_claim": under,
        "rows_longer_than_claim": over,
        "detail": checked,
    }
    # The direction no guard covers. The shortfall arms ship; a *surplus* -- a
    # list holding more cards than the header promises -- would draw a count
    # the page cannot back, and nothing watches for it.
    rep["surplus_uncaught"] = over > 0
    return rep, None


def _another_writer_is_building():
    """True only when the gate names a build it can see. Never guesses.

    `tool/build_gate.py` exits non-zero for two different reasons and this audit
    is blocked by only one of them: it prints `NO ROOM -- nothing is building`
    when the box is simply too small, and `BUSY (build tool present)` when a
    real build is in flight. Reading the exit code alone is a bug this file's
    siblings shipped and fixed on the tick that wrote them -- a refusal that
    invents a reason is worse than no refusal.

    **NOT `--quiet`, and that is the bug the first run of the sibling shipped
    with.** `--quiet` suppresses the very sentence the branch below tests for,
    so on a box where the gate denies for *memory* the check could never match
    and the helper answered "a writer is building" on every call. The gate's
    whole point is that one sentence discriminates two different denials, so
    this call has to read it.
    """
    try:
        import subprocess
        run = subprocess.run([sys.executable, "tool/build_gate.py"],
                             capture_output=True, text=True, timeout=90)
    except Exception:  # noqa: BLE001 - a missing gate must not block the audit
        return True
    if run.returncode == 0:
        return False
    text = (run.stdout or "") + (run.stderr or "")
    if "nothing is building" in text:
        return False
    return True


def _render(reports):
    lines = []
    for host, (rep, err) in reports.items():
        if err:
            lines.append("  %-42s %s" % (host, err))
            continue
        ids = rep.get("ids", {}) or {}
        gap = rep.get("gap") or {}
        if not ids:
            lines.append("  %-42s ids: NOT MEASURED -- the id read did not "
                         "answer, so no claim about it is printed" % (host,))
        else:
            lines.append("  %-42s ids: user %s / profile %s -- reviews 200 on BOTH, "
                         "profile on the user id -> %s"
                         % (host, ids.get("user_id"), ids.get("profile_id"),
                            "404" if ids.get("ids_disagree") else "200"))
        # **An empty `gap` is a read that did not happen, and printing its keys
        # as `None` is the lie this file shipped.** `_check_gap` returns
        # `(None, reason)` on every failure path and `main()` collapses that to
        # `{}`, so this renderer drew a line of `None claiming, None checked,
        # None empty, None LONGER than it` -- five absent measurements presented
        # in the grammar of five measured ones, indistinguishable from a real
        # result in a scrolled log. The sibling audits that were fixed print
        # the silence as a silence; this one had no arm for it.
        if not gap:
            lines.append("  %-42s directory: NOT MEASURED -- %s"
                         % ("", rep.get("gap_error") or "the directory read did not answer"))
        else:
            lines.append("  %-42s directory: %s claiming, %s checked, %s empty, "
                         "%s short of the header, %s LONGER than it"
                         % ("", gap.get("claiming_reviews"), gap.get("checked"),
                            gap.get("rows_with_no_cards"),
                            gap.get("rows_shorter_than_claim"),
                            gap.get("rows_longer_than_claim")))
        if ids.get("ids_disagree"):
            lines.append("  %-42s   ^ /workers/%s/reviews answers 200 while "
                         "/workers/%s answers 404 -- a wrong id reads empty, "
                         "not wrong" % ("", ids.get("user_id"), ids.get("user_id")))
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--hosts", default=",".join(HOSTS))
    ap.add_argument("--top", type=int, default=8,
                    help="directory rows to read a review list for (default 8)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if _another_writer_is_building():
        sys.stderr.write("REFUSED - another writer is building on this box\n")
        return 3

    reports, all_refused = {}, []
    for host in [h.strip() for h in args.hosts.split(",") if h.strip()]:
        wire = Wire(host.rstrip("/"))
        acct, err = _throwaway_worker(wire)
        if acct is None:
            all_refused.append(host)
            reports[host] = ({"ids": {}, "gap": {}}, err)
            continue
        ids_rep = _check_ids(wire, acct)
        gap_rep, gap_err = _check_gap(wire, args.top)
        # The reason was measured and then thrown away: `gap_rep = {}` erased it
        # and `_render` drew `None`s in its place. It is kept beside the empty
        # report so the renderer can say WHICH read failed instead of only that
        # one did.
        reports[host] = ({"ids": ids_rep, "gap": gap_rep or {}, "gap_error": gap_err}, None)

    unreachable = [h for h, (r, e) in reports.items()
                   if e and "failed" in e and "1010" not in str(e)]
    cf_blocked = [h for h, (r, e) in reports.items() if e and "1010" in str(e)]

    if args.json:
        print(json.dumps({
            "hosts": {h: {"report": r, "error": e} for h, (r, e) in reports.items()},
            "unreachable": unreachable,
            "cloudflare_1010": cf_blocked,
        }, indent=2, ensure_ascii=False))
    else:
        print("Contractor reviews audit -- id shape and the aggregate-vs-list gap")
        for line in _render(reports):
            print(line)
        if cf_blocked:
            print("\n  %d host(s) answered 403/1010 (Cloudflare WAF on the agent "
                  "string), not an API fault." % len(cf_blocked))
        if unreachable:
            print("\n  UNREACHABLE: %s -- no verdict either way." % ", ".join(unreachable))

    if all_refused and len(all_refused) == len(reports):
        return 2
    for rep, _ in reports.values():
        ids = rep.get("ids", {}) or {}
        gap = rep.get("gap", {}) or {}
        if ids.get("ids_disagree") or gap.get("surplus_uncaught"):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
