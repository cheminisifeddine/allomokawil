// A bid the server had already refused was still drawn as a live decision.
//
// Found on 29 Sep 2026 by driving a real accept against the live API, not by
// reading the widget. Two contractors bid on one project; the owner accepted
// the first; the Worker answered `GET /projects/:id/quotes` with a verdict on
// each row:
//
//   quote 48 -> status "accepted"     the bid the project is committed to
//   quote 49 -> status "rejected"     the other contractor, dropped at that
//                                      same moment
//
// and `Quote.fromJson` **dropped the field**. So the losing card kept a live,
// enabled «قبول العرض» button. Tapping it — which is exactly what an owner who
// changed his mind does, and exactly what a customer does when the list draws
// the wrong man on top — POSTs the accept, the server answers `{"ok":true}`,
// the screen reloads, and the card is **byte-for-byte identical** to the one
// before the tap.
//
// The worse half is what the screen is therefore claiming. The project reads
// `selected_worker_id: 125` — the bid that *won* — while the card he just
// tapped offers 126 and says nothing. Accepting the rejected quote 49 on the
// live API returned 200 and changed neither `selected_worker_id` nor either
// row's status: the one write in this product that signs a contract appeared
// to succeed while committing nothing, and the sentence under the button
// («بالقبول تُرفض باقي العروض تلقائياً») told him the rejection was still
// ahead of him when it had already happened.
//
// What this file pins:
//
//   1. the parser reads `status`, and `created_at` with it — both sent on
//      every real row and both dropped before;
//   2. an unknown or absent status is *pending*, never a throw and never
//      "rejected" — the card stays drawable;
//   3. the owner's copy: a decided bid carries no accept button, no
//      «تُرفض باقي العروض» sentence, and the verdict instead;
//   4. a live bid is untouched — the button is still there, the stamp is
//      still absent. A fix that greys out everything is not a fix.
//
// The [StatusPill.quote] shape is checked here rather than in a golden so a
// word change is a one-line diff, and the pixel evidence lives in the render
// tests at the bottom of this file.
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
import 'package:allomokawil/src/data/quote_status_copy.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/quote_review.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// The exact row the Worker sent, captured from production on 29 Sep 2026.
/// Verbatim, including the two fields the old parser threw away.
const String _liveAcceptedRow = '''{
  "id": 48,
  "project_id": "p1",
  "worker_id": 125,
  "amount": 6000,
  "message": "أعرض تنفيذ العمل خلال 5 أيام",
  "estimated_days": 5,
  "status": "accepted",
  "created_at": "2026-09-29 17:00:53",
  "updated_at": "2026-09-29 17:00:53",
  "worker_full_name": "خالد رحماني",
  "worker_avatar_url": null,
  "worker_avg_rating": 0,
  "worker_total_reviews": 0,
  "worker_verification_status": "pending"
}''';

const String _liveRejectedRow = '''{
  "id": 49,
  "project_id": "p1",
  "worker_id": 126,
  "amount": 5200,
  "message": "عرض ثانٍ للترتيب",
  "estimated_days": 3,
  "status": "rejected",
  "created_at": "2026-09-29 17:01:35",
  "updated_at": "2026-09-29 17:01:35",
  "worker_full_name": "مقاول ثانٍ للترتيب",
  "worker_avatar_url": null,
  "worker_avg_rating": 0,
  "worker_total_reviews": 0,
  "worker_verification_status": "pending"
}''';

Map<String, dynamic> _row(int id, {String status = 'pending'}) => <String, dynamic>{
      'id': id,
      'project_id': 'p1',
      'worker_id': 100 + id,
      'amount': 5000 + id,
      'message': 'عرض تجريبي',
      'estimated_days': 5,
      'status': status,
      'created_at': '2026-09-29 17:00:53',
      'worker_full_name': 'مقاول رقم $id',
      'worker_avatar_url': null,
      'worker_avg_rating': 0,
      'worker_total_reviews': 0,
      'worker_verification_status': 'verified',
    };

