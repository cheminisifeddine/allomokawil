#!/usr/bin/env python3
"""Pin the logic the notification read audit reasons with -- python, not Dart.

    python3 test/notification_read_audit_test.py

**Why this is Python and not a Dart test.** `tool/build_gate.py` refuses Dart
on this box whenever the hypervisor balloon is up (352 MB available against a
900 MB floor on the tick that wrote this file). Every claim below is about *this
file's* arithmetic -- what counts as capped, what counts as a stranding, when
the order verdict is allowed -- and none of it needs a Dart VM. The same
reasoning `test/run_tests_busy_code_test.py` records for itself: a suite that
stays checkable exactly when the gate refuses is the only kind worth having.

**No case here talks to the network.** Every case drives the tool's own `_check`
against a stub `Wire`, so the suite is deterministic, costs milliseconds, and
cannot pass or fail because a production host was up.

**The three claims, and why each one has a case that must fail if it is dropped:**

* **capped** -- the server's own `/api/unread` count is the *only* witness that
  can catch a lost row; asking the same route twice cannot. A tool that
  compared the list against itself would pass on a capped host forever.
* **strands rows** -- this is the defect, not the cap. It is measured by
  re-reading the server's count *after* clearing every row the centre drew, and
  the case asserts the arithmetic that turns "40 left" into a verdict.
* **write_survives_row_count** -- the reachable shape, because the read hands
  back exactly the number of ids a batched sweep would send. 100 ids returning
  500 is what makes the cap a stranding rather than a loss.
"""

from __future__ import annotations

import os
import sys
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tool"))

import notification_read_audit as audit  # noqa: E402

_results = []


def case(name):
    def wrap(fn):
        _results.append((name, fn))
        return fn
    return wrap


class StubWire:
    """The API, answered from a table, so `_check` runs for real.

    Every call is answered rather than attempted: the tool's `_check` decides
    what to ask, and these tests are about what it *concludes* from the answers.
    """

    def __init__(self, rows, unread, mark_status=200, cap_limit=None):
        self.rows = rows
        self.unread = unread
        self.mark_status = mark_status
        self.cap_limit = cap_limit
        self.marked = []

    def call(self, path, data=None, token=None):
        if path.startswith("/api/unread"):
            return {"ok": True, "status": 200, "body": {"unread": self.unread},
                    "bytes": 20, "cf1010": False}
        if path.startswith("/api/notifications/read"):
            self.marked.append(list((data or {}).get("ids") or []))
            # A server that refuses the batch returns an error object rather
            # than a count, which is exactly what a 500 body looks like.
            if self.mark_status != 200:
                return {"ok": False, "status": self.mark_status,
                        "body": '{"code":"internal"}', "bytes": 24, "cf1010": False}
            if data and data.get("ids") is not None:
                self.unread = max(0, self.unread - len(data["ids"]))
            else:
                self.unread = 0
            return {"ok": True, "status": 200, "body": {"unread": self.unread},
                    "bytes": 20, "cf1010": False}
        # The centre read: capped at `cap_limit` rows, newest first, exactly the
        # shape production answers.
        served = self.rows[: self.cap_limit] if self.cap_limit else self.rows
        return {"ok": True, "status": 200, "body": served,
                "bytes": 240 * len(served), "cf1010": False}


def _rows(n):
    """[n] newest-first rows, stamped in the order the server stamps them."""
    return [{"id": 1000 - i, "created_at": "2026-10-10 15:%02d:00" % (59 - i % 60),
             "is_read": 0} for i in range(n)]


def _acct():
    return {"token": "t", "made": 140}


@case("the server's own count is the only witness for a cap")
def _capped_needs_the_server_count():
    # 140 exist, the route answers 100. Only `/api/unread` can see the 40.
    wire = StubWire(_rows(140), unread=140, cap_limit=100)
    rep, err = audit._check(wire, _acct(), 140)
    assert err is None, err
    assert rep["capped"] is True, \
        "100 rows drawn against a server count of 140 is a cap, and the " \
        "audit must say so. Got %r" % rep
    assert rep["rows_returned"] == 100 and rep["server_unread"] == 140


@case("a read that drew everything is not reported as capped")
def _uncapped_is_clean():
    wire = StubWire(_rows(40), unread=40)
    rep, err = audit._check(wire, _acct(), 40)
    assert err is None, err
    assert rep["capped"] is False, \
        "40 drawn against 40 unread is a complete read; filing a cap here " \
        "would train a future tick to ignore the verdict. Got %r" % rep
    assert rep["strands_rows"] is False


