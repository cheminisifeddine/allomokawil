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

  test('a zoneless D1 timestamp is read as UTC, not local', () {
    final t = parseServerTime('2026-09-13 10:00:00');
    expect(t, isNotNull);
    expect(t!.toUtc(), DateTime.utc(2026, 9, 13, 10));
    expect(parseServerTime(null), isNull);
    expect(parseServerTime(''), isNull);
    expect(parseServerTime('not a date'), isNull);
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
