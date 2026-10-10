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


# --- the reader must judge ARITY, not the spelling of a parameter -----------
#
# Four cases, and all four are WRONG VERDICTS MEASURED on this tick rather
# than shapes imagined in advance. The reader used to decide which parameter
# was the count by its NAME (`used` or `count`), so a field's identity was
# guessed from the spelling a developer happened to choose -- the same defect
# the census tick shipped 1 Oct one layer over: a reader whose vocabulary is
# narrower than the tree it grades, so what it cannot recognise reads as
# ABSENT rather than UNMEASURED.
#
# The first case is the dangerous one. Renaming a parameter is an ordinary,
# behaviour-preserving edit, and it flipped this tool to `blind=True` and
# `header_contradicts=True` -- **exit 1 against two healthy hosts**, filing a
# server defect that does not exist. That is the failure a mirror has and no
# plain mirror can.


def _reader_says(src):
    """`dart_ceiling_line_takes_count` against a throwaway Dart file."""
    import tempfile
    fd, path = tempfile.mkstemp(suffix=".dart")
    try:
        os.write(fd, src.encode())
        os.close(fd)
        return audit.dart_ceiling_line_takes_count(path)
    finally:
        os.unlink(path)


@case("a RENAMED count parameter still reads as taking the count")
def t_reader_survives_a_rename():
    """The mutation that mattered: `used` -> `have`, with NO logic change.

    Arity is what the sentence needs -- one parameter means the only number
    this function was handed is the ceiling, whatever it is called. Judged by
    spelling, this file read as blind, the header read as contradicting
    itself, and the tool exited 1 on two hosts that are perfectly healthy.
    """
    assert _reader_says(
        "String portfolioFullLineAr(int limit, int have) => '';") is True, \
        "a behaviour-preserving rename must not blind the reader"


@case("a ONE-parameter function reads as blind whatever the parameter is called")
def t_reader_one_arg_is_false_whatever_its_name():
    """The opposite direction, and it was wrong the other way.

    `portfolioFullLineAr(int used)` -- one argument, named `count` -- reads as
    taking the count under the old spelling rule, because the rule asked what
    the parameter was CALLED and never how many there were. The function
    cannot see a gallery size: it was handed one number, and that number is
    the ceiling. Reporting it as count-aware cleared a real defect.
    """
    for one in ("String portfolioFullLineAr(int used) => '';",
                "String portfolioFullLineAr(int count) => '';",
                "String portfolioFullLineAr(int limit) => '';",
                "String portfolioFullLineAr(int n) => '';"):
        assert _reader_says(one) is False, \
            "a one-argument function takes no count, whatever it is called: %r" % one


@case("two parameters read as count-aware whatever they are named")
def t_reader_two_args_is_true_whatever_their_names():
    """A second value arrived; what it was called is not the question."""
    for two in ("String portfolioFullLineAr(int a, int b) => '';",
                "String portfolioFullLineAr(int limit, int have) => '';",
                "String portfolioFullLineAr(int x, int y, int z) => '';"):
        assert _reader_says(two) is True, \
            "two or more parameters means a count can reach it: %r" % two


@case("a parameter list with brackets in it is still ONE parameter list")
def t_reader_balances_brackets():
    """A default value that is itself a call, or a list of defaults, must not
    truncate the read.

    The old pattern stopped at the first `)`, so
    `portfolioFullLineAr(int limit, {int used = _fallback()})` was cut mid
    declaration and its own second parameter was never seen. A missing bracket
    does not mean the parameter list ended.
    """
    for src in ("String portfolioFullLineAr(int limit, {int used = fb()}) => '';",
                "String portfolioFullLineAr(int limit, [int a = 1, int b = 2]) => '';",
                "String portfolioFullLineAr(int limit, {int used = 0}) => '';"):
        assert _reader_says(src) is True, \
            "a bracket inside a default must not hide a parameter: %r" % src


@case("a list that never closes is UNREADABLE, and a list that is empty is NOT")
def t_reader_empty_is_measured_unclosed_is_not():
    """Two different verdicts that both once collapsed into None.

    `portfolioFullLineAr()` is a declaration this tool read perfectly well: it
    takes no count, and that is a measurement. A parameter list that never
    closes is not a declaration at all and must yield no answer. Reporting
    None for both tells a tick "no verdict" about a file that could be read,
    which is how an unmeasured thing becomes an absence nobody can see.
    """
    assert _reader_says("String portfolioFullLineAr() => '';") is False, \
        "an empty parameter list is a MEASUREMENT of a function taking no count"
    assert _reader_says(
        "String portfolioFullLineAr(int limit, {int used = 0 => '';") is None, \
        "a parameter list that never closes is not an answer"


