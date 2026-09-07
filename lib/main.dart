import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/app_scope.dart';
import 'src/core/network/api_client.dart';
import 'src/core/security/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final auth = AuthState(api);
  await auth.restore();
  runApp(AppScope(api: api, auth: auth, child: const AlloMokawilApp()));
}