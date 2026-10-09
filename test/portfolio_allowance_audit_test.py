#!/usr/bin/env python3
"""Pin the logic the portfolio-allowance audit reasons with -- python, not Dart.

    python3 test/portfolio_allowance_audit_test.py

**Why this is Python and not a Dart test.** `tool/build_gate.py` refuses Dart
on this box whenever the hypervisor balloon is up (340 MB available against a
900 MB floor on the tick that wrote this file). Every claim below is about
*this tool's* judgement -- is a ceiling stated, is the list capped, does the
header contradict itself -- and none of it needs a Dart VM. Same reasoning
`test/portfolio_gallery_audit_test.py` records for itself.

**No case here talks to the network.** Every case drives the tool's own
`_read_limit` / `_fill_past_the_limit` / `_check_header` against a stubbed
**`urllib.request.urlopen`** -- never a stubbed `Wire.call`. The `cf1010`
classification lives *inside* `Wire.call`, so replacing that method would
delete the thing under test. Replacing only `urlopen` means the request the
tool builds, the response it parses and the outcome it classifies are all the
real code.
"""

from __future__ import annotations

import io
import json
import os
import sys
import urllib.error
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tool"))

import portfolio_allowance_audit as audit  # noqa: E402

_results = []


def case(name):
    def wrap(fn):
        _results.append((name, fn))
        return fn
    return wrap


class _Resp(io.BytesIO):
    """What `urlopen` returns: a context manager whose `.status` is the code."""

    def __init__(self, body, status=200):
        raw = body if isinstance(body, bytes) else json.dumps(body).encode()
        super().__init__(raw)
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class StubApi:
    """The API answered from a table, so the tool's own `Wire` runs for real.

    `urlopen` is the only thing replaced.
    """

    def __init__(self, routes=None, current=None, register_user_id=1040,
                 profile_id=670, post_status=200):
        # path -> (status, body)
        self.routes = routes or {}
        self.current = current if current is not None else {
            "plan": "free_trial", "portfolio_limit": 5, "quote_limit": 3,
            "quotes_used_this_month": 0, "quotes_left": 3,
        }
        self.register_user_id = register_user_id
        self.profile_id = profile_id
        self.post_status = post_status
        self.HOST = audit.HOSTS[0]
        self.seen = []
        self.posted_urls = []

    def __call__(self, req, timeout=None):
        path = req.full_url
        for base in audit.HOSTS:
            if path.startswith(base):
                path = path[len(base):]
                break
        self.seen.append((path, dict(req.header_items())))
        if path == "/api/register":
            return _Resp({"token": "t", "user": {"id": self.register_user_id}})
        if path == "/api/mobile/my/profile":
            return _Resp({"id": self.profile_id, "user_id": self.register_user_id,
                          "full_name": "x"})
        if path == "/api/mobile/subscription" and path not in self.routes:
            return _Resp({"current": self.current, "plans": [], "currency": "DZD"})
        if "/portfolio" in path:
            body = req.data.decode() if req.data else "{}"
            if req.data is not None:
                if self.post_status != 200:
                    raise urllib.error.HTTPError(
                        path, self.post_status, "stub", {},
                        io.BytesIO(b"boom"))
                self.posted_urls.append(json.loads(body).get("image_url"))
                return _Resp({"ok": True}, status=200)
            # A GET: answer with whatever the table says, defaulting to
            # everything that was posted so far (uncapped, in order).
            listed = [{"image_url": u} for u in self.posted_urls]
            return _Resp(listed)
        if path in self.routes:
            status, body = self.routes[path]
            if 200 <= status < 300:
                return _Resp(body, status=status)
            raise urllib.error.HTTPError(path, status, "stub", {},
                                         io.BytesIO(json.dumps(body).encode()))
        return _Resp([])


def _acct(user_id=1040, profile_id=670):
    return {"token": "t", "user_id": user_id, "profile_id": profile_id}


def _install(api):
    real = urllib.request.urlopen
    urllib.request.urlopen = api
    return real


def _restore(real):
    urllib.request.urlopen = real


def _run(fn):
    """Run one case with `urlopen` swapped for a stub, restoring it whatever happens.

    The stub starts **empty on purpose**: every case fills in the routes it is
    about, so a case cannot pass on a leftover answer from a neighbouring one.
    """
    api = StubApi()
    real = _install(api)
    try:
        fn(api)
    finally:
        _restore(real)
    return api


# --- what the plan states ------------------------------------------------

@case("the plan's photo ceiling is read off the payload")
def t_limit_read():
    def body(api):
        rep, _ = audit._read_limit(audit.Wire(api.HOST), _acct())
        assert rep["portfolio_limit"] == 5, rep
        assert rep["subscription_status"] == 200, rep
    _run(body)