@case("a CALL SITE in a doc comment is not the declaration")
def t_reader_ignores_call_sites():
    """The declaration is the only mention that answers the question.

    `portfolioFullLineAr` appears three more times in its own file: once in a
    prose sentence, and as `[bracket]` doc references. The old pattern was the
    bare name plus `(`, so it matched a one-argument CALL written in a comment
    above the definition and reported a two-parameter function as taking one
    argument -- the same wrong verdict as the spelling rule, reached by a
    different road.
    """
    assert _reader_says(
        "/// old shape: `portfolioFullLineAr(limit)` named only the ceiling.\n"
        "String portfolioFullLineAr(int limit, int used) => '';") is True, \
        "a call site in a comment must not stand in for the declaration"
    assert _reader_says("// portfolioFullLineAr(limit)\nclass Unrelated {}") is None, \
        "with no declaration at all, a call site is not a definition"


@case("an annotated declaration is still the declaration")
def t_reader_accepts_annotations():
    """`@pragma` above the function must not hide the one line that counts."""
    assert _reader_says(
        "@pragma('vm:prefer-inline')\nString portfolioFullLineAr(int limit, int used) => '';"
    ) is True


@case("the header verdict no longer follows a parameter NAME")
def t_header_verdict_is_rename_stable():
    """End to end, on the numbers the live hosts actually produce.

    130 photographs against a limit of 5. Under the spelling rule a rename
    flipped `header_contradicts` to True, which is the verdict that drives
    **exit 1**. This pins the whole path, not just the reader, so the two
    cannot be fixed in isolation and the pair still disagree.
    """
    measured = {"plan": {"portfolio_limit": 5}, "gallery": {"app_rows": 130}}
    for name in ("used", "have"):
        with _dart_file_as("String portfolioFullLineAr(int limit, int %s) => '';" % name):
            head, _ = audit._check_header(None, None, measured)
        assert head["subline_takes_count"] is True, head
        assert head["over_ceiling_line"] is False, head
        assert head["header_contradicts"] is False, (
            "renaming the parameter must not file a contradiction against two "
            "healthy hosts: %r" % (head,))


# --- the UNREADABLE verdict must not arrive as a "no" ------------------------
#
# The reader grades by ARITY (ticked 10 Oct), and it distinguishes three states:
# True (the count is a parameter), False (it is not) and None (the declaration
# could not be read at all). `_render` handles the third one correctly, in
# words: "`portfolioFullLineAr` NOT READ -- no verdict".
#
# **`_check_header` does not.** It branches on `if takes_count:` -- so None and
# False take the SAME arm, and the tool prints a measured defect verdict for a
# file it could not read. Measured on this tree, two triggers, neither of which
# touches a line of app logic:
#
#   run from /tmp instead of the repo root -> takes_count None
#   `portfolioFullLineAr` renamed          -> takes_count None (no declaration)
#
# Both give `header_contradicts: True`, which is the verdict that drives
# **exit 1** against two live hosts, and `_render` prints the contradiction and
# the "no verdict" line on the same screen -- a report that says it could not
# measure while spending the rest of its budget asserting a measurement.
#
# This is the reader-narrower-than-the-tree defect of 1/9/10 Oct for the third
# time, and the first time the third state exists at all: the arity fix gave the
# reader a genuine `None`, and the caller one layer up folds it back into a
# `False`. What the tool cannot see reads as *absent* rather than *unmeasured*.


@case("an UNREADABLE declaration does not file a contradiction")
def t_unreadable_is_not_a_no():
    def body(api):
        measured = {"plan": {"portfolio_limit": 5}, "gallery": {"app_rows": 130}}
        saved = audit.dart_ceiling_line_takes_count
        # The reader cannot find a declaration at all -- no rename needed, the
        # simplest honest way to be unreadable.
        audit.dart_ceiling_line_takes_count = lambda *a, **k: None
        try:
            head, _ = audit._check_header(None, None, measured)
        finally:
            audit.dart_ceiling_line_takes_count = saved
        assert head["subline_takes_count"] is None, head
        assert head["header_contradicts"] is False, (
            "an unreadable file is not a verdict about the screen: %r" % (head,))
        assert head["over_ceiling_line"] is False, head
    _run(body)


