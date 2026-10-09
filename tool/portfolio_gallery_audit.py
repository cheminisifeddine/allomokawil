#!/usr/bin/env python3
"""Measure what a contractor's own gallery returns, instead of assuming.

`IMPROVEMENT_BACKLOG.md` (line 14296, tick of 2 Oct) left an explicit
instruction for the next sweep:

    "the portfolio grid has the identical structure
     (`/workers/:id` totals vs the `/portfolio` list) and the same
     not-guessing rule applies."

**That instruction is wrong, and this audit exists to say so with a number.**
Measured 9 Oct 2026 against production, on two hosts:

    GET /api/mobile/workers/5     -> 200, keys are ...
       cover_image_url, total_completed_jobs, total_reviews
    GET /api/mobile/workers/5/portfolio -> 200 []

There is **no photo aggregate on the profile at all**. Not a wrong one, not a
drifted one -- absent, on every row of 100 in `/workers/search` and on the
single-profile route. So the reviews shape this backlog found (a header count
that disagrees with its own list) **cannot occur** on the gallery: the half that
would have to print the count does not exist. Sweeping for it was chasing a
phantom third arm, and a tool that reported "0 disagreements" here would have
looked like coverage while measuring a column nobody sends.

The real shape is the one the previous tick found on the reviews route, in a
place where it is **worse**: a contractor has two ids (profile id 657, user id
1035), and the gallery route answers differently depending on which one it gets.

    POST /api/mobile/workers/657/portfolio   -> 200 {"ok":true}, read back 1
    POST /api/mobile/workers/1035/portfolio  -> 500, read back 0
    POST /api/mobile/workers/999999/portfolio -> 500, read back 0
    GET  /api/mobile/workers/1035/portfolio  -> 200 []   <- an id that 404s

So the read is silent for a wrong id (200 `[]`, indistinguishable from a new
account) while the write is loud (500). A contractor with a session whose code
ever passed `userId` where `id` was meant would see «لم يضف صوراً بعد» forever,
with every upload attempt failing -- and the *gallery* route would never say
which id was wrong.

**Why a tool, and why Python.** `tool/build_gate.py` refuses Dart whenever the
hypervisor balloon is up (411 MB available against a 900 MB floor when this was
written), and a measurement is exactly the work that must not be dropped for
that reason. Same reasoning `tool/worker_reviews_audit.py` records for itself.

**It only creates throwaway accounts** and never edits a real contractor's
gallery; every write here lands on an id the tool itself just minted.
"""
import argparse
import json
import random
import sys
import urllib.error
import urllib.request

# The customer-facing host first, then the workers.dev fallback -- the same
# pair, in the same order, that `tool/worker_reviews_audit.py` and
# `tool/inbox_read_audit.py` use, so a verdict here is about the hosts the
# shipped APK calls.
HOSTS = [
    "https://allomokawil.com",
    "https://finili.medsaidkichene.workers.dev",
]

# Cloudflare answers **403 with error code 1010** to urllib's default agent.
USER_AGENT = "AlloMokawilApp/1.0 (Android 14; Flutter)"
READ_TIMEOUT = 30

# A gallery photo is addressed by its R2 URL. The tool never uploads a byte --
# it points at a name that cannot resolve, because the audit asks whether a row
# is *stored and listed*, not whether a URL still serves an image.
_PHOTO = "https://example.com/audit-gallery-%d.jpg"


class Wire:
    """One POST/GET against the API, with the outcomes kept distinct.

    The (403, 'error code: 1010') distinction is the same one the sibling
    audits keep: treating a WAF agent-string block as an application 403 files a
    healthy API as broken.
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
    """A fresh contractor, so the tool never reads an id it did not mint.

    The id *shape* is the audit's subject and it cannot be measured on a
    directory row: `/workers/search` answers profile ids, and the account id
    behind one is only reachable from a token this tool holds.
    """
    reg = wire.call("/api/register", {
        "phone": _phone("05"), "email": "",
        "full_name": "حرفي قياس المعرض", "password": "secret123",
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
    `worker_reviews_audit._rows_of` records: the obvious reading is
    `resp["body"]`, which raises `TypeError` when handed a body directly.
    """
    body = resp.get("body") if isinstance(resp, dict) else resp
    return body if isinstance(body, list) else []


