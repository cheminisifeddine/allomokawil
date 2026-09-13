/// Where the launch time goes, phase by phase.
///
/// Written for the cold-start audit, because a number nobody can reproduce is
/// not a number: this file is deliberately plain Dart — no `flutter` import, no
/// engine, no platform channel — so the same recorder runs in a unit test with
/// an injected clock, on the bare Dart VM, and inside `main()` on a real phone.
/// `crash_log.dart` is engine-free for the same reason.
///
/// Reported phases, in the order the launch produces them:
///  * `binding`   — `WidgetsFlutterBinding.ensureInitialized()`
///  * `chrome`    — the status-bar / navigation-bar platform calls
///  * `hooks`     — `CrashReporter.install()`
///  * `runApp`    — everything `main()` does before the first frame is allowed
///                  to build. This is the number the audit exists to shrink.
///  * `session`, `crash-log` — storage reads that used to sit *inside*
///                  `runApp`'s phase and now land after the first frame.
library;

/// One measured stretch of the launch, in milliseconds.
class BootPhase {
  const BootPhase(this.name, this.ms);

  /// Short, stable, machine-readable — a report can grep it.
  final String name;

  /// Time since the previous mark. Not cumulative.
  final int ms;

  @override
  String toString() => '$name ${ms}ms';
}

/// A mark-per-step stopwatch for the boot path.
///
/// [nowMs] is the only clock it has, which is what makes it testable: inject a
/// counter and the phases are exact instead of wall-clock-flaky.
class BootTrace {
  BootTrace({int Function()? nowMs}) : _nowMs = nowMs ?? _stopwatchMs();

  static int Function() _stopwatchMs() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMilliseconds;
  }

  final int Function() _nowMs;
  final List<BootPhase> _phases = <BootPhase>[];
  int _lastMark = 0;
  int? _firstFrameMs;

  /// The trace of the process that is running, so a later reader (a diagnostics
  /// screen, a support session) can see the number without a rebuild.
  static BootTrace? last;

  /// Closes the stretch since the previous mark under [name].
  void mark(String name) {
    final now = _nowMs();
    _phases.add(BootPhase(name, now - _lastMark));
    _lastMark = now;
  }

  /// Records the moment the first frame was built — called from a post-frame
  /// callback, because that is the first point the launch can honestly be said
  /// to have painted. The first call wins: a later frame is not the number the
  /// user felt.
  void firstFrame() => _firstFrameMs ??= _nowMs();

  /// Milliseconds since the trace was constructed.
  int get elapsedMs => _nowMs();

  /// Time to the first built frame, or null while the launch is still running.
  int? get firstFrameMs => _firstFrameMs;

  /// The phases, oldest first. A copy: the report is not writable by its
  /// readers.
  List<BootPhase> get phases => List<BootPhase>.unmodifiable(_phases);

  /// Total time recorded under [name] — several total if it was marked twice.
  int msFor(String name) =>
      _phases.where((p) => p.name == name).fold(0, (sum, p) => sum + p.ms);

  /// One line, the way logcat and the CI log carry it:
  /// `boot: 96ms to first frame | binding 4 · chrome 1 · hooks 2 · runApp 3 · frame 86`
  String describe() {
    final parts = _phases.map((p) => '${p.name} ${p.ms}').join(' · ');
    final frame = _firstFrameMs;
    final body = parts.isEmpty ? 'no marks' : parts;
    return frame == null
        ? 'boot: still running | $body'
        : 'boot: ${frame}ms to first frame | $body';
  }
}
