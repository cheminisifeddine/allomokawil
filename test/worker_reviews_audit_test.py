#!/usr/bin/env python3
"""Pin the logic the contractor-reviews audit reasons with -- python, not Dart.

    python3 test/worker_reviews_audit_test.py

**Why this is Python and not a Dart test.** `tool/build_gate.py` refuses Dart
on this box whenever the hypervisor balloon is up (423 MB available against a
900 MB floor on the tick that wrote this file). Every claim below is about
*this tool's* judgement -- when two ids disagree, when a list contradicts the
header, when the verdict is allowed -- and none of it needs a Dart VM. The same
reasoning `test/notification_read_audit_test.py` records for itself: a suite
that stays checkable exactly when the gate refuses is the only kind worth
having.

**No case here talks to the network.** Every case drives the tool's own
`_check_ids` and `_check_gap` against a stubbed **`urllib.request.urlopen`** --
not a stubbed `Wire.call`.

**That is a deliberate correction of a bug the sibling suite shipped with.**
`notification_read_audit_test.py`'s first version stubbed `Wire.call` itself.
The `cf1010` split lives *inside* `Wire.call`, so a stub that replaces the whole
method deletes the thing under test: the suite went green whether or not the
tool could tell a Cloudflare WAF block from a real 403. Proven by mutation --
deleting the discrimination left every case passing. A test that cannot fail
when the thing it names is removed reads as coverage, and none of it is. Here
`urlopen` is the only thing replaced, so the request the tool builds, the
response it parses and the outcome it classifies are all the real code, and the
agent-pin case below is the one that proves it.
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

import worker_reviews_audit as audit  # noqa: E402

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
    """The API, answered from a table, so the tool's own `Wire` runs for real.

    `urlopen` is the only thing replaced. `Wire.call` -- which builds the
    request, adds the agent, reads the status and classifies a 1010 -- is the
    code under test and is never stubbed.
    """

    def __init__(self, routes, profile_body=None, search_body=None):
        # path -> (status, body) or (status, body, raise_http_error)
        self.routes = routes
        self.profile_body = profile_body
        self.search_body = search_body
        self.seen = []

    def __call__(self, req, timeout=None):
        path = req.full_url
        for base in audit.HOSTS:
            if path.startswith(base):
                path = path[len(base):]
                break
        self.seen.append((path, dict(req.header_items())))
        # `_throwaway_worker` first registers, then reads its own profile.
        if path == "/api/register":
            return _Resp({"token": "t", "user": {"id": 1030}})
        if path == "/api/mobile/my/profile":
            return _Resp(self.profile_body)
        if path.startswith("/api/mobile/workers/search"):
            return _Resp(self.search_body)
        if path in self.routes:
            status, body = self.routes[path][0], self.routes[path][1]
            # **Only a non-2xx raises.** The first version raised for every
            # table entry, which made a stubbed 200 arrive as an `HTTPError`
            # that `Wire.call` correctly classified as a failure -- so the suite
            # measured the stub, not the tool, and `ids_disagree` could never be
            # true because `ok` was False on both sides. The failure looked like
            # a bug in the audit and was a bug in the harness.
            if 200 <= status < 300:
                return _Resp(body, status=status)
            raise urllib.error.HTTPError(path, status, "stub", {},
                                         io.BytesIO(json.dumps(body).encode()))
        return _Resp([])


def _wire(base="https://allomokawil.com"):
    return audit.Wire(base)


def _acct(user_id=1030, profile_id=652):
    return {"token": "t", "user_id": user_id, "profile_id": profile_id}


def _install(monkey, api):
    """Swap `urlopen` only, and hand back an undo."""
    real = urllib.request.urlopen
    urllib.request.urlopen = api
    return real


def _restore(real):
    urllib.request.urlopen = real


@case("two ids that answer differently are the finding")
def _ids_disagree_is_caught():
    # The measured production shape: the reviews route answers 200 for an id
    # whose *profile* is a 404. A wrong id therefore reads empty rather than
    # wrong, which is the whole reason this needs watching.
    api = StubApi({
        "/api/mobile/workers/652": (200, {"id": 652, "user_id": 1030}),
        "/api/mobile/workers/1030": (404, {"error": "المقاول غير موجود"}),
        "/api/mobile/workers/652/reviews": (200, []),
        "/api/mobile/workers/1030/reviews": (200, []),
    }, profile_body={"id": 652, "user_id": 1030})
    real = _install(None, api)
    try:
        rep = audit._check_ids(_wire(), _acct())
    finally:
        _restore(real)
    assert rep["ids_disagree"] is True, \
        "reviews 200 on an id whose profile is 404 is the reachable defect; " \
        "the audit must name it. Got %r" % rep
    assert rep["public_by_user_status"] == 404, \
        "the witness is the profile route. Got %r" % rep
    assert rep["reviews_by_user_status"] == 200, \
        "both ids answer the reviews route 200 -- that is what makes the " \
        "wrong id silent. Got %r" % rep


@case("one id answering the same way for both is not reported")
def _matching_ids_is_clean():
    api = StubApi({
        "/api/mobile/workers/652": (200, {"id": 652, "user_id": 1030}),
        "/api/mobile/workers/1030": (200, {"id": 1030, "user_id": 1030}),
        "/api/mobile/workers/652/reviews": (200, []),
        "/api/mobile/workers/1030/reviews": (200, []),
    }, profile_body={"id": 652, "user_id": 1030})
    real = _install(None, api)
    try:
        rep = audit._check_ids(_wire(), _acct())
    finally:
        _restore(real)
    assert rep["ids_disagree"] is False, \
        "a server where both ids resolve is not a disagreement; filing one " \
        "here would train a future tick to ignore the verdict. Got %r" % rep


@case("the audit asks the routes with the agent the app actually sends")
def _agent_is_pinned():
    # Cloudflare answers urllib's DEFAULT agent with 403/1010 -- a WAF
    # signature match. This case is why the stub replaces `urlopen` and not
    # `Wire.call`: stubbing `Wire.call` would delete the line under test.
    api = StubApi({
        "/api/mobile/workers/652": (200, {"id": 652}),
        "/api/mobile/workers/1030": (200, {"id": 1030}),
        "/api/mobile/workers/652/reviews": (200, []),
        "/api/mobile/workers/1030/reviews": (200, []),
    }, profile_body={"id": 652, "user_id": 1030})
    real = _install(None, api)
    try:
        audit._check_ids(_wire(), _acct())
    finally:
        _restore(real)
    agents = {v for _, hdrs in api.seen for k, v in hdrs.items()
              if k.lower() == "user-agent"}
    assert agents == {audit.USER_AGENT}, \
        "every request must carry the app's agent string, not urllib's " \
        "default, which the WAF answers with 1010. Saw %r" % agents
    assert "AlloMokawilApp" in audit.USER_AGENT, \
        "the pinned agent must be the app's own, or the pin is theatre."


@case("a Cloudflare 1010 is its own outcome, not a real 403")
def _cf1010_is_not_a_403():
    # The split lives inside `Wire.call`, so it is exercised here for real: the
    # stub returns an HTTPError whose body carries the 1010 marker and the tool
    # must classify it, not report an API fault.
    api = StubApi({}, profile_body=None)
    real = _install(None, api)

    def _blocked(req, timeout=None):
        raise urllib.error.HTTPError(
            req.full_url, 403, "Forbidden", {},
            io.BytesIO(b"<html>error code: 1010</html>"))

    urllib.request.urlopen = _blocked
    try:
        resp = _wire().call("/api/mobile/workers/652/reviews")
    finally:
        _restore(real)
    assert resp["cf1010"] is True, \
        "a 1010 is a WAF signature match, not an application failure. Got %r" % resp
    assert resp["status"] == 403, "the status is still 403; it is the body " \
        "that discriminates. Got %r" % resp


@case("a list longer than the header claims is the arm nobody watches")
def _surplus_is_caught():
    # The shortfall arms ship (`reviews_section_copy.dart`); a *surplus* -- more
    # cards than the header promises -- has no guard, and would draw a count the
    # page cannot back.
    api = StubApi({}, search_body=[
        {"id": 5, "total_reviews": 2},
        {"id": 1, "total_reviews": 24},
    ])
    api.routes = {
        "/api/mobile/workers/5/reviews": (200, [{"id": 1}, {"id": 2}, {"id": 3}]),
        "/api/mobile/workers/1/reviews": (200, []),
    }
    real = _install(None, api)
    try:
        rep, err = audit._check_gap(_wire(), 8)
    finally:
        _restore(real)
    assert err is None, err
    assert rep["rows_longer_than_claim"] == 1, \
        "worker 5 claims 2 and returns 3 cards; that surplus must be counted. " \
        "Got %r" % rep
    assert rep["surplus_uncaught"] is True, \
        "the surplus is the direction with no guard; the audit must report it."
    assert rep["rows_with_no_cards"] == 1, \
        "worker 1 returns none, which the shipped empty arm already covers -- " \
        "it must still be counted, not folded into the surplus. Got %r" % rep


@case("a list at or under its header is not a gap in either direction")
def _agreeing_list_is_clean():
    api = StubApi({}, search_body=[
        {"id": 5, "total_reviews": 3},
        {"id": 1, "total_reviews": 24},
    ])
    api.routes = {
        "/api/mobile/workers/5/reviews": (200, [{"id": 1}, {"id": 2}, {"id": 3}]),
        "/api/mobile/workers/1/reviews": (200, [{"id": 9}]),
    }
    real = _install(None, api)
    try:
        rep, err = audit._check_gap(_wire(), 8)
    finally:
        _restore(real)
    assert err is None, err
    assert rep["rows_longer_than_claim"] == 0, \
        "equal and shorter are both ordinary; a surplus here would be a false " \
        "positive that buries the real finding. Got %r" % rep
    assert rep["surplus_uncaught"] is False


@case("only rows claiming reviews are asked at all")
def _non_claiming_rows_are_not_checked():
    # A directory row with total_reviews 0 cannot disagree with anything, so
    # asking it would spend a request per row for a verdict of zero.
    api = StubApi({}, search_body=[
        {"id": 6, "total_reviews": 0},
        {"id": 7},
        {"id": 5, "total_reviews": 1},
    ])
    api.routes = {"/api/mobile/workers/5/reviews": (200, [{"id": 1}])}
    real = _install(None, api)
    try:
        rep, err = audit._check_gap(_wire(), 8)
    finally:
        _restore(real)
    assert err is None, err
    assert rep["claiming_reviews"] == 1, \
        "only one of the three rows claims a review. Got %r" % rep
    assert rep["checked"] == 1, \
        "and only that one may be read. Got %r" % rep
    asked = [p for p, _ in api.seen if p.startswith("/api/mobile/workers/")
             and p.endswith("/reviews")]
    assert asked == ["/api/mobile/workers/5/reviews"], \
        "the rows with nothing to disagree about must not be asked: %r" % asked


def main():
    failed = 0
    for name, fn in _results:
        try:
            fn()
            print("  ok    %s" % name)
        except AssertionError as e:
            failed += 1
            print("  FAIL  %s\n          %s" % (name, e))
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("  ERROR %s\n          %r" % (name, e))
    print("\n%d/%d passed" % (len(_results) - failed, len(_results)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