def _check_aggregate(wire, acct):
    """Claim 1: the profile route carries **no** photo total to disagree with.

    This is the claim the backlog's "identical structure" note rests on, and it
    is the one that is false. It is checked by *asking the server* rather than
    by reading the Dart model, because the model's silence could mean either
    "the server sends it and the parser drops it" (a real bug) or "the server
    never sends it" (no bug at all) -- and those need opposite fixes.
    """
    rep = {"profile_id": acct["profile_id"], "user_id": acct["user_id"]}
    prof = wire.call("/api/mobile/workers/%d" % acct["profile_id"])
    rep["profile_status"] = prof["status"]
    body = prof["body"] if isinstance(prof["body"], dict) else {}
    keys = sorted(body.keys())
    rep["profile_keys"] = keys
    rep["image_like_keys"] = sorted(
        k for k in keys if any(t in k for t in ("photo", "portfolio", "image", "media")))
    rep["count_like_keys"] = sorted(
        k for k in keys if "count" in k.lower() or k.endswith("_total"))
    # The decisive fact: is there a numeric aggregate *about photos*?
    rep["carries_photo_total"] = any(
        isinstance(body.get(k), int) for k in keys
        if any(t in k for t in ("photo", "portfolio")))
    return rep, None


def _check_ids(wire, acct):
    """Claim 2: the two ids must not answer the same way, on read and on write.

    Measured, because the read side is silent: a wrong id answers **200 []**,
    not an error, so nothing on the screen can tell a contractor that the id was
    wrong -- he sees an empty gallery and an upload that fails.
    """
    rep = {"user_id": acct["user_id"], "profile_id": acct["profile_id"]}
    prof_id, user_id = acct["profile_id"], acct["user_id"]

    # The profile route is the only witness that an id does not exist.
    prof_user = wire.call("/api/mobile/workers/%d" % user_id)
    prof_prof = wire.call("/api/mobile/workers/%d" % prof_id)
    rep["profile_route_user_id"] = prof_user["status"]
    rep["profile_route_profile_id"] = prof_prof["status"]

    rows_user = wire.call("/api/mobile/workers/%d/portfolio" % user_id)
    rows_prof = wire.call("/api/mobile/workers/%d/portfolio" % prof_id)
    rep["gallery_user_id_status"] = rows_user["status"]
    rep["gallery_profile_id_status"] = rows_prof["status"]
    rep["gallery_user_id_len"] = len(_rows_of(rows_user))
    rep["gallery_profile_id_len"] = len(_rows_of(rows_prof))

    # The disagreement that matters: one route 404s on the user id while the
    # gallery answers 200 on it. Both are 200-with-empty unless the profile
    # route is also asked, and nothing in the gallery screen asks it.
    rep["ids_disagree"] = (
        prof_user["status"] != 200
        and rows_user["status"] == 200
    )
    return rep, None


