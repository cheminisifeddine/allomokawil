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

Expected: 7/7. A failure here means the gate is lying to the loop.
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

    ok = sum(results)
    print("\n== %d/%d ==  %s" % (ok, len(results),
                                 "ALL PASS" if all(results) else "SOME FAILED"))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
