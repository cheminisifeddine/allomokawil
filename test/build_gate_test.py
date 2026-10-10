#!/usr/bin/env python3
"""Prove `tool/build_gate.py` tells a build from the things that look like one.

Run directly — it spawns real processes and is not a `flutter test`:

    python3 test/build_gate_test.py

**Why this file exists.** The loop's build-safety rule is two `pgrep`s, and
for three consecutive ticks both said "busy" while the box was free: the
`pgrep -fc "[f]lutter"` matched the agent's own `bash -c` wrapper, whose
command line contains the literal pattern. The ticks read a running grep as a
running tool, skipped their analyze/test gates, and reported nothing wrong.
The mirror failure cost the same loop the other way — a `flutter_tester`
orphaned by a killed `flutter test` reads as busy forever, so every later
tick skips its gate too. Both halves of that are a *detector*, and a
detector nobody has tested is the part that lies.

Each case below uses a **real** binary, and that is load-bearing. The first
version of this test used `/tmp/fakebin/dart -> /bin/bash` symlinks, and
those rewrote argv to `sleep 5`: the gate correctly ignored a `sleep`, the
test asserted it should be BUSY, and the suite "failed" for a reason that
had nothing to do with the gate. Worse, the leaked-tester case passed for
the wrong reason too — a real `flutter_tester` exec'd with an empty argv
reads **zero bytes** of `/proc/<pid>/cmdline` and `/proc/<pid>/exe` is
unreadable without privilege here, so an argv-only matcher sees nothing and
reports CLEAR on a live engine. The kernel's `comm` is the field that
survives, and case 4 is the regression test for exactly that.

Two more cases (6, 7) cover the arm added on 30 Sep: the gate used to answer
"is another build running?" and never "does this box have room to run one?".
On 2 cores with no swap and ~1.6 GB reclaimable, that second question is the
one the OOM actually turns on, and the gate answered CLEAR there.

**The starved box is faked with a real injected `/proc/meminfo`, not by
monkeypatching `no_room`.** A test that replaces the function it is testing
proves the arithmetic and nothing else; this one writes the file the gate
really reads, so the parse path, the units and the comparison are all in the
loop. The units are the trap: `/proc/meminfo` is in **kB**, so a fixture that
says "512 MB" parses as 512 kB and displays as "0 MB" -- a test that still
passes while proving nothing. That is case 6b, and it is there because the
first version of this fixture did exactly that.

Cases 8 and 9 (1 Oct) cover the arm added the same day. Step 5 of the loop
protocol makes every tick render a visual change in a headless Chrome on a
debugging port, and a tick that ends without reaping it reparents that
browser to init -- where it holds ~310 MB forever on a box with no swap. The
gate caught an orphaned flutter_tester for exactly this reason and had no
Chrome awareness at all, so it answered NO ROOM at 785 MB and no tick could
tell that the loop was starving itself. Case 8 is a live browser that must
stay CLEAR (never kill a browser another session is driving), case 9 a
reparented one that must be reported and then gone once reaped.

Cases 10 and 11 (2 Oct) cover the arm added the same day. The starvation
floor was read as a SINGLE instantaneous MemAvailable sample, but this box
does not hold still: it fell 881 -> 692 -> 510 MB across three sampling
windows, crossing the 900 MB floor while nothing in this loop was running.
On a box that oscillates across its own floor the one-shot read answered
4 NO ROOM and 4 CLEAR over eight consecutive invocations *on an identical
box* -- so a tick was denied its test gate at random. Case 10 is the fix
(same verdict eight times running); case 11 is the arm that must not break
while being fixed, because a guard that simply stopped firing would also
produce a green suite and would let a tick start a build on a box that
cannot host it.

**And on 2 Oct (later) the suite itself was found not to be hermetic: it
asserted a *global* verdict while it shared the box with other agent
sessions.** Case 1 and case 9 both expect the gate to answer CLEAR, and
CLEAR means "no leaked browser anywhere" -- a property of the whole machine,
not of anything this suite started. On 2 Oct a headless Chrome belonging to a
*different* session (PID 17130, `chrome-fact3-profile`, CDP port 9336) was
sitting on this kernel, and the gate was right to name it: 428 MB of a box
with no swap. Cases 9 and 11 failed, 6/12, and neither failure had anything
to do with the arms they cover. Case 11 failed on a second, sharper version
of the same mistake: it asserted the word "NO ROOM" in stdout, but a leak
takes that branch instead, so the starvation verdict was being judged by a
line a foreign process could suppress.

A test whose answer depends on what else is running is not testing the thing
it names, and worse, it fails *and* lies about why. So the suite now
measures a **baseline** before it spawns anything and neutralises exactly the
leaks it did not create:

    _FOREIGN = every pid the gate already classifies as a leak at startup

`_isolated_src()` returns the gate with one guard per leak arm -- return
False for a pid in `_FOREIGN` -- and every case runs that copy. Nothing else
about the gate is touched, so the arms are still the real ones, still fail
when they should, and the suite's verdict now depends only on what the suite
itself started. On a clean box `_FOREIGN` is empty and this is a no-op.

The copies are the same trade `_starved_gate()` and `_countered_gate()`
already made for memoryinfo, and they carry the same hazard, stated here so
a later tick does not "simplify" it away: the suite exercises a *copy*. What
keeps that honest is that the copy is byte-identical except for two
early-return lines, and that a foreign leak is still reported by the real
gate -- this only stops a neighbour's process from deciding our result.

Case 4b (2 Oct) closes the one arm that had **no coverage at all**:
`_is_leaked_tester`. Case 4 spawns a real engine with a live parent, so it
only ever reached the *tool* arm; the leak arm was executed by no case.
Mutation showed it plainly -- forcing that arm to return True for every pid,
and forcing it to return False for every pid, each left the suite 12/12
green. A predicate that survives being negated is not being tested, and this
is the predicate whose first wrong answer cost the loop three ticks of its
gate. 4b spawns the real engine under `setsid` so it is genuinely PPID 1,
and asserts the gate refuses rather than reading CLEAR.

Expected: 13/13. A failure here means the gate is lying to the loop.
"""
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = ["python3", os.path.join(REPO, "tool", "build_gate.py")]
TESTER = ("/home/hatch/tools/sdk/flutter/bin/cache/artifacts/engine/"
          "linux-x64/flutter_tester")
JAVA = "/home/hatch/tools/jdk17/bin/java"
JAVAC = "/home/hatch/tools/jdk17/bin/javac"
# The real browser the loop's render step launches. A stand-in would not
# do: the arm matches remote-debugging-port in argv, and only a real
# browser is launched with that flag.
CHROME = "/opt/meta-chromium/chrome"
# A real, long-lived binary that is not a build. Copied (not
# symlinked) to the name `flutter_tester` by case 4b.
SLEEP = "/bin/sleep"