@case("an UNREADABLE declaration is reported as UNMEASURED, never as blind")
def t_unreadable_renders_as_unmeasured():
    def body(api):
        measured = {"plan": {"portfolio_limit": 5}, "gallery": {"app_rows": 130}}
        saved = audit.dart_ceiling_line_takes_count
        audit.dart_ceiling_line_takes_count = lambda *a, **k: None
        try:
            head, _ = audit._check_header(None, None, measured)
        finally:
            audit.dart_ceiling_line_takes_count = saved
        line = [ln for ln in audit._render(
            {"h": ({"plan": {"portfolio_limit": 5},
                    "gallery": {"app_rows": 130}, "header": head}, None)})
            if "ceiling sentence" in ln][0]
        assert "NOT READ" in line, line
        # The word `blind` in a row that also says "no verdict" is the report
        # contradicting itself one line under its own verdict.
        assert "blind to the count: True" not in line, line
    _run(body)


@case("a REAL False -- a one-parameter function -- still reads as blind")
def t_false_is_still_false():
    """The control, and it is the whole risk of the fix.

    Folding `None` into "not blind" would also silence a genuine defect: the
    one-parameter signature this tool exists to catch. If this case passes for
    the wrong reason it proves nothing, so it runs the real reader against real
    Dart rather than a stub.
    """
    def body(api):
        measured = {"plan": {"portfolio_limit": 5}, "gallery": {"app_rows": 130}}
        with _dart_file_as("String portfolioFullLineAr(int limit) => '';"):
            head, _ = audit._check_header(None, None, measured)
        assert head["subline_takes_count"] is False, head
        assert head["over_ceiling_line"] is True, (
            "a one-parameter function is the defect this tool exists to catch: "
            "%r" % (head,))
        assert head["header_contradicts"] is True, head
    _run(body)


@case("run from ANY directory the reader still finds the shipped Dart")
def t_reader_is_cwd_independent():
    """The trigger, measured: cwd is the only thing that can make it unreadable.

    `dart_ceiling_line_takes_count` resolved its default path through
    `os.getcwd()`, so every call that did not pass one -- which is every call
    in `_check_header`, because it passes no argument -- depended on the shell
    being in the repo root. The protocol's own commands all `cd` first, so it
    read as a non-issue and stayed for the tool's whole life.
    """
    real_cwd = os.getcwd()
    for elsewhere in ("/tmp", "/", os.path.expanduser("~")):
        audit.os.getcwd = lambda p=elsewhere: p
        try:
            got = audit.dart_ceiling_line_takes_count()
        finally:
            audit.os.getcwd = real_cwd
        assert got is True, (
            "from %s the reader must still grade the shipped Dart, got %r"
            % (elsewhere, got))


@case("a RENAMED declaration is UNREADABLE, and is not scored as a defect")
def t_rename_is_unreadable_not_blind():
    """A rename is the trigger that ships, so it is measured end to end.

    Renaming the function is as ordinary as renaming a parameter, and the arity
    fix last tick covered only the parameters. A rename leaves no declaration
    for `_DECL` to match, so the reader answers `None` -- and that `None` used
    to arrive at the exit code.
    """
    def body(api):
        measured = {"plan": {"portfolio_limit": 5}, "gallery": {"app_rows": 130}}
        src = open(os.path.join(REPO, "lib", "src", "data",
                                "portfolio_allowance.dart"),
                   encoding="utf-8").read()
        renamed = src.replace("portfolioFullLineAr", "portfolioCeilingLineAr")
        assert renamed != src, "the fixture must actually be a rename"
        with _dart_file_as(renamed):
            head, _ = audit._check_header(None, None, measured)
        assert head["subline_takes_count"] is None, head
        assert head["header_contradicts"] is False, (
            "a renamed function is a measurement gap, not a server defect: %r"
            % (head,))
    _run(body)


import contextlib


@contextlib.contextmanager
def _dart_file_as(src):
    """Point the tool at a throwaway Dart file for the duration of the block."""
    import tempfile
    fd, path = tempfile.mkstemp(suffix=".dart")
    try:
        os.write(fd, src.encode())
        os.close(fd)
        saved_file, saved_cwd = audit.DART_ALLOWANCE, audit.os.getcwd
        audit.DART_ALLOWANCE = path
        audit.os.getcwd = lambda: os.path.dirname(path) or "."
        try:
            yield
        finally:
            audit.DART_ALLOWANCE = saved_file
            audit.os.getcwd = saved_cwd
    finally:
        os.unlink(path)


