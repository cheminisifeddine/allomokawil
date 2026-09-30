// The banner's «تحقّق» button answered once per message, and the queue made the
// user read them in series.
//
// The rule every other write screen already follows is that a line which is
// about to be *replaced* must be removed first, because `ScaffoldMessenger`
// **queues**: a second `showSnackBar` while one is visible waits for the first
// to time out, four seconds by default. That rule was migrated into a shared
// helper this tick (`core/l10n/snack.dart`) after nine private copies of it were
// found, and the chat screen was the one place it had never been applied at
// all — `_toast` was a bare `showSnackBar`.
//
// The defect is specific to the chat banner, because the chat banner is the
// only control in the app that re-reads **many** rows in one tap.
// `_recheckUnconfirmed` loops over every `unconfirmed` message and toasted per
// iteration. So a user with three unconfirmed messages who pressed one button
// read three sentences, four seconds apart, and the one left on screen when he
// looked away was the verdict for whichever message happened to be last in the
// list — not a summary, and not the one he was asking about.
//
// The fix: one read, one sentence. The count goes through `arabicCounted`,
// because Arabic changes the noun on the number, not the number on the noun.
//
// **Red before green.** The two cases below are written against the widget tree
// only — no `chatRecheckVerdict`, no new keys, no new strings — so the same
// file runs against the screen restored from `git show HEAD:` and fails for the
// real reason. See the tick's notes for the restored run.
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
import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/data/chat_recheck_copy.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

final _me = <String, Object?>{
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'زبون تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-09-11 00:00:00',
};

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// The thread the Worker holds, and the only thing the re-read may consult.
class _Thread {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];

  /// When true, every read fails: the re-read cannot answer, so every message
  /// stays uncertain — the case the summary has to describe honestly.
  bool refuseReads = false;

  late final ApiClient api;
}

_Thread _buildServer() {
  late final _Thread thread;
  final client = MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
      return _json({'token': 'tok', 'user': _me});
    }
    if (p.endsWith('/api/unread')) return _json(0);
    if (p.startsWith('/api/messages/')) {
      if (req.method == 'GET') {
        if (thread.refuseReads) {
          throw http.ClientException('no route to host');
        }
        return _json(thread.rows);
      }
      return http.Response('{}', 500,
          headers: {'content-type': 'application/json'});
    }
    return _json(<Object>[]);
  });
  thread = _Thread();
  thread.api = ApiClient(baseUrls: ['https://x.test'], httpClient: client);
  return thread;
}

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return auth;
}

Future<void> _settle(WidgetTester tester, {int frames = 14}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth,
  ChatOutbox outbox,
) async {
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
        otherUserId: 31,
        repo: Repository(api),
        outbox: outbox,
      ),
    ),
  ));
  await _settle(tester);
}

/// The text of the line on screen, or `null` when no snack bar is drawn.
///
/// Read from the tree rather than from `ScaffoldMessenger`, because the whole
/// claim is about *which line is visible right now*: a queued second bar is in
/// the messenger's queue and not in the tree, which is precisely how the old
/// code looked correct to anyone reading the source and wrong to the user.
String? _visibleLine(WidgetTester tester) {
  final bars = find.byType(SnackBar);
  if (bars.evaluate().isEmpty) return null;
  final text = tester.widget<Text>(
      find.descendant(of: bars.first, matching: find.byType(Text)).first);
  return text.data;
}

/// How many snack bars exist in the tree at once.
int _barCount(WidgetTester tester) => find.byType(SnackBar).evaluate().length;

