import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/diagnostics/boot_trace.dart';

/// The recorder behind the cold-start audit. Pure Dart with an injected clock,
/// so the numbers asserted here are exact rather than wall-clock-flaky.
void main() {
  test('each mark closes the stretch since the previous one', () {
    var now = 0;
    final trace = BootTrace(nowMs: () => now);

    now = 12;
    trace.mark('binding');
    now = 15;
    trace.mark('chrome');
    now = 90;
    trace.mark('runApp');

    expect(trace.phases.map((p) => p.name).toList(),
        <String>['binding', 'chrome', 'runApp']);
    expect(trace.msFor('binding'), 12);
    expect(trace.msFor('chrome'), 3);
    expect(trace.msFor('runApp'), 75);
    expect(trace.elapsedMs, 90);
  });

  test('the first frame is recorded once, and only once', () {
    var now = 0;
    final trace = BootTrace(nowMs: () => now);

    now = 120;
    trace.firstFrame();
    now = 400;
    trace.firstFrame();

    expect(trace.firstFrameMs, 120);
  });

  test('the report line names the frame and every phase in order', () {
    var now = 0;
    final trace = BootTrace(nowMs: () => now);

    now = 4;
    trace.mark('binding');
    now = 96;
    trace.firstFrame();

    expect(trace.describe(), 'boot: 96ms to first frame | binding 4');
  });

  test('a launch still in progress says so instead of printing null', () {
    var now = 0;
    final trace = BootTrace(nowMs: () => now);
    now = 7;
    trace.mark('hooks');

    expect(trace.describe(), 'boot: still running | hooks 7');
    expect(trace.firstFrameMs, isNull);
    expect(BootTrace(nowMs: () => 0).describe(), 'boot: still running | no marks');
  });

  test('a phase marked twice totals, and the reader cannot rewrite the trace',
      () {
    var now = 0;
    final trace = BootTrace(nowMs: () => now);
    now = 10;
    trace.mark('session');
    now = 25;
    trace.mark('session');

    expect(trace.msFor('session'), 25);
    expect(trace.msFor('nothing-marked-that'), 0);
    expect(() => trace.phases.add(const BootPhase('x', 1)),
        throwsUnsupportedError);
  });

  test('the default constructor runs on the real clock', () {
    final trace = BootTrace();
    trace.mark('binding');
    expect(trace.elapsedMs, greaterThanOrEqualTo(0));
    expect(trace.describe(), startsWith('boot: still running | binding '));
  });
}
