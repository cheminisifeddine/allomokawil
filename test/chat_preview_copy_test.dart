// A thread whose last message was a photo rendered **no preview line at all**.
//
// Proven on the live API, not by reading code. `Repository.sendImage` posts
// `image_url` and `message_type: 'image'` and **no `content` field at all**, so
// the server stores a NULL, and `/api/mobile/conversations` answers:
//
//     "last_message_at":"2026-09-28 22:01:12",
//     "last_message_content":null
//
// The row gated its one-line preview on `lastMessageContent != null`, so that
// thread drew the name and nothing else. The same null comes back for a
// conversation that was opened and never written to, which makes the *newest*
// thread in the inbox — the one a customer has just opened and is waiting on —
// the emptiest-looking row on the screen.
//
// On a marketplace where a photo of a finished bathroom is how a contractor
// answers, the row whose job is to say "he sent you something" said nothing,
// and a user reads that as "he has not replied".
//
// The rule now lives in `data/chat_preview_copy.dart`. These cases pin the
// rule and the screen that consumes it.
import 'dart:convert';
import 'package:flutter/material.dart';
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
import 'package:allomokawil/src/data/chat_preview_copy.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/chat/chat_list_screen.dart';

const _user = {
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'زبونة تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-09-28 10:00:00',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

/// One conversation, with the two fields the preview rule reads and nothing
/// else invented.
Map<String, dynamic> _conv({
  required int id,
  required String name,
  Object? content = 'مرحبا، متى يمكنك البدء؟',
  Object? lastMessageAt = '2026-09-28 10:00:00',
}) =>
    {
      'id': id,
      'customer_id': 30,
      'worker_user_id': 7,
      'project_id': null,
      'other_user_name': name,
      'other_user_avatar': null,
      'last_message_content': content,
      'unread_count': 0,
      'last_message_at': lastMessageAt,
    };

ApiClient _api(List<Map<String, dynamic>> convs) => ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json({'token': 'tok', 'user': _user});
        }
        if (p.endsWith('/api/unread')) return _json({'unread': 0});
        if (p.endsWith('/api/mobile/conversations')) {
          return req.method == 'POST' ? _json({'id': 7}) : _json(convs);
        }
        return _json(<Object>[]);
      }),
    );

/// Pumps the **real** `ChatListScreen` under a real `AppScope`.
///
/// Nothing under test is constructed by hand: the row is the shipped widget and
/// the list arrives through the shipped `Repository` parsing the shipped JSON.
Future<void> _pumpInbox(WidgetTester tester, List<Map<String, dynamic>> c) async {
  final api = _api(c);
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);

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
      home: ChatListScreen(repo: Repository(api)),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  group('the rule', () {
    test('a photo thread is named, not left blank', () {
      // No content at all -> the caller falls back, and the fallback for a
      // thread that has a message is the picture word.
      expect(
        chatPreviewCopy(null) ?? chatFallbackPreview(hasMessage: true),
        'صورة',
      );
    });

    test('an opened thread nobody wrote in is a different sentence', () {
      expect(
        chatPreviewCopy(null) ?? chatFallbackPreview(hasMessage: false),
        'لا رسائل بعد',
      );
    });

    test('text is the server’s and is never rewritten', () {
      expect(chatPreviewCopy('  السلام عليكم  '), 'السلام عليكم');
    });

    test('a blank draft is not drawn as an empty line', () {
      // The composer can enqueue an empty draft, and an ellipsised blank reads
      // as a broken row rather than one that says there is nothing yet.
      expect(chatPreviewCopy(''), isNull);
      expect(chatPreviewCopy('   '), isNull);
      expect(chatPreviewCopy('\n\t '), isNull);
    });

    test('a long message is passed through whole, for the row to ellipsise', () {
      // Joined, not multiplied: `'قصير ' * 200` ends in a space, and the rule
      // trims that away on purpose. The words are what must survive, and the
      // row — not the data layer — is what decides where to cut.
      final long = List.filled(200, 'قصير').join(' ');
      expect(chatPreviewCopy(long), long);
      expect(chatPreviewCopy(long)!.length, greaterThan(900));
    });
  });

  group('the inbox row', () {
    testWidgets('a thread whose last message is a photo still has a preview',
        (tester) async {
      await _pumpInbox(tester, [
        _conv(id: 1, name: 'خالد رحماني', content: null),
      ]);

      expect(find.text('خالد رحماني'), findsOneWidget);
      expect(
        find.text('صورة'),
        findsOneWidget,
        reason: 'the row must say a picture arrived, not drop the line',
      );
    });

    testWidgets('a thread nobody replied in yet says so', (tester) async {
      await _pumpInbox(tester, [
        _conv(id: 1, name: 'عمر بن علي', content: null, lastMessageAt: null),
      ]);

      expect(find.text('لا رسائل بعد'), findsOneWidget);
    });

    testWidgets('a text thread still previews its words', (tester) async {
      await _pumpInbox(tester, [
        _conv(id: 1, name: 'عمر بن علي', content: 'السعر 25000 دج'),
      ]);

      expect(find.text('السعر 25000 دج'), findsOneWidget);
      expect(find.text('صورة'), findsNothing);
    });
  });
}
