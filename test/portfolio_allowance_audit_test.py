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

@case("a gallery past the ceiling states BOTH numbers, so it contradicts nothing")
def t_header_contradicts():
    """This case used to assert `header_contradicts: True` -- it was correct
    about the arithmetic and wrong about the screen, because the ceiling
    sentence it modelled was the old one-argument one. The Dart fix shipped
    `portfolioFullLineAr(int limit, int used)`, so the sentence now carries the
    count and the card stops contradicting itself.

    The arithmetic is still asserted in full: 12 against 5, `is_full`, `left`
    at zero, and `count_exceeds_limit` True. Those are facts about the
    numbers and they did not change -- only the sentence did. A header that
    "resolved" the contradiction by pretending 12 <= 5 would be caught here,
    because `count_exceeds_limit` is still pinned True.
    """
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
        assert head["header_contradicts"] is (not head["subline_takes_count"]), head
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


# --- the ceiling sentence is blind to the count --------------------------

@case("the ceiling sentence at 12-over-5 follows the shipped Dart")
def t_over_ceiling_line():
    """Driven by the Dart signature, not by a model of it.

    While the ceiling sentence was blind to the count this case asserted
    `True`; the 9 Oct tick shipped `portfolioFullLineAr(int limit, int used)`
    so the count is now mandatory and the sentence names both numbers. The
    case now asserts whatever the Dart actually does -- so it pins the FIX
    rather than the bug, and it will follow the next signature change instead
    of silently going red the way a hard-coded expectation would.
    """
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=12)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["over_ceiling_by"] == 7, head
        assert head["count_exceeds_limit"] is True, head
        # The sentence must name the count iff the Dart is told it, and the
        # count has to be in the string when it is -- otherwise the header
        # still prints a ceiling over pictures that pass it.
        assert head["over_ceiling_line"] is (not head["subline_takes_count"]), head
        assert head["header_contradicts"] is head["over_ceiling_line"], head
        if head["subline_takes_count"]:
            assert "12" in head["subline"], head
    _run(body)


@case("12-over-5 and 130-over-5 no longer print the same sentence")
def t_over_ceiling_line_far_over():
    """The defect this tool was built for, stated as a FAILURE it now passes.

    The old case asserted both states produced the identical string
    "full at limit: 5" -- a ceiling stated over a gallery that runs 125
    photographs past it. The count is now part of the sentence, so the two
    states must differ; if they ever print the same text again, the header is
    blind to the count whichever way the boolean reads.
    """
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=130)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["used"] == 130 and head["limit"] == 5, head
        assert head["over_ceiling_by"] == 125, head
        if head["subline_takes_count"]:
            assert "130" in head["subline"], head
            assert head["subline"] != "full at limit: 5", head
        else:
            assert head["over_ceiling_line"] is True, head
    _run(body)


@case("exactly at the ceiling is NOT over the ceiling")
def t_over_ceiling_line_exact():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=5)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["is_full"] is True, head
        assert head["over_ceiling_line"] is False, head
        assert head["over_ceiling_by"] == 0, head
    _run(body)


@case("under the ceiling is not over it either")
def t_over_ceiling_line_under():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=2)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["over_ceiling_line"] is False, head
        assert head["over_ceiling_by"] == 0, head
    _run(body)


@case("no stated limit yields no over-ceiling claim at all")
def t_over_ceiling_line_no_limit():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        api.current = {"plan": "free_trial"}
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=9)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        # Nine photos and no ceiling stated is not a contradiction -- there is
        # no ceiling to be over. Claiming one here would be the false
        # positive the `verdict` branch exists to prevent.
        assert head["verdict"] == "NO_LIMIT_STATED", head
        assert "over_ceiling_line" not in head, head
    _run(body)


@case("the check is NOT what turns the exit code red")
def t_over_ceiling_line_not_in_exit():
    """A ceiling-blind sentence is a COPY defect, fixed in Dart.

    If `over_ceiling_line` drove the exit code, this tool would be red on
    every healthy host from the day it was written until the Dart fix landed,
    and a permanently red tool stops being read. So it is reported and pinned,
    and exit 1 stays reserved for the server-side contradiction. This case
    exists because the opposite wiring is the obvious thing to type.
    """
    def body(api):
        blind = {"header": {"header_contradicts": False,
                            "over_ceiling_line": True}}
        contradicts = {"header": {"header_contradicts": True,
                                  "over_ceiling_line": True}}
        # `_verdict` walks `reports.values()` as `(report, error)` pairs, which
        # is what `main` builds; a bare report dict raises here rather than
        # silently passing a one-sided verdict.
        assert _verdict({"h": (blind, None)}) == 0
        assert _verdict({"h": (contradicts, None)}) == 1
    _run(body)


