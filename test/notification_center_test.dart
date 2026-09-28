// The notification centre is the record of what happened while the app was
// closed — the reason a user can reopen it and still know about the quote that
// arrived in the meantime.
//
// These tests drive the real widget tree, the real Repository and a fake HTTP
// client, and pin the three things the screen must never get wrong:
//   1. a developer key (`new_quote`) or any Latin string never reaches the user;
//   2. the unread pip can be cleared — a badge that only counts up is a bug;
//   3. a row opens the project it is about.
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
import 'package:allomokawil/src/data/chat_time.dart';
import 'package:allomokawil/src/data/notification_copy.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/notification.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';
import 'package:allomokawil/src/widgets/notifications_bell.dart';

// ── Fixtures ───────────────────────────────────────────────────────────────

/// One stored notification, shaped exactly like the D1 row the API returns.
///
/// The timestamp is relative to now on purpose: a fixed date would sit in the
/// future depending on when the suite runs, and «الآن» is the correct answer
/// for a future stamp — which would hide the time column from the assertions.
Map<String, Object?> _row({
  required int id,
  required String type,
  String title = 'عنوان',
  String? body = 'نص الإشعار',
  String? link,
  int isRead = 0,
  String? createdAt,
}) =>
    {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'link': link,
      'is_read': isRead,
      'created_at': createdAt ?? _stamp(const Duration(hours: 3)),
    };

/// A `created_at` the way D1 stores it: UTC, no zone marker.
String _stamp(Duration ago) {
  final t = DateTime.now().toUtc().subtract(ago);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// The project a notification can point at.
final _project = <String, Object?>{
  'id': '7',
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
  'status': 'open',
  'selected_worker_id': null,
  'created_at': '2026-09-11 20:23:44',
  'updated_at': '2026-09-11 20:23:44',
};

/// A fake backend that remembers what it was told, so «read» is state and not
/// just a recorded call: the reload after the write must agree with the write.
class _FakeBackend {
  _FakeBackend(this.rows, {this.unread = 0});

  List<Map<String, Object?>> rows;
  int unread;
  final List<String> log = [];
  Object? lastBody;

  ApiClient get client => ApiClient(
        baseUrls: const ['https://api.test'],
        httpClient: MockClient((req) async {
          final path = req.url.path;
          log.add('${req.method} $path');
          switch (path) {
            case '/api/notifications':
              return _json(rows);
            case '/api/unread':
              return _json({'unread': unread});
            case '/api/mobile/projects/7':
              return _json(_project);
            case '/api/mobile/projects/7/quotes':
              return _json(<Object>[]);
            case '/api/notifications/read':
              final decoded = req.body.isEmpty
                  ? const <String, Object?>{}
                  : jsonDecode(req.body) as Map<String, Object?>;
              lastBody = decoded;
              final ids = (decoded['ids'] as List?)
                  ?.map((v) => (v as num).toInt())
                  .toList();
              rows = [
                for (final r in rows)
                  if (ids == null || ids.contains(r['id']))
                    {...r, 'is_read': 1}
                  else
                    r,
              ];
              unread = rows.where((r) => r['is_read'] == 0).length;
              return _json({'unread': unread});
            default:
              return req.method == 'GET'
                  ? _json(<Object>[])
                  : _json({'ok': true});
          }
        }),
      );
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

/// The signed-in user those screens assume.
const _sessionUser = {
  'id': 7,
  'phone': '0550000000',
  'email': null,
  'full_name': 'Test User',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-01-01 00:00:00',
};

/// A session, because the screens in this file sit behind the bell and the bell
/// now opens the account form when there is nobody to show a centre to.
Future<AuthState> _signedIn(ApiClient api) async {
  SharedPreferences.setMockInitialValues({
    'auth.token': 'test-token',
    'auth.user': jsonEncode(_sessionUser),
  });
  final auth = AuthState(api);
  await auth.restore();
  return auth;
}

/// AppScope sits ABOVE MaterialApp, exactly as it does in the shipped app:
/// a screen pushed onto the navigator must still find it.
Widget _wrap(Widget child, ApiClient api, AuthState auth) => AppScope(
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
        home: child,
      ),
    );

/// A phone-shaped viewport with room for the whole list: a lazy ListView only
/// builds what fits, and an assertion about row six must not depend on scroll
/// position.
Future<void> _pump(WidgetTester tester, Widget child, ApiClient api) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(child, api, await _signedIn(api)));
  await tester.pumpAndSettle();
}

