/// Installs the app's uncaught-error hooks and writes what they catch to the
/// device through [CrashLog].
///
/// This is the Flutter-facing half of the pair: `crash_log.dart` is plain Dart
/// so it can be executed without an engine, and everything that needs a binding,
/// a platform channel or a [FlutterErrorDetails] lives here.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_log.dart';

/// Where the log lives between launches.
///
/// An interface so the reporter can be driven with an in-memory store in tests
/// — and with a deliberately broken one, to prove a failed write never escapes
/// as a second crash.
abstract interface class CrashStore {
  Future<List<String>> read();
  Future<void> write(List<String> lines);
}

/// The production store: one string list inside the app's own preferences.
class PrefsCrashStore implements CrashStore {
  const PrefsCrashStore();

  /// Versioned, so a future format change can walk away from old lines instead
  /// of trying to parse them.
  static const String key = 'diagnostics.crashes.v1';

  @override
  Future<List<String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(key) ?? const <String>[];
  }

  @override
  Future<void> write(List<String> lines) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, lines);
  }
}

/// Catches what the app cannot, and leaves a line behind.
class CrashReporter {
  CrashReporter({CrashStore store = const PrefsCrashStore(), int limit = 20})
      : _store = store,
        log = CrashLog(limit: limit) {
    // **The previous run's lines are read here, at construction, and every write
    // waits for that read.** The invariant is one sentence: *a write must never
    // reach storage before the read that would have told it what was already
    // there.* See [_initialRead] and [_scheduleWrite].
    _initialRead = _loadPrevious();
  }

  final CrashStore _store;

  /// Everything caught this run, plus what the previous run left behind.
  final CrashLog log;

  /// The one read of the previous run's log, started in the constructor.
  ///
  /// **Why it is not in [restore].** It used to be, and it used to be the only
  /// operation in this class running outside the serialisation: [capture] and
  /// [clear] both queued their write onto `_writes`, while `restore` called
  /// `_store.read()` whenever boot got to it. Boot deliberately schedules that
  /// *after the first frame* (see `Boot.restoreDiagnostics`) — because a
  /// startup crash may already be in the log — so the read and a capture
  /// genuinely overlap in production, and on a cold start with a slow
  /// preferences channel the capture's write wins.
  ///
  /// The consequence was total loss of the previous run, not a duplicate. The
  /// write carries the whole log as one string list, so a write that lands
  /// before the read replaces storage with a list holding only this run's
  /// records. The read then loads that list back and inserts it at the front,
  /// and the earlier lines exist in memory, on screen, and nowhere else — the
  /// one copy a crash log exists to keep.
  ///
  /// Starting the read in the constructor does not make the cold launch wait for
  /// it: nothing awaits [_initialRead] except a write that is already going to
  /// the same storage, and [restore] is still the off-path await boot makes
  /// after the frame. It just stops the read being *scheduled* later than a
  /// write.
  late final Future<void> _initialRead;

  /// Reads the previous run back into [log]. Never throws.
  Future<void> _loadPrevious() async {
    try {
      log.loadLines(await _store.read(), earlier: true);
    } catch (error) {
      debugPrint('crash: previous log unreadable ($error)');
    }
  }

  FlutterExceptionHandler? _outerFlutterHandler;
  bool Function(Object, StackTrace)? _outerAsyncHandler;
  bool _installed = false;
  Future<void> _writes = Future<void>.value();

  /// The reporter the running app installed. A diagnostics screen reads its
  /// [log]; tests read it to assert a capture landed.
  static CrashReporter? active;

  /// Reads the previous run's log back into [log].
  ///
  /// Called from `Boot.warmup` *after* the first frame — the log is a diagnostic,
  /// nothing on screen waits for it, and a cold launch should not pay for it. So
  /// it must never throw, and it must still land in the right place: `earlier:`
  /// puts the previous run's lines in front of anything this run already caught,
  /// which keeps the list newest-last even when a startup crash beats the read.
  ///
  /// The read itself is [_initialRead], begun in the constructor so that no
  /// write can overtake it; this only waits for it, and for whatever writes were
  /// already queued behind it.
  Future<void> restore() async {
    await _initialRead;
    await _writes;
  }

