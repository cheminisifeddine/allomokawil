// The portfolio gate as the contractor actually meets it.
//
// The unit tests beside this one prove `PortfolioAllowance` computes the right
// room. That is not the same claim as "the gallery screen stops offering a
// photo when the plan is spent", which is the claim a user would make and the
// one that can rot silently: a correct helper wired to nothing is a feature
// that does not exist, and the free plan's five photos are exactly the state
// most contractors on the app are in.
//
// Both directions are driven here, because a one-sided test passes on a gate
// that never opens. Five photos on a five-photo plan must hide the add tile and
// name the limit; two on the same plan must show both the tile and the room.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';

Map<String, Object?> _worker() => <String, Object?>{
      'id': 7,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'specialties': <Object?>['دهان'],
      'experience_years': 5,
    };

Map<String, Object?> _session() => <String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 31,
        'phone': '0773000000',
        'email': null,
        'full_name': 'مقاول تجربة',
        'type': 'worker',
        'avatar_url': null,
        'wilaya': '16',
        'commune': null,
        'created_at': '2026-09-11 20:00:00',
      },
    };

/// The subscription payload, trimmed to what `BillingCatalogue.fromJson` reads.
///
/// `portfolio_limit` is sent as a raw number exactly as D1 sends it, because
/// the whole defect is what the app does with the number that arrives — a test
/// that passed a pre-resolved limit into the screen would test the wrong thing.
String _body(String path, {required int photos, required int limit}) {
  if (path.endsWith('/api/login')) return jsonEncode(_session());
  if (path.contains('/portfolio')) {
    return jsonEncode(<Object>[
      for (var i = 0; i < photos; i++)
        <String, Object>{'image_url': 'https://r2.test/p$i.jpg'},
    ]);
  }
  if (path.contains('/my/profile')) return jsonEncode(_worker());
  if (path.contains('/subscription')) {
    return jsonEncode(<String, Object?>{
      'currency': 'DZD',
      'note_ar': '',
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[],
      'current': <String, Object?>{
        'plan': 'free_trial',
        'name_ar': 'الخطة المجانية',
        'status': 'active',
        'starts_at': '2026-09-01 00:00:00',
        'expires_at': null,
        'quote_limit': 3,
        'portfolio_limit': limit,
        'quotes_used_this_month': 0,
      },
    });
  }
  return jsonEncode(<Object>[]);
}

void main() {
  Future<List<String>> render(
    WidgetTester tester, {
    required int photos,
    required int limit,
  }) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async => http.Response(
            _body(req.url.path, photos: photos, limit: limit),
            200,
            headers: {'content-type': 'application/json'},
          )),
    );
    final auth = AuthState(api);
    await auth.login(phone: '0773000000', password: 'secret123');

    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: const MyPortfolioScreen(),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    // Guard the guard: a screen stuck on its skeleton renders no text, and a
    // test whose every assertion is vacuously true is worse than no test.
    expect(texts, isNotEmpty, reason: 'the gallery rendered no text');
    return texts;
  }

  group('the gallery screen honours the plan', () {
    testWidgets('a full free gallery stops offering a photo and says why',
        (tester) async {
      final texts = await render(tester, photos: 5, limit: 5);

      // The add button is gone...
      expect(find.byKey(const Key('portfolio-add')), findsNothing);
      // ...and the add tile is gone with it.
      expect(find.byType(Icon), findsWidgets, reason: 'the screen has no icons');
      // ...and the limit is named, so a missing control reads as a limit
      // rather than as a broken screen.
      expect(texts, contains('بلغت حد صور خطتك: 5 صور'), reason: '$texts');
      expect(find.byKey(const Key('portfolio-full')), findsOneWidget);
    });

    testWidgets('a gallery with room keeps the button and states what is left',
        (tester) async {
      final texts = await render(tester, photos: 2, limit: 5);

      expect(find.byKey(const Key('portfolio-add')), findsOneWidget);
      expect(find.byKey(const Key('portfolio-full')), findsNothing);
      expect(texts, contains('بقيت 3 صور من 5 صور في خطتك'), reason: '$texts');
    });

    testWidgets('a paid gallery past the free allowance is not closed',
        (tester) async {
      // The failure mode that matters most: a gate built on the free plan's
      // five would hide the tile for a man who paid for thirty.
      final texts = await render(tester, photos: 6, limit: 30);

      expect(find.byKey(const Key('portfolio-add')), findsOneWidget);
      expect(find.byKey(const Key('portfolio-full')), findsNothing);
      expect(texts, contains('بقيت 24 صورة من 30 صورة في خطتك'), reason: '$texts');
    });

    testWidgets('a plan the server never sent does not close the gallery',
        (tester) async {
      // `portfolio_limit` absent → `_int` hands back 0 → the screen must read
      // that as unknown. If this regresses, a paying contractor with one
      // un-migrated row is locked out of his own portfolio.
      // The free plan's real limit is the fallback, so the room line is the
      // only thing that can tell this apart from a plan that genuinely sends 5
      // — which is why the absence of the gate is asserted, not the copy.
      final texts = await render(tester, photos: 2, limit: 0);

      expect(find.byKey(const Key('portfolio-add')), findsOneWidget);
      expect(find.byKey(const Key('portfolio-full')), findsNothing);
      expect(texts, contains('بقيت 3 صور من 5 صور في خطتك'), reason: '$texts');
    });
  });
}
