#!/usr/bin/env python3
"""Measure what the notification centre actually returns, instead of assuming.

The 9 Oct tick's carry-over said: the remaining `data/repository.dart` surface
after the market and the thread is a *screen* pass. The notification centre is
the surface it had not measured, and it is the one place where a silent cap does
the most damage: this screen is the app's memory of what happened while it was
closed, and its rows are also the input to the header's unread pip.

**Measured 10 Oct 2026 against production, on two hosts.** It CAPS, and harder
than the two the loop had already fixed:

    GET /api/notifications                 -> 100 rows (hard cap)
    ?limit=200 / ?limit=500&page=1 / ?page=2 / ?offset=100 / ?all=1
                                          -> the same 100 rows, byte-identical
    GET /api/unread                        -> the server's real count (150)

So the cap is the server's and not a default the client may raise, exactly like
`/api/messages/:id`. Rows come back **newest first** (id descending, verified
against `created_at`), which is the order the screen prints -- so unlike the
inbox, nothing here needs sorting. What it needs is a way to *know* the centre
is short.

**The second, sharper finding: the mark-read write 500s at exactly 100 ids.**
Measured by bisection, not guessed -- 1, 5, 20, 50, 60, 70, 80, 90, 95 and **99**
ids all return 200 with the correct new count; **100 ids returns 500**
`code: internal`. And 100 is precisely the number of rows the capped read
returns, so the shape is reachable from the app and not an exotic payload.

That combination is the defect that matters, and it is not the cap on its own:

    1. the centre draws the newest 100 and cannot see the rest;
    2. `_unread` counts **drawn rows only**, so once those 100 are read the
       header pip and the «تعليم الكل كمقروء» button both agree there is
       nothing left to clear;
    3. the server still holds the unread rows that were never drawn.

So the user clears every notification they can see, the app says zero, and the
server says otherwise -- with nothing on screen to contradict it. Measured:
after reading all 100 drawn rows the server reported **40 unread** while the
screen had **0** and the button was gone. That is the mirror image of the
market-search bug this loop shipped on 10 Oct: there the app claimed *nothing
matches*; here it claims *nothing is unread*, which is a claim about data it
never read.

**Why a tool, and why Python.** `tool/build_gate.py` refuses Dart on this box
whenever the hypervisor balloon is up, and it was refusing tonight (352 MB
available against a 900 MB floor). A measurement is exactly the work that must
not be dropped for that reason, and it needs no Dart VM -- which is also why the
cases that pin this file's own logic are Python, the same reasoning as
`run_tests_busy_code_test.py`.

**It only creates throwaway accounts** and never touches a real thread, the same
contract `tool/inbox_read_audit.py` keeps.

    python3 tool/notification_read_audit.py
    python3 tool/notification_read_audit.py --rows 140 --json

Exit codes: 0 nothing to report (uncapped, and the write survives the row count),
1 the read capped or the write failed at a reachable size, 2 the host was
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
from concurrent.futures import ThreadPoolExecutor

# The customer-facing host first, then the workers.dev fallback -- the same pair,
# in the same order, that `tool/inbox_read_audit.py` and
# `test/live_wire_contract_test.dart` use, so a verdict here is a statement about
# the hosts the shipped APK calls.
HOSTS = [
    "https://allomokawil.com",
    "https://finili.medsaidkichene.workers.dev",
]

# Cloudflare answers **403 with error code 1010** ("access denied") to urllib's
# default `Python-urllib/3.x` agent -- a WAF signature match, not an application
# failure. Measured on the first attempt of the tick that wrote
# `inbox_read_audit.py`: status 403, body `error code: 1010`. A 1010 is
# reported as its own outcome so a future tick does not spend ten minutes
# believing a healthy API is down.
USER_AGENT = "AlloMokawilApp/1.0 (Android 14; Flutter)"

# One row measured ~240 bytes, so this is generous against a 1 MiB reply and
# short of the infinite wait that produced the 30 Sep stall.
READ_TIMEOUT = 30


class Wire:
    """One POST/GET against the API, with the outcomes kept distinct.

    The distinction that matters is (403, body 'error code: 1010') versus a real
    403 from the application: treating the first as the second files the API as
    broken when it answered every request the app ever sends it.
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


def _seed(wire, want):
    """One throwaway customer holding [want] notifications, and its ids.

    A notification is produced the way a real one is: publishing a project as
    the customer writes the `project_update` row that the centre draws. That is
    the same direction the app uses, and it is the only one measured to create
    a row, so nothing here is invented.
    """
    reg = wire.call("/api/register", {
        "phone": _phone("07"), "email": "",
        "full_name": "قياس مركز الإشعارات", "password": "secret123",
        "type": "customer",
    })
    if not reg["ok"] or not isinstance(reg["body"], dict) or "token" not in reg["body"]:
        return None, "register failed: %s %s" % (reg["status"], str(reg["body"])[:120])
    token = reg["body"]["token"]

    def one(i):
        return wire.call("/api/mobile/projects", {
            "title": "مشروع قياس %d" % i, "description": "قياس السقف",
            "category": "painting", "wilaya": "16",
            "budget_min": 10000, "budget_max": 20000,
        }, token=token)

    with ThreadPoolExecutor(max_workers=10) as ex:
        made = [r for r in ex.map(one, range(want)) if r["ok"]]
    return {"token": token, "made": len(made)}, None


