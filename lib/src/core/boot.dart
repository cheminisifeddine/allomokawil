import 'dart:async';

import 'package:flutter/foundation.dart';

import 'diagnostics/boot_trace.dart';
import 'diagnostics/crash_reporter.dart';
import 'security/auth_state.dart';

/// Everything the app needs, that the first frame must not wait for.
///
/// `main()` used to `await` two storage reads before `runApp` — the stored
/// session and the previous run's crash log — while the root gate was already
/// drawing `AppBootSkeleton` for exactly the unrestored state. On a cold Android
/// start that is one platform-channel round trip to the preferences file plus a
/// JSON decode of the session and of up to twenty crash lines, and it sat
/// between the user's tap and the first painted frame for no reason at all.
///
/// So the order changed: `runApp` first, this behind it. The two reads start
/// together instead of one after the other, and each one is individually
/// guarded — a launch that loses a diagnostic is still a launch.
class Boot {
  Boot._();

  /// Restores the session and the previous crash log, off the frame path.
  ///
  /// `main` hands the returned future to `unawaited`, so this must not throw:
  /// both halves catch their own failures. It is a plain future rather than a
  /// fire-and-forget call so a test — and any future "wait for boot" UI — can
  /// await the state it represents.
  static Future<void> warmup({
    required AuthState auth,
    required CrashReporter crashes,
    BootTrace? trace,
  }) =>
      Future.wait<void>(<Future<void>>[
        restoreSession(auth, crashes, trace: trace),
        restoreDiagnostics(crashes, trace: trace),
      ]);

  /// Reads the stored session back into [auth].
  ///
  /// The guard that used to live in `main` moved here with the call: `restore()`
  /// already swallows its own failures, and this second net means a future
  /// boot-time failure is captured as a startup crash and leaves the user on the
  /// landing page, signed out, instead of losing the frame.
  static Future<void> restoreSession(
    AuthState auth,
    CrashReporter crashes, {
    BootTrace? trace,
  }) async {
    try {
      await auth.restore();
    } catch (error, stack) {
      crashes.capture(error, stack,
          kind: 'startup', context: 'session restore');
      debugPrint('startup: session restore failed, opening logged out ($error)');
    } finally {
      trace?.mark('session');
    }
  }

  /// Reads back what the previous run left behind.
  ///
  /// The cheapest thing in the app to lose: nothing reads the log until someone
  /// asks for it, so it is the first candidate for "after the frame". The
  /// reporter already swallows a storage failure; this guard covers the call
  /// itself, since it is no longer awaited by `main`.
  static Future<void> restoreDiagnostics(
    CrashReporter crashes, {
    BootTrace? trace,
  }) async {
    try {
      await crashes.restore();
    } catch (error) {
      debugPrint('startup: previous crash log unreadable ($error)');
    } finally {
      trace?.mark('crash-log');
    }
  }
}