/// Rendered text only — what the user actually reads.
List<String> _shown(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .whereType<String>()
    .toList();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Copy ────────────────────────────────────────────────────────────────

  test('every API type maps to Arabic copy, never the raw key', () {
    for (final type in NotificationLook.knownTypes) {
      final look = NotificationLook.of(type);
      expect(look.label, isNotEmpty, reason: type);
      expect(look.label.contains('_'), isFalse, reason: '$type leaked its key');
      expect(RegExp(r'[A-Za-z]').hasMatch(look.label), isFalse,
          reason: '$type leaked Latin text: ${look.label}');
    }
    // The backend can add a type before the app knows about it.
    expect(NotificationLook.of('brand_new_event').label, 'إشعار');
    expect(NotificationLook.knownTypes.toSet().length,
        NotificationLook.knownTypes.length);
  });

  // ── Body ────────────────────────────────────────────────────────────────
  //
  // The `5/5` a review notification carries. Read live from
  // `/api/notifications` on 28 Sep 2026: the Worker sends the score as a bare
  // fraction and the card printed it. This is the widget-level proof, because
  // the rule alone cannot prove the screen called the rule.
  group('the line under the headline', () {
    Future<void> show(WidgetTester tester, String type,
        {String? body}) async {
      final api = _FakeBackend([
        {
          'id': 5,
          'type': type,
          'title': 'عنوان',
          'body': body,
          'link': null,
          'is_read': 0,
          'created_at': _stamp(const Duration(hours: 1)),
        }
      ]).client;
      await _pump(
          tester, NotificationsScreen(clock: () => DateTime.now()), api);
    }

    testWidgets('a review row never shows the raw 5/5', (tester) async {
      await show(tester, 'review_received', body: '5/5');
      expect(_shown(tester), contains('حصلت على تقييم 5 نجوم'));
      expect(_shown(tester), isNot(contains('5/5')));
    });

    testWidgets('words a person typed are shown exactly as typed',
        (tester) async {
      await show(tester, 'new_quote', body: 'جاهز للبدء');
      expect(_shown(tester), contains('جاهز للبدء'));
    });

    testWidgets('a row with no body still has its line', (tester) async {
      await show(tester, 'review_received');
      expect(_shown(tester), contains('لا تفاصيل'));
    });

    testWidgets('a message with no body points at the inbox', (tester) async {
      await show(tester, 'new_message');
      final shown = _shown(tester);
      expect(shown, isNot(contains('لا تفاصيل')));
      expect(shown.any((s) => s.contains('الرسائل')), isTrue);
    });

    testWidgets('no Latin fraction reaches any row', (tester) async {
      for (final b in <String?>[null, '', '  ', '5/5', '3/5', 'الجاهز غداً']) {
        await show(tester, 'review_received', body: b);
        expect(_shown(tester), isNot(contains('5/5')), reason: '"$b"');
        expect(
            _shown(tester).any((s) => RegExp(r'\d\s*/\s*\d').hasMatch(s)),
            isFalse,
            reason: 'a bare fraction was drawn for "$b"');
      }
    });
  });

  // ── Time ────────────────────────────────────────────────────────────────

  test('relative times read naturally in Arabic', () {
    final now = DateTime(2026, 9, 13, 12);
    String at(Duration ago) => relativeTimeAr(now.subtract(ago), now: now);

    expect(relativeTimeAr(null, now: now), '');
    expect(at(const Duration(seconds: 30)), 'الآن');
    expect(at(const Duration(minutes: 1)), 'قبل دقيقة');
    expect(at(const Duration(minutes: 2)), 'قبل دقيقتين');
    expect(at(const Duration(minutes: 7)), 'قبل 7 دقائق');
    expect(at(const Duration(minutes: 40)), 'قبل 40 دقيقة');
    expect(at(const Duration(hours: 3)), 'قبل 3 ساعات');
    expect(at(const Duration(days: 1)), 'أمس');
    expect(at(const Duration(days: 4)), 'قبل 4 أيام');
    expect(at(const Duration(days: 90)), 'قبل 3 أشهر');
    // A clock skew must not print «قبل -3 دقائق».
    expect(relativeTimeAr(now.add(const Duration(minutes: 5)), now: now), 'الآن');
  });

  // The day arithmetic is counted on the calendar, not in 24-hour periods, and
  // the two disagree at exactly the hours a phone is read. Each case below is
  // one the period count got wrong; the day arithmetic is the fix.
  test('twenty-seven hours old is the day before yesterday, not yesterday', () {
    // Read at 01:00; the message is from 22:00 the day before. `Duration.inDays`
    // floors 27h to 1 and the row printed «أمس» — yesterday — for a message two
    // calendar days old, while the chat divider on the same message correctly
    // said «25/09/2026». One screen's clock, two answers.
    final now = DateTime(2026, 9, 27, 1, 0);
    final at = DateTime(2026, 9, 25, 22, 0);
    expect(relativeTimeAr(at, now: now), 'قبل يومين');
    expect(chatDayLabel(at, now: now), '25/09/2026');
    // 24h and 23h on the same two dates are yesterday — the boundary the
    // period count used to get right by accident and the day count gets right
    // on purpose.
    expect(relativeTimeAr(DateTime(2026, 9, 25, 22, 0), now: DateTime(2026, 9, 26, 22, 0)), 'أمس');
  });

  test('a message from twenty minutes ago stays twenty minutes, day or not', () {
    // Crossing midnight must not make a 20-minute-old message «أمس»: inside
    // the first hour the honest answer is the elapsed time, and «أمس» would
    // read as a whole day the user never lost. The hour branches are period
    // arithmetic on purpose; only the day branches moved to the calendar.
    final now = DateTime(2026, 9, 27, 0, 10);
    expect(relativeTimeAr(DateTime(2026, 9, 26, 23, 50), now: now), 'قبل 20 دقيقة');
    expect(calendarDaysBetween(DateTime(2026, 9, 26, 23, 50), now), 1,
        reason: 'the day really did change — the copy just stays in minutes');
  });

  test('the day count is exact across short months and year ends', () {
    // The bug a `y*372 + m*31 + d` packing introduces: 27 Sep -> 1 Oct is
    // five "days" to a packed index and four to the calendar. The count has to
    // be the calendar's, so assert the month boundary in both directions.
    expect(calendarDaysBetween(DateTime(2026, 9, 27), DateTime(2026, 10, 1)), 4);
    expect(calendarDaysBetween(DateTime(2026, 10, 1), DateTime(2026, 9, 27)), -4);
    // February in a leap year, a 28-day month and a 30-day month.
    expect(calendarDaysBetween(DateTime(2024, 2, 1), DateTime(2024, 3, 1)), 29);
    expect(calendarDaysBetween(DateTime(2026, 2, 1), DateTime(2026, 3, 1)), 28);
    expect(calendarDaysBetween(DateTime(2026, 4, 30), DateTime(2026, 5, 1)), 1);
    // Year end, in both directions.
    expect(calendarDaysBetween(DateTime(2026, 12, 31), DateTime(2027, 1, 1)), 1);
    expect(calendarDaysBetween(DateTime(2026, 1, 1), DateTime(2027, 1, 1)), 365);
    expect(calendarDaysBetween(DateTime(2024, 1, 1), DateTime(2025, 1, 1)), 366);
    // The same calendar day is zero days apart whatever the hour.
    expect(calendarDaysBetween(DateTime(2026, 9, 27, 0, 1), DateTime(2026, 9, 27, 23, 59)), 0);
  });

  test('a month-old notification is a day count and never a negative one', () {
    final now = DateTime(2026, 9, 27, 12, 0);
    // 45 days -> «قبل شهر»; 90 days -> three months, not 3 days.
    expect(relativeTimeAr(DateTime(2026, 8, 13, 12, 0), now: now), 'قبل شهر');
    expect(relativeTimeAr(DateTime(2026, 6, 29, 12, 0), now: now), 'قبل 3 أشهر');
    // A clock skew still reads «الآن», never a negative count.
    expect(relativeTimeAr(now.add(const Duration(hours: 3)), now: now), 'الآن');
  });

  test('a zoneless D1 timestamp is read as UTC, not local', () {
    final t = parseServerTime('2026-09-13 10:00:00');
    expect(t, isNotNull);
    expect(t!.toUtc(), DateTime.utc(2026, 9, 13, 10));
    expect(parseServerTime(null), isNull);
    expect(parseServerTime(''), isNull);
    expect(parseServerTime('not a date'), isNull);
  });

  testWidgets('a row two days old is rendered as two days, not yesterday',
      (tester) async {
    // On the **screen**, not on the helper. Last cycle's lesson: a correct model
    // wired to an unfixed screen passes a first unit pass clean, so the cases
    // that matter have to be driven through the real widget tree.
    // **Pinned to noon, and that is the fix — found on 27 Sep 2026.** This
    // test used `DateTime.now()`, and a calendar-day assertion driven by the
    // wall clock is only true during part of every day.
    //
    // `now.subtract(Duration(days: 2, minutes: 30))` is an *elapsed* duration,
    // and the screen counts *calendar* days — the whole point of the code
    // under test. Between 00:00 and 00:30 the two disagree: at 00:20 on the
    // 27th, two days and thirty minutes earlier is the **24th** at 23:50, which
    // is three calendar days back, and the app quite correctly printed
    // «قبل 3 أيام».
    //
    // So the app was right and this test was wrong, and it had been passing only
    // because the loop has never run in the first half hour of a day: it failed
    // for real on the 27th, 00:05, and passed again minutes later. A test that
    // is green at 06:00 and red at 00:05 is not a test of the app, it is a test
    // of the hour, and it would have taken a user's real behaviour down with
    // it the day a release ran overnight.
    //
    // Noon is the one instant at which «N days and 30 minutes ago» is
    // unambiguously N calendar days back, so the assertion means what it says
    // at every hour of every day.
    final now = DateTime(DateTime.now().year, DateTime.now().month,
        DateTime.now().day, 12, 0);
    final twoDaysAgo = now.subtract(const Duration(days: 2, minutes: 30));
    String stamp(DateTime t) {
      final u = t.toUtc();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${u.year}-${two(u.month)}-${two(u.day)} '
          '${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
    }

    final backend = _FakeBackend(
      [_row(id: 1, type: 'new_quote', createdAt: stamp(twoDaysAgo))],
      unread: 1,
    );

    await _pump(
        tester,
        NotificationsScreen(
            repo: Repository(backend.client), clock: () => now),
        backend.client);

    final shown = _shown(tester);
    // 2 days and 30 minutes elapsed, and two calendar midnights crossed. A
    // 24-hour *period* count reads that as «أمس» and a user
    // is told a message from the 25th is from yesterday.
    expect(shown, isNot(contains('أمس')), reason: shown.join(' | '));
    expect(shown, contains('قبل يومين'), reason: shown.join(' | '));
  });

  testWidgets('the same elapsed span across a midnight is three calendar days',
      (tester) async {
    // The hour the test above used to break in, pinned as its own case so the
    // regression cannot come back through the wall clock.
    //
    // At 00:20 on the 27th, a notification stamped 2 days and 30 minutes
    // earlier is the **24th** at 23:50 — three midnights back, and «قبل 3
    // أيام» is the honest reading. The bug was never in the app: it was a
    // test asserting «دومين» from an *elapsed* duration while the app
    // counts *calendar* days, which only coincide outside the first half hour of
    // the day. This asserts the two agree where the previous version said they
    // must not, because here they are simply different questions.
    final now = DateTime(2026, 9, 27, 0, 20);
    final stamped = now.subtract(const Duration(days: 2, minutes: 30));
    expect(stamped, DateTime(2026, 9, 24, 23, 50));
    expect(calendarDaysBetween(stamped, now), 3);

    String stamp(DateTime t) {
      final u = t.toUtc();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${u.year}-${two(u.month)}-${two(u.day)} '
          '${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
    }

    final backend = _FakeBackend(
      [_row(id: 1, type: 'new_quote', createdAt: stamp(stamped))],
      unread: 1,
    );
    await _pump(
        tester,
        NotificationsScreen(
            repo: Repository(backend.client), clock: () => now),
        backend.client);

    final shown = _shown(tester);
    expect(shown, contains('قبل 3 أيام'), reason: shown.join(' | '));
  });

  // ── The centre ──────────────────────────────────────────────────────────

  testWidgets('the centre lists Arabic rows and clears them all', (tester) async {
    final backend = _FakeBackend(
      [
        _row(id: 1, type: 'new_quote', link: '/w/projects/7'),
        _row(id: 2, type: 'quote_accepted', link: '/dashboard/projects/9'),
        _row(id: 3, type: 'new_message', link: null),
        _row(id: 4, type: 'review_received', isRead: 1),
        _row(id: 5, type: 'project_update', isRead: 1),
        _row(id: 6, type: 'something_new', isRead: 1),
      ],
      unread: 3,
    );

    await _pump(tester, NotificationsScreen(repo: Repository(backend.client)),
        backend.client);

    final shown = _shown(tester);
    expect(shown, contains('عرض سعر جديد'));
    expect(shown, contains('تم قبول عرضك'));
    expect(shown, contains('رسالة جديدة'));
    expect(shown, contains('تقييم جديد'));
    expect(shown, contains('تحديث على المشروع'));
    expect(shown, contains('إشعار')); // the unknown type, in words
    expect(shown.any((s) => s.contains('new_quote')), isFalse);
    expect(shown.any((s) => s.contains('something_new')), isFalse);
    expect(shown.where((s) => s == 'جديد').length, 3,
        reason: 'one pip per unread row');
    expect(shown.where((s) => s.startsWith('قبل')).isNotEmpty, isTrue,
        reason: 'every row carries a time');

    // Clearing the unread state is the whole point of the endpoint.
    await tester.tap(find.byKey(const Key('notifications-mark-all')));
    await tester.pumpAndSettle();

    expect(backend.log.where((l) => l == 'POST /api/notifications/read').length,
        1);
    expect(backend.lastBody, isEmpty);
    expect(backend.unread, 0);
    expect(_shown(tester).where((s) => s == 'جديد'), isEmpty);
    expect(find.byKey(const Key('notifications-mark-all')), findsNothing);
  });

  testWidgets('tapping one row marks that row read and no other',
      (tester) async {
    final backend = _FakeBackend([
      _row(id: 41, type: 'new_quote'),
      _row(id: 42, type: 'new_message'),
    ], unread: 2);

    await _pump(tester, NotificationsScreen(repo: Repository(backend.client)),
        backend.client);

    await tester.tap(find.byKey(const Key('notification-42')));
    await tester.pumpAndSettle();

    expect(backend.lastBody, {
      'ids': [42]
    });
    expect(backend.rows.firstWhere((r) => r['id'] == 42)['is_read'], 1);
    expect(backend.rows.firstWhere((r) => r['id'] == 41)['is_read'], 0);
  });

  testWidgets('a project row opens the project it is about', (tester) async {
    final backend = _FakeBackend([
      _row(id: 7, type: 'new_quote', link: '/w/projects/7'),
    ], unread: 1);

    await _pump(tester, NotificationsScreen(repo: Repository(backend.client)),
        backend.client);

    await tester.tap(find.byKey(const Key('notification-7')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    expect(backend.log, contains('GET /api/mobile/projects/7'));
  });

  testWidgets('an empty centre explains itself and offers a way back',
      (tester) async {
    final backend = _FakeBackend(const []);

    await _pump(tester, NotificationsScreen(repo: Repository(backend.client)),
        backend.client);

    final shown = _shown(tester);
    expect(shown, contains('لا توجد إشعارات بعد'));
    expect(shown.any((s) => s.contains('عروض الأسعار')), isTrue);
    expect(find.widgetWithText(OutlinedButton, 'رجوع'), findsOneWidget);
  });

  // ── The bell ────────────────────────────────────────────────────────────

  testWidgets('the bell counts the unread notifications', (tester) async {
    final backend = _FakeBackend(const [], unread: 5);
    await _pump(
        tester, NotificationsBell(repo: Repository(backend.client)),
        backend.client);
    expect(find.byKey(const Key('notifications-badge')), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('the bell caps the count at 99+', (tester) async {
    final backend = _FakeBackend(const [], unread: 150);
    await _pump(
        tester, NotificationsBell(repo: Repository(backend.client)),
        backend.client);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('no unread means no pip at all', (tester) async {
    final backend = _FakeBackend(const [], unread: 0);
    await _pump(
        tester, NotificationsBell(repo: Repository(backend.client)),
        backend.client);
    expect(find.byKey(const Key('notifications-bell')), findsOneWidget);
    expect(find.byKey(const Key('notifications-badge')), findsNothing);
  });

  // A quote that lands while the phone is locked is the normal case, not the
  // edge case: the founder's own report on the centre is that what arrives
  // while the app is closed is what he opens the app for. The pip is the only
  // line on the home screen that claims something arrived, and it is read at a
  // glance, so a pip frozen at launch is a header that says «nothing new» over
  // a quote worth 40 000 DZD.
  testWidgets('the pip comes up when the app returns to the foreground',
      (tester) async {
    final backend = _FakeBackend(const [], unread: 0);

    await _pump(
        tester, NotificationsBell(repo: Repository(backend.client)),
        backend.client);
    expect(find.byKey(const Key('notifications-badge')), findsNothing);

    // The phone was locked, a quote arrived, the phone is unlocked.
    backend.unread = 1;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notifications-badge')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    // Exactly one extra read, not one per lifecycle message: `_refreshing`
    // is what stops a fast resume/lock/resume from racing two answers.
    expect(backend.log.where((l) => l == 'GET /api/unread').length, 2);
  });

  testWidgets('resuming does not spend a request while the app is not usable',
      (tester) async {
    final backend = _FakeBackend(const [], unread: 3);

    await _pump(
        tester, NotificationsBell(repo: Repository(backend.client)),
        backend.client);
    final after = backend.log.where((l) => l == 'GET /api/unread').length;

    // `inactive` is the app switcher, a permission sheet and an incoming
    // dialog. The screen behind it is not readable yet, so a read there is
    // data the user pays for to draw a number they have not looked at.
    for (final state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pumpAndSettle();
    }
    expect(backend.log.where((l) => l == 'GET /api/unread').length, after);

    backend.unread = 4;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('a double resume spends one request, not two', (tester) async {
    final backend = _FakeBackend(const [], unread: 1);

    await _pump(
        tester, NotificationsBell(repo: Repository(backend.client)),
        backend.client);
    final after = backend.log.where((l) => l == 'GET /api/unread').length;

    // Android sends `resumed` on every return to the foreground, and a phone
    // that is unlocked twice in a row while a 3G request is open would
    // otherwise queue a second read behind the first. Two answers then race to
    // `setState`, and the slower one wins — so the pip shows a count from
    // before the newer read. A badge that goes backwards on resume is worse
    // than one that is briefly stale, so the second resume is dropped instead.
    backend.unread = 2;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // No pump between the two: both land inside the same frame, with the
    // first request still open.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(backend.log.where((l) => l == 'GET /api/unread').length,
        after + 1);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('opening the centre and clearing it drops the pip', (tester) async {
    final backend = _FakeBackend([
      _row(id: 3, type: 'new_message'),
    ], unread: 1);

    await _pump(
        tester, NotificationsBell(repo: Repository(backend.client)),
        backend.client);
    expect(find.byKey(const Key('notifications-badge')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifications-bell')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notifications-mark-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(backend.unread, 0);
    expect(find.byKey(const Key('notifications-badge')), findsNothing);
  });
}
