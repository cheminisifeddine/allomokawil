#!/usr/bin/env python3
"""Decide whether it is safe to start a Flutter build on this box.

    python3 tool/build_gate.py            # human summary, exit 0 always
    python3 tool/build_gate.py --quiet    # exit 0 = clear, 1 = busy

The loop's build-safety rule is two `pgrep`s::

    pgrep -c java; pgrep -fc "[f]lutter"

and for three consecutive ticks both answered "busy" while **no build was
running**. The `flutter` match was this agent's own `bash -c` command line,
which contains the literal string ``[f]lutter``, so the bracket trick the
rule relies on — which exists so `pgrep` does not match its *own* invoking
shell — does not save the case where the pattern is written into a snapshot
wrapper. The ticks could not tell a running tool from a running grep, so
they skipped their gates, did non-build work instead, and said nothing. A
gate that reads busy when the box is free costs the loop its whole test
gate, silently, three ticks running.

The second failure is the mirror image: a `flutter_tester` left behind by a
killed or timed-out `flutter test` is a **leaked worker**, not a build. It
survives with `PPID 1`, burns ~170 MB of a 7.8 GB box that has no swap, and
reads as busy forever. Blocking on it means every future tick skips its
gate. Killing it is safe **only** when it is provably a leak, which is what
this decides.

The distinction, and it is the whole file:

  * **busy** — a real build *tool* simply existing, plus a java/gradle JVM
    that is actually consuming CPU. Existence is the right test for the tool
    and CPU the right test for the JVM: a `flutter test` between test files is
    blocked on I/O and burns 0% CPU, but it is unmistakably a build in
    progress, and a CPU test alone lets it through. A Gradle *daemon* is the
    mirror case — it exists forever and must be ignored when idle.
  * **leaked** — a `flutter_tester` whose parent tool is gone, which is
    exactly what PPID 1 means for a process that was never a daemon.
  * **no room** — no build is running, and the box cannot host one. This is
    a *different* answer from busy, and it is why this file is not only a
    process survey. Busy means "someone else started first"; no-room means
    "the box is starved and a second build gets OOM-killed", which is the
    failure the loop's own build-safety rule exists to prevent.
  * **clear** — anything else, including this script's own shell.

A leak is reported, not silently ignored: `--quiet` still fails, so the
caller cannot mistake "the script cleaned up" for "the box was free".
"""
import argparse
import os
import signal
import sys
import time

# How much reclaimable memory a build must find before it is worth starting.
#
# MEASURED on this box, 30 Sep, not guessed. With one test file running,
# MemAvailable fell 1715 MB -> 1177 MB; with three test files running
# concurrently (which is what a full `flutter test` does) it fell to
# 1278 MB. So a real run of this suite needs roughly 700-800 MB of headroom
# and bottoms out above 1.1 GB.
#
# 900 MB is deliberately *below* the 1177 MB floor a healthy run was
# measured at. That is the whole design constraint: this gate has already
# lied to the loop in both directions, so an arm that cries "no room" on a
# box that just finished a successful run is the same bug wearing new
# clothes. It may only fire when the box is worse than a run that is known
# to have worked.
MIN_AVAILABLE_MB = 900

# ...and it has to mean it on more than one reading.
#
# MEASURED 2 Oct, on this box, not theorised. Sampled MemAvailable every 2 s
# for 60 s: it fell **881 -> 692 MB**, and a second independent 45 s window
# took it **593 -> 510 MB**. That is not noise around a mean, it is a trend
# -- and it crosses MIN_AVAILABLE_MB. Against a fixture that alternates
# 488/1387 MB between ticks, the old one-shot read answered **4 NO ROOM and
# 4 CLEAR over eight consecutive invocations on an identical box**: a coin
# flip, decided entirely by which phase the tick happened to sample.
#
# The consequence is not cosmetic. This box is pressed against its own
# floor *by construction* (the pressure is outside our PID namespace), so a
# single-sample verdict means a tick is silently denied its test gate at
# random -- the same "the box is busy, skip the build" outcome that cost
# this loop three consecutive ticks, except now it is unpredictable instead
# of diagnosable. A detector that cannot be relied on to say the same thing
# twice about the same box is not a detector.
#
# So the floor must be **sustained**, not merely touched. Sample three
# times, take the MEDIAN, and refuse only when the middle reading is under
# the floor. The median is the point: it ignores one transient dip, which is
# what "a build started and has not settled" looks like, while still
# refusing on a box that is genuinely and repeatedly starved. Worst case it
# spends ~0.4 s of sampling on a path that already sleeps to measure CPU.
#: How many memory holders the starvation branch names, and the floor below
#: which one is not worth printing. They are MODULE CONSTANTS, not literals in
#: `main`, because that is the seam the gate's own test suite already uses to
#: drive the rest of this file's decisions on a controlled fixture.
HOLDER_LIMIT = 4
HOLDER_FLOOR_MB = 64.0

MEM_SAMPLES = 3
MEM_SAMPLE_GAP_SECONDS = 0.2

# The heavy compilers. `java` alone is not the signal — a Gradle *daemon*
# idles at 0% CPU between builds and is not a reason to skip a test run.
# What matters is that a JVM is consuming CPU right now.
CPU_SPIN_SECONDS = 2.0


