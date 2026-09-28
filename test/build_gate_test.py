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

Expected: 5/5. A failure here means the gate is lying to the loop.
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

    ok = sum(results)
    print("\n== %d/%d ==  %s" % (ok, len(results),
                                 "ALL PASS" if all(results) else "SOME FAILED"))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