Map<String, dynamic> _user(String type) => <String, dynamic>{
      'id': type == 'worker' ? 31 : 30,
      'phone': '0773000000',
      'email': null,
      'full_name': type == 'worker' ? 'مقاول تجربة' : 'زبون تجربة',
      'type': type,
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

Map<String, dynamic> _project({String status = 'open'}) => <String, dynamic>{
      'id': 'p1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': 'دهان كامل مع تصليح',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'latitude': null,
      'longitude': null,
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': status,
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// The instant every age in this file is measured against. Fixed, because
/// `relativeTimeAr` renders from the difference to now and a test that reads
/// the real clock passes on one run and fails on the next.
final DateTime _now = DateTime.utc(2026, 9, 29, 17, 0, 53);

void main() {
  group('the wire row, verbatim from production', () {
    test('the accepted row the Worker sent parses to a decided bid', () {
      final q = Quote.fromJson(jsonDecode(_liveAcceptedRow) as Map<String, dynamic>);
      expect(q.status, QuoteStatus.accepted);
      expect(q.isDecided, isTrue);
      expect(q.id, 48);
      expect(q.amount, 6000);
      expect(q.estimatedDays, 5);
    });

    test('the rejected row parses to a decided bid, not a live one', () {
      final q = Quote.fromJson(jsonDecode(_liveRejectedRow) as Map<String, dynamic>);
      expect(q.status, QuoteStatus.rejected);
      expect(q.isDecided, isTrue);
      expect(q.id, 49);
    });

    test('created_at is parsed, not dropped — the sibling of the review row', () {
      // The exact defect shipped on `Review` last cycle: the field is on the
      // wire, in the POST answer *and* the GET, and the parser threw it away.
      final q = Quote.fromJson(jsonDecode(_liveAcceptedRow) as Map<String, dynamic>);
      expect(q.createdAt, isNotNull,
          reason: 'the Worker sends created_at on every quote');
      expect(q.createdAt!.toUtc().hour, 17);
      expect(q.createdAt!.toUtc().minute, 0);
    });

    test('a row with no status is pending, and a row with a new one is too', () {
      // Neither is a reason to throw inside somebody's widget build, and
      // neither is evidence that a bid is dead.
      expect(QuoteStatus.from(null), QuoteStatus.pending);
      expect(QuoteStatus.from(''), QuoteStatus.pending);
      expect(QuoteStatus.from('cancelled_by_customer'), QuoteStatus.pending);
      final missing = _row(1)..remove('status');
      expect(Quote.fromJson(missing).status, QuoteStatus.pending);
      expect(Quote.fromJson(missing).isDecided, isFalse);
    });
  });

  group('the Arabic, without a widget', () {
    test('a live bid says nothing at all', () {
      expect(quoteStatusAr(QuoteStatus.pending), '');
      expect(quoteStatusNoteAr(QuoteStatus.pending), '');
    });

    test('a decided bid is named and explained', () {
      expect(quoteStatusAr(QuoteStatus.accepted), 'مقبول');
      expect(quoteStatusAr(QuoteStatus.rejected), 'مرفوض');
      expect(quoteStatusNoteAr(QuoteStatus.accepted), isNotEmpty);
      expect(quoteStatusNoteAr(QuoteStatus.rejected), isNotEmpty);
      expect(quoteStatusNoteAr(QuoteStatus.rejected), contains('عرض آخر'),
          reason: 'the owner must learn which bid he picked, not just that this one lost');
      // The note must not simply repeat the stamp three lines above it: the
      // stamp says this bid was refused, the note has to say what happened
      // instead.
      expect(quoteStatusNoteAr(QuoteStatus.rejected),
          isNot(contains('مرفوض')));
    });

    test('the note never claims the rejection is still to come', () {
      // The sentence under the old button was «بالقبول تُرفض باقي العروض
      // تلقائياً» — future tense, and it was still there *after* the other bids
      // had already been rejected. A decided bid cannot carry it.
      expect(quoteStatusNoteAr(QuoteStatus.rejected), isNot(contains('تلقائياً')));
    });
  });

  group('the card', () {
    late List<String> log;

    /// The signed-in owner, held between [boot] and [pump] so the screen and
    /// the fake API are the same pair — two clients would be two servers.
    AuthState? booted;

    /// A signed-in owner whose project carries [rows], and whose fake API
    /// answers the accept with [after] — the payload the Worker really sends
    /// once the owner has committed to a bid.
    ///
    /// Both halves matter. Without [after] the screen would reload into the
    /// same live list and the test would be asserting against a state the
    /// server can never produce; with it, the card under test is the one the
    /// owner is looking at **after** his tap, which is the only moment the
    /// defect was ever visible to a human.
    Future<ApiClient> boot(
      List<Map<String, dynamic>> rows, {
      List<Map<String, dynamic>>? after,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      log = <String>[];
      var committed = false;
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          log.add('${req.method} $p');
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json(<String, Object>{'token': 'tok', 'user': _user('customer')});
          }
          if (p.endsWith('/api/unread')) return _json(0);
          if (p.startsWith('/api/mobile/projects/p1/quotes/') &&
              p.endsWith('/accept')) {
            committed = true;
            return _json(<String, Object>{'ok': true});
          }
          if (p.startsWith('/api/mobile/projects/p1/quotes')) {
            return _json(committed && after != null ? after : rows);
          }
          if (p == '/api/mobile/projects/p1') {
            return _json(_project(
                status: committed ? 'in_progress' : 'open'));
          }
          return _json(<Object>[]);
        }),
      );
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      booted = auth;
      expect(auth.role.name, 'customer',
          reason: 'the fixture must land on the owner, or the action row is not drawn at all');
      return api;
    }

    Future<void> pump(WidgetTester tester, ApiClient api) async {
      tester.view.physicalSize = const Size(392, 2400) * 2.75;
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final repo = Repository(api);
      await tester.pumpWidget(AppScope(
        api: api,
        auth: booted!,
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
          home: ProjectDetailScreen(
            projectId: 'p1',
            repo: repo,
            clock: () => _now,
          ),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    /// Two live bids — the state a project is in from the moment it is posted
    /// until the owner taps one.
    final live = <Map<String, dynamic>>[_row(48), _row(49)];

    /// What the Worker sends once the owner has accepted bid 48: 48 becomes
    /// `accepted`, **49 is `rejected` at the same moment**, and the project
    /// moves to `in_progress`. Captured on production, 29 Sep 2026.
    final decided = <Map<String, dynamic>>[
      _row(48, status: 'accepted'),
      _row(49, status: 'rejected'),
    ];

    testWidgets('before the tap, both bids are live and both carry the button',
        (tester) async {
      final api = await boot(live);
      await pump(tester, api);
      expect(find.text('قبول العرض'), findsNWidgets(2));
      expect(find.text('مقبول'), findsNothing);
      expect(find.text('مرفوض'), findsNothing);
      expect(find.text(quoteStatusNoteAr(QuoteStatus.rejected)), findsNothing);
    });

    testWidgets(
        'after the tap, the losing bid has no button and says it lost — the '
        'whole defect', (tester) async {
      final api = await boot(live, after: decided);
      await pump(tester, api);

      // The tap, on the card as it looked before the tap.
      final tap = find.text('قبول العرض').first;
      await tester.ensureVisible(tap);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(tap);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      // **Zero** buttons, not two and not one. The backend rejects *every*
      // other bid at the moment one is accepted, so after a commit there is
      // nothing left on the table — and the screen used to draw a live
      // «قبول العرض» under **each** of the two cards, which means the owner
      // was offered, by the app, a decision the server had already made for
      // him. Tapping that second button POSTs an accept the backend refuses,
      // the call answers 200, and the reload produces a list that looks
      // identical to the one before the tap.
      expect(find.text('قبول العرض'), findsNothing);
      expect(log.where((e) => e.endsWith('/accept')).length, 1);

      // And the refusal is *visible* — this is the half the old card could not
      // draw, because the model had thrown the verdict away.
      expect(find.text('مقبول'), findsOneWidget);
      expect(find.text('مرفوض'), findsOneWidget);
      expect(find.text(quoteStatusNoteAr(QuoteStatus.accepted)), findsOneWidget);
      expect(find.text(quoteStatusNoteAr(QuoteStatus.rejected)), findsOneWidget);
    });

    testWidgets('the rejected bid cannot fire a second accept', (tester) async {
      // The guard has to be the *absence of the button*, not a flag on it: a
      // disabled button still invites the tap, and the card the owner is
      // reading after a commit is the losing one.
      final api = await boot(live, after: decided);
      await pump(tester, api);
      final tap = find.text('قبول العرض').first;
      await tester.ensureVisible(tap);
      await tester.tap(tap);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      // No button anywhere, so there is nothing to tap and nothing to POST.
      // The guard is the absence of the control rather than a disabled control:
      // a greyed «قبول العرض» still reads as "available, just busy", which is
      // how an owner talks himself into a second commit.
      expect(find.text('قبول العرض'), findsNothing);
      final posts = log.where((e) => e.endsWith('/accept')).length;
      expect(posts, 1, reason: 'the accept fired exactly once, on the tap');
      final doomed = tester.takeException();
      expect(doomed, isNull);
    });

    testWidgets('the «the rest are rejected» sentence belongs to the live bid only',
        (tester) async {
      final api = await boot(live, after: decided);
      await pump(tester, api);
      final tap = find.text('قبول العرض').first;
      await tester.ensureVisible(tap);
      await tester.tap(tap);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      // **None.** The sentence is in the future tense — «the rest *will* be
      // rejected» — and it was true exactly once, before the tap. After a commit
      // the rest already have been, so printing it under a card is the app
      // telling the owner to expect something that happened while he watched.
      // Under the old card it was under **every** card, refused ones included.
      expect(find.text('بالقبول تُرفض باقي العروض تلقائياً.'), findsNothing);
    });

    testWidgets('a live list still promises the rejection — the sentence is not deleted',
        (tester) async {
      // The other half, and the reason the fix is a gate rather than a delete:
      // before any commit the sentence is the *truth* — accepting one bid does
      // reject the rest — so removing it outright would be a regression.
      final api = await boot(live);
      await pump(tester, api);
      expect(find.text('بالقبول تُرفض باقي العروض تلقائياً.'), findsNWidgets(2));
    });

    testWidgets('the date line reaches the card through the shared clock',
        (tester) async {
      final api = await boot([_row(48, status: 'accepted')]);
      await pump(tester, api);
      expect(find.text('مقبول'), findsOneWidget);
      // The row is dated 29 Sep 17:00:53 and the injected clock is that same
      // instant, so the line reads «الآن» — the one word a stale golden cannot
      // reproduce, which is why this file pins it here and not in a PNG.
      expect(find.text('الآن'), findsOneWidget);
    });
  });

  group('the pill', () {
    test('a decided bid gets a stamp and a live one does not', () {
      // The card gates on `isDecided`; the factory is a pure function of the
      // status, so this is the shape the two decided cards share.
      expect(StatusPill.quote(QuoteStatus.accepted).label, 'مقبول');
      expect(StatusPill.quote(QuoteStatus.rejected).label, 'مرفوض');
      expect(StatusPill.quote(QuoteStatus.pending).label, isNot('مقبول'));
    });
  });
}