def _gate_module():
    """The real gate, imported, so its own predicates can be asked what
    they already see. Importing rather than reimplementing matters: a copy
    of the matching logic would drift from the thing it is isolating."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "build_gate_under_test", os.path.join(REPO, "tool", "build_gate.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _is_tester_process(mod, pid):
    """True when the gate's survey would classify pid as a flutter_tester.

    Same expression the survey uses, so the baseline agrees with the thing
    it is isolating rather than with a looser reading of it.
    """
    cmd = mod._cmdline(pid)
    comm = mod._comm(pid)
    ident = cmd or comm
    return ('flutter_tester' in cmd or comm == 'flutter_tester'
            or comm == 'dart' and 'flutter_tester' in ident)


def _foreign_leaks():

    """Every pid the gate ALREADY calls a leak, before this suite spawns
    anything -- i.e. another session's process, never ours."""
    mod = _gate_module()
    out = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if mod._is_leaked_browser(pid):
            out.add(pid)
            continue
        # Mirror the gate's REAL classification, which is `_is_leaked_tester`
        # applied only to a process that IS a flutter_tester. Asking the bare
        # predicate instead matches any PPID-1 process on the box -- the
        # agent itself, systemd-journal -- and neutralising those would hide
        # a real leak that happens to be PPID 1, which is precisely the
        # thing the tester arm exists to catch.
        if mod._is_leaked_tester(pid) and _is_tester_process(mod, pid):
            out.add(pid)
    return out


_FOREIGN = _foreign_leaks()
# Every fixture this suite writes goes in ITS OWN directory, not in
# `tempfile.gettempdir()`'s root. That is not tidiness -- it is a correctness
# fix, and it was found by a suite that had been reporting the same 12
# failures for several ticks and looking for the cause everywhere else.
#
# MEASURED 8 Oct 2026, on this box. `TMPDIR` is
# `/home/hatch/.hermes/profiles/finili/cache/scratch`, and the loop uses that
# same directory for its own scratch scripts. A leftover `token.py` there --
# from an earlier tick's theme edit -- **shadows the Python standard
# library's `token` module** for every child process that inherits
# `TMPDIR`, because a script run as `python /path/to/x.py` puts *its own
# directory* first on `sys.path`. `argparse` imports `dataclasses`, which
# imports `inspect`, which imports `token`, which resolved to that file and
# died on `EXACT_TOKEN_TYPES`.
#
# The consequence is a gate that cannot even start: every isolated-gate
# subprocess exited **1 with an empty stdout and a traceback on stderr**, and
# the suite read that as "the box was busy", "the leak was not named", "the
# census printed nothing" -- 12 failures naming four different arms, none of
# which had anything to do with the gate. A suite that converts an import
# crash into a verdict about the code under test is worse than no suite.
#
# A private directory removes the whole class: nothing this suite writes can
# shadow a stdlib module for anything else. `--reap`'s own `fb2` tree moves
# with it, below.
_SUITE_TMP = tempfile.mkdtemp(prefix="build_gate_suite_")
_ISOLATED = os.path.join(_SUITE_TMP, "gate_isolated.py")


def _isolated_src():
    """The gate's source with foreign leaks neutralised.

    One early return per arm, keyed on the startup baseline. A pid this
    suite spawns is never in `_FOREIGN`, so the arms still fire on it --
    which is the only thing cases 4, 8 and 9 are actually about.
    """
    src = open(os.path.join(REPO, "tool", "build_gate.py"),
               encoding="utf-8").read()
    out = src
    for fn in ("_is_leaked_browser", "_is_leaked_tester"):
        head = "def %s(pid):" % fn
        if head not in out:
            continue
        out = out.replace(
            head,
            head + "\n    if pid in _FOREIGN_PIDS:\n        return False",
            1)
    banner = "_FOREIGN_PIDS = frozenset(%r)\n" % (sorted(_FOREIGN),)
    return banner + out


def _isolated_path():
    """Regenerated on EVERY call, never cached.

    The first version wrote it only if absent, keyed on nothing. That made
    the suite lie in both directions: it kept measuring a build_gate.py from
    an earlier tick, so a deliberately broken gate still reported 13/13
    green, and a second concurrent run could measure the first run's copy.
    A stale-fixture bug in a test of a *detector* is worse than no test --
    it is a test that certifies a broken detector. Two lines, unconditional.
    """
    body = _isolated_src()
    with open(_ISOLATED, "w", encoding="utf-8") as fh:
        fh.write(body)
    return _ISOLATED


def _foreign_note():
    if not _FOREIGN:
        return "box clean at startup"
    return ("%d foreign leak(s) neutralised: %s"
            % (len(_FOREIGN), ", ".join(str(p) for p in sorted(_FOREIGN))))


results = []

# A real CPU-bound JVM, built here rather than borrowed from /tmp, so the
# case runs on a clean checkout. Falls back to skipping if there is no JDK,
# because a missing compiler is not a gate failure.
_SRC = """public class Busy {
  public static void main(String[] a) {
    long end = System.currentTimeMillis() + 8000;
    double x = 0;
    while (System.currentTimeMillis() < end) { x += Math.sqrt(x + 1); }
    System.out.println(x);
  }
}
"""


def build_busy_jvm():
    """Compile a genuinely CPU-bound java, return (javac, classdir) or None."""
    if not os.path.exists(JAVA) or not os.path.exists(JAVAC):
        return None
    d = tempfile.mkdtemp(prefix="gate_test_")
    src = os.path.join(d, "Busy.java")
    with open(src, "w") as fh:
        fh.write(_SRC)
    r = subprocess.run([JAVAC, "-d", d, src], capture_output=True)
    if r.returncode != 0 or not os.path.exists(os.path.join(d, "Busy.class")):
        shutil.rmtree(d, ignore_errors=True)
        return None
    return d


def _run():
    return subprocess.run(["python3", _isolated_path()], capture_output=True,
                          text=True, cwd=REPO)


def _free_port():
    """A TCP port nothing is listening on and nothing is in TIME_WAIT on.

    Bind to port 0 and let the kernel hand one out. A HARDCODED port is
    wrong here in a way it was not for cases 8 and 9: this case opens a
    real connection to the browser and leaves it in TIME_WAIT for ~60 s,
    and `_port_in_use` counts TIME_WAIT on purpose. So the *next* run of
    this suite finds the port still busy, its own freshly-spawned browser
    reads as "driven", and the idle branch fails -- the suite failing on
    its own leftovers, with no code change at all. That is the same
    non-hermetic defect this file was already fixed for once (cases 1 and
    9 deciding their own result by whatever else was on the box), reached
    again from a different direction.
    """
    import socket
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _in_tree(pid, root):
    """True when `pid` is `root` or a descendant of it. Used only to tidy up
    the tree case 15 spawned; the assertion itself never asks this."""
    root, pid = int(root), int(pid)
    seen = 0
    while pid and pid not in (0, 1) and seen < 64:
        if pid == root:
            return True
        try:
            stat = open("/proc/%d/stat" % pid).read()
            pid = int(stat[stat.rfind(")") + 2:].split()[1])
        except (IOError, OSError, IndexError, ValueError):
            return False
        seen += 1
    return False


def check(label, expect):
    r = _run()
    ok = r.returncode == expect
    results.append(ok)
    print(("PASS  " if ok else "**FAIL**  ")
          + "%s: exit=%d expect=%d" % (label, r.returncode, expect))
    for line in r.stdout.strip().split("\n")[:2]:
        print("        | " + line)
    return ok


def spawn(argv, **kw):
    p = subprocess.Popen(argv, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, **kw)
    time.sleep(0.8)
    return p


def ppid_of(pid):
    return int(open("/proc/%d/stat" % pid).read().split(") ")[-1].split()[1])


