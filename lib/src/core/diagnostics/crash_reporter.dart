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
        log = CrashLog(limit: limit);

  final CrashStore _store;

  /// Everything caught this run, plus what the previous run left behind.
  final CrashLog log;

  FlutterExceptionHandler? _outerFlutterHandler;
  bool Function(Object, StackTrace)? _outerAsyncHandler;
  bool _installed = false;
  Future<void> _writes = Future<void>.value();

  /// The reporter the running app installed. A diagnostics screen reads its
  /// [log]; tests read it to assert a capture landed.
  static CrashReporter? active;

  /// Reads the previous run's log back into [log].
  ///
  /// Called from `main` before the first frame, so it must never throw: a boot
  /// that dies here is a boot that dies for a reason nobody can read.
  Future<void> restore() async {
    try {
      log.loadLines(await _store.read());
    } catch (error) {
      debugPrint('crash: previous log unreadable ($error)');
    }
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
    final lines = log.toLines();
    _writes = _writes.then((_) => _store.write(lines)).catchError((Object error) {
      debugPrint('crash: log not saved ($error)');
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
