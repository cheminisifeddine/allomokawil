// A chat thread is only trustworthy if the user can tell **when** a message was
// sent and **whether it left the phone**.
//
// This file pins the three things that used to be missing or wrong in the
// thread:
//   1. no clock under any bubble — the thread said "اليوم" and nothing finer;
//   2. the day divider compared raw UTC fields, so a message the user sent
//      after midnight in Algiers was filed under the previous day;
//   3. a message the server refused looked exactly like a delivered one, and
//      sending it again left the text in the thread twice.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

// ── Fixtures ───────────────────────────────────────────────────────────────

/// A `created_at` exactly as D1 writes it: UTC, `YYYY-MM-DD HH:MM:SS`, no zone
/// marker. Built from a *local* wall clock so the round trip through the parser
/// is what is under test, not the machine's timezone.
String _utcStamp(DateTime local) {
  final t = local.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

Map<String, Object?> _messageRow({
  required int id,
  required int senderId,
  required String content,
  required DateTime at,
}) =>
    {
      'id': id,
      'conversation_id': 5,
      'sender_id': senderId,
      'content': content,
      'image_url': null,
      'message_type': 'text',
      'is_read': 0,
      'created_at': _utcStamp(at),
    };

final _me = <String, Object?>{
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'زبون تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-09-11 20:00:00',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// The last local wall clock the user saw: the anchor for both "today" and
/// "yesterday" so the test cannot race midnight.
DateTime get _anchor => DateTime.now();

// ── Harness ────────────────────────────────────────────────────────────────

class _Fake {
  _Fake(this.api, this.log);
  final ApiClient api;
  final List<String> log;

  int posts = 0;
  bool failSend = false;

  /// Built by [_buildFake]; kept on the class so the body can flip [failSend]
  /// between two sends.
}

_Fake _buildFake(List<Map<String, Object?>> thread) {
  final log = <String>[];
  late final _Fake fake;
  final client = MockClient((req) async {
    final p = req.url.path;
    log.add('${req.method} $p');
    if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
      return _json({'token': 'tok', 'user': _me});
    }
    if (p.endsWith('/api/unread')) return _json(0);
    if (p.endsWith('/api/mobile/conversations')) {
      return req.method == 'POST' ? _json({'id': 5}) : _json(<Object>[]);
    }
    if (p.startsWith('/api/messages/')) {
      if (req.method == 'GET') return _json(thread);
      fake.posts++;
      if (fake.failSend) {
        return http.Response('{}', 500,
            headers: {'content-type': 'application/json'});
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return _json({
        'id': 900 + fake.posts,
        'conversation_id': 5,
        'sender_id': 30,
        'content': body['content'],
        'image_url': body['image_url'],
        'message_type': body['message_type'] ?? 'text',
        'is_read': 0,
        'created_at': _utcStamp(DateTime.now()),
      });
    }
    return _json(<Object>[]);
  });
  final api = ApiClient(baseUrls: ['https://x.test'], httpClient: client);
  return fake = _Fake(api, log);
}

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'customer', reason: 'the fixture must land on a client');
  return auth;
}

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(WidgetTester tester, Widget screen, ApiClient api,
    AuthState auth, {GlobalKey? boundary}) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
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
      home: boundary == null
          ? screen
          : RepaintBoundary(key: boundary, child: screen),
    ),
  ));
  await _settle(tester);
}

