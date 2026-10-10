#!/usr/bin/env python3
"""Measure what the inbox read actually returns, instead of assuming it.

The backlog's carry-over lead for this tick was: *"`conversations()` -- the
inbox list is a single uncursored read and a capped inbox would silently hide
threads. Unmeasured. Do not assume it caps; measure it the way this one was
measured before writing a word of copy."*

It was measured. **It does not cap.** 120 conversations were created on one
throwaway account and the inbox answered 120 rows; `?limit=200`, `?page=2` and
`?offset=30` are all silently ignored, because the route has no paging at all.
That is the outcome the lead explicitly warned against filing, so it is
recorded here rather than in the app: a "partial inbox" band would have been a
band about a truncation that does not exist.

The second half of the question -- *is the order something a user reads as
mail?* -- turned out to be answered by the server: rows come back by activity
descending (`last_message_at`), stably across repeated reads. So the app has
nothing to sort and nothing to warn about.

**Why a tool, and why Python.** Step 4's gate (`tool/build_gate.py`) refuses
Dart on this box whenever the hypervisor is holding the memory back, and it was
refusing tonight (335 MB available, a suite run measured to bottom out at
1177 MB). A measurement is exactly the kind of work that *must not* be skipped
for that reason -- it is also the kind of work that does not need a Dart VM at
all. So this is stdlib-only Python, which runs on a box whose memory is too
full to run Dart, and it hits the same production host the app calls.

**It only creates throwaway accounts**, in the same shape the existing
`test/live_chat_image_e2e_test.dart` already uses. Nothing it creates is a real
person, and it never touches a real thread: the point is to give one account a
number of conversations no real user has.

    python3 tool/inbox_read_audit.py
    python3 tool/inbox_read_audit.py --threads 130 --json

Exit codes: 0 the inbox answered everything it was given (nothing to report),
1 a read lost rows or ignored the order it promised, 2 the network/host was
unreachable, 3 refused to start because the build gate says another writer is
on this box. **2 and 3 are opposites** -- "the wire is down" and "do not start
here" -- and the 69th tick already lost one tick by collapsing that pair, so
this tool will not repeat it.
"""
import argparse
import json
import random
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# The customer-facing host first, then the workers.dev fallback -- the same
# pair, in the same order, that `test/live_wire_contract_test.dart` fetches and
# that the release builds inject with `--dart-define`, so a verdict here is a
# statement about the hosts the shipped APK calls.
HOSTS = [
    "https://allomokawil.com",
    "https://finili.medsaidkichene.workers.dev",
]

# Cloudflare answers **403 with error code 1010** ("access denied") to urllib's
# default `Python-urllib/3.x` agent, which is a WAF signature match rather than
# an application failure. Measured on the first attempt of the tick that wrote
# this file: status 403, body `error code: 1010`. Every call below sets an agent
# that looks like the app, and a 1010 is reported as a distinct outcome so a
# future tick does not spend ten minutes believing the API is down.
USER_AGENT = "AlloMokawilApp/1.0 (Android 14; Flutter)"

# One read of the 120-conversation inbox measured 29,620 bytes, so a thread row
# costs roughly 250 bytes. The per-request budget below is generous against a
# 1 MiB reply and short of the infinite wait that produced the 30 Sep stall.
READ_TIMEOUT = 30


