// How many photos, said the way the number says it.
//
// Found on 26 Sep 2026. The portfolio header counted its own photos with
// string interpolation and one fixed noun:
//
//     '$count صورة في معرض أعمالك'
//     'أضفت $uploaded صورة في هذه الجلسة.'
//
// «5 صورة» is not a value this app is unlikely to see: the free plan ships
// `portfolio_limit: 5`, so filling the free allowance prints the wrong noun on
// the one screen whose whole job is to show a contractor what he has, and the
// session line moves fastest of all — it counts 1 → 2 → 3 → 4 as a man adds
// photos one at a time, and is wrong from the third on.
//
// The counts are driven from the real parsed server payload rather than from
// hand-built ints, because "a contractor read «5 صورة»" is a claim about the
// shape D1 actually sends.
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
import 'package:allomokawil/src/data/photo_count_copy.dart';
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';

/// The portfolio row production answers, trimmed to what the screen parses.
Map<String, Object?> _worker() => <String, Object?>{
      'id': 7,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'specialties': <Object?>['دهان'],
      'experience_years': 5,
    };

/// The free plan's `portfolio_limit: 5` — the value that makes «5 صورة» an
/// ordinary state rather than a theoretical one.
List<String> _photos(int n) => List<String>.generate(
      n,
      (i) => 'https://r2.test/p$i.jpg',
      growable: false,
    );

void main() {
  group('the four forms', () {
    test('1 / 2 / 3-10 / 11+ each take their own noun', () {
      expect(photosAr(1), 'صورة');
      expect(photosAr(2), 'صورتان');
      expect(photosAr(3), '3 صور');
      expect(photosAr(10), '10 صور');
      expect(photosAr(11), '11 صورة');
      expect(photosAr(40), '40 صورة');
    });

    test('the singular is not counted with a 1', () {
      expect(photosAr(1), isNot(contains('1 ')));
    });

    test('the dual is not counted with a 2 — it already says two', () {
      expect(photosAr(2), isNot(contains('2 ')));
    });

    test('11+ never takes a «واحدة» form with its number', () {
      // The trap the quote fix hit: passing «صورة واحدة» in as the singular
      // would make 11 read «11 صورة واحدة».
      expect(photosAr(11), isNot(contains('واحدة')));
      expect(photosAr(40), isNot(contains('واحدة')));
    });

    test('a zero is silence, not «0 صور»', () {
      expect(photosAr(0), '');
      expect(photosAr(-1), '');
    });
  });

  group('the two sentences', () {
    test('the count line names the gallery', () {
      expect(portfolioCountLineAr(1), 'صورة في معرض أعمالك');
      expect(portfolioCountLineAr(2), 'صورتان في معرض أعمالك');
      expect(portfolioCountLineAr(5), '5 صور في معرض أعمالك');
      expect(portfolioCountLineAr(11), '11 صورة في معرض أعمالك');
    });

    test('a zero count line is empty rather than «0 صور»', () {
      expect(portfolioCountLineAr(0), '');
    });

    test('the session line counts only this sitting', () {
      expect(uploadedThisSessionAr(1), 'أضفت صورة في هذه الجلسة.');
      expect(uploadedThisSessionAr(2), 'أضفت صورتان في هذه الجلسة.');
      expect(uploadedThisSessionAr(3), 'أضفت 3 صور في هذه الجلسة.');
      expect(uploadedThisSessionAr(4), 'أضفت 4 صور في هذه الجلسة.');
    });

    test('a zero session line is empty — the screen has other copy for that', () {
      expect(uploadedThisSessionAr(0), '');
    });
  });

  group('the sentence on the real screen', () {
    // A string function can be right while the screen still prints the old
    // line. These mount MyPortfolioScreen itself and read what build()
    // produced, because "a contractor read «5 صورة»" is a claim about a
    // rendered screen and not about a function's return value.
    //
    // Each pump carries a key derived from the count: pumping the same widget
    // type into the same tree slot reuses its State, so a second call inside
    // one test body would silently keep the first call's photo list and the
    // test would assert against stale data.
    Future<List<String>> rendered(WidgetTester tester, int count) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final path = req.url.path;
          if (path.contains('/portfolio')) {
            return http.Response(
              jsonEncode(<Object>[
                for (final url in _photos(count)) <String, Object>{'image_url': url},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (path.contains('/my/profile')) {
            return http.Response(
              jsonEncode(_worker()),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      await tester.pumpWidget(AppScope(
        api: api,
        auth: AuthState(api),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: MyPortfolioScreen(key: ValueKey<int>(count)),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      // Guard the guard: a screen stuck on its error state renders none of
      // this, and a test that "passes" because every `any()` is false is worse
      // than no test at all.
      expect(texts.any((t) => t.contains('أعد المحاولة')), isFalse,
          reason: 'the screen never loaded, so the copy was never rendered: '
              '$texts');
      return texts;
    }

    testWidgets('a contractor on the free plan reads «5 صور», not «5 صورة»',
        (tester) async {
      final texts = await rendered(tester, 5);
      expect(texts, contains('5 صور في معرض أعمالك'));
      // The old line was «5 صورة في معرض أعمالك».
      expect(texts.any((t) => t.contains('5 صورة')), isFalse,
          reason: '$texts');
    });

    testWidgets('the 1 / 2 / 3-10 / 11+ boundary reads right on the screen',
        (tester) async {
      expect(await rendered(tester, 1), contains('صورة في معرض أعمالك'));
      expect(await rendered(tester, 2), contains('صورتان في معرض أعمالك'));
      expect(await rendered(tester, 3), contains('3 صور في معرض أعمالك'));
      expect(await rendered(tester, 10), contains('10 صور في معرض أعمالك'));
      expect(await rendered(tester, 11), contains('11 صورة في معرض أعمالك'));
    });

    testWidgets('3-10 never print the bare singular — the live defect',
        (tester) async {
      for (final n in [3, 5, 7, 10]) {
        final texts = await rendered(tester, n);
        expect(texts.any((t) => t.contains('$n صورة ')), isFalse,
            reason: '$n photos printed the singular: $texts');
        expect(texts, contains(portfolioCountLineAr(n)), reason: '$n photos');
      }
    });

    testWidgets('11+ return to the counted singular, not the plural',
        (tester) async {
      // «11 صورة» is right and «11 صور» is wrong: from eleven up the number
      // is what makes the noun singular. This assertion is deliberately the
      // mirror of the one above — a version of it that forbade the singular
      // everywhere would have "caught" this correct line as a defect.
      for (final n in [11, 15, 30]) {
        final texts = await rendered(tester, n);
        expect(texts, contains(portfolioCountLineAr(n)), reason: '$n photos');
        expect(texts.any((t) => t.contains('$n صور ')), isFalse,
            reason: '$n photos printed the 3-10 plural: $texts');
      }
    });

    testWidgets('an empty gallery still has no count line at all',
        (tester) async {
      final texts = await rendered(tester, 0);
      expect(texts.any((t) => t.contains('صورة في معرض أعمالك')), isFalse,
          reason: '$texts');
    });
  });
}
