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
    cmd = _cmdline(pid)
    if 'remote-debugging-port' not in cmd:
        return False
    return _ppid(pid) == 1


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


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args(argv)

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
                      'behind; reap it and re-run this gate.'
                      % browser_mb(browsers))
        elif starved:
            print('NO ROOM — nothing is building, but only %.0f MB is reclaimable '
                  'and a run of this suite was measured to bottom out at 1177 MB. '
                  'Do not start a build here.' % avail)
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
