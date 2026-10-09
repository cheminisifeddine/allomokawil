#!/usr/bin/env python3
"""Pin the three claims `tool/inbox_read_audit.py` makes, without touching the wire.

    python3 test/inbox_read_audit_test.py

Python, for the reason `test/run_tests_busy_code_test.py` gives: this box
refuses a Dart build whenever the hypervisor balloon is up, and a live-wire
measurement is exactly the work that must not be skipped for that reason. Every
case here drives the tool against a **stub** transport, so the suite is
deterministic and offline. The production run that produced the numbers in the
docstring was a real one, taken 10 Oct, and is re-taken by hand whenever the
inbox route changes.

Three things are load-bearing, and each is a way this tool could quietly
publish a defect that does not exist -- the failure mode the backlog has now
hit twice (a colour threshold, and a counting reader).

* **Capped means rows went missing, not "the list was short".** The tick that
  shipped the chat paging fixed an off-by-one that made a complete read look
  truncated, by treating "the last page came back full" as the signal when a
  full page is what a walk that *reached the end* looks like on the way out.
  Here the signal is set membership: every id created must come back. A short
  list that still contains everything asked for is `capped = false`.
* **`paging_params_honoured` compares the reply to the plain one.** A parameter
  that changes nothing has changed nothing, so `!= rows` is the test and
  "the server ignored it" is the honest reading of `False`.
* **A refusal must name a build it can see.** The first version read
  `build_gate.py`'s exit code alone, and that gate folds BUSY and NO ROOM into
  one code on purpose. The result was a refusal that printed BUSY while the
  gate was simultaneously reporting that nothing was building -- an invented
  reason, which is worse than no guard at all. The gate's own sentence is the
  discriminator and both halves are pinned here.
"""
from __future__ import annotations

import importlib.util
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(REPO, "tool", "inbox_read_audit.py")


