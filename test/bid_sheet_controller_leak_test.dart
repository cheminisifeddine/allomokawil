// The bid sheet's three fields are the only controllers in the app that are
// never disposed — and the screen is the one a contractor returns to most.
//
// Every other screen builds its controllers as State fields and disposes them
// in `dispose()`: 19 of 19. `_showBidSheet` builds three of them as *locals*,
// and a local is not disposed by anything. A `TextEditingController` owns a
// native input connection and a listener list, so every tap of «قدّم عرضك»
// stranded three of them for the life of the process — and `_showBidSheet` has
// five exits, so no single `dispose` at the bottom would have been enough
// anyway.
//
// The signal used here is the framework's own, not a hand-rolled counter:
// `dispose()` dispatches an `ObjectDisposed` event through
// `FlutterMemoryAllocations` (always on in debug), while an undisposed
// controller only ever dispatches `ObjectCreated`. Counting created-vs-disposed
// is therefore a direct measurement of the leak, and it is exactly the claim a
// code read cannot make.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

Map<String, dynamic> _project() => {
      'id': 'p-1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': 'الوصف',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-13 08:00:00',
    };

/// A signed-in **contractor** on someone else's open project: the bid button is
/// only offered to a non-owner, so a customer session would never draw it.
ApiClient _workerApi() => ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        final json = {'content-type': 'application/json'};
        if (p.endsWith('/login')) {
          return http.Response(
            jsonEncode({
              'token': 'tok',
              'user': {
                'id': 16,
                'phone': '0550000000',
                'email': null,
                'full_name': 'مقاول تجربة',
                'type': 'worker',
                'avatar_url': null,
                'wilaya': '16',
                'commune': null,
                'created_at': '2026-01-01 00:00:00',
              },
            }),
            200,
            headers: json,
          );
        }
        if (p.contains('/quotes')) {
          return http.Response('[]', 200, headers: json);
        }
        if (p.contains('/projects/')) {
          return http.Response(jsonEncode(_project()), 200, headers: json);
        }
        return http.Response('[]', 200, headers: json);
      }),
    );

/// Counts the controllers created and disposed while [body] runs.
///
/// Listens to the framework's allocation events rather than inspecting the
/// app, so a controller disposed by *anything* — including a fix this test has
/// never heard of — is counted as disposed. That is the point: the assertion
/// is about the number of live controllers, not about where the `dispose`
/// call was written.
class _LeakWatch {
  int created = 0;
  int disposed = 0;
  int get live => created - disposed;

  void _on(ObjectEvent e) {
    if (e.object is! TextEditingController) return;
    if (e is ObjectCreated) {
      created++;
    } else if (e is ObjectDisposed) {
      disposed++;
    }
  }

  /// Runs [body] under the watch and returns it.
  ///
  /// The listener is held across the **whole** await, not just the call: an
  /// earlier version of this helper unregistered in a `finally` that ran as
  /// soon as [body] returned its Future, so the sheet was built and closed
  /// with nothing listening and the watch honestly reported zero controllers
  /// created. The `created` assertion below is what caught that — without it
  /// this test would have passed by measuring nothing.
  Future<T> measure<T>(Future<T> Function() body) async {
    FlutterMemoryAllocations.instance.addListener(_on);
    try {
      return await body();
    } finally {
      FlutterMemoryAllocations.instance.removeListener(_on);
    }
  }
}

Future<({ApiClient api, AuthState auth})> _bootWorker() async {
  SharedPreferences.setMockInitialValues({});
  final api = _workerApi();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0550000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _pumpDetail(WidgetTester tester, ApiClient api, AuthState auth) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ar'),
    home: AppScope(
      api: api,
      auth: auth,
      child: ProjectDetailScreen(projectId: 'p-1', repo: Repository(api)),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  testWidgets('backing out of the bid sheet disposes its three controllers',
      (tester) async {
    final boot = await _bootWorker();
    await _pumpDetail(tester, boot.api, boot.auth);

    expect(find.text('قدّم عرضك'), findsOneWidget,
        reason: 'a contractor on an open project must be offered the bid button');

    final watch = _LeakWatch();
    // Open the sheet and dismiss it with the barrier, which is the path a
    // contractor takes every time he changes his mind about the price.
    await watch.measure(() async {
      await tester.tap(find.text('قدّم عرضك'));
      await tester.pumpAndSettle();
    });

    expect(find.text('إرسال العرض'), findsOneWidget,
        reason: 'the bid form must actually be on screen for this to measure it');

    await watch.measure(() async {
      // Tap outside the sheet: the cancel-without-sending exit.
      await tester.tapAt(const Offset(40, 120));
      await tester.pumpAndSettle();
    });

    expect(find.text('إرسال العرض'), findsNothing);

    expect(watch.created, greaterThanOrEqualTo(3),
        reason: 'the sheet builds three controllers, so the watch must see them');
    expect(watch.live, 0,
        reason: 'every controller the bid sheet built must be disposed when it '
            'closes — $watch');
  });
}