def _read(path):
    try:
        with open(path, 'r') as fh:
            return fh.read()
    except (IOError, OSError):
        return ''


def _stat_fields(pid):
    """utime + stime from /proc/<pid>/stat, in clock ticks.

    Field 14/15 by the 1-indexed man page; the comm field may contain
    spaces and parentheses, so parsing splits on the *last* ')' first.
    """
    raw = _read('/proc/%s/stat' % pid).strip()
    if not raw:
        return None
    close = raw.rfind(')')
    if close < 0:
        return None
    rest = raw[close + 2:].split()
    # After comm and state, index 11 and 12 are utime and stime.
    if len(rest) < 13:
        return None
    try:
        return int(rest[11]) + int(rest[12])
    except ValueError:
        return None


def _ppid(pid):
    raw = _read('/proc/%s/stat' % pid).strip()
    close = raw.rfind(')')
    if close < 0:
        return None
    parts = raw[close + 2:].split()
    if not parts:
        return None
    try:
        return int(parts[1])
    except ValueError:
        return None


def _cmdline(pid):
    return _read('/proc/%s/cmdline' % pid).replace('\x00', ' ').strip()


def _comm(pid):
    """The kernel's own 15-char name for the process.

    This is the fallback that matters. A `flutter_tester` can be exec'd with
    an empty argv — the engine writes its command line in pieces and a
    process caught mid-exec, or one re-exec'd by the tool, reads
    `/proc/<pid>/cmdline` as **zero bytes**, and `/proc/<pid>/exe` is
    unreadable without privilege on this box. Matching argv alone therefore
    misses the exact leak this file exists to catch, which is how the first
    version of the test "passed" while reporting CLEAR on a live tester.
    `comm` is set by the kernel from the executable name and is always there.
    """
    return _read('/proc/%s/comm' % pid).strip()


def _cwd(pid):
    """The process's working directory -- the one field that names its OWNER.

    `argv` says what a program was asked to do, and on a box running several
    services the same binary appears under every one of them. `cwd` is where
    it was actually started, and that is what told the 5 Oct tick that the
    ~700 MB headless Chrome sitting under its NO ROOM verdict belongs to a
    supervised `waha-lite` service that the loop has no business touching.

    Empty string when unreadable, and never a guess: reading another user's
    cwd needs privilege this box does not grant, and an invented path would
    be worse than no path at all.
    """
    try:
        return os.readlink('/proc/%s/cwd' % pid)
    except OSError:
        return ''


def _self_and_ancestors():
    """This script's own pid, plus every ancestor of it.

    Any hit inside this set is the caller looking at itself in the mirror,
    which is precisely the false positive that cost three ticks their gate.
    """
    out, pid = set(), os.getpid()
    while pid and pid > 1:
        out.add(pid)
        pid = _ppid(pid)
    return out


def _tick_seconds():
    try:
        return float(os.sysconf('SC_CLK_TCK'))
    except (ValueError, OSError, AttributeError):
        return 100.0


def _is_leaked_tester(pid):
    """A flutter_tester whose owning tool process is gone.

    PPID 1 on a process that was never a daemon means its parent exited
    without reaping it: the classic signature of a killed `flutter test`.
    A *live* test run keeps the tester as a child of the tool, so PPID 1 is
    safe to treat as leak only for this specific binary.
    """
    return _ppid(pid) == 1


def _debug_port(cmd):
    """The --remote-debugging-port value in argv, or None.

    Both spellings the browser accepts, because only reading the `=` form
    is how a port silently goes undetected: `--remote-debugging-port 9398`
    is a legal argv and leaves `cmd` containing the flag with no value
    glued to it.
    """
    parts = cmd.split()
    for i, tok in enumerate(parts):
        if tok == '--remote-debugging-port' and i + 1 < len(parts):
            try:
                return int(parts[i + 1])
            except ValueError:
                return None
        if tok.startswith('--remote-debugging-port='):
            try:
                return int(tok.split('=', 1)[1])
            except ValueError:
                return None
    return None


def _port_in_use(port):
    """True when something is *connected* to `port`, listener excluded.

    Read from the kernel's own socket tables rather than `ss`, which is
    absent on this box's minimal image, and from `/proc/net/tcp{,6}`
    rather than by scanning fds, so the answer does not depend on the
    privilege of the caller.

    A LISTEN socket (state 0A) does not count: that is the browser's own
    listening socket, present whether or not anyone is talking to it.
    Any other state on that local port is a client, so the browser is
    being driven. TIME_WAIT (06) counts too, deliberately: it is the
    remnant of a session that was just using it, and under-reporting a
    leak only makes the gate stay busy, while over-reporting one tells a
    tick to kill a live render.
    """
    if port is None:
        return False
    needle = '%04X' % (port & 0xFFFF)
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        raw = _read(table)
        if not raw:
            continue
        for line in raw.split('\n')[1:]:
            fields = line.split()
            if len(fields) < 4:
                continue
            local = fields[1].rsplit(':', 1)
            if len(local) != 2 or local[1].upper() != needle:
                continue
            if fields[3].upper() == '0A':      # TCP_LISTEN
                continue
            return True
    return False