def _load():
    spec = importlib.util.spec_from_file_location("inbox_read_audit", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_results = []


def case(name):
    def wrap(fn):
        _results.append((name, fn))
        return fn
    return wrap


class StubWire:
    """A Wire whose every call is a canned answer, so the checks run offline.

    Three distinct reads are stubbed, because `_check` makes three: the plain
    inbox, the same route again for the stability claim, and the route with
    paging params. The first draft keyed the second and the third on the same
    marker, so a case written to prove the *stability* check fired was in fact
    proving the *paging* check -- and the new case failed for a reason that had
    nothing to do with the code under test. Two different stubs for two different
    reads is the fix; a stub that quietly answers the wrong question is the same
    defect as a test that asserts the wrong thing.
    """

    def __init__(self, rows, repeat=None, paged=None):
        self.rows = rows
        self.repeat = repeat if repeat is not None else rows
        self.paged = paged if paged is not None else self.repeat
        self.calls = []

    def call(self, path, data=None, token=None):
        self.calls.append(path)
        if "limit=500" in path or "page=" in path:
            return {"ok": True, "status": 200, "body": self.paged, "bytes": 1}
        # The first read and the re-read share a path, so they are told apart by
        # how many plain reads have already been answered.
        plain = [c for c in self.calls if c == "/api/mobile/conversations"]
        body = self.rows if len(plain) == 1 else self.repeat
        return {"ok": True, "status": 200, "body": body, "bytes": 255 * len(body)}


def _row(i, stamp):
    return {"id": i, "last_message_at": stamp}


@case("a read that returns every id asked for is UNCAPPED, however short the list looks")
def _short_but_complete_is_not_capped():
    mod = _load()
    # Three of three came back. The point of the case is the second half: a
    # future edit that compares row counts would call this capped.
    rows = [_row(i, "2026-10-09 15:00:0%d" % i) for i in (1, 2, 3)]
    acct = {"token": "t", "owner": 1, "made": [1, 2, 3]}
    report, err = mod._check(StubWire(rows), acct, 3)
    assert err is None, err
    assert report["rows_returned"] == 3 and report["all_made_present"] is True
    assert report["capped"] is False, \
        "every id created came back, so the inbox did not truncate. A count " \
        "comparison would have filed a defect here.\n%r" % report


@case("the cap signal is set membership, not a row count")
def _cap_signal_is_membership_not_count():
    """The case that mutation 1 exposed, rewritten after the run contradicted it.

    Swapping `all_made_present` for `len(rows) < threads` kept **every** other
    case green, because in all of them the count and the membership happened to
    agree. They disagree only when the server hands back a different number of
    rows than the account owns.

    The first version of this case asserted that 3 rows against 4 requested must
    be UNCAPPED. **The run said no, and it was right**: `threads_made` is read
    from `len(acct["made"])` precisely so a signup that never landed cannot be
    charged to the inbox. That distinction is the whole point. On
    `https://allomowil.com` this tool reported `39 made, 39 rows` for a
    `--threads 40` run -- one register call lost a race -- and called it
    UNCAPPED. A count comparison against the *requested* 40 would have filed a
    defect against a server that lost nothing at all.

    So the discriminator is membership against what was **actually created**,
    and both halves are pinned: a creation shortfall is not a read loss, and a
    genuine dropped id still is.
    """
    mod = _load()
    # 3 created, 3 returned: a creation shortfall happened upstream and the
    # inbox answered everything it owned.
    rows = [_row(i, "2026-10-09 15:00:0%d" % i) for i in (1, 2, 3)]
    acct = {"token": "t", "owner": 1, "made": [1, 2, 3]}
    report, err = mod._check(StubWire(rows), acct, 4)
    assert err is None, err
    assert report["threads_requested"] == 4 and report["threads_made"] == 3, \
        "the two counts are kept apart precisely so they can be compared.\n%r" % report
    assert report["rows_returned"] == 3 and report["all_made_present"] is True
    assert report["capped"] is False, \
        "3 created, 3 returned, every id present. Charging the missing signup to " \
        "the inbox would file a defect against a server that lost nothing.\n%r" % report

    # And the mirror: one id the account owns is absent from the reply. Count
    # alone would not catch this, because rows_returned can exceed the count of
    # ids that come back once a server duplicates anything.
    acct2 = {"token": "t", "owner": 1, "made": [1, 2, 3, 4]}
    rows2 = [_row(i, "2026-10-09 15:00:0%d" % i) for i in (1, 2, 3)]
    report2, _ = mod._check(StubWire(rows2), acct2, 4)
    assert report2["rows_returned"] == 3 and report2["capped"] is True, \
        "4 owned, 3 returned, id 4 missing: a silently hidden thread.\n%r" % report2


@case("a read that drops one id is CAPPED -- the defect the carry-over lead predicted")
def _dropped_row_is_capped():
    mod = _load()
    rows = [_row(i, "2026-10-09 15:00:0%d" % i) for i in (1, 2, 3)]
    acct = {"token": "t", "owner": 1, "made": [1, 2, 3, 4]}   # id 4 never comes back
    report, err = mod._check(StubWire(rows), acct, 4)
    assert err is None, err
    assert report["capped"] is True, \
        "an id that was created and never answered is a silently hidden thread.\n%r" % report


@case("order is by activity, not by id -- the claim the measurement actually settled")
def _order_is_activity_not_id():
    mod = _load()
    # Returned newest-first by id, but the oldest id has the newest message.
    rows = [
        _row(7, "2026-10-09 15:00:01"),
        _row(9, "2026-10-09 15:00:09"),
        _row(8, "2026-10-09 15:00:02"),
    ]
    acct = {"token": "t", "owner": 1, "made": [7, 8, 9]}
    report, err = mod._check(StubWire(rows), acct, 3)
    assert report["ordered_by_activity_desc"] is False, \
        "rows sorted by id are not sorted by activity, and the tool must say so.\n%r" % report
    rows_by_activity = [
        _row(9, "2026-10-09 15:00:09"),
        _row(8, "2026-10-09 15:00:02"),
        _row(7, "2026-10-09 15:00:01"),
    ]
    report2, _ = mod._check(StubWire(rows_by_activity), acct, 3)
    assert report2["ordered_by_activity_desc"] is True, \
        "activity-descending order is what production returned.\n%r" % report2


@case("a row with no timestamp is counted, not sorted into a place it cannot hold")
def _undated_rows_are_excluded_not_guessed():
    mod = _load()
    rows = [_row(1, None), _row(2, "2026-10-09 15:00:02")]
    acct = {"token": "t", "owner": 1, "made": [1, 2]}
    report, err = mod._check(StubWire(rows), acct, 2)
    assert err is None, err
    assert report["rows_without_timestamp"] == 1, \
        "an undated row must be counted so the order claim is honestly scoped.\n%r" % report
    assert report["ordered_by_activity_desc"] is True, \
        "the order claim is made over the dated rows only.\n%r" % report


@case("paging params that change nothing are reported as not honoured")
def _paging_params_ignored():
    mod = _load()
    rows = [_row(i, "2026-10-09 15:00:0%d" % i) for i in (1, 2)]
    acct = {"token": "t", "owner": 1, "made": [1, 2]}
    report, _ = mod._check(StubWire(rows, repeat=rows), acct, 2)
    assert report["paging_params_honoured"] is False, \
        "the route ignored ?limit=500&page=1 and returned the same list.\n%r" % report
    report2, _ = mod._check(StubWire(rows, paged=list(reversed(rows))), acct, 2)
    assert report2["paging_params_honoured"] is True, \
        "a genuinely different reply IS the signal that paging exists.\n%r" % report2


@case("an inbox that reshuffles between reads is reported unstable")
def _unstable_order_is_reported():
    """The case mutation 6 exposed: nothing killed `order_stable = True`.

    A list that reorders itself under the user's thumb between a pull and a
    resume is a real defect, and it is the one this tool is uniquely placed to
    see -- the server owns the order, so the client cannot sort its way out of
    it. Production answered stably across four consecutive reads, which is why
    the field exists to be *checked* rather than assumed.
    """
    mod = _load()
    rows = [_row(i, "2026-10-09 15:00:0%d" % i) for i in (1, 2, 3)]
    acct = {"token": "t", "owner": 1, "made": [1, 2, 3]}
    report, err = mod._check(StubWire(rows, repeat=list(reversed(rows))), acct, 3)
    assert err is None, err
    assert report["order_stable_across_reads"] is False, \
        "the second read came back in a different order; that is the defect, " \
        "and reporting it as stable would hide a list that moves under a thumb.\n%r" % report
    report2, _ = mod._check(StubWire(rows, repeat=rows), acct, 3)
    assert report2["order_stable_across_reads"] is True, \
        "identical reads are stable, which is what production did.\n%r" % report2


@case("a refused read is an error, never a verdict of zero lost")
def _failed_read_is_not_a_clean_bill():
    mod = _load()
    class Dead:
        def call(self, path, data=None, token=None):
            return {"ok": False, "status": 0, "body": "timed out", "cf1010": False, "bytes": 0}
    acct = {"token": "t", "owner": 1, "made": [1, 2]}
    report, err = mod._check(Dead(), acct, 2)
    assert err is not None, \
        "a read that never answered must return an error. Returning an empty " \
        "report is how a tool reports 'nothing lost' for a wire that was down."
    assert "capped" not in report, \
        "an error carries no verdict; `capped` present here would read as False " \
        "-- 'the inbox is fine' -- on a dead network.\n%r" % report


@case("the refusal names a build it can see, and ignores a memory-only denial")
def _refusal_discriminates_busy_from_no_room():
    mod = _load()
    import subprocess
    real = subprocess.run

    class Stub:
        def __init__(self, rc, text):
            self.returncode, self.stdout, self.stderr = rc, text, ""

    saved = {}

    def fake(cmd, **kw):
        saved["cmd"] = cmd
        return Stub(saved["rc"], saved["text"])

    subprocess.run = fake
    try:
        # NO ROOM and nothing building -> the denial is memory, so a stdlib
        # HTTP audit is not blocked by it.
        saved["rc"], saved["text"] = 1, "NO ROOM -- nothing is building, but only 335 MB is reclaimable"
        assert mod._another_writer_is_building() is False, \
            "the gate said nothing is building. Refusing here abandons the " \
            "measurement on a box that holds a few hundred KB of HTTP fine."
        # A visible build -> refuse.
        saved["rc"], saved["text"] = 1, "BUSY (build tool present): flutter"
        assert mod._another_writer_is_building() is True, \
            "a build this loop can see must block 120 account creations."
        # Clear -> never refuse.
        saved["rc"], saved["text"] = 0, "CLEAR"
        assert mod._another_writer_is_building() is False
    finally:
        subprocess.run = real


@case("the refusal gate reads build_gate.py, and a gate that vanishes blocks rather than waves through")
def _refusal_fails_closed():
    mod = _load()
    import subprocess
    real = subprocess.run

    def boom(*a, **kw):
        raise OSError("no gate")

    subprocess.run = boom
    try:
        assert mod._another_writer_is_building() is True, \
            "failing open would create 120 accounts with no contention check."
    finally:
        subprocess.run = real


@case("every request carries an agent, because Cloudflare 1010 is a WAF match and not an API fault")
def _user_agent_is_always_sent():
    """The case mutation 9 exposed: removing the header broke nothing.

    The first probe of this tick, run by hand, answered **403 with body
    `error code: 1010`** on a perfectly healthy API. That is Cloudflare's
    signature match on urllib's default `Python-urllib/3.x` agent, not the
    server refusing the app -- and read naively it is "the API is down", which
    is the wrong conclusion about production taken by the simplest possible
    misread. `ApiClient` sends no User-Agent of its own, so the tool's is the
    only thing standing between a clean measurement and that false alarm.

    The assertions are on the outgoing request, not on the reply: the point is
    that the header is set at all, which is invisible from a stubbed body.
    """
    mod = _load()
    sent = {}

    class Capture:
        def do_GET(self, full_url, headers=None, timeout=None):
            sent["headers"] = dict(headers or {})
            raise RuntimeError("stop here -- the header is what is under test")

    # `Wire.call` builds a real `urllib.request.Request`; catching the send is
    # the only way to see what went on the wire without making the call.
    import urllib.request as _u
    real = _u.urlopen

    def trap(req, **kw):
        sent["headers"] = dict(req.headers)
        sent["ua"] = req.get_header("User-agent")
        raise RuntimeError("captured")

    _u.urlopen = trap
    try:
        try:
            mod.Wire("https://example.invalid").call("/api/mobile/conversations", token="t")
        except RuntimeError:
            pass
    finally:
        _u.urlopen = real
    ua = sent.get("ua") or ""
    assert ua, "no User-Agent was sent at all"
    assert "Python-urllib" not in ua, \
        "urllib's default agent is exactly what Cloudflare answered 403/1010 " \
        "on this tick. It must not be the agent here."
    assert "AlloMokawil" in ua, \
        "the agent must identify the app, so a 1010 in a future run is " \
        "readable as 'this tool was blocked', not as 'the API is down'.\n%r" % ua


def main():
    ok = 0
    bad = 0
    for name, fn in _results:
        try:
            fn()
        except AssertionError as exc:
            bad += 1
            print("FAIL  %s\n      %s" % (name, exc))
        except Exception as exc:  # a crash is a failure, not a skip
            bad += 1
            print("ERROR %s\n      %r" % (name, exc))
        else:
            ok += 1
            print("ok    %s" % name)
    print("\n%d passed, %d failed" % (ok, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