@case("a capped centre that clears every drawn row strands the rest")
def _cap_alone_would_only_lose_rows():
    # This is the defect rather than the cap: after clearing all 100 drawn rows
    # the server still holds 40, and the screen's `_unread` reads 0.
    wire = StubWire(_rows(140), unread=140, cap_limit=100)
    rep, _ = audit._check(wire, _acct(), 140)
    # The stub only decrements by what it was sent, so 140 - 100 = 40 left.
    assert rep["unread_left_after_clearing_drawn"] == 40, \
        "the audit must measure what survives, not assume. Got %r" % rep
    assert rep["strands_rows"] is True, \
        "40 unread rows the centre never drew is a stranding, and it is the " \
        "finding this file exists to produce."


@case("the order claim is only made on rows that carry a timestamp")
def _undated_rows_do_not_break_the_order_verdict():
    # A row with no stamp cannot be compared, so it is excluded and counted --
    # never sorted into a position it cannot be proven to hold.
    rows = _rows(50)
    rows[7] = {"id": 9999, "created_at": None, "is_read": 0}
    wire = StubWire(rows, unread=50)
    rep, _ = audit._check(wire, _acct(), 50)
    assert rep["rows_without_timestamp"] == 1, \
        "the undated row must be counted, not silently dropped. Got %r" % rep
    assert rep["newest_first"] is True, \
        "the 49 comparable rows are newest-first and that verdict stands."


@case("a server that orders oldest-first is caught, not waved through")
def _wrong_order_is_reported():
    rows = list(reversed(_rows(30)))
    wire = StubWire(rows, unread=30)
    rep, _ = audit._check(wire, _acct(), 30)
    assert rep["newest_first"] is False, \
        "oldest-first is the order that makes a cap *most* harmful -- the " \
        "newest fact is the first thing dropped. It must not read as clean."


@case("the mark-read write is judged at the size the read actually hands back")
def _write_is_probed_at_the_reachable_size():
    # 100 ids is exactly what the capped read returns, and it 500s on
    # production. The audit must catch that shape, not only a 1000-id payload.
    wire = StubWire(_rows(140), unread=140, cap_limit=100, mark_status=500)
    rep, _ = audit._check(wire, _acct(), 140)
    assert rep["ids_returned"] == 100, \
        "the ids sent must be the ones the read returned. Got %r" % rep
    assert rep["write_survives_row_count"] is False, \
        "a write that fails at the size the screen actually sends is the " \
        "reachable defect; the audit must report it."


@case("a write that survives is not reported as broken")
def _healthy_write_is_clean():
    wire = StubWire(_rows(140), unread=140, cap_limit=100)
    rep, _ = audit._check(wire, _acct(), 140)
    assert rep["write_survives_row_count"] is True, \
        "a 200 at 100 ids is the healthy case; a false here would bury the " \
        "real finding. Got %r" % rep
    assert rep["mark_all_drawn_status"] == 200


@case("a list-shaped refusal is not read as a clean empty centre")
def _unreadable_read_is_an_error_not_a_verdict():
    class Broken(StubWire):
        def call(self, path, data=None, token=None):
            if path.startswith("/api/notifications") and not path.startswith(
                    "/api/notifications/read"):
                return {"ok": False, "status": 500, "body": "boom",
                        "bytes": 4, "cf1010": False}
            return StubWire.call(self, path, data, token)

    rep, err = audit._check(Broken(_rows(10), unread=10), _acct(), 10)
    assert err is not None, \
        "a centre that would not answer has produced no verdict at all; " \
        "returning one would be inventing a measurement."
    assert rep.get("capped") is None, \
        "no verdict is published when there was nothing to measure. Got %r" % rep


@case("a Cloudflare 1010 is reported apart from an application failure")
def _cf_1010_is_not_a_broken_api():
    """Drives the real [Wire.call] -- the stub version proved nothing.

    The first draft of this case stubbed `call` itself and therefore asserted
    only that a dict it had just built contains a flag it had just set: it
    passed with the discrimination deleted out of `Wire.call`. A case that
    cannot fail when the thing it names is removed is worse than no case,
    because it reads as coverage. This one replaces `urlopen` instead, so the
    403 body is parsed by the code that actually parses it.
    """
    import urllib.error

    class FakeResponse:
        status = 200

        def read(self):
            return b'[]'

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    def _boom(req, timeout=None):
        raise urllib.error.HTTPError(
            req.full_url, 403, "Forbidden", {},
            __import__("io").BytesIO(b"error code: 1010"))

    real_open = audit.urllib.request.urlopen
    try:
        audit.urllib.request.urlopen = _boom
        blocked = audit.Wire("https://example.invalid").call("/api/notifications")
        audit.urllib.request.urlopen = lambda req, timeout=None: FakeResponse()
        healthy = audit.Wire("https://example.invalid").call("/api/notifications")
    finally:
        audit.urllib.request.urlopen = real_open

    assert blocked["cf1010"] is True, \
        "1010 is the WAF matching the agent string on a healthy API. Without " \
        "the flag a tick reads it as the wire being down -- the exact loss " \
        "the sibling audit documents. Got %r" % blocked
    assert blocked["status"] == 403 and blocked["ok"] is False
    assert healthy.get("cf1010") is not True and healthy["ok"] is True, \
        "the flag must not fire on a normal answer, or every refusal reads " \
        "as a WAF match. Got %r" % healthy


