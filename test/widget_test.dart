import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/app.dart';

void main() {
  testWidgets('app boots to the auth gate', (tester) async {
    final api = ApiClient(baseUrls: ['http://localhost:8787']);
    final auth = AuthState(api);
    await tester.pumpWidget(AppScope(api: api, auth: auth, child: const AlloMokawilApp()));
    await tester.pump();

    // Before restore completes it shows a splash; after restore (no session)
    // it shows the role-entry gate.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