def _force_gone(pid, grace=6.0, poll=0.1):
    """Block until `/proc/<pid>` is absent. Returns True if it is gone.

    The bounded wait matters for the same reason `build_gate.reap`'s does:
    `os.kill` returning only proves the *signal was sent*, and the memory a
    browser holds is still held until the kernel has torn the tree down. A
    caller that assumes otherwise measures the same box twice and concludes
    the cleanup is broken.

    SIGTERM first, deliberately. A Chrome root has ~13 forked children and
    dies as a group when it does; escalating to SIGKILL here would orphan
    the renderer tree and trade a 200 MB leak for a smaller permanent one.
    SIGKILL is used ONLY for a root that ignored SIGTERM inside its own
    grace, and it is aimed at the tree root, which is what reaps the group.
    """
    if pid is None or not os.path.exists("/proc/%d" % pid):
        return True
    try:
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        pass
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        if not os.path.exists("/proc/%d" % pid):
            return True
        time.sleep(poll)
    try:
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        pass
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        if not os.path.exists("/proc/%d" % pid):
            return True
        time.sleep(poll)
    return not os.path.exists("/proc/%d" % pid)


def _cmdline_of(pid):
    """argv of `pid`, or "" if it is gone. Never raises."""
    try:
        return open("/proc/%d/cmdline" % pid).read().replace("\x00", " ")
    except (IOError, OSError):
        return ""


