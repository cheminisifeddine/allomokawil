// The **screen** half of the market-header trade-line defect, and the only
// half that could have caught it.
//
// The pure agreement in `market_identity_specialty_test.dart` compares two
// *strings* — the shared rule and the shape of the private copy. That is a
// true statement about the code but it is not a statement about the app: it
// would still pass if the header had stopped rendering its trade line at all,
// or if some other private copy had come back wearing a different shape. This
// file renders the real [MarketplaceView] and reads the trade line off the
// glass.
//
// The fixture is the same live row the original 28 Sep defect was proven on
// (`["painting","wallpaper","tiling_marble"]`, خالد رحماني), served through the
// real profile endpoint the header actually reads, because the defect is only
// reachable if the header really is built from `my/profile` — a synthetic
// widget test of `_identity` would not prove the screen still uses it.
//
// Expected before the fix: «دهان وطلاء ديكوري · ورق الجدران» and no «+1».
// Expected after: the third trade accounted for.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/specialty_label.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

/// A real worker payload carrying the three trades, everything else healthy so
/// the header renders its identity block rather than its own error page.
Map<String, Object?> _worker() => {
      'id': 16,
      'user_id': 31,
      'bio': 'دهان وديكور',
      'specialties': <String>['painting', 'wallpaper', 'tiling_marble'],
      'experience_years': 5,
      'price_range_min': 20000,
      'price_range_max': 60000,
      'service_radius_km': 30,
      'is_available': 1,
      'is_identity_verified': 1,
      'is_certificate_verified': 0,
      'verification_status': 'verified',
      'subscription_plan': 'free_trial',
      'avg_rating': 0.0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'response_time_hours': 2,
      'cover_image_url': null,
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
      'full_name': 'خالد رحماني',
      'phone': '077442495',
      'user_wilaya': '16',
      'avatar_url': null,
    };

Map<String, Object?> _user() => {
      'id': 31,
      'role': 'worker',
      'full_name': 'خالد رحماني',
      'phone': '0773000000',
      'user_wilaya': '16',
    };

void main() {
  testWidgets('the market header accounts for the trade it no longer names',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json(<String, Object?>{'token': 'tok', 'user': _user()});
        }
        if (p.endsWith('/api/unread')) return _json(0);
        if (p.endsWith('/api/mobile/my/profile')) return _json(_worker());
        if (p.endsWith('/api/mobile/my/subscription')) {
          return _json(<String, Object?>{
            'plan': <String, Object?>{'id': 'basic', 'name_ar': 'أساسي'},
            'usage': <String, Object?>{'quotes_used': 1, 'quote_limit': 3},
            'payment': <String, Object?>{'methods': <Object?>[]},
          });
        }
        if (p == '/api/mobile/projects') return _json(<Object>[]);
        if (p.endsWith('/portfolio')) return _json(<Object>[]);
        if (p.endsWith('/documents')) return _json(<Object>[]);
        return _json(<Object>[]);
      }),
    );
    final auth = AuthState(api);
    await auth.restore();
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);

    tester.view.physicalSize = const Size(1176, 2550);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: MarketplaceView(repo: Repository(api))),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // The header really is on screen and really is showing him: without these
    // two the assertions below could pass on an empty or error page, which is
    // the vacuous-test fault this repo has already paid for twice.
    expect(find.text('خالد رحماني'), findsOneWidget,
        reason: 'the fixture must really put the contractor on screen');

    // The defect: three trades, and the line under his name on his own market
    // header names two and accounts for none.
    final label = SpecialtyLabel.of(_worker()['specialties']! as List<String>);
    expect(find.text(label), findsOneWidget,
        reason: 'the market header must print the one trade line the app owns; '
            'it printed «$label» nowhere, so it is still building its own');
  });
}