@case("the User-Agent is pinned, so the WAF match cannot be provoked by this tool")
def _agent_is_pinned():
    """The 403 above is provoked by a *bad* agent; this tool must not send one.

    Cloudflare answers 1010 to `Python-urllib/3.x`. Every request here claims to
    be the app, so the audit measures the API rather than testing the WAF -- and
    a future edit that drops the header would make every verdict here a study
    of the WAF instead.
    """
    class FakeResponse:
        status = 200
        seen = []

        def read(self):
            return b'[]'

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    captured = {}

    real_open = audit.urllib.request.urlopen
    try:
        def capture(req, timeout=None):
            captured["ua"] = req.get_header("User-agent")
            return FakeResponse()
        audit.urllib.request.urlopen = capture
        audit.Wire("https://example.invalid").call("/api/notifications")
    finally:
        audit.urllib.request.urlopen = real_open

    assert captured.get("ua") == audit.USER_AGENT, \
        "the agent must be the pinned app string, not urllib's default. " \
        "Got %r" % captured.get("ua")
    assert "urllib" not in (captured.get("ua") or "").lower(), \
        "an agent naming urllib is the signature Cloudflare answers 1010 to."


@case("the gate check reads the sentence, so a memory denial is not a BUSY")
def _gate_check_can_actually_discriminate():
    """The bug this first run shipped, pinned so it cannot return.

    The helper called `build_gate.py --quiet` and then tested its output for
    `nothing is building`. `--quiet` prints nothing, so that test can never
    succeed: on a box denied for *memory* -- the common case here -- the audit
    reported "another writer is building" on every single run. The run that
    caught it was the live invocation, which refused instantly on a box whose
    gate was simultaneously reporting that nothing was building.

    A refusal that invents a reason is worse than no refusal, and this box
    refuses builds constantly, so it would have made this tool useless exactly
    when it is most needed.
    """
    class R:
        def __init__(self, rc, text):
            self.returncode = rc
            self.stdout = text
            self.stderr = ""

    real_run = audit.subprocess.run if hasattr(audit, "subprocess") else None
    import subprocess
    real = subprocess.run
    seen = []

    def fake_run(cmd, **kw):
        seen.append(cmd)
        # The denial a memory-starved box actually produces: non-zero exit and
        # the sentence naming memory, not another writer.
        return R(1, "NO ROOM - nothing is building, but only 352 MB is reclaimable")

    try:
        subprocess.run = fake_run
        # `_another_writer_is_building` imports subprocess inside the function,
        # so patching the module attribute is what it sees.
        import importlib
        import notification_read_audit as mod
        real_import = importlib.import_module
        verdict = mod._another_writer_is_building()
    finally:
        subprocess.run = real

    assert verdict is False, (
        "a NO ROOM denial is memory, not another writer, and this audit does "
        "not need 1.2 GB to make a few hundred KB of HTTP. It must proceed."
    )
    assert any("--quiet" not in c for c in seen), (
        "`--quiet` prints nothing, so the sentence this check depends on is "
        "absent and the test can never match. Saw %r" % (seen,)
    )

    # The second half of the same branch, which the first assertion cannot see:
    # the sentence must actually be *what is being matched*. Deleting the match
    # while keeping the call would make every denial a refusal, and the
    # assertion above still passes because the command line is unchanged.
    calls = []

    def recursing_run(cmd, **kw):
        calls.append(cmd)
        return fake_run(cmd, **kw)

    try:
        subprocess.run = recursing_run
        import notification_read_audit as mod
        verdict2 = mod._another_writer_is_building()
    finally:
        subprocess.run = real

    assert verdict2 is False, (
        "the gate read the NO ROOM denial and still called it a writer, so "
        "the sentence match itself was dropped. This box denies builds "
        "constantly, and a tool that refuses on all of them is dead weight."
    )
    assert calls, "the gate was never consulted."


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