def _looks_like_browser(pid, cmd):
    """Is this process itself a browser, or merely a script naming one?

    `_debug_port` answers "does argv contain the flag", which a *launcher*
    also answers. This asks the narrower question the leak arm needs: the
    process's own executable is the browser. `argv[0]`'s basename is the
    test, with `comm` as the fallback for the exec'd-with-empty-argv case
    `_comm` already exists to cover.
    """
    browsers = ('chrome', 'chromium', 'chrome-headless-shell',
                'headless_shell', 'google-chrome', 'chromium-browser')
    # A shell or wrapper that *runs* a browser. Its own executable is not the
    # browser and it holds no debugging port of its own.
    launchers = ('bash', 'sh', 'dash', 'zsh', 'ksh', 'env', 'nohup', 'setarch',
                 'timeout', 'script', 'sudo', 'su', 'xargs', 'nice', 'setsid',
                 'stdbuf', 'watch', 'command', 'time')
    comm = _comm(pid)
    if cmd:
        base = os.path.basename(cmd.split()[0])
        if base in browsers:
            return True
        if base in launchers:
            return False
    # Neither a known browser nor a known launcher: do **not** guess True from
    # an unfamiliar argv[0]. Between `fork` and `exec` a child carries its
    # parent's cmdline verbatim, so "unrecognised" here usually means "has not
    # become itself yet" -- and the parent's argv is exactly what this whole
    # bug is about. `comm` is the kernel's own name for what is running now
    # and is the one signal here that is not inherited from the parent.
    return comm in browsers


def _is_leaked_browser(pid):
    """A headless Chrome the loop itself left behind.

    Step 5 of the loop protocol tells every tick to render and *look* at a
    visual change, and the render runs a headless Chrome on a debugging port
    (9333/9444/9335). When a tick ends without reaping it -- the process
    outlives the shell that launched it, so it reparents to init -- that
    browser holds ~330-380 MB of a box that has no swap, and the gate then
    answers NO ROOM forever. That is what this arm is for: the same shape as
    `_is_leaked_tester`, one binary further down the loop.

    The signal is `remote-debugging-port` in argv, and the leak test is the
    same PPID 1 rule. Two details are load-bearing:

      * **argv, not comm.** A Chrome tree is ~13 processes whose `comm` is
        all `chrome` -- zygotes, gpu-process, renderers, crashpad. Counting
        them is what made a first version of this look like it worked while
        reporting a wrong total. Only the *root* browser carries the
        debugging flag; its children inherit argv fragments but not the
        browser's own `--headless` root switch, so the flag names one
        process, not a tree. One leak is one report.
      * **PPID 1 alone is not enough.** A live browser whose parent is the
        agent's own shell has a normal parent, so it is not counted; but a
        browser a *different* live session is driving right now also has a
        non-1 ppid and must not be killed by a later tick. Same discipline
        as the tester arm: prove the leak, then report it.
    """
    # **argv is a description of intent, not of identity.** A process only
    # *has* a debugging port if its own command line is the browser's; a
    # `bash -c '... chrome --remote-debugging-port=9333 ...'` launcher contains
    # the flag in the script text the shell is about to run, and every browser
    # token in it belongs to a *child* the shell is about to exec.
    #
    # Measured on this box, 2 Oct 2026, and it was not hypothetical: the gate
    # printed `LEAKED headless chrome` naming pid **20299**, a `/bin/bash`
    # holding 618 kB, whose PPID was 1. The real browser was its child 20303
    # (70 MB, `comm` = `chrome`), and 20303 was correctly *not* a leak because
    # its PPID was 20299 -- a launcher from a live session, not a dead one.
    # So the gate classified the one process on the box that was provably
    # *not* a browser as a browser leak, and printed the instruction to reap
    # it: `--reap` SIGTERMs exactly the pids this survey names, which would
    # have killed a live session's browser mid-screenshot. The `_rss_kb` number
    # in the same report said 0 MB, which is the tell: a 330-380 MB leak does
    # not weigh 0 MB.
    #
    # The identity test is argv[0], not `comm`: `comm` is truncated to 15
    # chars, which is fine for `flutter_tester` but would mangle a longer
    # wrapper path, and `_comm` is already the fallback this file uses where
    # argv is empty. Both are checked so an exec'd-with-empty-argv browser is
    # still caught.
    cmd = _cmdline(pid)
    port = _debug_port(cmd)
    if port is None:
        return False
    if not _looks_like_browser(pid, cmd):
        return False
    if _ppid(pid) != 1:
        return False
    # PPID 1 is NECESSARY but NOT SUFFICIENT here, and the gap is not
    # theoretical: a browser is a server. The shell that launched it can
    # exit while the session that is *driving* it over CDP carries on --
    # that is the normal shape of a tick whose render outlived its own
    # command. The tester arm gets away with PPID 1 because a flutter_tester
    # talks to nobody; this one answers on a port, so reparenting says only
    # that the launcher is gone, never that the browser is unused.
    #
    # This matters because the gate does not merely report what it finds:
    # its own output tells the reader to "reap it and re-run this gate".
    # An instruction to kill, derived from a fact that does not support it,
    # is how a live render dies mid-screenshot.
    return not _port_in_use(port)


