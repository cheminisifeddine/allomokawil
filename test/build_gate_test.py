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

Expected: 11/11. A failure here means the gate is lying to the loop.
"""
import os
import shutil
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
    return subprocess.run(GATE, capture_output=True, text=True, cwd=REPO)


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


def _starved_gate():
    """A copy of the gate whose /proc/meminfo read is redirected to a
    fixture holding 512 MB available. Returns the path, or None."""
    src = os.path.join(REPO, "tool", "build_gate.py")
    fixture = os.path.join(tempfile.gettempdir(), "gate_meminfo_starved")
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
    out = os.path.join(tempfile.gettempdir(), "gate_starved_build_gate.py")
    body = open(src).read()
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
    src = open(os.path.join(REPO, "tool", "build_gate.py")).read()
    ctr = os.path.join(tempfile.gettempdir(), "gate_osc_ctr_%s" % tag)
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
    out = os.path.join(tempfile.gettempdir(), "gate_osc_%s.py" % tag)
    with open(out, "w") as fh:
        fh.write(patched)
    return out


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

    print("\n5) back to clean")
    check("after cleanup -> CLEAR", 0)

    print("\n6) a starved box with nothing building (2 cores, no swap)")
    starved = _starved_gate()
    if starved:
        r = subprocess.run(["python3", starved], capture_output=True, text=True,
                           cwd=REPO)
        ok = r.returncode == 1 and "NO ROOM" in r.stdout
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
        d = tempfile.mkdtemp(prefix="gate_chrome_leak")
        code = (
            "import os\n"
            "pid = os.fork()\n"
            "if pid:\n"
            "    os._exit(0)\n"
            "os.setsid()\n"
            "os.execv(%r, [%r, '--headless', '--no-sandbox', '--disable-gpu',"
            " '--remote-debugging-port=9398', '--user-data-dir=' + %r,"
            " 'about:blank'])\n" % (CHROME, CHROME, d))
        r = subprocess.Popen([sys.executable, "-c", code],
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
        r.wait()
        time.sleep(4.0)   # the browser takes a moment to bind the port
        leaked = None
        for entry in os.listdir('/proc'):
            if not entry.isdigit():
                continue
            pid = int(entry)
            if ppid_of(pid) != 1:
                continue
            try:
                cmd = open("/proc/%d/cmdline" % pid).read().replace("\x00", " ")
            except (IOError, OSError):
                continue
            if "remote-debugging-port=9398" in cmd:
                leaked = pid
                break
        if leaked is None:
            print("  **FAIL** no reparented browser to test with")
            results.append(False)
        else:
            print("   leaked pid=%d ppid=%d" % (leaked, ppid_of(leaked)))
            out = _run()
            # The two claims that are about the ARM, and hold whatever the
            # memory does: the leak is named, and the gate fails closed. The
            # "reclaimable" sentence is deliberately not asserted -- it is
            # gated on MIN_AVAILABLE_MB, so a box with room to spare prints
            # neither it nor the STARVED line, and asserting it would make
            # the case fail for the box being healthy.
            ok = (out.returncode == 1
                  and "LEAKED headless chrome" in out.stdout
                  and str(leaked) in out.stdout)
            results.append(ok)
            print(("PASS  " if ok else "**FAIL**  ")
                  + "reparented browser -> named as a leak, exit 1")
            for line in out.stdout.strip().split("\n")[:4]:
                print("        | " + line)
            try:
                os.kill(leaked, 9)
            except OSError:
                pass
            time.sleep(0.5)
            # The reaped box must come back to CLEAR, or this arm cannot
            # tell a real leak from a permanent "busy".
            check("after reaping the browser -> CLEAR", 0)
        shutil.rmtree(d, ignore_errors=True)
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
        ok = r.returncode == 1 and "NO ROOM" in r.stdout
        results.append(ok)
        print(("PASS  " if ok else "**FAIL**  ")
              + "sustained starvation -> still NO ROOM, exit 1")
        for line in r.stdout.strip().split("\n")[:2]:
            print("        | " + line)
    else:
        print("  **FAIL** could not build the starved fixture")
        results.append(False)

    ok = sum(results)
    print("\n== %d/%d ==  %s" % (ok, len(results),
                                 "ALL PASS" if all(results) else "SOME FAILED"))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