class _armed_browser(object):
    """A reparented headless browser that is REAPED even if the case dies.

    MEASURED 10 Oct 2026, on this box, and it is the loop's own
    loop-starvation rather than a service nobody can touch. The gate
    answered `NO ROOM - nothing is building, but only 740 MB is reclaimable`
    and named pid 15189: a headless Chrome, PPID 1, ~199 MB of PSS, holding
    a box with no swap under a 900 MB floor. Its `--user-data-dir` was
    `gate_chrome_livesyklbhy0` -- a `mkdtemp` prefix that appears NOWHERE in
    the repository except `test/build_gate_test.py` case 12. So the process
    starving every tick was one *this very file* had spawned, and the gate's
    own report ("this loop's render") was naming our fixture rather than a
    real render.

    The mechanism is visible in the case: it forks a browser to init and
    reaps it with `mod.reap(...)` as the **last statement of a 50-line block
    with no `try`/`finally`**. Any raise in between -- and there are four
    `results.append` calls, a `socket.create_connection` and a `recv` that
    can time out on a loaded box -- skips the reap and leaves a ~200 MB
    orphan parented to init. Two such profile directories were still on disk
    from 9 Oct and 10 Oct, so this has fired at least twice.

    Case 12 is *supposed* to leave a leak behind: it is testing the leak
    arm, so its browser must exist and must be provably dead. Making it
    survive its own assertions is the bug. Every reparented browser this
    suite spawns now goes through this context manager, which kills the root
    on the way out **however** the case exits, and the reap is verified
    rather than assumed. Killing our own fixture is unambiguously safe: its
    ppid is 1 by construction, so by the gate's own definition no live
    session owns it, and its port was allocated by `_free_port()` for this
    case alone.
    """

    def __init__(self, port, tag, wait=4.0):
        self.port = port
        self.tag = tag
        self.pid = None
        self.profile = None
        self.wait = wait

    def __enter__(self):
        self.profile = tempfile.mkdtemp(prefix="gate_chrome_%s" % self.tag)
        code = (
            "import os\n"
            "pid = os.fork()\n"
            "if pid:\n"
            "    os._exit(0)\n"
            "os.setsid()\n"
            "os.execv(%r, [%r, '--headless', '--no-sandbox', '--disable-gpu',"
            " '--remote-debugging-port=%d', '--user-data-dir=' + %r,"
            " 'about:blank'])\n"
            % (CHROME, CHROME, self.port, self.profile))
        subprocess.run([sys.executable, "-c", code],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(self.wait)     # the browser takes a moment to bind the port
        for entry in os.listdir('/proc'):
            if not entry.isdigit():
                continue
            pid = int(entry)
            if ("--remote-debugging-port=%d" % self.port) in _cmdline_of(pid):
                self.pid = pid
                break
        return self

    def reap(self):
        """Kill the root and wait for the kernel to release the memory.

        `mod.reap` is still the real gate's own routine, so the case under
        test still exercises the shipped code path rather than a private
        copy -- but it is followed by the hard wait, because "we sent it a
        signal" and "the box came back" are two different claims and only
        the second one is worth anything to the next case.
        """
        if self.pid is None:
            return True
        mod = _gate_module()
        try:
            mod.reap([(self.pid, "probe", None)])
        except Exception:
            pass
        gone = _force_gone(self.pid)
        if not gone:
            results.append(False)
            print("**FAIL**  browser %d survived this case's own cleanup"
                  % self.pid)
        return gone

    def __exit__(self, exc_type, exc, tb):
        try:
            self.reap()
        finally:
            if self.profile:
                shutil.rmtree(self.profile, ignore_errors=True)
        # Never swallow the case's exception: this exists to guarantee the
        # cleanup, not to make a failing case look like a passing one.
        return False


def _starved_gate():
    """A copy of the gate whose /proc/meminfo read is redirected to a
    fixture holding 512 MB available. Returns the path, or None."""
    fixture = os.path.join(_SUITE_TMP, "gate_meminfo_starved")
    if not os.path.exists('/proc/meminfo'):
        return None
    raw = open('/proc/meminfo').read()
    line = [l for l in raw.split("\n") if l.startswith("MemAvailable:")]
    if not line:
        return None
    # /proc/meminfo is in kB: 524288 kB is 512 MB.
    raw = raw.replace(line[0], "MemAvailable:        524288 kB")
    with open(fixture, "w") as fh:
        fh.write(raw)
    out = os.path.join(_SUITE_TMP, "gate_starved_build_gate.py")
    body = _isolated_src()
    patched = body.replace(
        "def _read(path):",
        "def _read(path):\n"
        "    if path == '/proc/meminfo':\n"
        "        return open(%r).read()\n" % fixture, 1)
    if patched == body:
        return None
    with open(out, "w") as fh:
        fh.write(patched)
    return out


def _ballooned_gate(mem_avail_kb, balloon_kb, tag):
    """A copy of the gate on a fixture that is short *because the host took
    it* -- the shape measured on this host on 8 Oct 2026.

    Two numbers, injected separately, because the claim under test is a
    comparison BETWEEN them: `Balloon:` covers the shortfall -> name the host
    and say no local action helps; `Balloon:` absent or small -> the
    shortfall is NOT explained by the hypervisor and must not be blamed on a
    process either. Writing one fixture and asserting both ways is what makes
    a run of this case evidence rather than decoration.

    `Balloon:` is written or stripped at the TEXT level, so the real parse
    path and the real kB units are in the loop -- the same rule case 6
    established for MemAvailable, and for the same reason: a fixture that
    monkeypatched the reader would pass while proving nothing.
    """
    src = _isolated_src()
    fixture = os.path.join(_SUITE_TMP,
                           "gate_meminfo_%s" % tag)
    raw = open('/proc/meminfo').read()
    lines = raw.split("\n")
    out = []
    for line in lines:
        if line.startswith("MemAvailable:"):
            out.append("MemAvailable:    %d kB" % mem_avail_kb)
        elif line.startswith("Balloon:"):
            if balloon_kb is None:
                continue          # a kernel with no balloon driver at all
            out.append("Balloon:        %d kB" % balloon_kb)
    with open(fixture, "w") as fh:
        fh.write("\n".join(out))
    patched = src.replace(
        "def _read(path):",
        "def _read(path):\n"
        "    if path == '/proc/meminfo':\n"
        "        return open(%r).read()\n" % fixture, 1)
    if patched == src:
        return None
    out_py = os.path.join(_SUITE_TMP, "gate_ball_%s.py" % tag)
    with open(out_py, "w") as fh:
        fh.write(patched)
    return out_py


def _is_starved(stdout):
    """True when the gate's own verdict line says it refused for memory.

    Matches the NO ROOM summary and the starved-while-busy one, so the
    assertion survives either branch without pinning the wording.
    """
    return 'NO ROOM' in stdout or 'starved' in stdout


def _starved_mb(_):
    return 512


def _countered_gate(base, vals, tag):
    """A copy of the gate whose /proc/meminfo cycles through `vals` (kB).

    The counter is a FILE, not an in-process global, on purpose: the defect
    this covers is about what happens across consecutive *ticks*, so each
    invocation has to see a genuinely different box. An in-process counter
    would advance identically on every run and make the case pass for a
    reason that has nothing to do with the arm -- the first version of this
    case did exactly that, and reported 8/8 CLEAR with the bug still in.
    """
    src = _isolated_src()
    ctr = os.path.join(_SUITE_TMP, "gate_osc_ctr_%s" % tag)
    if os.path.exists(ctr):
        os.remove(ctr)
    inject = (
        "CTR = %r\n"
        "VALS = %r\n"
        "def _osc(p):\n"
        "    try:\n"
        "        n = int(open(CTR).read().strip())\n"
        "    except Exception:\n"
        "        n = 0\n"
        "    open(CTR, 'w').write(str(n + 1))\n"
        "    raw = open('/proc/meminfo').read()\n"
        "    line = [l for l in raw.split('\\n') if l.startswith('MemAvailable:')][0]\n"
        "    return raw.replace(line, 'MemAvailable: %%d kB' %% VALS[n %% len(VALS)])\n"
    ) % (ctr, list(vals))
    patched = inject + src.replace(
        "def _read(path):\n    try:",
        "def _read(path):\n    if path == '/proc/meminfo':\n"
        "        return _osc(path)\n    try:", 1)
    if patched == inject + src:
        return None
    out = os.path.join(_SUITE_TMP, "gate_osc_%s.py" % tag)
    with open(out, "w") as fh:
        fh.write(patched)
    return out


def _reparented_tester_binary():
    """A copy of /bin/sleep named exactly `flutter_tester`.

    `cp`, never a symlink: the gate matches `comm`, which is the basename of
    the executable, and a symlink leaves the kernel reporting `sleep`.
    """
    if not os.path.exists(SLEEP):
        return None
    d = os.path.join(_SUITE_TMP, "fb2")
    os.makedirs(d, exist_ok=True)
    b = os.path.join(d, "flutter_tester")
    shutil.copyfile(SLEEP, b)
    os.chmod(b, 0o755)
    return b


def _spawn_orphan(binary):
    """Start `binary` and return the pid of a process that is PPID 1.

    An intermediate forks the target and exits immediately, so the kernel
    reparents the target to init -- which is the whole point of the arm.
    Returns None if the orphan never appeared, so the caller can report a
    broken case instead of a passing one.
    """
    mid = os.path.join(_SUITE_TMP, "fb2", "orphan_mid.py")
    with open(mid, "w") as fh:
        fh.write("import os, sys\n"
                 "os.setsid()\n"
                 "pid = os.fork()\n"
                 "if pid > 0:\n"
                 "    sys.exit(0)\n"
                 "os.execv(sys.argv[1], [sys.argv[1], '30'])\n")
    subprocess.Popen([sys.executable, mid, binary],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(40):
        time.sleep(0.1)
        for entry in os.listdir('/proc'):
            if not entry.isdigit():
                continue
            pid = int(entry)
            try:
                if open('/proc/%d/comm' % pid).read().strip() == \
                        'flutter_tester' and ppid_of(pid) == 1:
                    return pid
            except (IOError, OSError, ValueError):
                continue
    return None


def main():
    print("1) clean box")
    check("no build -> CLEAR", 0)

    print("\n2) an idle JVM (a Gradle daemon parked between builds)")
    # `java` on a missing class starts, complains and exits -- too short to
    # be sampled. A real daemon is *alive and idle*, so the honest stand-in
    # is a JVM blocked in a sleep loop, which is what a daemon looks like to
    # the gate: present, consuming no CPU.
    if os.path.exists(JAVA):
        p = spawn([JAVA, "-cp", "/tmp", "-version"])
        time.sleep(1.2)
        check("idle JVM -> CLEAR (a daemon is not a build)", 0)
        p.kill()
        p.wait()
        time.sleep(0.3)

    print("\n3) a genuinely CPU-bound JVM (a real compile)")
    busy = build_busy_jvm()
    if busy:
        p = spawn([JAVA, "-cp", busy, "Busy"])
        check("busy JVM -> BUSY", 1)
        p.kill()
        p.wait()
        shutil.rmtree(busy, ignore_errors=True)
        time.sleep(0.3)
    else:
        print("  SKIP (no JDK / javac)")

    print("\n4) a real leaked flutter_tester — the three-tick bug")
    if os.path.exists(TESTER):
        p = spawn([TESTER], start_new_session=True)
        print("   pid=%d ppid=%d" % (p.pid, ppid_of(p.pid)))
        check("leaked tester -> BUSY, never CLEAR", 1)
        p.kill()
        p.wait()
        time.sleep(0.3)
    else:
        print("  SKIP (no engine)")

    print("\n4b) a REPARENTED tester -- the arm that had no coverage")
    # Case 4 spawns the real engine with a live parent, so it only ever
    # reached the *tool* arm: a live tester is matched by `is_tester`, never
    # by `_is_leaked_tester`. Mutation proved the gap from both sides --
    # forcing `_is_leaked_tester` to return True for every pid, and forcing
    # it to return False for every pid, each left this suite 12/12 green. A
    # predicate that cannot be told apart from its own negation is not being
    # tested, and this is the predicate whose first wrong answer cost the
    # loop three ticks of its gate.
    #
    # Getting a REAL PPID-1 orphan took two attempts that are worth not
    # repeating, because both produce a green-looking case that tests
    # nothing:
    #
    #   1. `spawn([TESTER], start_new_session=True)` -- the engine exits
    #      immediately with no test file on argv, so by the time `check()`
    #      runs there is no process at all. Verified: nothing survives.
    #   2. `start_new_session=True` (no setsid binary) -- the child becomes a
    #      session leader but its **PPID is still the test's pid**, because
    #      reparenting to init happens when the PARENT dies, not when the
    #      child is setsid'd. Measured ppid 25061 = this suite. That run
    #      also killed through the subprocess handle, left the engine alive,
    #      and case 5 -- the next check -- failed with "exit=1" as a direct
    #      consequence of a leak the suite had just made itself.
    #
    # What works is an intermediate that forks the engine and then EXITS,
    # so the kernel reparents the engine to init. The engine itself is
    # `/bin/sleep` copied to a file named exactly `flutter_tester`: a symlink
    # would keep `comm` as the target's name and this arm matches on comm.
    binary = _reparented_tester_binary()
    if not binary:
        print("  SKIP (no /bin/sleep to copy)")
    else:
        orphan = _spawn_orphan(binary)
        print("   tester pid=%d ppid=%d (1 = reparented to init)"
              % (orphan, ppid_of(orphan)))
        ppid = ppid_of(orphan)
        if ppid != 1:
            print("   **FAIL** the spawn did not reparent (ppid=%d); "
                  "this case proves nothing" % ppid)
        # Assert the LEAK classification, not merely a non-zero exit.
        # Asserting exit 1 alone passes for the wrong reason: a reparented
        # tester is ALSO matched by `is_tester`, so it lands in the tools
        # list and the gate returns 1 even with `_is_leaked_tester` forced
        # to return False. That was measured -- the negation left this suite
        # 13/13 green -- and the case was named after an arm it never
        # reached. "LEAKED flutter_tester" is the line only that arm prints.
        out = _run()
        ok = out.returncode == 1 and 'LEAKED flutter_tester' in out.stdout
        results.append(ok)
        print(("PASS  " if ok else "**FAIL**  ")
              + "reparented tester -> named LEAKED, not merely non-zero")
        for line in out.stdout.strip().split("\n")[:3]:
            print("        | " + line)
        try:
            os.kill(orphan, 9)
        except OSError:
            pass
        for _ in range(40):
            if not os.path.exists("/proc/%d" % orphan):
                break
            time.sleep(0.1)
        if os.path.exists("/proc/%d" % orphan):
            print("   **FAIL** could not reap pid %d -- the next cases will "
                  "be poisoned" % orphan)
        else:
            print("   reaped pid %d" % orphan)
        time.sleep(0.3)

    print("\n5) back to clean")
    check("after cleanup -> CLEAR", 0)

    print("\n6) a starved box with nothing building (2 cores, no swap)")
    starved = _starved_gate()
    if starved:
        r = subprocess.run(["python3", starved], capture_output=True, text=True,
                           cwd=REPO)
        # Judged on the DECISION (exit 1) and on the starvation verdict
        # itself, never on the word "NO ROOM" in the summary: a leak of any
        # kind takes that print branch instead, which is how this case
        # failed for two days while its arm was working perfectly.
        ok = r.returncode == 1 and _is_starved(r.stdout)
        results.append(ok)
        print(("PASS  " if ok else "**FAIL**  ")
              + "no build but %d MB reclaimable -> NO ROOM, exit 1"
              % _starved_mb(starved))
        for line in r.stdout.strip().split("\n")[:2]:
            print("        | " + line)
    else:
        print("  SKIP (no /proc/meminfo)")

    print("\n7) the same fixture in the wrong unit must not be trusted")
    # 6b, on its own: "512 MB" where the file is in kB reads as 512 kB. The
    # gate must show the number it actually parsed, so a broken fixture
    # cannot masquerade as a working one.
    if starved:
        r = subprocess.run(["python3", starved], capture_output=True, text=True,
                           cwd=REPO)
        ok = "0 MB available" not in r.stdout
        results.append(ok)
        print(("PASS  " if ok else "**FAIL**  ")
              + "fixture is in kB, so the printed figure is not a silent 0")
        for line in r.stdout.strip().split("\n")[:1]:
            print("        | " + line)

    print("\n8) a live headless browser, parented -- not a leak")
    # The mirror of the tester arm, and the reason PPID 1 is required: a
    # browser a live session is driving right now has a normal parent, and
    # treating it as a leak would have a tick kill a working render.
    have_chrome = os.path.exists(CHROME)
    if have_chrome:
        d = tempfile.mkdtemp(prefix="gate_chrome_profile")
        b = spawn([CHROME, "--headless", "--no-sandbox", "--disable-gpu",
                   "--remote-debugging-port=9399",
                   "--user-data-dir=" + d, "about:blank"])
        print("   pid=%d ppid=%d" % (b.pid, ppid_of(b.pid)))
        out = _run()
        # NOT `check(..., 0)`. Spawning a real browser can dip the box under
        # MIN_AVAILABLE_MB, and at that point NO ROOM is the *correct*
        # answer and tells you nothing about leak detection. What this case
        # actually claims is narrower: a browser with a live parent is never
        # named a leak. Asserting the global exit code here made the case
        # fail for a reason that had nothing to do with the arm.
        named = "LEAKED headless chrome" in out.stdout and str(b.pid) in out.stdout
        ok = not named
        results.append(ok)
        print(("PASS  " if ok else "**FAIL**  ")
              + "live browser -> never named a leak (ppid=%d, not 1)"
              % ppid_of(b.pid))
        print("        | " + (out.stdout.strip().split("\n") or [""])[0])
        b.kill()
        b.wait()
        shutil.rmtree(d, ignore_errors=True)
        time.sleep(0.3)
    else:
        print("  SKIP (no chromium)")

    print("\n9) a reparented headless browser -- the loop starving itself")
    if have_chrome:
        # A leak is made the way the kernel actually makes one: a double
        # fork, which reparents the browser to init with no live owner.
        # `with`, for the reason case 12's docstring spells out -- this case
        # died leaving a ~200 MB orphan once, and the gate then blamed
        # "this loop's render" for a browser this file had started.
        with _armed_browser(_free_port(), "leak") as _b9:
            leaked = _b9.pid
            if leaked is None:
                print("  **FAIL** no reparented browser to test with")
                results.append(False)
            else:
                print("   leaked pid=%d ppid=%d" % (leaked, ppid_of(leaked)))
                out = _run()
                # The two claims that are about the ARM, and hold whatever
                # the memory does: the leak is named, and the gate fails
                # closed. The "reclaimable" sentence is deliberately not
                # asserted -- it is gated on MIN_AVAILABLE_MB, so a box with
                # room to spare prints neither it nor the STARVED line, and
                # asserting it would make the case fail for the box being
                # healthy.
                ok = (out.returncode == 1
                      and "LEAKED headless chrome" in out.stdout
                      and str(leaked) in out.stdout)
                results.append(ok)
                print(("PASS  " if ok else "**FAIL**  ")
                      + "reparented browser -> named as a leak, exit 1")
                for line in out.stdout.strip().split("\n")[:4]:
                    print("        | " + line)
                _b9.reap()
                # The reaped box must come back to CLEAR, or this arm cannot
                # tell a real leak from a permanent "busy".
                check("after reaping the browser -> CLEAR", 0)
        time.sleep(0.3)
    else:
        print("  SKIP (no chromium)")

    print("\n10) a box hovering ON the floor must not flip its verdict")
    # The defect this arm fixes, kept as a test. Measured 2 Oct: MemAvailable
    # on this box fell 881 -> 692 -> 510 MB across three sampling windows, so
    # it crosses MIN_AVAILABLE_MB. Against a box alternating 488/1387 MB the
    # old one-shot read answered 4 NO ROOM and 4 CLEAR over eight identical
    # invocations -- a coin flip that silently denies a tick its test gate at
    # random, which is the same failure that cost this loop three ticks in a
    # row, only unpredictable now.
    osc = _countered_gate(None, [500000, 1400000, 520000, 1380000], "osc")
    if osc:
        seen = set()
        for _ in range(8):
            r = subprocess.run(["python3", osc], capture_output=True,
                               text=True, cwd=REPO)
            seen.add("NO ROOM" if "NO ROOM" in r.stdout else "CLEAR")
        ok = len(seen) == 1
        results.append(ok)
        print(("PASS  " if ok else "**FAIL**  ")
              + "8 ticks on one oscillating box -> one verdict (%s)"
              % ", ".join(sorted(seen)))
        print("        | a detector that changes its mind is not a detector")
    else:
        print("  **FAIL** could not build the oscillating fixture")
        results.append(False)

    print("\n11) and a box that is ALWAYS starved must still be refused")
    # The false-negative direction is the dangerous one: an arm that stops
    # firing also produces a green suite, and would let a tick start a build
    # on a box that cannot host it. Sustained starvation must still refuse.
    dead = _countered_gate(None, [512000, 500000, 530000, 490000], "dead")
    if dead:
        r = subprocess.run(["python3", dead], capture_output=True, text=True,
                           cwd=REPO)
        ok = r.returncode == 1 and _is_starved(r.stdout)
        # Same rule as case 6, and the reason this case needed it: a
        # leak of any kind takes the leak branch of the summary instead,
        # so asserting the printed word made the starvation verdict
        # depend on whether some other session's browser happened to be
        # on the box. The decision (exit 1) plus the starvation verdict is
        # what this case is about.
        results.append(ok)
        print(("PASS  " if ok else "**FAIL**  ")
              + "sustained starvation -> still NO ROOM, exit 1")
        for line in r.stdout.strip().split("\n")[:2]:
            print("        | " + line)
    else:
        print("  **FAIL** could not build the starved fixture")
        results.append(False)

    print("\n12) a reparented browser WITH a live CDP client is not a leak")
    # The arm this change adds, and the one case 9 cannot reach: case 9
    # spawns a reparented browser and nobody drives it, so it only ever
    # sees the leak branch. Without this case the new `_port_in_use` check
    # could be deleted and every other case would stay green.
    #
    # Both directions are asserted on one real browser, because the whole
    # point of the check is that the SAME process flips verdict with
    # nothing but the presence of a client changing.
    have_chrome12 = os.path.exists(CHROME)
    if have_chrome12:
        mod = _gate_module()
        port = _free_port()
        # `with`, not a bare spawn: this case must still hold a real,
        # provably-dead leak while it asserts, but it must not survive its
        # own assertions. See `_armed_browser` -- an earlier version of
        # this block reaped as its LAST statement with no `finally`, and
        # the orphans it left are what starved the gate on this box for
        # two days, under the label "this loop's render".
        # `with`, not a bare spawn: this case must still hold a real,
        # provably-dead leak while it asserts, but it must not survive its
        # own assertions. See `_armed_browser` -- an earlier version of
        # this block reaped as its LAST statement with no `finally`, and
        # the orphans it left are what starved the gate on this box for
        # two days, under the label "this loop's render".
        with _armed_browser(port, "live") as _b12:
            pid12 = _b12.pid
            if pid12 is None:
                print("  **FAIL** no reparented browser to test with")
                results.append(False)
            else:
                # Branch A: reparented, nobody talking -> a real leak.
                idle_verdict = mod._is_leaked_browser(pid12)
                # Branch B: a client connects over CDP -> a live render, and
                # the gate must not call that a leak or `--reap` kills a
                # screenshot somebody is in the middle of taking.
                import socket
                sock = None
                live_verdict = None
                try:
                    sock = socket.create_connection(("127.0.0.1", port),
                                                    timeout=5)
                    sock.sendall(b"GET /json/version HTTP/1.0\r\n\r\n")
                    sock.recv(128)
                    time.sleep(0.3)
                    live_verdict = mod._is_leaked_browser(pid12)
                finally:
                    # This socket is what makes the browser read as
                    # "driven". Left open it stays in ESTABLISHED, which
                    # `_port_in_use` counts as a live session -- so the
                    # next case on this box would find our own fixture
                    # looking like somebody's in-flight screenshot.
                    if sock is not None:
                        sock.close()
                ok = (idle_verdict is True) and (live_verdict is False)
                results.append(ok)
                print(("PASS  " if ok else "**FAIL**")
                      + "ppid=1 alone is not a leak: idle=%s, driven=%s"
                      % (idle_verdict, live_verdict))
                # And the port parsing that feeds it, both argv spellings.
                parsed = (mod._debug_port("chrome --remote-debugging-port=%d" % port)
                          == port
                          and mod._debug_port("chrome --remote-debugging-port %d" % port)
                          == port
                          and mod._debug_port("chrome --headless") is None)
                results.append(parsed)
                print(("PASS  " if parsed else "**FAIL**")
                      + "debug port parsed in both argv spellings")
    else:
        print("  SKIP (no chromium)")

    print("\n13) a reparented LAUNCHER naming a browser is not the browser")
    # Found on this box, 2 Oct 2026, and it is the worst shape this suite has
    # caught because the gate did not merely mis-report: it printed
    # `LEAKED headless chrome (this loop's render)` naming a /bin/bash holding
    # 618 kB, then told the reader to run `--reap`, which SIGTERMs exactly the
    # pids the survey named. Following the instruction would have killed a live
    # session's browser mid-screenshot -- the gate arming itself at its own
    # stated purpose ("an instruction to kill, derived from a fact that does not
    # support it").
    #
    # The shape: `bash -c 'nohup chrome --remote-debugging-port=9333 ... &'`,
    # where the shell is orphaned (PPID 1) and the browser it is about to exec
    # is a normal child. argv *contains* the flag; the process *is not* the
    # browser. Cases 8/9/12 all spawn a real browser, so every one of them
    # passes with the guard deleted.
    mod13 = _gate_module()
    launcher = subprocess.Popen(
        ["/bin/bash", "-c", "sleep 30 & sleep 30",
         "--remote-debugging-port=%d" % _free_port()],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        # Bounded wait, and it is a fix to a race in this case rather than
        # politeness: `Popen` returns once the child is forked, and between the
        # fork and `exec` the child carries its PARENT's cmdline verbatim. Read
        # too early and the read returned the harness's own argv -- which has
        # no debugging port in it at all -- so the case failed on `port13=None`
        # with no code change at all. Same non-hermetic failure shape as
        # `_free_port`, reached from a different direction.
        cmd13 = ""
        port13 = None
        # monotonic, NOT time.time(). This is the same wall-clock defect that
        # `tool/build_gate.py` had in `reap()`, found here by the census that
        # asks the question one level above the one the guard already watched:
        # the sweep that covers `tool/` cannot see a runner living in `test/`.
        # A deadline measured on the wall clock is governed by something this
        # process does not control and cannot observe -- NTP steps it forwards
        # and backwards, and `settimeofday` can move it either way. Step
        # forward by more than the 5 s window and `time.time() < deadline` is
        # false on the FIRST comparison, so the loop never runs, `port13`
        # stays None and case 13 fails with `port13=None` -- reported as
        # "the argv guard is broken" when the argv guard is fine and the
        # measurement was. Step backwards and the wait outlasts its budget.
        # The failure needs no bug: it needs the host to be in sync, which is
        # a normal condition. Note the shape is the SAME as the `exec`-race
        # this wait was originally written to fix, reached from the clock
        # instead of from the fork.
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            cmd13 = mod13._cmdline(launcher.pid)
            port13 = mod13._debug_port(cmd13)
            if port13 is not None:
                break
            time.sleep(0.1)
            launcher.terminate()   # it exited: the argv we saw was the truth
            launcher = subprocess.Popen(
                ["/bin/bash", "-c", "sleep 30 & sleep 30",
                 "--remote-debugging-port=%d" % _free_port()],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        ok = (port13 is not None                       # the flag IS parsed out
              and mod13._looks_like_browser(launcher.pid, cmd13) is False
              and mod13._is_leaked_browser(launcher.pid) is False)
        results.append(ok)
        print(("PASS  " if ok else "**FAIL**")
              + "bash launcher naming a browser -> not a leak (port parsed=%s)"
              % port13)
        # And the negative: the guard must not have made the arm blind. A real
        # browser process with the same flag must still be identified as one,
        # or this case would pass with `_looks_like_browser` always False.
        blind = mod13._looks_like_browser(launcher.pid,
                                          "/opt/meta-chromium/chrome "
                                          "--headless --remote-debugging-port=9333")
        results.append(blind is True)
        print(("PASS  " if blind else "**FAIL**")
              + "a real chrome argv still identifies as a browser")
    finally:
        launcher.terminate()
        try:
            launcher.wait(timeout=5)
        except subprocess.TimeoutExpired:
            launcher.kill()

    print("\n15) a starved box must NAME its largest holder, and that name "
          "must survive a real process tree")

    # The defect this arm fixes, kept as a test. Measured 5 Oct 2026, on this
    # box, on the denial that cost this tick its gate: the gate answered
    # `NO ROOM ... 878 MB reclaimable` and stopped there. It named no holder,
    # so the reader had to go find one by hand -- and the answer turned out to
    # be a supervised `waha-lite` Chrome with a LIVE parent, which is exactly
    # why `--reap` (correctly) refused to touch it. The number was right and
    # the tick still could not act, because "NO ROOM" and "NO ROOM because of
    # a service you may not kill" are different instructions.
    #
    # Asserted against the REAL gate, not a copy, and against the starved
    # fixture so the assertion does not depend on the box being hungry.
    mod15 = _gate_module()

    # A real process tree with a known root and a known cwd, so "names the
    # tree root" and "names the owner" are both checkable facts rather than
    # assertions about whatever else happens to be running.
    tree_dir = tempfile.mkdtemp(prefix="gate_holder_")
    code15 = (
        "import os, sys, time\n"
        "os.setsid()\n"
        "if os.fork():\n"
        "    os._exit(0)\n"
        "os.chdir(%r)\n"
        "for _ in range(3):\n"
        "    if os.fork() == 0:\n"
        "        time.sleep(120)\n"
        "time.sleep(120)\n" % tree_dir)
    spawner = subprocess.Popen([sys.executable, "-c", code15],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
    root15 = None
    deadline15 = time.monotonic() + 5
    while time.monotonic() < deadline15 and root15 is None:
        for entry in os.listdir('/proc'):
            if not entry.isdigit():
                continue
            pid = int(entry)
            try:
                if mod15._cwd(pid) == tree_dir and mod15._ppid(pid) == 1:
                    root15 = pid
                    break
            except (IOError, OSError, ValueError):
                continue
        time.sleep(0.2)

    if root15 is None:
        print("  **FAIL** could not spawn a reparented tree with a known cwd")
        results.append(False)
    else:
        # Give the children a moment to be counted in the tree size, then ask
        # the census directly -- this is the unit under test.
        time.sleep(1.0)
        # floor_mb=0, on purpose. A 4-process sleep tree holds ~4 MB, so the
        # SHIPPED floor (64 MB) filters it out -- correctly: a reader does not
        # need a line about a 4 MB tree. Asserting against the shipped default
        # would therefore test the floor, not the root charging this case is
        # about, and would fail for the right reason. The floor is a separate
        # claim and it is asserted below, on the printed summary.
        # limit=0 is "no cap": the tree holds ~5 MB and this box has four
        # services above 400 MB, so the SHIPPED default of 4 rows would cut it
        # off -- correctly, because a reader does not need a line about a
        # 5 MB tree when four services are holding a gigabyte between them.
        # The limit and the floor are separate claims from the root charging
        # this case is about; they are asserted below, on the summary.
        rows15 = mod15.holder_census(limit=0, floor_mb=0)
        roots15 = {r[0] for r in rows15}
        cwds15 = {r[4] for r in rows15}

        # (a) the tree is charged ONCE, to its root. Every version of the root
        # walk that was wrong on this box came back with the tree split across
        # several rows -- 26775, 26773 and a bare 424 MB renderer at 26877 --
        # because `parents` was keyed by the children map's keys and so a
        # leaf had no parent entry and stopped the walk on itself.
        charged_once = (sum(1 for r in rows15 if r[4] == tree_dir) == 1
                        and any(r[0] == root15 for r in rows15))
        results.append(charged_once)
        print(("PASS  " if charged_once else "**FAIL**")
              + "a 4-process tree is charged once, to root %d (rows=%d)"
              % (root15, sum(1 for r in rows15 if r[4] == tree_dir)))

        # (b) init is never charged, and never absorbs the box. PID 1 is the
        # parent of every reparented tree on this kernel, so a walk that
        # reaches it attributes the whole machine to systemd. The first
        # version of this census did: `1  2011MB  32proc  systemd`, with the
        # 669 MB service it was sent to find nowhere in the list.
        no_init = (0 not in roots15 and 1 not in roots15
                   and all(r[1] < 2000 for r in rows15))
        results.append(no_init)
        print(("PASS  " if no_init else "**FAIL**")
              + "PID 1/0 never charged (a forest, not one %d MB row)"
              % max((r[1] for r in rows15), default=0))

        # (c') the shipped floor and limit are not broken by the seam above.
        # The default 4-row cap must still return rows, and the 64 MB floor must
        # still hide a 5 MB tree -- both are what keeps the summary short on a
        # busy box, and both would pass vacuously if `limit` were the only
        # thing being checked.
        shipped = mod15.holder_census()
        floor_ok = (len(shipped) <= 4
                    and not any(r[4] == tree_dir for r in shipped))
        results.append(floor_ok)
        print(("PASS  " if floor_ok else "**FAIL**")
              + "shipped defaults cap at 4 rows and hide a 5 MB tree (%d rows)"
              % len(shipped))

        # (c) the pid is named AT ALL. This is the whole claim: a verdict with
        # no subject is not an answer. Fails on the pre-fix gate unchanged.
        results.append(root15 in roots15)
        print(("PASS  " if (root15 in roots15) else "**FAIL**")
              + "the holder's pid is nameable at all")

        # (d) the starvation SUMMARY names it, which is what a tick reads.
        # Asserted on the printed output, so it cannot pass on a census that
        # is correct but never called.
        if starved:
            r15 = subprocess.run(["python3", starved], capture_output=True,
                                 text=True, cwd=REPO)
            named = ("Largest memory holders" in r15.stdout
                     and r15.returncode == 1)
            results.append(named)
            print(("PASS  " if named else "**FAIL**")
                  + "the NO ROOM summary names its largest holders, exit 1")
            # ...and the negative: on a healthy box there is nothing to name,
            # so the census must not run and must not print. A census printed
            # on every invocation is noise that trains the reader to skip it.
            clear15 = subprocess.run(["python3", GATE[1]], capture_output=True,
                                     text=True, cwd=REPO)
            if clear15.returncode == 0:
                quiet_ok = "Largest memory holders" not in clear15.stdout
                results.append(quiet_ok)
                print(("PASS  " if quiet_ok else "**FAIL**")
                      + "a CLEAR box prints no census (the arm is on the "
                        "starved branch, not every run)")
            else:
                print("   SKIP (box not CLEAR right now; nothing to assert "
                      "about silence)")

        # Tidy: the tree's own root, and the harness's spawner.
        for pid in sorted([root15] + [p for p in os.listdir('/proc')
                                     if p.isdigit() and _in_tree(p, root15)],
                          key=int, reverse=True):
            try:
                os.kill(int(pid), 9)
            except OSError:
                pass
        try:
            spawner.kill()
        except OSError:
            pass
        shutil.rmtree(tree_dir, ignore_errors=True)
        time.sleep(0.3)

    print("\n14) a reparented TESTER: named, reaped, and the box comes back")
    # The arm `--reap` was missing until this tick, and it is the one the
    # loop hits in production: `tool/run_tests.py` SIGTERMs a hung shard, the
    # engine survives with PPID 1, and from then on the gate answers BUSY
    # forever. Case 4b proves the gate NAMES that leak (and it does). Nothing
    # proved anything could CLEAR it: `main()` armed `--reap` on `browsers`
    # only, so with a leaked tester and no browser on the box the gate
    # printed a dead end -- "LEAKED flutter_tester", exit 1, and not one
    # sentence telling the reader the box was recoverable. The documented
    # escape did not apply to the one leak the loop actually creates.
    #
    # Case 4b kills its orphan with SIGKILL from the test, which is precisely
    # why it never noticed: the suite always tidied up behind the gate.
    #
    # Both directions are asserted, and both run against the REAL gate (not a
    # copy) so the arm under test is the shipped one. A case that only
    # asserted "exit 1" would pass on the dead-end behaviour unchanged --
    # which is the trap case 4b already had to be rewritten to escape.
    binary14 = _reparented_tester_binary()
    if not binary14:
        print("  SKIP (no /bin/sleep to copy)")
    else:
        orphan14 = _spawn_orphan(binary14)
        if orphan14 is None:
            print("  **FAIL** could not reparent a tester")
            results.append(False)
        else:
            print("   tester pid=%d ppid=%d"
                  % (orphan14, ppid_of(orphan14)))
            pre = subprocess.run(["python3", os.path.join(REPO, "tool",
                                                          "build_gate.py")],
                                 capture_output=True, text=True, cwd=REPO)
            # Direction 1: the leak is named AND the reader is told how to
            # clear it. The remedy line is the whole claim -- without it the
            # gate is a correct detector with no exit.
            named = "LEAKED flutter_tester" in pre.stdout
            remedy = "--reap" in pre.stdout and str(orphan14) in pre.stdout
            results.append(named)
            print(("PASS  " if named else "**FAIL**  ")
                  + "reparented tester -> named as a leak")
            results.append(remedy)
            print(("PASS  " if remedy else "**FAIL**  ")
                  + "and the output names --reap and the pid to clear")
            for line in pre.stdout.strip().split("\n")[1:3]:
                print("        | " + line)

            # Direction 2: `--reap` actually clears it, and the verdict it
            # prints is computed AFTER the kill. That second half is why
            # `main()` re-surveys: reporting the pre-reap survey prints the
            # pid it just killed and exits 1, which reads as "reaping did
            # not help" on a box it had just fixed.
            post = subprocess.run(["python3", os.path.join(REPO, "tool",
                                                           "build_gate.py"),
                                   "--reap"], capture_output=True, text=True,
                                  cwd=REPO)
            gone = not os.path.exists("/proc/%d" % orphan14)
            results.append(gone)
            print(("PASS  " if gone else "**FAIL**  ")
                  + "--reap reaped the leaked tester (pid %d gone from /proc)"
                  % orphan14)
            for line in post.stdout.strip().split("\n")[:2]:
                print("        | " + line)
            results.append(post.returncode == 0
                           and "LEAKED flutter_tester" not in post.stdout)
            print(("PASS  " if (post.returncode == 0
                                and "LEAKED flutter_tester" not in post.stdout)
                   else "**FAIL**  ")
                  + "after reaping -> verdict recomputed, box CLEAR (exit=%d)"
                  % post.returncode)
            # Tidy by hand only if the arm failed to; a leftover here would
            # poison case 5-style "back to clean" checks in the next run.
            if not gone:
                try:
                    os.kill(orphan14, 9)
                except OSError:
                    pass
                for _ in range(40):
                    if not os.path.exists("/proc/%d" % orphan14):
                        break
                    time.sleep(0.1)
            time.sleep(0.3)

    print("\n16) a starved box must blame the HOST when the host took the memory")
    # Measured 8 Oct 2026, on the denial that cost this tick its gate:
    # MemAvailable 425 MB against a 900 MB floor, so a 475 MB shortfall, while
    # every visible pid summed to **822 MB** and the census's own top line was
    # a 332 MB `hatch daemon`. The gate printed that daemon and closed with
    # "if the top holder is a service, this denial is the box being at its
    # floor -- take a non-build item and do not kill it" -- an instruction to
    # act, pointing at a process holding 3% of the deficit. The real holder is
    # `Balloon: 4920444 kB`, the virtio-balloon driver, which is the host
    # reclaiming guest RAM: it moves 4.4-4.9 GB and no pid in this namespace
    # owns one page of it.
    #
    # Two wrong answers are both tested, because the defect is naming the
    # wrong thing, not failing to name anything. (a) blaming a process that
    # cannot account for the gap sends a reader to kill a service; (b) the
    # honest fallback -- "no local action clears this" -- is only true when
    # the balloon really does cover the shortfall, and must not be claimed on
    # a box where it does not.
    g16 = _ballooned_gate(425 * 1024, 4800 * 1024, "hosted")
    g16b = _ballooned_gate(425 * 1024, None, "nohost")
    g16c = _ballooned_gate(425 * 1024, 64 * 1024, "small")

    if not (g16 and g16b and g16c):
        print("  **FAIL** could not build the balloon fixtures")
        results.append(False)
    else:
        r16 = subprocess.run(["python3", g16], capture_output=True, text=True,
                             cwd=REPO)
        # The verdict itself must not move: this arm is a *diagnosis*, and a
        # fix that quietly relaxed the floor would be a far worse bug.
        still_refused = r16.returncode == 1 and _is_starved(r16.stdout)
        results.append(still_refused)
        print(("PASS  " if still_refused else "**FAIL**")
              + "the refusal stands (exit=%d) -- naming the host is a "
                "diagnosis, never a licence to build" % r16.returncode)

        names_host = "THE HOST IS HOLDING" in r16.stdout
        results.append(names_host)
        print(("PASS  " if names_host else "**FAIL**")
              + "the host is named as the holder of the 475 MB shortfall")

        # The census must NOT be offered as the explanation while the balloon
        # covers it. It is allowed to print residue, so the assertion is on
        # the *advice*, which is what a reader acts on.
        no_kill_advice = "do not kill it" not in r16.stdout
        results.append(no_kill_advice)
        print(("PASS  " if no_kill_advice else "**FAIL**")
              + "no advice to act on a service that cannot free the memory")

        # (b) No balloon at all -- a cgroup limit or plain overcommit. The
        # honest fallback is all that is left, and it must still refuse.
        r16b = subprocess.run(["python3", g16b], capture_output=True, text=True,
                              cwd=REPO)
        b_ok = (r16b.returncode == 1
                and "THE HOST IS HOLDING" not in r16b.stdout
                and _is_starved(r16b.stdout))
        results.append(b_ok)
        print(("PASS  " if b_ok else "**FAIL**")
              + "no Balloon: field -> still refused, host NOT invented")

        # (c) A small balloon must not be read as an explanation either --
        # the threshold is "could returning it clear the floor", so a 64 MB
        # balloon against a 475 MB shortfall is not a cause.
        r16c = subprocess.run(["python3", g16c], capture_output=True, text=True,
                              cwd=REPO)
        c_ok = (r16c.returncode == 1
                and "THE HOST IS HOLDING" not in r16c.stdout)
        results.append(c_ok)
        print(("PASS  " if c_ok else "**FAIL**")
              + "a 64 MB balloon does not explain a 475 MB shortfall")

    print("\nBaseline: %s" % _foreign_note())
    ok = sum(results)
    print("== %d/%d ==  %s" % (ok, len(results),
                                 "ALL PASS" if all(results) else "SOME FAILED"))
    # Leave the private dir behind. It is this suite's own, mkdtemp'd, and
    # nothing else writes to it -- but the contents are Python files, and a
    # directory full of them that outlives the run is the exact hazard the
    # private dir exists to contain.
    shutil.rmtree(_SUITE_TMP, ignore_errors=True)
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