# --- the NO_LIMIT_STATED branch reported a Dart verdict it never measured --
#
# The unreadable-vs-blind fix (10 Oct, second tick) taught this tool that a
# reader which cannot see must say so. It repaired ONE branch with a third
# state. `NO_LIMIT_STATED` is the other branch that ends early, one screen
# higher, and it carries the same defect in the same words.
#
# Measured on this tree. `_check_header` returns after the `isinstance(limit,
# int)` guard with only `verdict`, `used`, `limit` and `subline_takes_count` in
# the dict -- and `_render` then prints, for that host:
#
#   header_contradicts: None (used 7 > limit None) | ...
#   ceiling sentence is blind to the count: None (over by None) --
#     `portfolioFullLineAr` is handed the count and names both
#
# Four `None`s, then a full-sentence claim about the SHIPPED Dart, in the
# present tense, as though it had been read. It was not: the branch returned
# before `over_ceiling_line` existed, so there is no measurement in the dict to
# read the sentence from. `check_ceiling_line` agrees -- it returns `False`
# (not blind) from a dict that never had the key.
#
# This is the reader-narrower-than-the-tree defect for the FOURTH time, and the
# difference from 10 Oct is the point: there the reader had a third state and
# its CALLER threw it away. Here the measurement was never taken at all, and
# `_render` invents the verdict from a missing key.


@case("an UNSTATED ceiling yields no verdict, not a confident one")
def t_no_limit_renders_no_verdict():
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        api.current = {"plan": "free_trial"}      # no `portfolio_limit`
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=9)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert head["verdict"] == "NO_LIMIT_STATED", head
        lines = audit._render({"h": ({"plan": plan, "gallery": gal,
                                     "header": head}, None)})
        ceiling = [ln for ln in lines if "ceiling sentence" in ln]
        assert len(ceiling) == 1, lines
        # Nothing was measured, so the report must not name a verdict.
        assert "names both" not in ceiling[0], (
            "a ceiling this tool never read is not a sentence it can "
            "describe: %s" % ceiling[0])
        assert "no ceiling was stated" in ceiling[0], ceiling[0]
        assert "not measured" in ceiling[0], ceiling[0]
        # And the four `None`s beside it are the same silence, one row up.
        contra = [ln for ln in lines if "header_contradicts" in ln][0]
        assert "None" not in contra, (
            "an unmeasured contradiction must print no verdict at all: %s"
            % contra)
    _run(body)


@case("a REAL stated ceiling is still reported by name")
def t_limit_still_rendered_by_name():
    """The control, and the whole risk of the fix above.

    Reading "did not read it" instead of "the report is broken" would also
    silence every host that DID state a ceiling, which is the case this tool
    exists to judge. If the new branch were too wide, this one fails.
    """
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        api.current = {"plan": "free_trial", "portfolio_limit": 5}
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=9)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        # `.get`, not `[]`: the healthy branch never carries a `verdict` key at
        # all -- its whole meaning is that there was nothing to excuse.
        assert head.get("verdict") != "NO_LIMIT_STATED", head
        assert head["header_contradicts"] is False, head
        ceiling = [ln for ln in audit._render(
            {"h": ({"plan": plan, "gallery": gal, "header": head}, None)})
            if "ceiling sentence" in ln][0]
        assert "no ceiling was stated" not in ceiling, ceiling
        assert "names both" in ceiling or "takes only a limit" in ceiling, ceiling
    _run(body)


@case("the exit code ignores an unstated ceiling, as it ignores a healthy one")
def t_no_limit_never_exits_one():
    """`None` must not reach the exit decision the way a contradiction would.

    `main` reads `head.get("header_contradicts")`, which is absent on this
    branch. Pinned here so a future `bool(...)` coercion cannot turn a silent
    host into a red audit against two live ones.
    """
    def body(api):
        wire = audit.Wire(api.HOST)
        acct = _acct()
        api.current = {"plan": "free_trial"}
        plan, _ = audit._read_limit(wire, acct)
        gal, _ = audit._fill_past_the_limit(wire, acct, rows=9)
        head, _ = audit._check_header(wire, acct, {"plan": plan, "gallery": gal})
        assert not head.get("header_contradicts"), head
        assert "verdict" in head and head["verdict"] == "NO_LIMIT_STATED", head
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
