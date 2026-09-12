import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/app_scope.dart';
import 'src/core/network/api_client.dart';
import 'src/core/security/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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