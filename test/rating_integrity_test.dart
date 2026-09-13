// The rating contract: a review that nobody chose is not a review.
//
// `_rating` opened at 5, so the fastest path through the screen — tap the
// orange button — published a five-star review on behalf of a user who never
// looked at the picker. For a marketplace whose entire promise is "the rating
// tells you who to trust", that is the one bug that cannot ship: it inflates
// every contractor at once. The tests below hold the line on both halves of
// the fix: the screen starts empty, and an empty screen cannot submit.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/review/review_screen.dart';

/// Records every review the screen tries to publish.
class _Recorder {
  final reviews = <Map<String, dynamic>>[];

  ApiClient client() => ApiClient(
        baseUrls: ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/review')) {
            reviews.add(jsonDecode(req.body) as Map<String, dynamic>);
            return http.Response(
                '{"id":1,"worker_id":16,"rating":2,"comment":null,'
                '"created_at":"2026-09-13T00:00:00Z"}',
                201,
                headers: {'content-type': 'application/json'});
          }
          return http.Response('{"error":"unexpected"}', 404,
              headers: {'content-type': 'application/json'});
        }),
      );
}

Future<_Recorder> _pump(WidgetTester tester) async {
  final rec = _Recorder();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ar'),
    home: ReviewScreen(
      projectId: 'demo-project',
      workerId: 16,
      repo: Repository(rec.client()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return rec;
}

/// Stars *inside the picker* — the trust line at the bottom of the screen also
/// carries a single star glyph, and it is not part of the control.
Finder _pickerStars(IconData icon) => find.descendant(
    of: find.byType(InkWell), matching: find.byIcon(icon));

void main() {
  testWidgets('opens with no stars chosen', (tester) async {
    await _pump(tester);

    // Five empty stars, zero filled ones — the user's own scale, drawn.
    expect(_pickerStars(Icons.star_outline_rounded), findsNWidgets(5));
    expect(_pickerStars(Icons.star_rounded), findsNothing);
    expect(find.text('اختر تقييماً'), findsOneWidget);
  });

  testWidgets('submitting an untouched screen sends nothing', (tester) async {
    final rec = await _pump(tester);

    await tester.tap(find.text('إرسال التقييم'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(rec.reviews, isEmpty,
        reason: 'a rating nobody picked must never reach the API');
    expect(find.text('اختر عدد النجوم أولاً'), findsOneWidget,
        reason: 'the user has to be told what is missing, in Arabic');
  });

  testWidgets('picking 2 of 5 sends exactly 2', (tester) async {
    final rec = await _pump(tester);

    await tester.tap(_pickerStars(Icons.star_outline_rounded).at(1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_pickerStars(Icons.star_outline_rounded), findsNWidgets(3));
    expect(_pickerStars(Icons.star_rounded), findsNWidgets(2));

    await tester.tap(find.text('إرسال التقييم'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(rec.reviews, hasLength(1));
    expect(rec.reviews.single['rating'], 2);
    expect(rec.reviews.single['worker_id'], 16);
  });
}