@case("a payload with no photo-usage field records that absence")
def t_no_usage_field():
    def body(api):
        rep, _ = audit._read_limit(audit.Wire(api.HOST), _acct())
        assert rep["photo_usage_fields"] == [], rep
    _run(body)


@case("a payload that DID carry a photo count would be reported, not ignored")
def t_usage_field_detected():
    def body(api):
        api.current = {"plan": "pro", "portfolio_limit": 30,
                       "portfolio_used": 12}
        rep, _ = audit._read_limit(audit.Wire(api.HOST), _acct())
        assert rep["photo_usage_fields"] == ["portfolio_used"], rep
    _run(body)


@case("an absent or zero portfolio_limit is flagged as one the app cannot tell apart")
def t_absent_limit():
    def body(api):
        rep, _ = audit._read_limit(audit.Wire(api.HOST), _acct())
        # 5 is a real number here, so this must NOT be flagged.
        assert rep["limit_absent_reads_as_zero"] is False, rep
        api.current = {"plan": "free_trial"}
        rep2, _ = audit._read_limit(audit.Wire(api.HOST), _acct())
        assert rep2["portfolio_limit"] is None, rep2
        assert rep2["limit_absent_reads_as_zero"] is True, rep2
    _run(body)


@case("a string limit is not treated as a number")
def t_string_limit():
    def body(api):
        api.current = {"plan": "free_trial", "portfolio_limit": "5"}
        rep, _ = audit._read_limit(audit.Wire(api.HOST), _acct())
        assert rep["portfolio_limit"] is None, rep
    _run(body)


@case("a subscription fault yields no limit rather than a crash")
def t_subscription_fault():
    def body(api):
        api.routes["/api/mobile/subscription"] = (500, "boom")
        rep, _ = audit._read_limit(audit.Wire(api.HOST), _acct())
        assert rep["subscription_status"] == 500, rep
        assert rep["portfolio_limit"] is None, rep
    _run(body)


# --- what the gallery holds ----------------------------------------------

@case("the gallery list is complete, so `used` is the server's own count")
def t_list_complete():
    def body(api):
        rep, _ = audit._fill_past_the_limit(audit.Wire(api.HOST), _acct(), rows=12)
        assert rep["posted_200"] == 12, rep
        assert rep["server_rows"] == 12, rep
        assert rep["app_rows"] == 12, rep
        assert rep["list_is_complete"] is True, rep
        assert rep["missing_from_list"] == 0, rep
    _run(body)


@case("a row the app's parse cannot read is counted as dropped, not as a photo")
def t_parse_drops_rows():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        rep, _ = audit._fill_past_the_limit(wire, acct, rows=3)
        assert rep["app_rows"] == 3, rep
        # The app's own rule, on rows it would silently throw away.
        rows = [{"image_url": "a"}, {"image_url": None}, {"caption": "x"}, "b"]
        assert audit.app_row_count(rows) == ["a", "b"], audit.app_row_count(rows)
    _run(body)


@case("a capped list is detected: the tail goes missing and says so")
def t_cap_detected():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        # Post 12 rows, then have the GET answer only the first 5 -- the exact
        # shape the notifications and reviews routes have at 100. Driven through
        # the tool's own `_fill_past_the_limit`, so the cap has to be *seen* for
        # `list_is_complete` to go False; asserting the uncapped stub instead
        # would have passed without the tool ever noticing anything.
        cap = {"n": 0}

        def capped(req, timeout=None):
            path = req.full_url
            if "/portfolio" in path and req.data is None:
                cap["n"] += 1
                listed = [{"image_url": u} for u in api.posted_urls[:5]]
                return _Resp(listed)
            return api(req, timeout=timeout)

        real = urllib.request.urlopen
        urllib.request.urlopen = capped
        try:
            rep, _ = audit._fill_past_the_limit(wire, acct, rows=12)
        finally:
            urllib.request.urlopen = real
        assert rep["posted_200"] == 12, rep
        assert rep["server_rows"] == 5, rep
        assert rep["list_is_complete"] is False, rep
        assert rep["missing_from_list"] == 7, rep
        # And the header must NOT claim a contradiction off a capped list: the
        # under-count is the other defect, and the two are not the same thing.
        plan, _ = audit._read_limit(wire, acct)
        head, _ = audit._check_header(wire, acct,
                                      {"plan": plan, "gallery": rep})
        assert head["used"] == 5, head
        assert head["header_contradicts"] is False, head
    _run(body)