@case("the fix is falsifiable: rewording the SUBLINE alone does not clear it")
def t_fix_must_touch_the_ceiling_line():
    """The pending Dart fix has a shape, and this case refuses a cheaper one.

    `portfolioFullLineAr` is the function that cannot see the count. So a fix
    that only re-words the sentence printed *around* it -- `_Header._subLine`
    or `_FullNotice` -- would make the screen read better and leave the defect
    exactly where it was. This case models that cheap fix (subline text moves,
    ceiling function untouched) and asserts the check still reports the defect.
    A test that could be satisfied by re-wording would be pinning the wrong
    thing, and the Dart tick would land a half-fix that reads green here.
    """
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=12)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        # Start from a header judged by the SHIPPED Dart, so this case still
        # refuses the half-fix after the real fix landed rather than being
        # retired alongside it. The ceiling function is modelled as blind
        # again -- which is the state the cheap fix leaves behind.
        blind = {"over_ceiling_line": True, "subline_takes_count": False}

        # The cheap fix: a different subline sentence, same ceiling function.
        cheap = dict(blind)
        cheap["subline"] = "you are past your plan limit"
        assert audit.check_ceiling_line(cheap) is True, \
            "re-wording the subline must not clear a ceiling-blind line"

        # The real fix: `portfolioFullLineAr` is handed the count as well, so
        # the sentence it builds differs between 5-against-5 and 130-against-5.
        real = dict(head)
        real["subline_takes_count"] = True
        real["over_ceiling_line"] = False
        assert audit.check_ceiling_line(real) is False, head
    _run(body)


@case("the ceiling check reads a header of any shape without raising")
def t_check_shape_tolerance():
    """`check_ceiling_line` is handed whatever `_check_header` produced.

    A caller that passes None, a list or a bare report must get a verdict, not
    a traceback: the tool prints this check for every host it talked to,
    including one that answered with nothing at all.
    """
    def body(api):
        for shape in (None, [], "5", 7, {}, {"over_ceiling_line": True}):
            assert isinstance(audit.check_ceiling_line(shape), bool), shape
        assert audit.check_ceiling_line({"over_ceiling_line": True}) is True
        assert audit.check_ceiling_line({}) is False
    _run(body)


@case("a ceiling line that took the count is not reported as blind")
def t_check_respects_takes_count():
    """The ONLY thing that can clear this check is the count reaching the line.

    `subline_takes_count` is how the Dart fix will report itself: once
    `portfolioFullLineAr` is handed the count, the sentence can distinguish a
    full gallery from an overfull one, so this check must go False. Until then
    it stays True, and a caller that ignored the flag would report the fixed
    build as still broken -- which is worse than reporting nothing, because the
    fix would never look landed.
    """
    def body(api):
        blind = {"over_ceiling_line": True}
        fixed = {"over_ceiling_line": True, "subline_takes_count": True}
        assert audit.check_ceiling_line(blind) is True
        assert audit.check_ceiling_line(fixed) is False
        # And the flag is honoured even when the raw flag says otherwise, so
        # it cannot be set by accident on a build that did not fix it.
        assert audit.check_ceiling_line({"subline_takes_count": True}) is False
    _run(body)


@case("the gap is reported even when no ceiling is stated")
def t_no_limit_branch_by_zero():
    """`over_ceiling_by` must be absent, or 0 -- never a number.

    A `_check_header` that answered `NO_LIMIT_STATED` has no ceiling to be over,
    so there is no gap to measure. Emitting a number there would be the app's
    own defect re-created in the audit: a figure standing where nothing was
    measured.
    """
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        api.current = {"plan": "free_trial"}
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=9)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert "over_ceiling_by" not in head or head["over_ceiling_by"] == 0, head
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


# --- the report must not contradict its own verdict ---------------------

