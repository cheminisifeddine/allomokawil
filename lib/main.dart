import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/core/app_scope.dart';
import 'src/core/network/api_client.dart';
import 'src/core/security/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app is dark from the first frame, so the system bars must not paint
  // light chrome around it: white-on-dark status icons, and the gesture bar in
  // the canvas colour rather than the platform default.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF0B0E13),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final api = ApiClient();
  final auth = AuthState(api);
  // Awaited before the first frame, so nothing may escape it: restore() guards
  // its own reads, and this second guard means a future boot-time failure still
  // reaches runApp instead of leaving the user on a blank white page.
  try {
    await auth.restore();
  } catch (error) {
    debugPrint('startup: session restore failed, opening logged out ($error)');
  }
  runApp(AppScope(api: api, auth: auth, child: const AlloMokawilApp()));
}