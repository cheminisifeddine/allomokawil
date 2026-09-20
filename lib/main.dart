import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/core/app_scope.dart';
import 'src/core/boot.dart';
import 'src/core/diagnostics/boot_trace.dart';
import 'src/core/diagnostics/crash_reporter.dart';
import 'src/core/location/place_state.dart';
import 'src/core/network/api_client.dart';
import 'src/core/security/auth_state.dart';

Future<void> main() async {
  // The clock starts on the first line of the launch, so the number the
  // cold-start audit reports is the whole path and not the part after the
  // engine had already warmed up.
  final boot = BootTrace();
  BootTrace.last = boot;

  WidgetsFlutterBinding.ensureInitialized();
  boot.mark('binding');
  // White canvas: the status bar sits on white, so it needs dark glyphs, and
  // the gesture bar is white rather than the platform's translucent grey.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFFFFFFF),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  boot.mark('chrome');
  // Installed before anything else can fail: a session restore that dies, an
  // async error inside a screen, a first frame that never renders — each one now
  // writes a line the next launch can read, instead of leaving a user with an
  // app that closed for no visible reason.
  final crashes = CrashReporter();
  crashes.install();
  boot.mark('hooks');
  final api = ApiClient();
  // AuthState installs the 401 handler on the client itself: a rejected token
  // drops the session and the root gate swaps the signed-in home for the landing
  // page with a notice saying why — instead of leaving the user on an empty home.
  final auth = AuthState(api);
  // Where the phone is: read once here, asked once by `PlaceWarmup` above the
  // root gate, then shared by every screen that shows nearby offers.
  final place = PlaceState();

  // Frame first, storage second.
  //
  // Until this change `main()` awaited the stored session *and* the previous
  // run's crash log before `runApp`, while the root gate was already drawing
  // `AppBootSkeleton` for exactly that unrestored state. A cold Android start
  // therefore paid one platform-channel round trip to the preferences file plus
  // two JSON decodes before it was allowed to paint a frame it had a designed
  // screen for. The reads still happen — `Boot.warmup` starts them here and the
  // gate swaps itself when they land — they just no longer hold the launch.
  runApp(AppScope(api: api, auth: auth, place: place, child: const AlloMokawilApp()));
  boot.mark('runApp');

  // The honest end of the launch: `addPostFrameCallback` runs the moment frame
  // one has been built, which is what the user sees first.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    boot.firstFrame();
    debugPrint(boot.describe());
  });

  unawaited(Boot.warmup(auth: auth, crashes: crashes, trace: boot));
  // The stored fix lands a few frames after the first paint, exactly like the
  // session does: `PlaceWarmup` rebuilds whatever needs it when it arrives.
  unawaited(place.restore());
}