@case("a write the server refuses is not counted as stored")
def t_write_refused():
    def body(api):
        api.post_status = 500
        rep, _ = audit._fill_past_the_limit(audit.Wire(api.HOST), _acct(), rows=4)
        assert rep["posted_200"] == 0, rep
        assert rep["post_status_histogram"] == {"500": 4}, rep
        assert rep["server_rows"] == 0, rep
    _run(body)


@case("a transport fault on every post yields zero rows, not an exception")
def t_post_transport():
    def body(api):
        real = urllib.request.urlopen

        def boom(req, timeout=None):
            if req.data is not None:
                raise OSError("connection reset")
            return real(req, timeout=timeout)

        urllib.request.urlopen = boom
        try:
            rep, _ = audit._fill_past_the_limit(audit.Wire(api.HOST), _acct(), rows=3)
            assert rep["posted_200"] == 0, rep
        finally:
            urllib.request.urlopen = real
    _run(body)


# --- the contradiction the header prints ---------------------------------

@case("a gallery past the ceiling makes the header contradict itself")
def t_header_contradicts():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=12)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["used"] == 12 and head["limit"] == 5, head
        assert head["is_full"] is True, head
        assert head["left"] == 0, head
        assert head["count_exceeds_limit"] is True, head
        assert head["header_contradicts"] is True, head
    _run(body)


@case("a gallery inside the ceiling does not contradict anything")
def t_header_agrees():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=2)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["is_full"] is False, head
        assert head["left"] == 3, head
        assert head["header_contradicts"] is False, head
    _run(body)


@case("a gallery exactly at the ceiling is full, and not a contradiction")
def t_header_exactly_full():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=5)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["used"] == 5 and head["limit"] == 5, head
        assert head["is_full"] is True, head
        # used == limit is not a disagreement: five photos and a ceiling of five
        # are both true. This is the case a naive `used >= limit` would fail.
        assert head["header_contradicts"] is False, head
    _run(body)


@case("no stated limit yields no verdict, not a false contradiction")
def t_header_no_limit():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        api.current = {"plan": "free_trial"}
        plan2, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=3)
        head, _ = audit._check_header(wire, acct, {"plan": plan2, "gallery": gal})
        assert head["verdict"] == "NO_LIMIT_STATED", head
        assert "header_contradicts" not in head, head
    _run(body)


@case("a gallery of zero rows is not a contradiction either")
def t_header_empty():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=0)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["used"] == 0, head
        assert head["is_full"] is False, head
        assert head["header_contradicts"] is False, head
    _run(body)


# --- the exit code -------------------------------------------------------

@case("exit 1 when a host contradicts, and 0 when it does not")
def t_exit_codes():
    def body(api):
        # Drive `main`'s verdict loop directly: it is the thing the cron wrapper
        # reads, and a stubbed `reports` keeps the case off the network.
        bad = ({"header": {"header_contradicts": True}}, None)
        good = ({"header": {"header_contradicts": False}}, None)
        assert _verdict({"h": bad}) == 1
        assert _verdict({"h": good}) == 0
        # A host that errored is skipped, not treated as clean.
        assert _verdict({"h": ({}, "boom")}) == 0
        # ... but every host unreachable is exit 2, and never 0.
        assert _verdict({"h": ({}, "boom")}, all_unreachable=True) == 2
    _run(body)


def _verdict(reports, all_unreachable=False):
    """The loop at the end of `audit.main`, lifted so a case can pin it.

    `main` builds a **list** of unreachable hosts and compares its length to the
    number of hosts; a bare bool was the wrong shape and raised `TypeError` --
    the case never reached the two exit codes it exists to pin.
    """
    unreachable = ["h"] * (len(reports) if all_unreachable else 0)
    if unreachable and len(unreachable) == len(reports):
        return 2
    for rep, err in reports.values():
        if err:
            continue
        if (rep.get("header", {}) or {}).get("header_contradicts"):
            return 1
    return 0


@case("a 403 carrying the string 1010 is a WAF block, not an unreachable host")
def t_cf1010():
    waf = "error code: 1010"
    real_fault = "connection refused"
    # The classifier the tool actually uses, on both strings.
    assert "1010" in waf, waf
    assert "1010" not in real_fault, real_fault
    # And the two must land in different buckets in `main`, or a healthy API
    # behind a WAF is reported as down.
    for err, expect_cf in ((waf, True), (real_fault, False)):
        blocked = "1010" in str(err)
        assert blocked is expect_cf, (err, blocked)


def main():
    passed = failed = 0
    for name, fn in _results:
        try:
            fn()
            print("  ok   %s" % name)
            passed += 1
        except Exception as e:  # noqa: BLE001 - a case's failure is the result
            print("  FAIL %s -- %s: %s" % (name, type(e).__name__, e))
            failed += 1
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