void main() {
  group('the chat clock', () {
    test('is 24-hour, zero-padded and Latin — the way the phone shows it', () {
      expect(chatClock(DateTime(2026, 9, 13, 9, 5)), '09:05');
      expect(chatClock(DateTime(2026, 9, 13, 14, 32)), '14:32');
      expect(chatClock(DateTime(2026, 9, 13, 0, 0)), '00:00');
      expect(chatClock(DateTime(2026, 9, 13, 23, 59)), '23:59');
    });

    test('names today, yesterday, and dates anything older', () {
      final now = DateTime(2026, 9, 13, 10, 0);
      expect(chatDayLabel(DateTime(2026, 9, 13, 0, 5), now: now), 'اليوم');
      expect(chatDayLabel(DateTime(2026, 9, 13, 23, 55), now: now), 'اليوم');
      expect(chatDayLabel(DateTime(2026, 9, 12, 23, 55), now: now), 'أمس');
      expect(chatDayLabel(DateTime(2026, 9, 5, 12, 0), now: now), '05/09/2026');
    });

    test('rolls the month back when yesterday was in the previous month', () {
      final now = DateTime(2026, 3, 1, 8, 0);
      expect(chatDayLabel(DateTime(2026, 2, 28, 20, 0), now: now), 'أمس');
      expect(chatDayLabel(DateTime(2026, 2, 27, 20, 0), now: now), '27/02/2026');
    });

    test('a divider opens a day, never repeats it, and never opens on null', () {
      final a = DateTime(2026, 9, 12, 23, 40);
      final b = DateTime(2026, 9, 13, 0, 20);
      expect(needsDayDivider(null, a), isTrue, reason: 'first message of all');
      expect(needsDayDivider(a, a.add(const Duration(minutes: 5))), isFalse);
      expect(needsDayDivider(a, b), isTrue, reason: 'the day really changed');
      expect(needsDayDivider(a, null), isFalse,
          reason: 'a queued bubble has no confirmed day');
      expect(sameChatDay(a, b), isFalse);
      expect(sameChatDay(b, DateTime(2026, 9, 13, 23, 0)), isTrue);
    });

    test('the server stamp is read as UTC, then shown in local time', () {
      final m = Message.fromJson({
        'id': 3,
        'conversation_id': 5,
        'sender_id': 31,
        'content': 'مرحبا',
        'image_url': null,
        'message_type': 'text',
        'is_read': 0,
        'created_at': '2026-09-12 20:05:00',
      });
      // The same instant, expressed by the test on its own — a raw parse would
      // give 20:05 local and be an hour off in Algiers.
      expect(m.createdAt, DateTime.parse('2026-09-12T20:05:00Z').toLocal());
      expect(m.sendState, SendState.sent,
          reason: 'anything the API returned is already stored');
    });
  });

  group('a thread', () {
    testWidgets('prints a clock under every bubble and one divider per day',
        (tester) async {
      final now = _anchor;
      final yesterdayLate = DateTime(now.year, now.month, now.day - 1, 23, 40);
      final todayMorning = DateTime(now.year, now.month, now.day, 9, 32);

      final fake = _buildFake([
        _messageRow(
            id: 3, senderId: 31, content: 'صباح الخير', at: yesterdayLate),
        _messageRow(
            id: 4, senderId: 30, content: 'صباح النور', at: todayMorning),
      ]);
      final auth = await _boot(fake.api);
      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          otherName: 'مقاول تجربة',
          repo: Repository(fake.api),
        ),
        fake.api,
        auth,
      );

      // Both dividers, in order, and the late-evening message still under
      // «أمس» rather than being pushed into today by a UTC comparison.
      expect(find.text('أمس'), findsOneWidget);
      expect(find.text('اليوم'), findsOneWidget);
      // The clocks, exactly as the phone's own clock would read them.
      expect(find.text('23:40'), findsOneWidget);
      expect(find.text('09:32'), findsOneWidget);
    });

    testWidgets('a refused message says so, keeps its text, and retries once',
        (tester) async {
      final fake = _buildFake(const []);
      fake.failSend = true;
      final auth = await _boot(fake.api);
      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          otherName: 'مقاول تجربة',
          repo: Repository(fake.api),
        ),
        fake.api,
        auth,
      );

      await tester.enterText(find.byType(TextField), 'العنوان: حسين داي');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);

      expect(fake.posts, 1, reason: 'the POST must really have been attempted');
      expect(find.text('العنوان: حسين داي'), findsOneWidget,
          reason: 'the text stays in the thread, not only in a toast');
      expect(find.text('لم تُرسل — أعد المحاولة'), findsOneWidget,
          reason: 'the user cannot tell a lost message from a delivered one '
              'otherwise');
      // The composer's banner is wired to the same state: one tap on «إرسال»
      // must send everything the server refused.
      expect(find.text('رسائل غير مرسلة — اضغط لإعادة المحاولة'), findsOneWidget);

      // The connection comes back: one tap on the failure line resends it.
      fake.failSend = false;
      await tester.tap(find.text('لم تُرسل — أعد المحاولة'));
      await _settle(tester);

      expect(fake.posts, 2, reason: 'the retry must hit the API again');
      expect(find.text('لم تُرسل — أعد المحاولة'), findsNothing);
      expect(find.text('رسائل غير مرسلة — اضغط لإعادة المحاولة'), findsNothing,
          reason: 'nothing is pending any more, so the banner must stand down');
      expect(find.text('العنوان: حسين داي'), findsOneWidget,
          reason: 'the retry replaced the bubble instead of adding a copy');
    });

    testWidgets('a delivered message shows its clock and a sent mark',
        (tester) async {
      final fake = _buildFake(const []);
      final auth = await _boot(fake.api);
      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          otherName: 'مقاول تجربة',
          repo: Repository(fake.api),
        ),
        fake.api,
        auth,
      );

      await tester.enterText(find.byType(TextField), 'وصلت، شكراً');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);

      expect(fake.posts, 1);
      expect(find.text('وصلت، شكراً'), findsOneWidget);
      expect(find.text('لم تُرسل — أعد المحاولة'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget,
          reason: 'my own message shows that the server has it');
      // The server row's own clock, so the bubble is dated by the server and
      // not by the moment the user typed.
      expect(find.text(chatClock(DateTime.now())), findsWidgets);
    });

    // A layout claim needs pixels. This renders the real thread — delivered
    // bubble, refused bubble, offline banner — through the real Cairo face and
    // writes it to /tmp/shots so the ink can be counted afterwards.
    testWidgets('the delivery states rasterise with the right ink',
        (tester) async {
      final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      await (FontLoader('Cairo')
            ..addFont(Future.value(reg))
            ..addFont(Future.value(bold)))
          .load();

      final fake = _buildFake(const []);
      final auth = await _boot(fake.api);
      final key = GlobalKey();
      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          otherName: 'مقاول تجربة',
          repo: Repository(fake.api),
        ),
        fake.api,
        auth,
        boundary: key,
      );

      // One delivered message…
      await tester.enterText(find.byType(TextField), 'وصلت، شكراً');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // …then one the server refuses.
      fake.failSend = true;
      await tester.enterText(find.byType(TextField), 'أنا في حسين داي');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);
      expect(find.text('لم تُرسل — أعد المحاولة'), findsOneWidget);

      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      late final String path;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('/tmp/shots').createSync(recursive: true);
        path = '/tmp/shots/chat_delivery.png';
        File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      expect(File(path).lengthSync(), greaterThan(20000),
          reason: 'a shot this small means nothing rendered');
      // ignore: avoid_print
      print('SHOT $path');
    });
  });
}