  /// Chains both uncaught-error hooks, keeping whatever was installed before.
  ///
  /// The outer handler is still called: in debug that is the red screen that
  /// says where the throw came from, and taking it away would turn a diagnostics
  /// change into a debugging regression.
  void install() {
    if (_installed) return;
    _installed = true;
    active = this;

    final outerFlutter = FlutterError.onError;
    _outerFlutterHandler = outerFlutter;
    FlutterError.onError = (FlutterErrorDetails details) {
      capture(details.exception, details.stack, kind: 'flutter');
      outerFlutter?.call(details);
    };

    final dispatcher = PlatformDispatcher.instance;
    final outerAsync = dispatcher.onError;
    _outerAsyncHandler = outerAsync;
    dispatcher.onError = (Object error, StackTrace stack) {
      capture(error, stack, kind: 'async');
      // Whatever the app did before this file existed, it still does. Returning
      // what the outer handler returned (false by default) leaves the engine's
      // own reporting untouched; only the local record is new. Swallowing the
      // error instead is a founder decision, not a diagnostics one.
      return outerAsync?.call(error, stack) ?? false;
    };
  }

  /// Puts the old hooks back. Used by tests; production installs once, at boot.
  void uninstall() {
    if (!_installed) return;
    _installed = false;
    FlutterError.onError = _outerFlutterHandler;
    PlatformDispatcher.instance.onError = _outerAsyncHandler;
    if (identical(active, this)) active = null;
  }

  /// Records one failure by hand, for the paths that catch their own errors —
  /// `main`'s boot guard, or a screen that recovers but still wants the trace.
  void capture(
    Object error,
    StackTrace? stack, {
    String kind = 'flutter',
    String? context,
  }) {
    final record = CrashRecord(
      at: DateTime.now(),
      kind: kind,
      message: CrashRecord.trim(_safeText(error), CrashRecord.maxMessage),
      detail: CrashRecord.trim(_detail(context, stack), CrashRecord.maxDetail),
    );
    log.add(record);
    debugPrint('crash[$kind]: ${record.message}');
    _scheduleWrite();
  }

  /// Queues a write of the whole log.
  ///
  /// Serialised, so a second crash cannot interleave with the first one's write
  /// and leave a half-written list; failures are swallowed on purpose, because
  /// storage refusing a diagnostic must not become a second crash.
  void _scheduleWrite() {
    // Two things are different from the old version, and both are load-bearing.
    //
    // **The write waits for [_initialRead].** That is the whole fix: a write that
    // lands before the read replaces storage with this run's records alone, and
    // the previous run is gone. Queuing the read *behind* the writes instead
    // does not work — it makes the overwrite happen first and then reads the
    // overwritten value back, which is the same loss with an extra step.
    //
    // **The snapshot is taken here, inside the queue, not at the call site.**
    // Taking `log.toLines()` before queuing froze the log as of the moment the
    // write was requested, so any operation that could still change the log
    // before the write ran — the restore landing, a `clear` — was silently
    // excluded from what reached the device. The serialisation already
    // guarantees one write at a time; reading the log in that ordered slot is
    // what makes the value written the value the log holds when the write
    // happens.
    //
    // The failure is caught per write rather than by a `catchError` on the
    // chain, because a rejected `_writes` would reject every `flush` after it,
    // including `clear`'s, and the next crash still has to be able to write.
    _writes = _writes.then<void>((_) async {
      await _initialRead;
      try {
        await _store.write(log.toLines());
      } catch (error) {
        debugPrint('crash: log not saved ($error)');
      }
    });
  }

  /// Completes once everything captured so far has reached storage.
  Future<void> flush() => _writes;

  /// Empties the log, on the device and in memory.
  Future<void> clear() async {
    log.clear();
    _scheduleWrite();
    await flush();
  }

  static String _safeText(Object error) {
    try {
      return error.toString();
    } catch (_) {
      // An object whose toString throws is exactly the kind of thing that ends
      // up in this list, and it must not take the reporter down with it.
      return '<unprintable ${error.runtimeType}>';
    }
  }

  static String _detail(String? context, StackTrace? stack) {
    final parts = <String>[
      if (context != null && context.isNotEmpty) context,
      if (stack != null) stack.toString(),
    ];
    return parts.join('\n');
  }
}