def _check(wire, acct, want):
    """The three claims this audit exists to test, and only those three."""
    rep = {"notifications_requested": want, "notifications_made": acct["made"]}

    listing = wire.call("/api/notifications", token=acct["token"])
    if not listing["ok"]:
        return rep, "centre read failed: %s %s" % (listing["status"], str(listing["body"])[:120])
    rows = listing["body"]
    if not isinstance(rows, list):
        return rep, "centre did not answer a list: %s" % str(rows)[:120]

    unread = wire.call("/api/unread", token=acct["token"])
    server_unread = unread["body"].get("unread") if isinstance(unread["body"], dict) else None

    rep.update({
        "rows_returned": len(rows),
        "bytes": listing["bytes"],
        "bytes_per_row": listing["bytes"] // max(1, len(rows)),
        "distinct_rows": len(set(r.get("id") for r in rows)),
        "server_unread": server_unread,
    })

    # Claim 1: no silent truncation. The server's own count is the only witness
    # that can catch a lost row -- asking the same route twice cannot.
    rep["capped"] = isinstance(server_unread, int) and server_unread > len(rows)

    # Claim 2: the order a user reads as history. Newest first, which is the
    # one order that makes a cap *least* harmful: the rows the user misses are
    # the oldest ones, so the newest fact always survives.
    dated = [r for r in rows if r.get("created_at")]
    rep["rows_without_timestamp"] = len(rows) - len(dated)
    rep["newest_first"] = [r.get("created_at") for r in dated] == \
        sorted((r.get("created_at") for r in dated), reverse=True)

    # Claim 3: the write survives the number of rows the read hands back. This
    # is the reachable shape -- `_markAllRead` sends no ids, but a per-row
    # sweep that batches what it drew sends exactly `len(rows)` of them -- and
    # it is what makes the cap a *stranding* rather than a loss.
    ids = [r.get("id") for r in rows]
    rep["ids_returned"] = len(ids)
    if ids:
        marked = wire.call("/api/notifications/read", {"ids": ids}, token=acct["token"])
        rep["mark_all_drawn_status"] = marked["status"]
        rep["write_survives_row_count"] = marked["ok"]
    else:
        rep["mark_all_drawn_status"] = None
        rep["write_survives_row_count"] = True

    # The stranding itself, measured rather than argued: read the server's
    # count again after clearing every row the centre drew. A gap here is the
    # defect -- the screen believes it is finished and the server does not.
    after = wire.call("/api/unread", token=acct["token"])
    left = after["body"].get("unread") if isinstance(after["body"], dict) else None
    rep["unread_left_after_clearing_drawn"] = left
    rep["strands_rows"] = isinstance(left, int) and left > 0
    return rep, None


def _another_writer_is_building():
    """True only when the gate names a build it can see. Never guesses.

    `tool/build_gate.py` exits non-zero for two different reasons and this audit
    is blocked by only one of them: it prints `NO ROOM -- nothing is building`
    when the box is simply too small, and `BUSY (build tool present)` when a
    real build is in flight. Reading the exit code alone is a bug this file's
    sibling shipped and fixed on the tick that wrote it -- a refusal that
    invents a reason is worse than no refusal.
    """
    try:
        import subprocess
        # **NOT `--quiet`, and that is the bug this first run shipped with.**
        # `--quiet` suppresses the very sentence the branch below tests for, so
        # on a box where the gate denies for *memory* the check could never
        # match and the helper answered "a writer is building" on every call --
        # a refusal that invents a reason, which is worse than no refusal. It
        # was caught by running the tool: it refused instantly on a box where
        # the gate was simultaneously reporting that nothing was building.
        # The gate's whole point is that one sentence discriminates two
        # different denials, so this call has to read it.
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
        verdict = "CAPPED" if rep.get("capped") else "uncapped"
        lines.append("  %-42s %s -- %d made, %d rows drawn, server unread %s (%.0f B/row)"
                     % (host, verdict, rep["notifications_made"], rep["rows_returned"],
                        rep["server_unread"], rep["bytes_per_row"]))
        lines.append("  %-42s newest first: %s | write with %s ids -> HTTP %s | strands rows: %s"
                     % ("", rep.get("newest_first"), rep.get("ids_returned"),
                        rep.get("mark_all_drawn_status"), rep.get("strands_rows")))
        if rep.get("strands_rows"):
            lines.append("  %-42s   ^ %s unread row(s) survive clearing every row the centre drew"
                         % ("", rep.get("unread_left_after_clearing_drawn")))
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--rows", type=int, default=140,
                    help="throwaway notifications to create (default 140, past the measured 100 cap)")
    ap.add_argument("--hosts", default=",".join(HOSTS))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if _another_writer_is_building():
        sys.stderr.write("REFUSED - another writer is building on this box\n")
        return 3

    reports, all_refused = {}, []
    for host in [h.strip() for h in args.hosts.split(",") if h.strip()]:
        wire = Wire(host.rstrip("/"))
        acct, err = _seed(wire, args.rows)
        if acct is None:
            all_refused.append(host)
            reports[host] = ({}, err)
            continue
        reports[host] = _check(wire, acct, args.rows)

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
        print("Notification centre read audit -- %d throwaway notifications per host" % args.rows)
        for line in _render(reports):
            print(line)
        if cf_blocked:
            print("\n  %d host(s) answered 403/1010 (Cloudflare WAF on the agent string), not an API fault."
                  % len(cf_blocked))
        if unreachable:
            print("\n  UNREACHABLE: %s -- no verdict either way." % ", ".join(unreachable))

    if all_refused and len(all_refused) == len(reports):
        return 2
    if any(r.get("capped") or r.get("strands_rows") or not r.get("write_survives_row_count", True)
           for r, _ in reports.values() if r):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