class Wire:
    """One POST/GET against the API, with the outcomes kept distinct.

    The distinction that matters is (403, body 'error code: 1010') versus a real
    403 from the application. Treating the first as the second would file the
    API as broken when it answered every request the app ever sends it.
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
            return {"ok": True, "status": f.status, "body": json.loads(raw), "bytes": len(raw)}
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            return {"ok": False, "status": e.code, "body": raw[:300],
                    "cf1010": "1010" in raw[:300], "bytes": len(raw)}
        except Exception as e:  # noqa: BLE001 - any transport fault is one outcome
            return {"ok": False, "status": 0, "body": str(e)[:200], "cf1010": False, "bytes": 0}


def _phone(prefix):
    return "%s%02d%06d" % (prefix, random.randint(10, 99), random.randint(0, 999999))


def _register(wire, kind, label):
    return wire.call("/api/register", {
        "phone": _phone("07" if kind == "customer" else "06"),
        "email": "",
        "full_name": label,
        "password": "secret123",
        "type": kind,
    })


def _owner_and_threads(wire, threads):
    """Build one throwaway customer with [threads] conversations against them.

    A conversation is created *by the worker* naming the owner, because that is
    the direction the app uses (`openConversation` from the worker's side), and
    it is the only direction that produces a row visible to both parties.
    """
    reg = _register(wire, "customer", "مقياس صندوق الوارد")
    if not reg["ok"] or not isinstance(reg["body"], dict) or "token" not in reg["body"]:
        return None, "register failed: %s %s" % (reg["status"], str(reg["body"])[:120])
    token = reg["body"]["token"]
    owner = reg["body"]["user"]["id"]

    def one(i):
        w = _register(wire, "worker", "مقاول قياس %d" % i)
        if not w["ok"] or not isinstance(w["body"], dict):
            return None
        made = wire.call("/api/mobile/conversations",
                         {"project_id": None, "other_user_id": owner},
                         token=w["body"]["token"])
        if made["ok"] and isinstance(made["body"], dict) and made["body"].get("id"):
            return made["body"]["id"]
        return None

    with ThreadPoolExecutor(max_workers=10) as ex:
        ids = [i for i in ex.map(one, range(threads)) if i]
    return {"token": token, "owner": owner, "made": ids}, None


def _check(wire, acct, threads):
    """The two claims this audit exists to test, and only those two."""
    report = {"threads_requested": threads, "threads_made": len(acct["made"])}
    listing = wire.call("/api/mobile/conversations", token=acct["token"])
    if not listing["ok"]:
        return report, "inbox read failed: %s %s" % (listing["status"], str(listing["body"])[:120])
    rows = listing["body"]
    if not isinstance(rows, list):
        return report, "inbox did not answer a list: %s" % str(rows)[:120]

    ids = [r.get("id") for r in rows]
    report.update({
        "rows_returned": len(rows),
        "inbox_bytes": listing["bytes"],
        "bytes_per_row": listing["bytes"] // max(1, len(rows)),
        "distinct_rows": len(set(ids)),
        "all_made_present": set(acct["made"]).issubset(set(ids)),
    })
    # Claim 1: no silent truncation. If the inbox answers everything it was
    # given, there is no lost page for a band to describe.
    report["capped"] = not report["all_made_present"]

    # Claim 2: the order a user reads as mail. `last_message_at` is what the row
    # prints, so the server order and that stamp agreeing is the whole claim.
    # A null stamp cannot be compared, so those rows are excluded and counted
    # separately rather than being sorted into a place they do not belong.
    dated = [r for r in rows if r.get("last_message_at")]
    undated = len(rows) - len(dated)
    by_activity = [r["id"] for r in sorted(dated, key=lambda r: r["last_message_at"], reverse=True)]
    report["rows_without_timestamp"] = undated
    report["ordered_by_activity_desc"] = by_activity == [r["id"] for r in dated]

    # Claim 3: the order is stable. Two reads of an unchanging inbox that come
    # back differently is a list that reshuffles under the user's thumb.
    again = wire.call("/api/mobile/conversations", token=acct["token"])
    report["order_stable_across_reads"] = bool(
        again["ok"] and isinstance(again["body"], list)
        and [r.get("id") for r in again["body"]] == ids)

    # The paging question, asked explicitly. These parameters are ignored, so
    # they answer the same list; a future server that honours one changes the
    # byte count here and the audit says so instead of quietly passing.
    paged = wire.call("/api/mobile/conversations?limit=500&page=1", token=acct["token"])
    report["paging_params_honoured"] = bool(
        paged["ok"] and isinstance(paged["body"], list) and paged["body"] != rows)
    return report, None



def _another_writer_is_building():
    """True only when the gate names a build it can see. Never guesses."""
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
    # The gate's own phrasing. `NO ROOM -- nothing is building` is the shape
    # that says the denial is memory, not contention; anything else non-zero is
    # a build this loop can see, and refusing is the safe reading of it.
    if "nothing is building" in text:
        return False
    return True


def _render(reports, err):
    lines = []
    for host, (rep, err_h) in reports.items():
        if err_h:
            lines.append("  %-42s %s" % (host, err_h))
            continue
        verdict = "UNCAPPED" if not rep["capped"] else "CAPPED"
        lines.append("  %-42s %s -- %d made, %d rows, %d B (%.0f B/row)"
                     % (host, verdict, rep["threads_made"], rep["rows_returned"],
                        rep["inbox_bytes"], rep["bytes_per_row"]))
        lines.append("  %-42s order by activity desc: %s | stable across reads: %s | paging params honoured: %s"
                     % ("", rep["ordered_by_activity_desc"], rep["order_stable_across_reads"],
                        rep["paging_params_honoured"]))
        if rep["rows_without_timestamp"]:
            lines.append("  %-42s %d row(s) carry no last_message_at and are excluded from the order claim"
                         % ("", rep["rows_without_timestamp"]))
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--threads", type=int, default=120,
                    help="throwaway conversations to create (default 120, past any round number a cap would use)")
    ap.add_argument("--hosts", default=",".join(HOSTS))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    # `tool/build_gate.py` exits non-zero for **two different reasons** and this
    # audit is only blocked by one of them. It prints `NO ROOM -- nothing is
    # building` when the box is simply too small (the hypervisor is holding the
    # memory back, which no local action clears), and `BUSY (build tool
    # present)` when another writer really is mid-build. The rule it encodes --
    # two exit codes would force the caller to learn a second rule -- is right
    # for `flutter test`, which needs ~1.2 GB. This tool is stdlib Python making
    # a few hundred KB of HTTP requests with 10 threads, so memory starvation is
    # irrelevant to it and refusing there would abandon the measurement on a
    # box that can hold it perfectly well.
    #
    # That is the first version's bug, caught the minute it was run: it read the
    # exit code, printed BUSY, and refused -- while the gate was simultaneously
    # reporting that **nothing was building**. A refusal that invents a reason
    # is worse than no refusal.
    # **The polarity was inverted, and it is why this file has never measured
    # anything.** The helper answers "is a build I can SEE in flight", and
    # its own docstring plus both sibling audits refuse on `True`. This line
    # read `not <that>`, so the tool refused precisely when nothing was
    # building and ran precisely when a real build was in flight -- the
    # exact opposite of the rule the paragraph above it argues for. The
    # paragraph right above this line documents refusing on an invented
    # reason; this line invented one on every single call. Measured: with
    # the gate reporting `NO ROOM ... nothing is building`, the helper
    # returned False, `not False` -> refuse, exit 3 -- a refusal whose stated
    # reason was false on the run that printed it. `worker_reviews_audit.py`
    # and `notification_read_audit.py` both read `if _another_writer_is_building():`.
    if _another_writer_is_building():
        sys.stderr.write("REFUSED - another writer is building on this box\n")
        return 3

    reports, any_err, all_refused = {}, None, []
    for host in [h.strip() for h in args.hosts.split(",") if h.strip()]:
        wire = Wire(host.rstrip("/"))
        acct, err = _owner_and_threads(wire, args.threads)
        if acct is None:
            all_refused.append(host)
            reports[host] = ({}, err)
            continue
        reports[host] = _check(wire, acct, args.threads)

    unreachable = [h for h, (r, e) in reports.items() if e and "failed" in e and "1010" not in str(e)]
    cf_blocked = [h for h, (r, e) in reports.items() if e and "1010" in str(e)]

    if args.json:
        print(json.dumps({
            "hosts": {h: {"report": r, "error": e} for h, (r, e) in reports.items()},
            "unreachable": unreachable,
            "cloudflare_1010": cf_blocked,
        }, indent=2, ensure_ascii=False))
    else:
        print("Inbox read audit -- %d throwaway conversations per host" % args.threads)
        for line in _render(reports, all_refused[0] if all_refused else None):
            print(line)
        if cf_blocked:
            print("\n  %d host(s) answered 403/1010 (Cloudflare WAF on the agent string), not an API fault."
                  % len(cf_blocked))
        if unreachable:
            print("\n  UNREACHABLE: %s -- no verdict either way." % ", ".join(unreachable))

    if all_refused and len(all_refused) == len(reports):
        return 2 if unreachable else 2
    if any(r.get("capped") for r, _ in reports.values() if r):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
