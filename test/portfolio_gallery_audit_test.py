#!/usr/bin/env python3
"""Pin the logic the contractor-gallery audit reasons with -- python, not Dart.

    python3 test/portfolio_gallery_audit_test.py

**Why this is Python and not a Dart test.** `tool/build_gate.py` refuses Dart
on this box whenever the hypervisor balloon is up (411 MB available against a
900 MB floor on the tick that wrote this file). Every claim below is about
*this tool's* judgement -- is the photo aggregate really absent, do the two ids
disagree, does a wrong-id write claim success -- and none of it needs a Dart VM.
Same reasoning `test/worker_reviews_audit_test.py` records for itself.

**No case here talks to the network.** Every case drives the tool's own
`_check_aggregate` / `_check_ids` / `_check_write` against a stubbed
**`urllib.request.urlopen`** -- never a stubbed `Wire.call`. The
`cf1010` classification lives *inside* `Wire.call`, so replacing that method
would delete the thing under test; `test/notification_read_audit_test.py`
shipped that bug and proved it by mutation. Replacing only `urlopen` means the
request the tool builds, the response it parses and the outcome it classifies
are all the real code.
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

import portfolio_gallery_audit as audit  # noqa: E402

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

    def __init__(self, routes=None, profile_body=None, register_user_id=1030):
        # path -> (status, body)
        self.routes = routes or {}
        self.profile_body = profile_body if profile_body is not None else {
            "id": 652, "user_id": 1030, "full_name": "x",
        }
        self.register_user_id = register_user_id
        self.seen = []

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
            return _Resp(self.profile_body)
        if path in self.routes:
            status, body = self.routes[path]
            # **Only a non-2xx raises.** Raising for a stubbed 200 made it arrive
            # as an `HTTPError` that `Wire.call` correctly classified as a
            # failure -- so the suite measured the stub rather than the tool, and
            # `ids_disagree` could never be true because `ok` was False on both
            # sides. That failure looked like an audit bug and was a harness bug.
            if 200 <= status < 300:
                return _Resp(body, status=status)
            raise urllib.error.HTTPError(path, status, "stub", {},
                                         io.BytesIO(json.dumps(body).encode()))
        return _Resp([])


def _raise_transport():
    """The transport fault `Wire.call` catches -- raised, so the real `except`
    branch runs. Without this the case could only stub an HTTPError."""
    raise OSError("connection reset")


def _acct(user_id=1030, profile_id=652):
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


# --- the aggregate that is not there --------------------------------------

@case("the profile route carries no photo total, so no contradiction is possible")
def t_no_aggregate():
    def body(api):
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_aggregate(wire, _acct())
        assert rep["carries_photo_total"] is False, rep
        assert rep["count_like_keys"] == [], rep
    _run(body)


@case("a profile that DID grow a photo count is detected -- the claim is falsifiable")
def t_aggregate_when_present():
    def body(api):
        # `_check_aggregate` reads **/workers/<id>**, not /my/profile -- the
        # first version set `profile_body` and watched the stub's default `[]`
        # answer the route instead, so the case asserted against nothing.
        api.routes = {
            "/api/mobile/workers/652": (200, {"id": 652, "user_id": 1030,
                                              "photo_count": 7}),
        }
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_aggregate(wire, _acct())
        assert rep["carries_photo_total"] is True, rep
        assert "photo_count" in rep["image_like_keys"] or \
            "photo_count" in rep["count_like_keys"], rep
    _run(body)


# --- the id shape ---------------------------------------------------------

@case("a 404 on the profile and a 200 on the gallery is reported as disagreement")
def t_ids_disagree():
    def body(api):
        api.routes = {
            "/api/mobile/workers/652": (200, {"id": 652, "user_id": 1030}),
            "/api/mobile/workers/1030": (404, {"error": "المقاول غير موجود"}),
            "/api/mobile/workers/652/portfolio": (200, [{"image_url": "a"}]),
            "/api/mobile/workers/1030/portfolio": (200, []),
        }
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_ids(wire, _acct())
        assert rep["ids_disagree"] is True, rep
        assert rep["gallery_profile_id_len"] == 1, rep
    _run(body)


@case("two ids that answer identically are NOT disagreement -- the check can pass")
def t_ids_agree():
    def body(api):
        api.routes = {
            "/api/mobile/workers/652": (200, {"id": 652}),
            "/api/mobile/workers/1030": (200, {"id": 1030}),
            "/api/mobile/workers/652/portfolio": (200, []),
            "/api/mobile/workers/1030/portfolio": (200, []),
        }
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_ids(wire, _acct())
        assert rep["ids_disagree"] is False, rep
    _run(body)


# --- the write ------------------------------------------------------------

@case("a wrong-id write that answers 200 is flagged as claiming success")
def t_wrong_id_success():
    def body(api):
        api.routes = {
            "/api/mobile/workers/652/portfolio": (200, {"ok": True}),
            "/api/mobile/workers/1030/portfolio": (200, {"ok": True}),
        }
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_write(wire, _acct())
        assert rep["wrong_id_reports_success"] is True, rep
        assert rep["wrong_id_write_landed_somewhere"] is False, rep
    _run(body)


@case("a wrong-id write landing on the real gallery is caught by count, not status")
def t_wrong_id_landed():
    def body(api):
        # The gallery grows between the two reads -- a silent mis-target.
        # **GETs only.** The first version counted the correct-id *POST* to the
        # same path as a read, so the row appeared before `before` was taken and
        # the case read as "no growth" against a stub that was growing. A
        # measurement harness that moves the thing it measures is worse than no
        # harness.
        class Growing(StubApi):
            gets = 0

            def __call__(self, req, timeout=None):
                path = req.full_url.split("com", 1)[-1]
                if (req.get_method() == "GET" and path.endswith("/portfolio")
                        and "/652/" in path):
                    Growing.gets += 1
                    n = 3 if Growing.gets > 1 else 1
                    return _Resp([{"image_url": "x%d" % i} for i in range(n)])
                return StubApi.__call__(self, req, timeout=timeout)

        api.__class__ = Growing
        Growing.gets = 0
        api.routes = {"/api/mobile/workers/1030/portfolio": (200, {"ok": True})}
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_write(wire, _acct())
        assert rep["gallery_len_before_wrong_write"] == 1, rep
        assert rep["gallery_len_after_wrong_write"] == 3, rep
        assert rep["wrong_id_write_landed_somewhere"] is True, rep
    _run(body)


# --- the harness itself ---------------------------------------------------

@case("the User-Agent is the pinned app string, not urllib's (Cloudflare 1010)")
def t_agent_pin():
    def body(api):
        wire = audit.Wire("https://allomokawil.com")
        wire.call("/api/mobile/workers/652/portfolio")
        path, headers = api.seen[-1]
        assert headers.get("User-agent") == audit.USER_AGENT, headers
        assert "Python-urllib" not in headers.get("User-agent", ""), headers
    _run(body)


@case("a 404 on the gallery alone is not disagreement -- both halves are needed")
def t_gallery_404_only():
    # Found by mutation: dropping the `rows_user["status"] == 200` half of
    # `ids_disagree` survived every case. The predicate has two conjuncts and
    # only the 404 half was ever falsified, so the second was untested.
    def body(api):
        api.routes = {
            "/api/mobile/workers/652": (200, {"id": 652}),
            "/api/mobile/workers/1030": (404, {"error": "x"}),
            "/api/mobile/workers/652/portfolio": (200, []),
            "/api/mobile/workers/1030/portfolio": (404, {"error": "x"}),
        }
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_ids(wire, _acct())
        assert rep["ids_disagree"] is False, rep
    _run(body)


@case("a transport fault on the profile route is recorded, not swallowed")
def t_profile_transport_fault():
    # Found by mutation: `rep["profile_status"] = 200` survived. The status is
    # what the report shows for each id, so a fault that silently reported 200
    # would print "profile 200" for a host that answered nothing.
    def body(api):
        class Dead(StubApi):
            def __call__(self, req, timeout=None):
                if "/workers/652" in req.full_url and req.get_method() == "GET":
                    return _raise_transport()
                return StubApi.__call__(self, req, timeout=timeout)

        api.__class__ = Dead
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_aggregate(wire, _acct())
        assert rep["profile_status"] == 0, rep
        assert rep["carries_photo_total"] is False, rep
    _run(body)


@case("a 204 with an empty body is still a success -- status==200 would miss it")
def t_empty_2xx_success():
    # Found by mutation: `wrong["ok"]` -> `wrong["status"] == 200` survived every
    # case, because every stubbed write answered 200. A 2xx that carries no body
    # is a success `ok` reports and `status == 200` does not, so it is the case
    # that separates the two.
    def body(api):
        api.routes = {
            "/api/mobile/workers/652/portfolio": (200, {"ok": True}),
            "/api/mobile/workers/1030/portfolio": (204, b""),
        }
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_write(wire, _acct())
        assert rep["wrong_id_reports_success"] is True, rep
    _run(body)


@case("a gallery body that is not a list counts as zero, it does not crash")
def t_non_list_gallery():
    # Found by mutation: loosening `_rows_of`'s shape check survived, because
    # every stub answered a list. A drifted body (an object where an array is
    # documented) must read as an empty gallery, not as a TypeError on `len`.
    def body(api):
        api.routes = {
            "/api/mobile/workers/652": (200, {"id": 652}),
            "/api/mobile/workers/1030": (404, {"error": "x"}),
            "/api/mobile/workers/652/portfolio": (200, {"error": "not a list"}),
            "/api/mobile/workers/1030/portfolio": (200, {"error": "not a list"}),
        }
        wire = audit.Wire("https://allomokawil.com")
        rep, _ = audit._check_ids(wire, _acct())
        assert rep["gallery_profile_id_len"] == 0, rep
        assert rep["gallery_user_id_len"] == 0, rep
    _run(body)


@case("a real 403 with no 1010 in it is NOT called Cloudflare")
def t_403_without_1010():
    # Found by mutation: widening the match from "1010" to "10" survived,
    # because only the positive case existed. This is the case that makes the
    # discrimination a discrimination.
    def body(api):
        api.routes = {"/api/mobile/workers/652/portfolio": (403, "Forbidden")}
        wire = audit.Wire("https://allomokawil.com")
        resp = wire.call("/api/mobile/workers/652/portfolio")
        assert resp["status"] == 403, resp
        assert resp["cf1010"] is False, resp
    _run(body)


@case("a 403 whose body merely CONTAINS 1010 elsewhere is not a WAF block")
def t_403_body_mentioning_1010():
    # Found by mutation: widening the match from "1010" to "10" survived. The
    # real Cloudflare body is short ("error code: 1010"); an application 403
    # whose text quotes a number starting 10 -- a rate-limit answer, an id in a
    # message -- must not be filed as a WAF block, because that outcome tells
    # the next tick the API is healthy when it is refusing.
    def body(api):
        api.routes = {
            "/api/mobile/workers/652/portfolio":
                (403, "rate limit: 10 requests per minute"),
        }
        wire = audit.Wire("https://allomokawil.com")
        resp = wire.call("/api/mobile/workers/652/portfolio")
        assert resp["status"] == 403, resp
        assert resp["cf1010"] is False, resp
    _run(body)


@case("a 403/1010 is classified as Cloudflare, not as an application failure")
def t_cf1010():
    class Blocked(StubApi):
        def __call__(self, req, timeout=None):
            raise urllib.error.HTTPError(req.full_url, 403, "Forbidden", {},
                                         io.BytesIO(b"error code: 1010"))

    api = Blocked()
    real = _install(api)
    try:
        wire = audit.Wire("https://allomokawil.com")
        resp = wire.call("/api/mobile/workers/652/portfolio")
        assert resp["status"] == 403, resp
        assert resp["cf1010"] is True, resp
    finally:
        _restore(real)


def main():
    passed = failed = 0
    for name, fn in _results:
        try:
            fn()
            print("  PASS  %s" % name)
            passed += 1
        except AssertionError as e:
            print("  FAIL  %s\n        %s" % (name, e))
            failed += 1
        except Exception as e:  # noqa: BLE001
            print("  ERROR %s\n        %r" % (name, e))
            failed += 1
    print("\n%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