void main() {
  group('the banner re-reads many messages and answers once', () {
    testWidgets('three unconfirmed messages produce one line, not three',
        (tester) async {
      final server = _buildServer();
      final auth = await _boot(server.api);
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      // The thread cannot be read, so the re-read settles nothing and every
      // message stays uncertain — the case where the old code toasted once per
      // message and the user read the same uncertainty three times, in series.
      server.refuseReads = true;
      for (final t in const [
        'الطابق الأول',
        'الطابق الثاني',
        'الطابق الثالث'
      ]) {
        await outbox.add(
            conversationId: 5, text: t, uncertain: SendState.unconfirmed);
      }

      await _pump(tester, server.api, auth, outbox);
      expect(find.text('تحقّق'), findsOneWidget);
      expect(_barCount(tester), 0,
          reason: 'nothing is on screen before the tap');

      await tester.tap(find.text('تحقّق'));
      await _settle(tester, frames: 30);

      expect(_barCount(tester), 1,
          reason: 'one tap on one button is one answer; the old code raised '
              'one toast per unconfirmed message inside the loop');
      final line = _visibleLine(tester);
      expect(line, isNotNull);
      expect(line, contains('3'),
          reason: 'the one sentence must say how many messages it answered '
              'for — a user with three outstanding messages is owed a count, '
              'not one message\'s verdict repeated');

      // The bar count above is **not** sufficient on its own, and this is the
      // finding that cost the first version of this test a false green: the
      // messenger's queue is not in the widget tree, so three *queued* bars
      // read as exactly one bar to a finder. The old code passes `findsOne`
      // while holding two more lines the user has not reached yet.
      //
      // So the queue is caught by letting it run: the first bar times out after
      // its four seconds and whatever was behind it arrives. If only one line
      // was ever raised, the screen is empty at the end of this pump and stays
      // empty.
      final seen = <String>{};
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 80));
        final now = _visibleLine(tester);
        if (now != null) seen.add(now);
      }
      expect(seen.length, 1,
          reason: 'only one line was ever raised, so nothing was queued '
              'behind it; the old code shows ${seen.length} distinct lines '
              'arriving in series, four seconds apart');
    });

    testWidgets('a single unconfirmed message keeps its own per-outcome line',
        (tester) async {
      final server = _buildServer();
      final auth = await _boot(server.api);
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      server.refuseReads = true;
      await outbox.add(
          conversationId: 5,
          text: 'الطابق الأول',
          uncertain: SendState.unconfirmed);

      await _pump(tester, server.api, auth, outbox);
      await tester.tap(find.text('تحقّق'));
      await _settle(tester, frames: 30);

      expect(_barCount(tester), 1);
      expect(_visibleLine(tester), isNot(contains('1')),
          reason: 'one message is the per-outcome case and keeps the sentence '
              'that names *that* message\'s reason for still being uncertain; '
              'a count of one is not that sentence');
    });
  });

  group('the summary does not blur a proven absence into no answer at all', () {
    // This is the defect the plural case could have shipped. `WriteOutcome` has
    // three values and the sentence has to keep all three apart:
    //
    //   landed  — the thread holds it
    //   missing — the thread came back **without** it, so re-sending is safe
    //   unknown — the thread could not be read, so nothing is known
    //
    // Counting `missing` as `unknown` produces a man on a dead connection being
    // told his messages are not there, and re-sending them — which is the exact
    // duplicate the whole of Phase 5 exists to prevent, restated in a toast.
    test('a proven absence says so, and invites the safe retry', () {
      final line = chatRecheckVerdict(landed: 0, absent: 3, unclear: 0);
      expect(line, contains('لم نجد'));
      expect(line, contains('أعِد إرسالها'),
          reason: 'a proven absence is the one case where re-sending is safe, '
              'so the sentence has to say so rather than only reporting the gap');
      expect(line, isNot(contains('النتيجة غير معروفة')),
          reason: 'nothing here is unknown — the app read the thread and the '
              'words were not in it');
    });

    test('no answer at all refuses to answer, and never claims an absence', () {
      final line = chatRecheckVerdict(landed: 0, absent: 0, unclear: 3);
      expect(line, contains('النتيجة غير معروفة'));
      expect(line, isNot(contains('أعِد إرسالها')),
          reason: 'telling a man with no connection that re-sending is safe is '
              'the duplicate, written as advice');
      expect(line, isNot(contains('وجدناهم')),
          reason: 'nothing was found; the sentence must not claim a read that '
              'never happened');
    });

    test('the two classes are named separately when both are present', () {
      final line = chatRecheckVerdict(landed: 2, absent: 1, unclear: 1);
      // Three messages, two arrived, one is provably not there, one is unknown:
      // four facts cannot be carried by one clause, so the sentence has to.
      //
      // **No digit is asserted, and that is the Arabic rule, not a loose
      // test.** The first version of this case asserted `contains('2')` and
      // failed on `وصلت رسالتان` — the dual, which correctly carries the noun
      // *without* the number. The count is not missing from the sentence; the
      // number is not written in the dual, and asserting the digit here would
      // have been asserting a grammatical error.
      expect(line, contains('رسالتان'));
      expect(line, contains('لم نجد'));
      expect(line, contains('لم يتأكّد وصولها'));
    });

    test('all three together do not collapse into the one strong claim', () {
      final line = chatRecheckVerdict(landed: 2, absent: 1, unclear: 1);
      expect(line, isNot(contains('وجدناهم')),
          reason: 'a summary that says «we found them in the list» while a '
              'message is proven absent is the exact claim this file is for');
    });

    test('a count in Arabic takes the form the number gives it', () {
      // 2 is the dual and takes the noun with **no number**; 3–10 is the broken
      // plural and takes the number. Printing «2 رسائل» is the same number
      // error the `arabicCount` file was written for.
      expect(chatRecheckVerdict(landed: 2, absent: 0, unclear: 0),
          contains('رسالتان'));
      expect(chatRecheckVerdict(landed: 2, absent: 0, unclear: 0),
          isNot(contains('رسائل')));
      expect(chatRecheckVerdict(landed: 3, absent: 0, unclear: 0),
          contains('3 رسائل'));
    });
  });
}
