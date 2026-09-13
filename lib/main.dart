import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/core/app_scope.dart';
import 'src/core/diagnostics/crash_reporter.dart';
import 'src/core/network/api_client.dart';
import 'src/core/security/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // White canvas: the status bar sits on white, so it needs dark glyphs, and
  // the gesture bar is white rather than the platform's translucent grey.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFFFFFFF),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  // Installed before anything else can fail: a session restore that dies, an
  // async error inside a screen, a first frame that never renders — each one now
  // writes a line the next launch can read, instead of leaving a user with an
  // app that closed for no visible reason.
  final crashes = CrashReporter();
  crashes.install();
  await crashes.restore();
  final api = ApiClient();
  // AuthState installs the 401 handler on the client itself: a rejected token
  // drops the session and the root gate swaps the signed-in home for the landing
  // page with a notice saying why — instead of leaving the user on an empty home.
  final auth = AuthState(api);
  // Awaited before the first frame, so nothing may escape it: restore() guards
  // its own reads, and this second guard means a future boot-time failure still
  // reaches runApp instead of leaving the user on a blank white page.
  try {
    await auth.restore();
  } catch (error, stack) {
    crashes.capture(error, stack, kind: 'startup', context: 'session restore');
    debugPrint('startup: session restore failed, opening logged out ($error)');
  }
  runApp(AppScope(api: api, auth: auth, child: const AlloMokawilApp()));
}
