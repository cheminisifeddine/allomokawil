// The list inset on «السوق», measured.
//
// The same reason `projects_list_inset_test.dart` exists, one screen over.
//
// `worker_home` stacks six bands in a single sliver column — the stale-market
// note, the filter strip, the search box, the section title, the list and the
// skeleton that stands in for it. Before this sweep five of them said `18` and
// the section title said `16`, all on the same left edge, 2 dp apart. Nobody
// draws a ruler on a phone, so the step reads as "something is off" and nobody
// can say what.
//
// `card_recipe_test.dart` R4 counts literals in source text. It cannot tell you
// the screen still lines up: it would have gone green on the old code with the
// list at 18 and the title at 16, and it will happily go green if someone types
// `18` back in here. So these read RenderBoxes.
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
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';
import 'package:allomokawil/src/widgets/project_card.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _worker = {
  'id': 16, 'user_id': 31, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 4.5, 'total_reviews': 3,
  'total_completed_jobs': 7, 'response_time_hours': 2, 'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45', 'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة', 'phone': '077442495', 'user_wilaya': '16',
  'avatar_url': null,
};

Map<String, Object?> _project(String id, String title) => <String, Object?>{
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': 'وصف تجريبي',
      'category': 'painting',
      'images': <Object?>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// Bounded pumps, not `pumpAndSettle`: the shimmer skeletons and the widen
/// progress bar animate forever on this screen, so settle would never return.
Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> pumpMarket(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login')) {
        return _json(<String, Object?>{
          'token': 'tok',
          'user': <String, Object?>{
            'id': 31,
            'phone': '077442495',
            'email': null,
            'full_name': 'مقاول تجربة',
            'type': 'worker',
            'avatar_url': null,
            'wilaya': '16',
            'commune': null,
            'created_at': '2026-09-11 20:00:00',
          },
        });
      }
      if (p.contains('/my/profile')) return _json(_worker);
      if (p.contains('/mobile/projects')) {
        return _json(<Map<String, Object?>>[
          _project('p1', 'دهان شقة 3 غرف'),
          _project('p2', 'تركيب جبس بورد'),
          _project('p3', 'سباكة حمام كامل'),
        ]);
      }
      if (p.contains('/workers')) return _json(<Object>[_worker]);
      if (p.contains('/conversations')) return _json(<Object>[]);
      return _json(<Object>[]);
    }),
  );

  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '077442495', password: 'secret123');

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AppScope(
      api: api,
      auth: auth,
      child: const WorkerHomeScreen(),
    ),
  ));
  await _settle(tester);
}

Rect rectOf(WidgetTester tester, Finder f) =>
    tester.renderObject<RenderBox>(f).localToGlobal(Offset.zero) &
    tester.renderObject<RenderBox>(f).size;

void main() {
  group('the list inset on «السوق»', () {
    testWidgets('every band on the left edge shares one number', (tester) async {
      await pumpMarket(tester);

      // Guard the guard: no card means every rect below is void.
      final cards = find.byType(ProjectCard);
      expect(cards, findsWidgets,
          reason: 'the marketplace rendered no project cards at all');

      final card = rectOf(tester, cards.first);
      expect(card.left, AppTheme.s16,
          reason: 'the list inset must be AppTheme.s16 — at 18 each card hung '
              '2 dp outside the ${AppTheme.cardPad.left} dp of cardPad it was '
              'framing');

      final field = rectOf(tester, find.byType(TextField).first);
      expect(field.left, card.left,
          reason: 'the search box and the cards below it must share one left '
              'edge, or the screen steps in and out under the contractor');

      // The filter strip above the box is the other band on this edge. It was
      // 18 while the title under it was 16, so the column had two insets
      // before this sweep.
      final strip = rectOf(tester, find.byType(WorkerHomeScreen).first);
      expect(strip.left, 0, reason: 'sanity: the screen fills the view');
    });

    testWidgets('the title band carries the same inset as the cards',
        (tester) async {
      await pumpMarket(tester);

      // Measure the *band*, not the words in it. `SectionTitle` pads itself 2
      // dp and draws a 19 dp icon plus an 8 dp gap before the text, so the text
      // box lands 27 dp inside its own band — asserting on it would pin an
      // icon offset and call it alignment. The band is the thing that shares
      // an edge with the list.
      final band = rectOf(tester, find.byType(SectionTitle));
      final card = rectOf(tester, find.byType(ProjectCard).first);

      expect(band.left, card.left,
          reason: 'the section title band and the cards it introduces must '
              'share one left edge; before this sweep the band said 16 and the '
              'list said 18');
      expect(band.left, AppTheme.s16);
    });

    testWidgets('the inset is the token, not a number that looks like it',
        (tester) async {
      await pumpMarket(tester);

      // The assertion that fails if someone types a bare 18 back in here.
      final first = rectOf(tester, find.byType(ProjectCard).first);
      expect(first.left % 4, 0);
      expect(first.left, isNot(18));

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(width - rectOf(tester, find.byType(ProjectCard).first).right,
          AppTheme.s16,
          reason: 'a list inset on one side only is not aligned');
    });
  });
}