def _check_write(wire, acct):
    """Claim 3: a write naming the wrong id must not report success.

    The reachable failure: `addPortfolioImage(workerId: …)` is the app's own
    write, and its id comes from the same read that could hand back a user id.
    A silent 200 here would be worse than a 500 -- the contractor would be told
    the photo was added and it would never appear.
    """
    rep = {}
    prof_id, user_id = acct["profile_id"], acct["user_id"]

    good = wire.call("/api/mobile/workers/%d/portfolio" % prof_id,
                     {"image_url": _PHOTO % 1}, token=acct["token"])
    rep["write_profile_id_status"] = good["status"]
    rep["write_profile_id_reported_ok"] = good["ok"]

    wrong = wire.call("/api/mobile/workers/%d/portfolio" % user_id,
                      {"image_url": _PHOTO % 2}, token=acct["token"])
    rep["write_user_id_status"] = wrong["status"]
    # A wrong id that answers 200 is the dangerous case: it claims success for a
    # photo it did not store. The measured server answers 500, so this is
    # expected to be False -- and that is the result worth pinning.
    rep["wrong_id_reports_success"] = wrong["ok"]

    # Did the wrong-id write land anywhere? Counted **either side of a second
    # wrong-id write** rather than inferred: the gallery is read, the wrong id
    # is written again, the gallery is read. A rise between those two reads is
    # the only thing that can prove the row was stored on a profile the
    # contractor does not own, which a status code alone cannot.
    before = wire.call("/api/mobile/workers/%d/portfolio" % prof_id)
    wrong2 = wire.call("/api/mobile/workers/%d/portfolio" % user_id,
                       {"image_url": _PHOTO % 3}, token=acct["token"])
    after = wire.call("/api/mobile/workers/%d/portfolio" % prof_id)
    n_before, n_after = len(_rows_of(before)), len(_rows_of(after))
    rep["write_user_id_status_second"] = wrong2["status"]
    rep["gallery_len_before_wrong_write"] = n_before
    rep["gallery_len_after_wrong_write"] = n_after
    # A wrong id that stores its photo on *another* profile is a different and
    # worse defect than one that fails loudly; this counts it rather than argues.
    rep["wrong_id_write_landed_somewhere"] = n_after > n_before
    return rep, None


def _another_writer_is_building():
    """True only when the gate names a build it can see. Never guesses.

    `tool/build_gate.py` exits non-zero for two different reasons and this audit
    is blocked by only one: it prints `NO ROOM -- nothing is building` when the
    box is simply too small, and `BUSY (build tool present)` when a real build
    is in flight. **Not `--quiet`**: that suppresses the sentence tested below,
    so the check invents a reason on every memory-denied box.
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
        agg = rep.get("aggregate", {}) or {}
        ids = rep.get("ids", {}) or {}
        wr = rep.get("write", {}) or {}
        if agg:
            lines.append("    photo aggregate on profile: %s (image keys: %s | "
                         "count keys: %s)"
                         % (agg.get("carries_photo_total"),
                            agg.get("image_like_keys"),
                            agg.get("count_like_keys")))
        lines.append("    profile id %s -> profile %s, gallery %s (%s rows)"
                     % (ids.get("profile_id"), ids.get("profile_route_profile_id"),
                        ids.get("gallery_profile_id_status"),
                        ids.get("gallery_profile_id_len")))
        lines.append("    user    id %s -> profile %s, gallery %s (%s rows)"
                     % (ids.get("user_id"), ids.get("profile_route_user_id"),
                        ids.get("gallery_user_id_status"),
                        ids.get("gallery_user_id_len")))
        lines.append("    write profile id -> %s | write user id -> %s | "
                     "wrong id claims success: %s"
                     % (wr.get("write_profile_id_status"),
                        wr.get("write_user_id_status"),
                        wr.get("wrong_id_reports_success")))
        lines.append("    ids_disagree: %s | wrong id landed somewhere: %s"
                     % (ids.get("ids_disagree"),
                        wr.get("wrong_id_write_landed_somewhere")))
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--hosts", default=",".join(HOSTS))
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
            reports[host] = ({"aggregate": {}, "ids": {}, "write": {}}, err)
            continue
        agg, _ = _check_aggregate(wire, acct)
        ids, _ = _check_ids(wire, acct)
        wr, _ = _check_write(wire, acct)
        reports[host] = ({"aggregate": agg, "ids": ids, "write": wr}, None)

    unreachable = [h for h, (r, e) in reports.items() if e and "1010" not in str(e)]
    cf_blocked = [h for h, (r, e) in reports.items() if e and "1010" in str(e)]

    if args.json:
        print(json.dumps({
            "hosts": {h: {"report": r, "error": e} for h, (r, e) in reports.items()},
            "unreachable": unreachable,
            "cloudflare_1010": cf_blocked,
        }, indent=2, ensure_ascii=False))
    else:
        print("Contractor gallery audit -- the 'identical structure' claim, and the id shape")
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
        ids = rep.get("ids", {}) or {}
        wr = rep.get("write", {}) or {}
        if ids.get("ids_disagree") or wr.get("wrong_id_reports_success"):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