def _rss_kb(pid):
    """Proportional set size of one process in kB, or None.

    PSS, not VmRSS, and the difference is the whole point. A Chrome tree
    shares most of its memory: the zygotes and the renderers forked from
    them map the same code and data pages, so summing VmRSS across a tree
    counts each shared page once per process. Measured on a real leaked
    browser on this box: **sum(VmRSS) = 1167 MB, sum(PSS) = 444 MB** --
    RSS over-reports the true cost by 2.6x. A gate that prints "this is
    holding 1.1 GB" on a box with 1.1 GB *available* is not describing a
    memory problem, it is describing an arithmetic error, and a tick that
    believed it would go looking for a gigabyte that is not there.

    PSS divides each shared page by the number of processes mapping it, so
    the sum over a tree is what the kernel would actually reclaim. It lives
    in smaps_rollup, which is the cheap per-process version -- the full
    smaps walk is far too slow to run across a process survey.

    VmRSS from status is the fallback, and it is *only* a fallback: on a
    box where smaps_rollup is unreadable (it needs the same privilege as
    the rest of /proc here) a number is still better than none, so the
    report is explicitly labelled as RSS in that case.
    """
    raw = _read('/proc/%s/smaps_rollup' % pid)
    total = 0
    for line in raw.split('\n'):
        if line.startswith('Pss:'):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    return int(parts[1])
                except ValueError:
                    break
            break
    raw = _read('/proc/%s/status' % pid)
    for line in raw.split('\n'):
        if line.startswith('VmRSS:'):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    return int(parts[1])
                except ValueError:
                    return None
    return None


def browser_mb(browsers):
    """Total RSS of the leaked browser roots, in MB.

    The root is what the flag lands on, but a Chrome root is only ~66 MB of
    its own: the zygotes and renderers it forks are the rest of the cost,
    and they are its children. Charging the loop only the root would report
    a third of the memory actually held, which is how a real 330 MB leak
    gets written down as a harmless 66 MB.
    """
    total_kb = 0
    seen = set()
    frontier = [rec[0] for rec in browsers]
    while frontier:
        pid = frontier.pop()
        if pid in seen:
            continue
        seen.add(pid)
        rss = _rss_kb(pid)
        if rss:
            total_kb += rss
        try:
            for entry in os.listdir('/proc'):
                if not entry.isdigit():
                    continue
                child = int(entry)
                if child not in seen and _ppid(child) == pid:
                    frontier.append(child)
        except OSError:
            pass
    return total_kb / 1024.0


def _children_map():
    """parent pid -> [child pids], from /proc, one pass.

    Built once and reused by both tree walks below. Asking the kernel for
    each pid's children separately is a listing per process; this is one
    listing.
    """
    kids = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        parent = _ppid(int(entry))
        if parent is not None and parent > 0:
            kids.setdefault(parent, []).append(int(entry))
    return kids


def _tree_pids(root, kids):
    """root plus every descendant, as a set."""
    out, frontier = set(), [root]
    while frontier:
        pid = frontier.pop()
        if pid in out:
            continue
        out.add(pid)
        frontier.extend(kids.get(pid, ()))
    return out


#: Never charged as a holder, and never walked *through*. PID 1 is the parent
#: of every process that was reparented to init -- which is precisely every
#: tree this gate can see, on this kernel. Walking up to it makes init "own"
#: the whole box, and a census that attributes 2 GB to systemd instead of to
#: the 669 MB service that is actually holding it is a census that names a
#: falsehood. The first version of this function did exactly that: measured
#: on 5 Oct, it reported `1  2011MB  32proc  systemd` and hid `waha-lite` at
#: 26775 -- the one process the reader was sent here to find.
#: ...and PID 0, which is not a process at all but the ppid the kernel reports
#: for anything whose real parent is gone. `hatch daemon` reads PPID 0 on this
#: box and held **487 MB**; rooted normally it was charged to pid 0, whose
#: "tree" then collected every unrelated parentless process on the box into
#: one 492 MB phantom row. A census that merges strangers under a fake parent
#: is the same falsehood as the init one, one level down.
HOLDERS_EXCLUDE = (0, 1)


def _all_pids():
    """Every pid on the box, from one /proc listing."""
    return [int(e) for e in os.listdir('/proc') if e.isdigit()]


def _forest_root_of(pid, kids, parents=None):
    """The topmost non-init ancestor of `pid`, or `pid` itself.

    One row per tree, so every pid must land on the same root as its parent.
    The walk reads `parents` for the *current* pid, so that mapping has to be
    keyed by **every** pid, not only by the pids that happen to be somebody's
    parent -- the first version built it from the children map's keys and
    stopped the walk dead on any leaf. That silently re-rooted every
    leaf-wrapped tree at its own leaf: measured on 5 Oct, the `waha-lite` tree
    came back split across 26775, 26773 and a bare 424 MB renderer at 26877,
    which is the opposite of the one-line answer this exists to produce.
    """
    if parents is None:
        parents = {p: _ppid(p) for p in _all_pids()}
    cur, seen = pid, set()
    while cur not in seen:
        seen.add(cur)
        nxt = parents.get(cur)
        # A parent of 0 or 1 means "there is no real parent to walk to", so
        # this pid IS the root of its own tree. Returning the sentinel instead
        # would merge every parentless process into one row.
        if nxt is None or nxt == cur or nxt in HOLDERS_EXCLUDE:
            return cur
        cur = nxt
    return cur


