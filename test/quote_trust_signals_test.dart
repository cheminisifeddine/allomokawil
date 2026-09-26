// The photo and the verified tick the API sends on every quote, and the quote
// card used to print neither.
//
// `GET /api/mobile/projects/{id}/quotes` returns `worker_avatar_url` and
// `worker_verification_status`. `Quote.fromJson` parsed both. The card drew a
// coloured circle with the contractor's first letter and stopped — so a
// customer choosing between four bids chose between four monograms, and a
// **verified** contractor looked exactly like an unverified one on the one
// screen where he is about to hand someone his house.
//
// Fifth in a row of the same shape: the server sends it, the model parses it,
// the read path drops it. These are the unit-level rules; the screen itself is
// driven in `quote_trust_widget_test.dart`, because a correct widget wired to
// nothing is how this class of fix rots silently.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/quote_review.dart';
import 'package:allomokawil/src/widgets/net_image.dart';
import 'package:allomokawil/src/widgets/quote_worker_trust.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// Verbatim from the live API — `test/live_payload_models_test.dart` carries
/// the same row, `worker_avatar_url` and `worker_verification_status` included.
const _quoteJson = '''
{"id":13,"project_id":"b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551",
 "worker_id":16,"amount":75000,"message":"جاهز للبدء فوراً","estimated_days":5,
 "status":"pending","created_at":"2026-09-11 20:23:45",
 "updated_at":"2026-09-11 20:23:45","worker_full_name":"مقاول تجربة",
 "worker_avatar_url":null,"worker_avg_rating":0,"worker_total_reviews":0,
 "worker_verification_status":"pending"}''';

Quote _quote({
  int id = 13,
  String? avatar,
  String status = 'pending',
  String name = 'مقاول تجربة',
}) =>
    Quote(
      id: id,
      projectId: 'b0b5644a223e43f37bf8d675bfb78ae509c0869d31103748489b45ece551',
      workerId: 16,
      amount: 75000,
      workerFullName: name,
      workerAvatarUrl: avatar,
      workerAvgRating: 0,
      workerTotalReviews: 0,
      workerVerificationStatus: status,
    );

Widget _host(Quote q) => MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: Scaffold(body: QuoteWorkerTrust(quote: q)),
    );

void main() {
  group('the payload really carries the two fields', () {
    test('the live quote row parses both, and the old card used neither', () {
      final json = jsonDecode(_quoteJson) as Map<String, dynamic>;
      final q = Quote.fromJson(json);
      expect(json.containsKey('worker_avatar_url'), isTrue);
      expect(json.containsKey('worker_verification_status'), isTrue);
      expect(q.workerVerificationStatus, 'pending');
      expect(q.workerAvatarUrl, isNull);
    });
  });

  group('which wire values earn a tick', () {
    test('only a literal verified is verified', () {
      expect(quoteWireVerification('verified'), VerificationStatus.verified);
    });

    test('pending, rejected, junk and absent are all "not verified"', () {
      for (final v in const [null, '', 'pending', 'rejected', 'VERIFIED', '1']) {
        expect(quoteWireVerification(v), isNot(VerificationStatus.verified),
            reason: '«$v» must not pass as verified');
      }
    });
  });

  group('the avatar', () {
    testWidgets('a photo is drawn as a network image, not a monogram',
        (tester) async {
      const url = 'https://cdn.test/avatar.png';
      await tester.pumpWidget(_host(_quote(avatar: url)));
      await tester.pump();
      expect(find.byType(NetImage), findsOneWidget);
      expect(tester.widget<NetImage>(find.byType(NetImage)).url, url);
      // Not `findsNothing` here. Under TestWidgetsFlutterBinding every
      // HttpClient answers 400, so the load always fails and the deliberate
      // errorBuilder puts the monogram back. That fallback is the claim worth
      // pinning — a dead photo URL must degrade to a letter, never to a broken
      // image glyph — and it is asserted on its own, below.
    });

    testWidgets('no photo falls back to the monogram', (tester) async {
      await tester.pumpWidget(_host(_quote()));
      await tester.pump();
      expect(find.byType(NetImage), findsNothing);
      expect(find.byType(InitialAvatar), findsOneWidget);
    });

    testWidgets('an empty or blank url is a monogram, not a broken image',
        (tester) async {
      for (final bad in const ['', '   ']) {
        await tester.pumpWidget(_host(_quote(avatar: bad)));
        await tester.pump();
        expect(find.byType(NetImage), findsNothing, reason: 'url «$bad»');
        expect(find.byType(InitialAvatar), findsOneWidget, reason: 'url «$bad»');
      }
    });
  });

  group('the badge', () {
    testWidgets('verified draws the green tick', (tester) async {
      await tester.pumpWidget(_host(_quote(status: 'verified')));
      await tester.pump();
      final icon = tester.widget<Icon>(find.byIcon(Icons.verified_rounded));
      expect(icon.color, AppTheme.success);
    });

    testWidgets('pending draws the clock — "asked, not answered" is not "no"',
        (tester) async {
      await tester.pumpWidget(_host(_quote(status: 'pending')));
      await tester.pump();
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
    });

    testWidgets('rejected draws nothing — no tick and no clock', (tester) async {
      await tester.pumpWidget(_host(_quote(status: 'rejected')));
      await tester.pump();
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('an absent status is treated as pending, not as verified',
        (tester) async {
      await tester.pumpWidget(_host(_quote(status: '')));
      await tester.pump();
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    });

    test('the standalone icon agrees with the composited badge', () {
      expect(quoteVerificationIcon(_quote(status: 'verified')), isNotNull);
      expect(quoteVerificationIcon(_quote(status: 'rejected')), isNull);
      expect(quoteVerificationIcon(_quote(status: 'pending')), isNotNull);
    });
  });

  group('the badge is a badge, not a second avatar', () {
    testWidgets('it never grows past the avatar it is pinned to',
        (tester) async {
      await tester.pumpWidget(_host(_quote(avatar: 'https://x.test/a.png')));
      await tester.pump();
      // Measured against the whole trust block, not a ClipOval: the badge is
      // `Positioned`, so it contributes no size of its own and the avatar is
      // what fixes the box.
      final avatar = tester.getSize(find.byType(QuoteWorkerTrust));
      final badge = tester.getSize(find.byIcon(Icons.schedule_rounded));
      expect(avatar.width, 48.0);
      expect(badge.width, lessThan(avatar.width));
      expect(badge.height, lessThan(avatar.height));
    });

    testWidgets('a verified bid and a pending one do not draw the same badge',
        (tester) async {
      // The control, and it is deliberately not a size comparison. Both states
      // render the same 48x48 box, so any "they differ" check written on
      // geometry passes on a widget that draws nothing at all — which is
      // exactly what the previous revision of this file did. The difference
      // that is real is *which* mark is on the corner.
      await tester.pumpWidget(_host(_quote(avatar: 'https://x.test/a.png',
          status: 'verified')));
      await tester.pump();
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);

      await tester.pumpWidget(_host(_quote(avatar: 'https://x.test/a.png',
          status: 'pending')));
      await tester.pump();
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    });
  });
}