@case("the rendered line never explains a False with a 'blind' reason")
def t_render_follows_the_verdict():
    """A report that says "False -- still takes only a limit" is a report
    contradicting itself one line under its own verdict, which is the exact
    failure this tool exists to catch -- caught in the tool.

    Both states are rendered: the reason has to change WITH the boolean, not
    merely be worded so it happens to read true today.
    """
    base = {"used": 130, "limit": 5, "left": 0, "is_full": True,
            "count_line": "130 photos in your gallery",
            "subline": "over your plan's limit: 130 against 5",
            "count_exceeds_limit": True, "over_ceiling_by": 125}

    seen = {}
    for takes, blind in ((True, False), (False, True), (None, False)):
        head = dict(base, subline_takes_count=takes, over_ceiling_line=blind,
                    header_contradicts=blind)
        rep = {"plan": {"portfolio_limit": 5},
               "gallery": {"app_rows": 130, "rows_dropped_by_app_parse": 0},
               "header": head}
        row = [ln for ln in audit._render({"h": (rep, None)})
               if "blind to the count" in ln]
        assert len(row) == 1, row
        text = row[0]
        seen[takes] = text
        if takes is None:
            # An unreadable signature is a THIRD state: the tool has no
            # verdict to give, and must not dress one up in either wording.
            assert "NOT READ" in text, text
            assert "blind to the count: False" in text or blind, text
        elif blind:
            assert "still takes only a limit" in text, text
        else:
            # The reason must be the NOT-blind one, not merely something else:
            # MUTATED TWICE here. Asserting only the absence of the blind
            # wording let a reason that is constant, or one that ignores the
            # verdict entirely, pass while still misleading the reader.
            assert "handed the count" in text, (
                "a False verdict not explained as fixed: %s" % text)
            assert "still takes only a limit" not in text, (
                "a False verdict explained as blind: %s" % text)
    # The two must not render identically -- a constant reason would pass a
    # single-state check and still be lying in the other.
    assert seen[True] != seen[False], seen
    # And an unreadable signature says NO VERDICT, which is a third distinct
    # thing from both of the above: neither "blind" nor "fixed".
    assert "NOT READ" in seen[None], seen
    assert "handed the count" not in seen[None], seen
    assert "still takes only a limit" not in seen[None], seen


# --- does the mirror still model the Dart that is actually shipped? ---

@case("the ceiling sentence is judged against the Dart signature on disk")
def t_ceiling_reads_the_dart_signature():
    """The mirror must READ `portfolioFullLineAr`, not assume it.

    A tick shipped `portfolioFullLineAr(int limit, int used)` -- the count is
    a REQUIRED argument, so a caller cannot build the sentence without the
    state. The mirror kept its own one-argument model, so it answered
    `subline_takes_count: <missing>` forever: the tool called the FIXED Dart
    blind, and reported `header_contradicts: True` against a header that
    prints both numbers.

    A mirror with a hard-coded model of the code under test goes stale the
    moment the code moves -- and it fails SILENTLY, as a wrong verdict, not as
    a crash. So the model is read out of the file, and if the signature cannot
    be read the tool says so rather than guessing.
    """
    dart = os.path.join(REPO, "lib", "src", "data", "portfolio_allowance.dart")
    takes = audit.dart_ceiling_line_takes_count(dart)
    assert takes is True, (
        "the shipped signature reads as NOT taking the count: %r" % (takes,))


@case("an unreadable Dart signature is reported, never guessed")
def t_ceiling_signature_absent_is_none():
    missing = os.path.join(REPO, "lib", "src", "data", "no_such_file.dart")
    assert audit.dart_ceiling_line_takes_count(missing) is None, "guessed"
    assert audit.dart_ceiling_line_takes_count(None) is None, "guessed"


@case("a file with no recognisable signature yields no answer, not a guess")
def t_ceiling_signature_unmatched_is_none():
    """The third way the read can fail, and the one that SURVIVED mutation.

    `except OSError` covers a file that is not there, and `if not m` covers a
    signature that is not there -- but when the regex matched nothing and the
    handler returned the ASSUMED answer, a Dart file without this function
    would read as "takes the count" and the tool would report the fixed
    screen correct. Nobody would notice: the file exists, nothing raises, and
    the verdict is confident.
    """
    import tempfile, os as _os
    fd, path = tempfile.mkstemp(suffix=".dart")
    try:
        _os.write(fd, b"class Unrelated {}\n")
        _os.close(fd)
        assert audit.dart_ceiling_line_takes_count(path) is None, \
            "a file with no such function must yield no answer"
    finally:
        _os.unlink(path)


@case("a one-argument signature is read as blind, honestly")
def t_ceiling_signature_one_arg_is_false():
    """`check_ceiling_line` already handles `subline_takes_count`; this pins
    the OTHER half -- that the reader can still say False, so the reader is
    measuring and not hard-coding True."""
    with io.StringIO("String portfolioFullLineAr(int limit) => '';\n") as fh:
        import tempfile, os as _os
        fd, path = tempfile.mkstemp(suffix=".dart")
        try:
            _os.write(fd, fh.getvalue().encode())
            _os.close(fd)
            assert audit.dart_ceiling_line_takes_count(path) is False
        finally:
            _os.unlink(path)


@case("the header stops claiming a contradiction the shipped Dart does not print")
def t_header_reflects_shipped_dart():
    """The live run: both hosts reported `header_contradicts: True` on a
    header that is now correct. `_check_header` mirrors the ceiling sentence;
    when the Dart takes the count the sentence names BOTH numbers and stops
    contradicting the count line above it."""
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=130)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["over_ceiling_by"] == 125, head
        assert head["header_contradicts"] is False, (
            "the shipped Dart prints both numbers, so this header does not "
            "contradict itself: %r" % (head,))
        assert audit.check_ceiling_line(head) is False, head
    _run(body)


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
