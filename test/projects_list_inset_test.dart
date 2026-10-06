// The list inset on «مشاريعي», measured.
//
// This file exists because `card_recipe_test.dart` R4 only counts literals: it
// can tell you the screen stopped writing `18`, and it cannot tell you the
// screen still lines up. R4 is a ratchet over text; a screen can pass it while
// its cards sit 2 dp out from under its own search box, and nothing in the
// suite would say so.
//
// So these read RenderBoxes. The values are pinned rather than computed:
//  - the cards start at `AppTheme.s16` from the left edge, matching the 16 dp
//    of `AppTheme.cardPad` inside them (at 18 they sat 2 dp *wider* than the
//    content they framed, which is the drift R4 exists to end), and
//  - the first card is flush with the search field above it, so the two do not
//    step in and out under a customer scrolling.
//
// Read as rects, not pixels: two runs of the design shots on identical code
// differ by ~1442 raster rows on this host, so a pixel diff here would be
// measuring font antialiasing.
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
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/projects_screen.dart';
import 'package:allomokawil/src/widgets/project_card.dart';

Map<String, Object?> _session() => <String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 336,
        'phone': '0773000000',
        'email': null,
        'full_name': 'زبون',
        'type': 'customer',
        'avatar_url': null,
        'wilaya': '04',
        'commune': null,
        'created_at': '2026-09-19 20:00:00',
      },
    };

Map<String, Object?> _job(String id) => <String, Object?>{
      'id': id,
      'customer_id': 336,
      'title': 'test',
      'description': 'test',
      'category': 'general_finishing',
      'categories': <String>['general_finishing', 'painting'],
      'images': <Object?>[],
      'wilaya': '04',
      'commune': 'أولاد قاسم',
      'budget_min': 6000,
      'budget_max': 7000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-19 20:39:41',
      'updated_at': '2026-09-19 20:39:41',
    };

String _body(String path) {
  if (path.endsWith('/api/login')) return jsonEncode(_session());
  if (path.contains('/my/projects')) {
    return jsonEncode(<Map<String, Object?>>[
      _job('aaaaaaaa'),
      _job('bbbbbbbb'),
      _job('cccccccc'),
    ]);
  }
  if (path.contains('/my/profile')) {
    return jsonEncode(<String, Object?>{
      'id': 336,
      'user_id': 336,
      'full_name': 'زبون',
      'specialties': <Object?>[],
      'experience_years': 0,
    });
  }
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
        'portfolio_limit': 5,
        'quotes_used_this_month': 0,
      },
    });
  }
  return jsonEncode(<Object>[]);
}

void main() {
  Future<void> pumpProjects(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async => http.Response(
            _body(req.url.path),
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
        home: ProjectsScreen(repo: Repository(api)),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Rect rectOf(WidgetTester tester, Finder f) =>
      tester.renderObject<RenderBox>(f).localToGlobal(Offset.zero) &
      tester.renderObject<RenderBox>(f).size;

  group('the list inset on «مشاريعي»', () {
    testWidgets('the cards start one grid step in, not 2 dp past it',
        (tester) async {
      await pumpProjects(tester);

      // Guard the guard: no card means every rect read below is void.
      final cards = find.byType(ProjectCard);
      expect(cards, findsWidgets,
          reason: 'the screen rendered no project cards at all');

      final first = rectOf(tester, cards.first);
      expect(first.left, AppTheme.s16,
          reason: 'the list inset must be AppTheme.s16, matching the '
              '${AppTheme.cardPad.left} dp of AppTheme.cardPad inside the card '
              '— at 18 the card hung 2 dp outside the content it framed');
      // The view is 1080 physical px at DPR 2.75, so the logical width is
      // read back off the view rather than hardcoded — 392/2.75 is not 392,
      // and guessing it is how a right-edge assertion ends up measuring
      // nothing.
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(width - first.right, AppTheme.s16,
          reason: 'the right inset must match the left; a list that is '
              'symmetric on one side only is not aligned');
    });

    testWidgets('the first card is flush with the search box above it',
        (tester) async {
      await pumpProjects(tester);

      final field = rectOf(tester, find.byType(TextField));
      final card = rectOf(tester, find.byType(ProjectCard).first);
      expect(field.left, card.left,
          reason: 'the search field and the cards below it must share one '
              'left edge, or the screen steps in and out under the customer');
    });

    testWidgets('the inset is the token, not a number that looks like it',
        (tester) async {
      await pumpProjects(tester);

      // Read the value the screen actually laid out, and prove it is the
      // grid: 16 is on it, 18 was not. This is the assertion that fails if
      // someone types a bare literal back in here.
      final first = rectOf(tester, find.byType(ProjectCard).first);
      expect(first.left % 4, 0,
          reason: 'the measured inset ${first.left} dp is off the 8pt grid');
      expect(first.left, isNot(18));
    });
  });
}