def holder_census(limit=HOLDER_LIMIT, floor_mb=HOLDER_FLOOR_MB):
    """Who is actually holding this box's memory, biggest first.

    Charged to the **tree root**, never to the process that happens to be
    biggest, for the reason `browser_mb` already documents: a Chrome root is
    ~66 MB of its own and the rest is the renderers it forked, so scoring
    processes individually writes the loop's own loop-starvation down as a
    harmless 66 MB and buries the 700 MB that is actually there. A tree
    already charged is not charged again through one of its children.

    Sized with PSS (`_rss_kb`) rather than RSS, so shared pages are counted
    once per process actually mapping them -- the same correction
    `browser_mb` records, from sum(VmRSS) 1167 MB vs sum(PSS) 444 MB on a
    real leaked tree.

    Measured cost on this box: **0.049 s** over 34 pids, which is why it is
    gated on the starved branch instead of running on every invocation.

    Rows are (pid, MB, process count, comm, cwd). Below `floor_mb` a holder is
    not worth the reader's time; the largest is never suppressed, because a
    census that hides its own biggest entry is worse than no census.
    """
    kids = _children_map()
    # Every pid, not just the ones that are somebody's parent: a leaf holds
    # memory too, and a leaf is its own tree root.
    pids = _all_pids()
    # Built ONCE, keyed by every pid. Rebuilt per pid it was a second
    # /proc-listing-sized cost per process, and it was wrong for leaves.
    parents = {p: _ppid(p) for p in pids}
    pss = {}
    for pid in pids:
        val = _rss_kb(pid)
        if val:
            pss[pid] = val

    # One row per forest root, not one per process. A root's whole subtree is
    # charged to it -- that is what `browser_mb` does and why a Chrome tree
    # reads as one 600 MB line instead of ten 60 MB ones -- and a tree already
    # charged is never charged again through one of its own children.
    root_score = {}
    for pid in pids:
        if pid in HOLDERS_EXCLUDE or pid in _self_and_ancestors():
            continue
        root = _forest_root_of(pid, kids, parents)
        if root is None or root in HOLDERS_EXCLUDE:
            continue
        mb = _rss_kb(pid)
        if mb:
            root_score[root] = root_score.get(root, 0.0) + mb / 1024.0
    mine = _self_and_ancestors()
    scored = []
    for root, mb in root_score.items():
        if root in mine or mb <= 0:
            continue
        comm = _comm(root) or '?'
        # The tree a root "owns" is its descendants plus itself; count it the
        # way `browser_mb` counts one, walking children rather than assuming
        # a flat family.
        npids = len(_tree_pids(root, kids)) if root in kids else 1
        scored.append((root, mb, npids, comm, _cwd(root)))
    scored.sort(key=lambda row: -row[1])
    if not scored:
        return []
    biggest = scored[0][1]
    kept = [r for r in scored if r[1] >= floor_mb or r[1] == biggest]
    # `limit=0` means NO CAP. `kept[:0]` is an empty slice, so the first
    # version of this line silently returned nothing at all to the one caller
    # that asked for every row -- and the gate's own test caught it, because
    # a test that asserts "the tree is named" is worth more than the slice
    # expression that hid it.
    return kept if limit <= 0 else kept[:limit]


def _available_once():
    """One instantaneous MemAvailable reading in MB, or None.

    MemFree is the wrong field and the difference is the point. MemFree
    excludes page cache, and this box runs a 3-hour-old headless Chrome on
    ~1.4 GB of it, so MemFree sits under 1 GB while there is genuinely
    ~2 GB reclaimable. A build is refused by the kernel against
    *available*, not free, so that is the number this reads.

    MemAvailable is in **kB**, so the division by 1024 is not cosmetic: a
    fixture that says "512 MB" in a kB field parses as 512 kB and prints as
    "0 MB", which is a test that still passes while proving nothing.
    """
    raw = _read('/proc/meminfo')
    for line in raw.split('\n'):
        if line.startswith('MemAvailable:'):
            try:
                return int(line.split()[1]) / 1024.0
            except (IndexError, ValueError):
                return None
    return None


def available_mb(samples=None):
    """MemAvailable in MB -- memory a build could actually claim.

    The MEDIAN of several readings, not one of them. A single reading on a
    box that oscillates across its own floor produces a different verdict
    for the same box, which is the defect this function was changed to fix;
    see MEM_SAMPLES in the header for the measurement. Sampling three times
    and taking the middle one ignores a single transient dip -- which is
    what a build starting up looks like -- without ever ignoring a box that
    is starved on every reading.

    Unreadable /proc/meminfo returns None rather than a guess, and a None
    never blocks a build (see no_room).
    """
    if samples is None:
        samples = MEM_SAMPLES
    seen = []
    for _ in range(max(1, samples)):
        reading = _available_once()
        if reading is not None:
            seen.append(reading)
        if len(seen) < max(1, samples):
            time.sleep(MEM_SAMPLE_GAP_SECONDS)
    if not seen:
        return None
    seen.sort()
    mid = len(seen) // 2
    if len(seen) % 2:
        return seen[mid]
    # Even count: mean of the two middle readings, so the result is still a
    # value the box actually reported rather than a piece of arithmetic.
    return (seen[mid - 1] + seen[mid]) / 2.0


