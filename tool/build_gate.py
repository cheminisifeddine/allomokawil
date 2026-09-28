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
  * **clear** — anything else, including this script's own shell.

A leak is reported, not silently ignored: `--quiet` still fails, so the
caller cannot mistake "the script cleaned up" for "the box was free".
"""
import argparse
import os
import sys
import time

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


def survey():
    mine = _self_and_ancestors()
    tck = _tick_seconds()

    tools = []      # real flutter/dart tool: existence is enough
    jvms = []       # java/gradle: counted, but only "busy" if burning CPU
    leaked = []     # orphaned flutter_tester

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
        is_tool = ('bin/flutter' in cmd or 'flutter_tools' in cmd
                   or cmd.startswith('dart ') or '/dart ' in cmd
                   or comm == 'dart' and cmd == '')
        if not (is_tester or is_java or is_tool):
            continue

        before = _stat_fields(pid)
        is_tester_leaked = is_tester and _is_leaked_tester(pid)
        time.sleep(CPU_SPIN_SECONDS)
        after = _stat_fields(pid)
        busy = (before is not None and after is not None
                and (after - before) > 0)

        rec = (pid, cmd[:70], busy)
        if is_tester_leaked:
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

    return jvms, tools, leaked


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args(argv)

    jvms, tools, leaked = survey()
    busy_jvms = [j for j in jvms if j[2]]

    if not args.quiet:
        for label, group in (('BUSY (build tool present)', tools + busy_jvms),
                             ('LEAKED flutter_tester', leaked),
                             ('IDLE java/gradle (ignored)', [j for j in jvms if not j[2]])):
            if group:
                print('%s:' % label)
                for pid, cmd, busy in group:
                    print('  %-7d %-6s %s' % (pid, 'busy' if busy else 'idle', cmd))
        if not (tools or busy_jvms or leaked):
            print('CLEAR — no flutter/dart tool, no busy JVM, no leaked tester.')
        elif not busy_jvms and jvms:
            idle = [j for j in jvms if not j[2]]
            if idle:
                print('(%d idle daemon(s) ignored — not consuming CPU.)' % len(idle))

    # Busy is busy. A leak also counts: the caller must not start a build on
    # top of it, and must not read a clean run as proof the box was free.
    return 1 if (tools or busy_jvms or leaked) else 0


if __name__ == '__main__':
    sys.exit(main())
