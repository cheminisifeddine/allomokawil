// A thread's day dividers are the only thing that tells a user how stale the
// conversation is, and they are **calendar** labels: «اليوم» and «أمس» both
// expire, at midnight, without anything in the app noticing.
//
// `chatDayLabel` takes an injectable `now:` for exactly this reason, and its
// unit test pins that. But the *screen* never passed one: the call read
// `chatDayLabel(at!)`, so the label was decided against `DateTime.now()`
// inside `data/chat_time.dart` and then frozen for as long as the thread sat
// open. A customer who opened a conversation in the evening, asked a
// contractor a question, and came back to it the next morning was shown every
// message stamped «اليوم» — the divider, the evidence of age, was the one thing
// on screen that could not age.
//
// This file pins the screen half of that fix: the clock is a seam, and the
// screen re-decides the labels while it sits open.
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
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

String _utcStamp(DateTime local) {
  final t = local.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

Map<String, Object?> _row({
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

ApiClient _api(List<Map<String, Object?>> thread) {
  final client = MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
      return _json({'token': 'tok', 'user': _me});
    }
    if (p.endsWith('/api/unread')) return _json(0);
    if (p.endsWith('/api/mobile/conversations')) {
      return req.method == 'POST' ? _json({'id': 5}) : _json(<Object>[]);
    }
    if (p.startsWith('/api/messages/')) {
      if (req.method == 'GET') return _json(thread);
      return _json(<Object>[]);
    }
    return _json(<Object>[]);
  });
  return ApiClient(baseUrls: ['https://x.test'], httpClient: client);
}

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return auth;
}

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Every day divider currently on screen, in order.
///
/// Read through the divider's own `Key`, never by scanning the page for
/// «اليوم» / «أمس»: a page-wide scan matches a *message* whose text is that
/// word. The first version of this file did exactly that and reported four
/// dividers on a two-message thread, because the fixture's message bodies were
/// themselves «أمس» and «اليوم» — the test was measuring its own fixture.
List<String> _dividers(WidgetTester tester) {
  final dividers = find.byKey(const Key('chat-day-divider'));
  if (dividers.evaluate().isEmpty) return const <String>[];
  return tester
      .widgetList<Text>(
        find.descendant(of: dividers, matching: find.byType(Text)),
      )
      .map((t) => t.data)
      .whereType<String>()
      .toList();
}

void main() {
  // A fixed day, so nothing in this file can race the host's midnight.
  final anchor = DateTime(2026, 9, 13, 21, 0);

  group('the thread dates itself while it sits open', () {
    testWidgets('a message drawn as «اليوم» reads «أمس» once the day rolls',
        (tester) async {
      final sent = DateTime(2026, 9, 13, 20, 30);
      final api = _api([
        _row(id: 1, senderId: 7, content: 'مساء الخير', at: sent),
      ]);
      final auth = await _boot(api);

      var now = anchor;
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
          home: ChatScreen(
            conversationId: 5,
            otherUserId: 7,
            otherName: 'مقاول',
            repo: Repository(api),
            clock: () => now,
          ),
        ),
      ));
      await _settle(tester);

      expect(_dividers(tester), ['اليوم'],
          reason: 'at 21:00 a message from 20:30 is today');

      // **Only the clock moves.** No pumpWidget, no key change, no setState
      // issued by the test — this is the only thing that happens when a thread
      // is left open, and before the fix it was a no-op.
      now = DateTime(2026, 9, 14, 0, 5);
      await tester.pump(const Duration(minutes: 1, seconds: 5));
      await _settle(tester);

      expect(_dividers(tester), ['أمس'],
          reason: 'at 00:05 the same message is yesterday, and the divider must '
              'say so without a read, a send or a scroll');
    });

    testWidgets('a divider does not reopen on a day it already drew',
        (tester) async {
      final api = _api([
        _row(id: 1, senderId: 7, content: 'أمس', at: DateTime(2026, 9, 12, 9)),
        _row(id: 2, senderId: 7, content: 'اليوم', at: DateTime(2026, 9, 13, 20)),
      ]);
      final auth = await _boot(api);
      var now = anchor;

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
          home: ChatScreen(
            conversationId: 5,
            otherUserId: 7,
            otherName: 'مقاول',
            repo: Repository(api),
            clock: () => now,
          ),
        ),
      ));
      await _settle(tester);

      expect(_dividers(tester), ['أمس', 'اليوم']);

      // Both dividers age, and the older one is now a plain date.
      now = DateTime(2026, 9, 14, 0, 5);
      await tester.pump(const Duration(minutes: 1, seconds: 5));
      await _settle(tester);

      expect(_dividers(tester), ['12/09/2026', 'أمس'],
          reason: 'the 12th is two days back and must be dated, while the 13th '
              'is yesterday — one tick, two different corrections');
    });

    testWidgets('an empty thread does not rebuild once a minute',
        (tester) async {
      final api = _api(<Map<String, Object?>>[]);
      final auth = await _boot(api);
      var now = anchor;

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
          home: ChatScreen(
            conversationId: 5,
            otherUserId: 7,
            otherName: 'مقاول',
            repo: Repository(api),
            clock: () => now,
          ),
        ),
      ));
      await _settle(tester);

      // The whole point of the guard: an empty thread has no dividers to age,
      // so the tick must not call `setState`. Counting real rebuilds through
      // the framework's own dirty-widget hook is the only way to say that —
      // an assertion on the *text* would pass with or without the guard,
      // because an empty thread draws no divider either way.
      var dirty = 0;
      debugOnRebuildDirtyWidget = (e, _) {
        if (e.widget is ChatScreen) dirty++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      now = DateTime(2026, 9, 14, 0, 5);
      await tester.pump(const Duration(minutes: 5));
      await _settle(tester);

      expect(dirty, 0,
          reason: 'nothing to age: an empty thread must not rebuild');
    });
  });
}