def _total_mb():
    raw = _read('/proc/meminfo')
    for line in raw.split('\n'):
        if line.startswith('MemTotal:'):
            try:
                return int(line.split()[1]) / 1024.0
            except (IndexError, ValueError):
                return None
    return None


def balloon_mb():
    """Memory the HYPERVISOR has taken back out of this guest, in MB, or None.

    Measured on this host, 8 Oct 2026. `/proc/meminfo` carries a `Balloon:`
    line (the virtio-balloon driver) and it reads **4920444 kB -- 4.9 GB,
    three fifths of `MemTotal`** -- while `nr_balloon_pages` in
    `/proc/vmstat` sits flat at 1082655 across repeated samples, i.e. the
    guest is not being drained further and is not being handed any back.

    This is the memory that makes this box read NO ROOM, and the reason it
    matters is that **no process in this PID namespace owns any of it.** The
    census below sums every visible pid and reaches **822 MB against 7.5 GB
    in use** -- the gap is real, it is large, and it is invisible to a
    process survey by construction. So the gate printed its one honest
    number, named a 332 MB `hatch daemon` as the largest holder, and closed
    with "if the top holder is a service, this denial is the box being at its
    floor". That is an instruction to act, derived from a holder that cannot
    account for the shortfall: the daemon is 3% of it. A reader following it
    faithfully waits on, or worse signals, a process that could not free the
    memory even if it exited.

    A separate kernel mechanism (a cgroup memory limit, plain overcommit)
    produces the same starvation with no `Balloon:` line at all, so
    **None is a normal answer** and callers must fall back rather than treat
    a missing field as zero. Same shape as `_available_once`: unreadable
    input returns None and never blocks on a guess.
    """
    raw = _read('/proc/meminfo')
    for line in raw.split('\n'):
        if line.startswith('Balloon:'):
            try:
                return int(line.split()[1]) / 1024.0
            except (IndexError, ValueError):
                return None
    return None


def no_room():
    """True when the box is too starved to host a build.

    Only consulted when no build is already running, so it can never turn a
    real busy box into anything other than busy.
    """
    avail = available_mb()
    if avail is None:
        return False          # cannot measure -> never block on a guess
    return avail < MIN_AVAILABLE_MB


def sustained_no_room():
    """True only when the box is starved *and* stays starved.

    Two consecutive median readings, both under the floor. One median
    already rejects a single unlucky sample; requiring the next one to agree
    means a transient neighbour -- the case that made the old gate flip
    between NO ROOM and CLEAR on an identical box -- can no longer talk the
    loop out of its gate on its own.
    """
    if not no_room():
        return False
    return no_room()


def survey():
    mine = _self_and_ancestors()
    tck = _tick_seconds()

    tools = []      # real flutter/dart tool: existence is enough
    jvms = []       # java/gradle: counted, but only "busy" if burning CPU
    leaked = []     # orphaned flutter_tester
    browsers = []   # orphaned headless Chrome, this loop's own render

    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid in mine:
            continue
        cmd = _cmdline(pid)
        comm = _comm(pid)
        if not cmd and not comm:
            continue

        # `ident` is argv, or comm when argv is empty/unreadable. Both are
        # needed: argv names the *tool snapshot* a real `flutter test` runs,
        # comm names the engine binary, and neither field covers the other.
        ident = cmd or comm
        is_tester = ('flutter_tester' in cmd or comm == 'flutter_tester'
                     or comm == 'dart' and 'flutter_tester' in ident)
        is_java = (cmd.startswith('java') or '/bin/java' in cmd
                   or comm == 'java')
        is_browser = _is_leaked_browser(pid)
        is_tool = ('bin/flutter' in cmd or 'flutter_tools' in cmd
                   or cmd.startswith('dart ') or '/dart ' in cmd
                   or comm == 'dart' and cmd == '')
        if not (is_tester or is_java or is_tool or is_browser):
            continue

        before = _stat_fields(pid)
        is_tester_leaked = is_tester and _is_leaked_tester(pid)
        time.sleep(CPU_SPIN_SECONDS)
        after = _stat_fields(pid)
        busy = (before is not None and after is not None
                and (after - before) > 0)

        rec = (pid, cmd[:70], busy)
        if is_browser:
            # Recorded with a None verdict on purpose. A parked browser
            # burns ~0% CPU and an idle one ticks a little, so sampling it
            # makes the label flicker between runs for a fact that does not
            # depend on CPU at all: the process is leaked either way. None
            # prints as "leak", which is the thing the reader must act on.
            browsers.append((pid, cmd[:70], None))
        elif is_tester_leaked:
            # A tester that survived its tool. Reported, never silently
            # dropped: the caller has to know the box was not actually free.
            leaked.append(rec)
        elif is_tester:
            # A tester with a live parent: a real test run is in flight.
            tools.append(rec)
        elif is_tool:
            tools.append(rec)
        else:  # java
            jvms.append(rec)

    return jvms, tools, leaked, browsers


def reap(browsers, dry_run=False, grace=6.0, poll=0.2, kind='browser'):
    """SIGTERM the leaked process roots and wait for them to actually die.

    Takes only the pids the survey already classified as leaks, so this
    cannot become a second, looser process survey that kills something the
    gate had deliberately called clear. Returns (killed, survivors).

    [kind] is only the noun in the two messages -- the pids are the ones the
    survey already proved leaked, and the signalling below is identical.

    SIGTERM, never SIGKILL, and only after the process has gone: a Chrome
    root with ~13 forked children dies as a group when it does, and a
    SIGKILL to the root would orphan the renderer tree instead of removing
    it -- trading one leak for a bigger one.

    The wait is what makes the exit code mean something. Without it the
    call returns while the memory is still held, the caller re-runs the
    gate, reads NO ROOM on the same browser it was told it had just
    killed, and concludes the gate is broken. It is not a guess about the
    kernel: the pid is gone from /proc before this returns.
    """
    killed, survivors = [], []
    for pid, _cmd, _verdict in browsers:
        if _ppid(pid) is None and not os.path.exists('/proc/%d' % pid):
            continue                       # already gone; nothing to reap
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            continue                       # exited between survey and here
        except PermissionError:
            survivors.append(pid)          # not ours to signal; never force
            continue
        killed.append(pid)
        # monotonic, NOT time.time(). This wait is the only thing that makes
        # the exit code mean what its own docstring claims ("the wait is what
        # makes the exit code mean something" -- without it the caller re-runs
        # the gate, reads NO ROOM on a browser it was just told it had killed,
        # and concludes the gate is broken). A deadline measured on the wall
        # clock is governed by something the gate does not control and cannot
        # observe: NTP steps it forwards and backwards, and `settimeofday` can
        # move it either way. Forward by more than `grace` and the loop
        # compares against a deadline that is already in the past, so the
        # *first* comparison fails and the wait is skipped entirely -- the
        # function returns while the browser still holds ~600 MB, which is
        # precisely the "gate says it reaped it, memory still gone" state the
        # docstring was written to prevent. Backward by more than `grace` and
        # the same wait never terminates inside its own budget. Neither needs
        # the box to be loaded; it needs the host to be in sync, which is a
        # normal condition and not a fault.
        # `run_tests.py` already bounds its SIGTERM grace the same way, and
        # the two instruments are read by the same tick.
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            if not os.path.exists('/proc/%d' % pid):
                break
            time.sleep(poll)
        else:
            # It ignored SIGTERM. Say so rather than escalating: a tick must
            # never SIGKILL a process it cannot prove it owns.
            survivors.append(pid)
    return killed, survivors


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--quiet', action='store_true')
    ap.add_argument('--reap', action='store_true',
                    help='SIGTERM leaked flutter_tester and browser roots '
                         'this loop left behind, then re-survey. Acts only '
                         'on pids already proven leaked; never on a live '
                         'test run or a live render.')
    args = ap.parse_args(argv)

    jvms, tools, leaked, browsers = survey()

    # Both leak classes, in the order they are printed. A leaked
    # `flutter_tester` had NO arm here until this tick: the survey named it
    # (`LEAKED flutter_tester`), counted it as busy so the gate refused to
    # build, and then -- with no browser on the box -- printed no remedy at
    # all. The reader was told the box was blocked by a process the one
    # documented command for unblocking could not touch, which is the same
    # "an instruction to act, derived from nothing that supports it" defect
    # case 13 was written for, one class over.
    #
    # Both calls re-SURVEY (see below): the verdict must never be computed
    # from a process this same call is about to kill.
    for group, kind in ((leaked, 'flutter_tester'), (browsers, 'browser')):
        if not (args.reap and group):
            continue
        killed, survivors = reap(group, kind=kind)
        if not args.quiet:
            for pid in killed:
                print('reaped leaked %s %d (SIGTERM, waited for exit)'
                      % (kind, pid))
            for pid in survivors:
                print('%s %d ignored SIGTERM or is not ours to signal; '
                      'left running and NOT force-killed' % (kind, pid))
        if killed:
            jvms, tools, leaked, browsers = survey()

    busy_jvms = [j for j in jvms if j[2]]
    busy = bool(tools or busy_jvms or leaked or browsers)
    avail = available_mb()
    # ONE verdict for both the printed line and the exit code. Deriving the
    # two separately is how the gate ends up printing NO ROOM and exiting 0
    # on the same run, which reads to the loop as "the box is empty but I am
    # forbidden to build" -- a contradiction it cannot resolve.
    starved = sustained_no_room()

    if not args.quiet:
        if avail is not None:
            print('Memory: %.0f MB available of %.0f MB, no swap; '
                  'a build needs >= %d MB'
                  % (avail, _total_mb() or 0.0, MIN_AVAILABLE_MB))
        for label, group in (('BUSY (build tool present)', tools + busy_jvms),
                             ('LEAKED flutter_tester', leaked),
                             ('LEAKED headless chrome (this loop\'s render)',
                              browsers),
                             ('IDLE java/gradle (ignored)', [j for j in jvms if not j[2]])):
            if group:
                print('%s:' % label)
                for pid, cmd, busy_flag in group:
                    state = ('leak' if busy_flag is None
                             else 'busy' if busy_flag else 'idle')
                    print('  %-7d %-6s %s' % (pid, state, cmd))
        if busy:
            # The starvation line names the holder, and when the *only*
            # holder is our own leaked browser there is no other build at
            # all -- saying "another build holds the box" here would send a
            # reader hunting for a build that was never started.
            holders = tools + busy_jvms + leaked
            if starved and not holders:
                print('STARVED BY OUR OWN LEAK: nothing is building, and only '
                      '%.0f MB is reclaimable because of the leaked headless '
                      'Chrome listed above.' % avail)
            elif starved:
                print('BUSY and starved: another build holds the box while only '
                      '%.0f MB is reclaimable.' % avail)
            if browsers:
                print('A leaked headless Chrome from an earlier tick is holding '
                      '~%.0f MB. The loop\'s own render step is what leaves it '
                      'behind; run `python3 tool/build_gate.py --reap` to '
                      'clear it, then re-run this gate.'
                      % browser_mb(browsers))
            if leaked:
                print('A leaked flutter_tester (pid %s) from an earlier tick is '
                      'still holding the box; nothing else will clear it, '
                      'because its tool is gone. run `python3 '
                      'tool/build_gate.py --reap` to clear it, then re-run '
                      'this gate.'
                      % ', '.join(str(pid) for pid, _c, _b in leaked))
        elif starved:
            print('NO ROOM — nothing is building, but only %.0f MB is reclaimable '
                  'and a run of this suite was measured to bottom out at 1177 MB. '
                  'Do not start a build here.' % avail)
            # A verdict with no subject is not an answer. The line above says
            # the box is short of memory and stops: it names no holder, so the
            # reader is left hunting with `ps` for something the gate already
            # surveyed. Measured on 5 Oct, on this exact denial: ~700 MB sat
            # under a supervised `waha-lite` Chrome whose parent was alive,
            # which is exactly why `--reap` refused it -- and the only way to
            # learn that was ten process lookups by hand. The number was
            # right and the tick still could not act, because "NO ROOM" and
            # "NO ROOM because of a service you may not touch" call for
            # different decisions: one is worth retrying, the other is the box
            # sitting at its floor, and only the first ever clears on its own.
            shortfall = MIN_AVAILABLE_MB - (avail or 0.0)
            ball = balloon_mb()
            # Named BEFORE the census, and deliberately. When the balloon
            # covers the shortfall it *is* the explanation, and the process
            # list printed under it is residue -- so a reader who meets the
            # census first is sent to hunt for a process to kill. The
            # threshold is "could returning it clear the floor", which is a
            # checkable claim about the two numbers we hold.
            if ball is not None and ball >= shortfall:
                print('THE HOST IS HOLDING %.0f MB OF THIS BOX (`Balloon:` in '
                      '/proc/meminfo, %.0f MB of %s) -- more than the %.0f MB '
                      'the box is short. Nothing in this PID namespace owns '
                      'it. Only the hypervisor can give it back, so NO local '
                      'action clears this denial -- not --reap, not waiting, '
                      'and there is no process here you may usefully kill.'
                      % (ball, ball, _total_mb() or 0.0, shortfall))
            rows = holder_census()
            if rows:
                print('Largest memory holders (PSS, by process tree root):')
                for pid, mb, npids, comm, cwd in rows:
                    where = cwd if cwd else 'cwd unreadable'
                    print('  %-7d %6.0f MB  %2d proc  %-12s %s'
                          % (pid, mb, npids, comm[:12], where))
                top = max(r[1] for r in rows)
                if top >= shortfall:
                    print('None of these is a build this loop started: --reap only '
                          'clears processes the survey proves are this loop\'s own '
                          'leaked renders. If the top holder is a service, this '
                          'denial is the box being at its floor -- take a non-build '
                          'item and do not kill it.')
                else:
                    # The arm the census did not have. Every holder above the
                    # floor, combined, is smaller than the deficit, so this
                    # branch cannot be the cause and must not be offered as
                    # one -- and this is reachable with no `Balloon:` line at
                    # all, under a cgroup limit. Naming the largest process on
                    # a box it cannot account for is the same defect as naming
                    # no holder: both send the reader after the wrong thing.
                    print('NO process here accounts for this: the %.0f MB '
                          'shortfall is larger than every visible holder '
                          'combined (largest: %d, %.0f MB). Do not signal any '
                          'of them to free it -- exiting would not help. Take a '
                          'non-build item and re-check later.' % (
                              shortfall, top, top))

        else:
            print('CLEAR — no flutter/dart tool, no busy JVM, no leaked tester, '
                  'no leaked browser, and enough memory to run a build.')
        if not busy and not busy_jvms and jvms:
            idle = [j for j in jvms if not j[2]]
            if idle:
                print('(%d idle daemon(s) ignored — not consuming CPU.)' % len(idle))

    # Busy is busy. A leak also counts: the caller must not start a build on
    # top of it, and must not read a clean run as proof the box was free.
    #
    # No-room is folded into the same exit code on purpose. The loop's rule
    # is "if this is non-zero, do not build, take a non-build item instead",
    # and that is exactly the right advice whether the box is busy or just
    # too small. Two exit codes would force the caller to learn a second
    # rule, and a second rule is a second thing to get wrong.
    if busy:
        return 1
    return 1 if starved else 0


if __name__ == '__main__':
    sys.exit(main())
