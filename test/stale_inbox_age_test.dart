// The ninth member of the stale-band family, and the only one that could be
// correct about its data and still be *unreachable*.
//
// Every other surface got the age first. The ordinary defect here is that the
// band said its rows *might* be out of date but never *how* out of date: a
// refresh that failed four seconds ago and one that failed three hours ago
// printed the same sentence. On an inbox that gap is the whole question the
// user came to ask, because this is the one list in the app that moves — the
// moment the other person replies, the thing you opened the tab for is already
// on screen somewhere else.
//
// The unusual defect is the reason this file exists. `_cache` is written on
// success whatever the list contains, so **an inbox that genuinely has no
// conversations and an inbox whose read failed are the same value by the time
// the builder looks at them** — `_cache == []`. The screen printed «لا محادثات
// بعد» for both. That is a confident false statement built out of a read that
// never returned, on the one screen whose empty state is a *true* statement
// with a real meaning, and the view it printed carried no retry at all: a
// browse button, and no way to re-read.
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
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/stale_inbox_copy.dart';
import 'package:allomokawil/src/screens/chat/chat_list_screen.dart';

const String _arabic = r'[\u0600-\u06FF]';

Map<String, dynamic> _me() => {
      'id': 391,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'customer',
    };

Map<String, dynamic> _inbox() => {
      'id': 7,
      'customer_id': 391,
      'worker_user_id': 392,
      'other_user_name': 'سمير بن عمر',
      'last_message_content': 'بخصوص ديال المطبخ',
      'unread_count': 2,
      'last_message_at': '2026-09-29T10:00:00Z',
    };

/// A signed-in inbox whose server answers however the test needs it to.
///
/// [rearm] hands the screen a **new future**, which is the path the home shells
/// actually use (`didUpdateWidget` re-arms on a new `initial`). Driving real
/// code beats tapping a gesture a user cannot perform on this state: the empty
/// inbox is not inside a `RefreshIndicator`, so there is no pull gesture to
/// perform on it, which is half of why the retry disappeared.
class _Harness {
  _Harness(this.api, this.auth, this.repo);

  final ApiClient api;
  final AuthState auth;
  final Repository repo;

  /// Whether the next read of the inbox fails.
  bool fail = false;

  /// Whether a successful read answers with a row or with nothing.
  bool seeded = true;

  int reads = 0;

  /// Hands the screen a fresh read, the way a shell re-reading on the way back
  /// from the background does.
  void Function() rearm = _noOp;
  static void _noOp() {}

  int get readCount => reads;
}

Future<_Harness> _boot(
  WidgetTester tester, {
  required DateTime Function() now,
  bool signedIn = true,
  bool failFirstRead = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2532);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final harnessApi = _pendingApi();
  // Installed before the first pump, so a test can reach the branch that has
  // no cache at all — the dead-network-at-launch case. A test that boots
  // healthy and fails a *later* read is testing the band, not this branch,
  // because a successful first read has already written `_cache`.
  harnessApi.failFirst = failFirstRead;
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final path = req.url.path;
      // A real session first: `AuthGate.isGuest` swaps the whole inbox for a
      // sign-in wall when there is no user, so an unauthenticated test would
      // pass against a screen that never drew a conversation at all.
      if (path.endsWith('/api/login') || path.endsWith('/api/register')) {
        return http.Response(
            jsonEncode(<String, Object?>{'token': 't', 'user': _me()}),
            200,
            headers: {'content-type': 'application/json'});
      }
      if (path.endsWith('/api/mobile/conversations')) {
        final h = harnessApi.harness!;
        h.reads++;
        if (h.fail || harnessApi.failFirst) {
          return http.Response('', 503,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(
            jsonEncode(h.seeded ? <dynamic>[_inbox()] : <dynamic>[]),
            200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(<String, Object?>{}), 200,
          headers: {'content-type': 'application/json'});
    }),
    timeout: const Duration(milliseconds: 200),
  );

  final repo = Repository(api);
  final auth = AuthState(api);
  await auth.restore();
  if (signedIn) {
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);
  }
  final h = _Harness(api, auth, repo);
  harnessApi.harness = h;

  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: ChatListScreen(repo: repo, clock: now),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));
  return h;
}

/// A mutable cell, so the mock client can reach the harness it belongs to.
class _PendingApi {
  _Harness? harness;
  bool failFirst = false;
}

_PendingApi _pendingApi() => _PendingApi();

/// Re-arms the screen with a genuinely new future and settles.
Future<void> _reread(
    WidgetTester tester, _Harness h, DateTime Function() now) async {
  // **The error handler is not optional, and its absence is a harness bug that
  // costs a whole debugging cycle to spot.** `ChatListScreen` hands the future
  // to a `FutureBuilder`, which handles the error for its own state, and the
  // two home shells additionally attach `.catchError` through
  // `_resolveUnread` — so in the app this future is never left unhandled. A
  // test that builds one bare and hands it in gets an *unhandled* `ApiException`
  // that the framework reports as an exception even though every assertion
  // passed, and it reads like the screen throwing on a failed read. Probed this
  // tick rather than guessed at.
  final future = h.repo.conversations();
  future.then((_) {}, onError: (_, __) {});
  await tester.pumpWidget(AppScope(
    api: h.api,
    auth: h.auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: ChatListScreen(repo: h.repo, initial: future, clock: now),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

String _band(WidgetTester tester) => tester
    .widgetList<Text>(find.byKey(const Key('stale-inbox-line')))
    .map((t) => t.data ?? '')
    .join();

void main() {
  group('staleInboxAgeAr / staleInboxLineWithAgeAr', () {
    test('the age is appended, never substituted for the failure', () {
      final line = staleInboxLineWithAgeAr(
        'الإنترنت غير متصل',
        DateTime(2026, 9, 29, 9, 0),
        now: DateTime(2026, 9, 29, 9, 40),
      );
      expect(line, contains('لم نتمكن من تحديث المحادثات'));
      expect(line, contains('الإنترنت غير متصل'),
          reason: 'the diagnosed failure must survive the age: "$line"');
      expect(line, contains('قبل 40 دقيقة'));
    });

    test('a read inside the minute keeps the old line byte for byte', () {
      // Every assertion the inbox tests were written against has to survive, so
      // the silent case returns the *exact* previous string — not a shorter
      // variant, not a trailing dash.
      final base = staleInboxLineAr('الإنترنت غير متصل');
      expect(
        staleInboxLineWithAgeAr('الإنترنت غير متصل', DateTime(2026, 9, 29, 9, 0),
            now: DateTime(2026, 9, 29, 9, 0, 59)),
        base,
      );
    });

    test('an absent read, and a clock ahead of the phone, are silent', () {
      final base = staleInboxLineAr('الإنترنت غير متصل');
      expect(staleInboxLineWithAgeAr('الإنترنت غير متصل', null), base);
      // Skew is somebody else's broken clock, not a negative age to print.
      expect(
        staleInboxLineWithAgeAr('الإنترنت غير متصل', DateTime(2026, 9, 29, 9),
            now: DateTime(2026, 9, 29, 8)),
        base,
      );
    });
  });

  group('ChatListScreen — the band knows how old its rows are', () {
    testWidgets('a read inside the minute adds nothing to the line',
        (tester) async {
      final now = DateTime(2026, 9, 29, 9, 0);
      final h = await _boot(tester, now: () => now);
      expect(h.readCount, 1);
      expect(find.text('سمير بن عمر'), findsOneWidget,
          reason: 'the premise: a row is on screen');
      expect(find.byKey(const Key('stale-inbox')), findsNothing,
          reason: 'a successful first read must not warn about anything');

      h.fail = true;
      await _reread(tester, h, () => now);
      expect(find.byKey(const Key('stale-inbox')), findsOneWidget,
          reason: 'a failed re-read is being swallowed');

      // The read landed one frame ago, so the age is silence and the line is
      // the old one. Asserted so a later tick that makes the age speak too
      // eagerly has something to fail against.
      //
      // **The marker is the age sentence, not the word.** The base line already
      // ends «آخر قائمة قرأناها», so the first version of this assertion looked
      // for «قرأناها» — a substring the line contains *whether or not the age
      // was appended*, which made it pass for the wrong reason and would have
      // failed the moment the copy was reworded. What is being asserted is
      // that the *appended* clause is absent, and the only unambiguous way to
      // say that is to look for the phrase the age sentence begins with.
      final atNine = _band(tester);
      expect(atNine, isNot(contains('قرأناها قبل')),
          reason: 'a read inside the minute must add nothing: "$atNine"');
      expect(atNine, isNot(contains('\\n')),
          reason: 'the age is a second sentence; an undated band is one: '
              '"$atNine"');
      expect(atNine, matches(RegExp(_arabic)),
          reason: 'the banner must be readable Arabic, got "$atNine"');
    });

    testWidgets('the screen ages the band without being touched',
        (tester) async {
      var now = DateTime(2026, 9, 29, 9, 0);
      final h = await _boot(tester, now: () => now);
      h.fail = true;
      await _reread(tester, h, () => now);

      // The network went under the phone and nobody touches it for forty
      // minutes. The tick re-dates the band; the screen has to rebuild for
      // that to show, which is the wiring this test exists for.
      now = DateTime(2026, 9, 29, 9, 40);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 1));

      final line = _band(tester);
      expect(line, contains('قبل 40 دقيقة'),
          reason: 'the band still cannot say how old these rows are: "$line"');
      // The failure clause survives the age — asserted by shape, not by a
      // constant, because a 503 and a dropped connection are two different
      // sentences from `errorCopy`.
      expect(line, contains('لم نتمكن من تحديث المحادثات'),
          reason: 'the age must be appended, not substituted: "$line"');
    });

    testWidgets('the stamp follows the last read, not the first',
        (tester) async {
      // The half a naive implementation gets wrong: a screen that stamps only
      // its *first* successful read answers the second outage with the age of
      // the first one, and tells a user their conversation list is hours old
      // when it was fetched this very second.
      //
      // **The staging is the second thing that is easy to get wrong.** The
      // obvious version fails a read and only then moves the clock, which puts
      // both candidate stamps on the same instant — correct and broken code
      // print the identical number and the sabotage passes. A test that cannot
      // tell right from wrong is a comment. So this one interleaves a *second
      // success* at 09:30 before the second outage at 11:30, where the two
      // candidate stamps name genuinely different reads: 120 minutes, or 150.
      // Both land on `relativeTimeAr`'s hour floor, which is lossy — so the
      // discriminator has to sit either side of it, and the outage is placed
      // where 09:00 and 09:30 differ.
      var now = DateTime(2026, 9, 29, 9, 0);
      final h = await _boot(tester, now: () => now);

      // A second read that SUCCEEDS at 09:30. Nothing is shown, because there
      // is nothing to doubt yet — and the stamp has to move with it.
      now = DateTime(2026, 9, 29, 9, 30);
      h.fail = false;
      await _reread(tester, h, () => now);
      expect(find.byKey(const Key('stale-inbox')), findsNothing,
          reason: 'a successful read must leave no doubt on screen');

      // The network goes again, at 10:00: the correct stamp is 30 minutes old.
      // A stamp left behind at 09:00 would be an hour, and 60 minutes is
      // exactly where `relativeTimeAr` turns «قبل 59 دقيقة» into «قبل ساعة» —
      // so this boundary separates the two implementations by a whole word.
      now = DateTime(2026, 9, 29, 10, 0);
      h.fail = true;
      await _reread(tester, h, () => now);
      expect(find.byKey(const Key('stale-inbox')), findsOneWidget,
          reason: 'the second outage must state its own doubt');

      final aged = _band(tester);
      expect(aged, contains('قبل 30 دقيقة'),
          reason: 'the rows were read at 09:30, not at the very first read at '
              '09:00 — a stamp that is never refreshed dates the wrong read and '
              'states a number nobody can rely on: "$aged"');
      expect(aged, isNot(contains('قبل ساعة')),
          reason: 'that is the 09:00 stamp talking: 60 minutes from 10:00');
    });
  });

  group('ChatListScreen — a failed read is not an empty inbox', () {
    testWidgets('a failed first read never claims "no conversations"',
        (tester) async {
      // The premise is a read that fails **from the start**, with nothing ever
      // cached: the dead-network-at-launch case. The first version of this test
      // booted with a successful read carrying a row and then failed a *later*
      // one — which is the band's state, not the error view's, so it asserted
      // «تعذّر جلب الرسائل» against a screen correctly showing the band, and
      // failed for a reason that had nothing to do with the defect. Staging it
      // on a genuinely failed first read is the only way to reach the branch.
      final now = DateTime(2026, 9, 29, 9);
      await _boot(tester, now: () => now, failFirstRead: true);

      expect(find.text('لا محادثات بعد'), findsNothing,
          reason: 'a failed read must never print the empty-inbox statement');
      expect(find.text('تعذّر جلب الرسائل'), findsOneWidget,
          reason: 'with nothing cached there is genuinely nothing to draw, '
              'and the retry is the whole answer');
      expect(find.text('إعادة المحاولة'), findsOneWidget,
          reason: 'the only thing a dead network should offer is a re-read');
    });

    testWidgets('a refresh that fails on an empty inbox keeps the retry',
        (tester) async {
      // The defect: a first read succeeds and is *genuinely* empty, so
      // `_cache == []`; then a refresh fails. Both are `_cache == []` to the
      // builder, and the old code answered the empty-inbox CTA for both —
      // telling the user «لا محادثات بعد» after a read that never returned, and
      // giving them a browse button with no way to re-read.
      final now = DateTime(2026, 9, 29, 9);
      final h = await _boot(tester, now: () => now);
      h.seeded = false;
      await _reread(tester, h, () => now);
      expect(find.text('لا محادثات بعد'), findsOneWidget,
          reason: 'the premise: a read succeeded and it was genuinely empty');
      expect(find.text('تعذّر جلب الرسائل'), findsNothing,
          reason: 'a live read must not warn about anything');

      h.fail = true;
      await _reread(tester, h, () => now);

      expect(find.text('لا محادثات بعد'), findsNothing,
          reason: 'a failed refresh over an empty cache must not claim the '
              'user has no conversations — that is a true statement with a '
              'real meaning, printed from a read that never returned');
      expect(find.text('تعذّر جلب الرسائل'), findsOneWidget,
          reason: 'and it must offer the retry, not the browse CTA');

      // The retry has to actually work, or the fix is only a different dead
      // end: a user who taps it must get their inbox back.
      h.fail = false;
      h.seeded = true;
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('سمير بن عمر'), findsOneWidget,
          reason: 'the retry button must re-read the server');
      expect(find.text('تعذّر جلب الرسائل'), findsNothing);
    });
  });

  group('ChatListScreen — a tile dates its row on the screen\'s own clock', () {
    testWidgets('the tile measures against the injected clock, not the wall',
        (tester) async {
      // The row arrives stamped at 10:00 and [now] is 11:00, so the honest
      // answer is exactly one hour — the singular arm, «قبل ساعة».
      final now = DateTime(2026, 9, 29, 11, 0);
      await _boot(tester, now: () => now);
      expect(find.text('سمير بن عمر'), findsOneWidget,
          reason: 'the premise: a conversation tile is on screen');

      // **What this pins.** The tile called `relativeTimeAr` with no `now:`,
      // so it fell back to `DateTime.now()` — the *system* clock — while the
      // stale band drawn nine lines above it measured against this screen's
      // own `_now()`. In the app `clock` is null and the two agree, which is
      // exactly why this survived review: it is invisible in the app and
      // unreachable from a test. The wall clock is three days past the
      // fixture, so the tile answered «قبل 3 أيام» for a message that was
      // sent an hour ago.
      //
      // And that is the fuse the `created_at` audit was opened to defuse: a
      // frozen `last_message_at` here could never be turned into an age
      // assertion, so this surface could only ever be tested by *not* looking
      // at the one thing it prints.
      expect(find.text('قبل ساعة'), findsOneWidget,
          reason: 'the tile must measure against the clock the screen was '
              'handed, not the wall clock');
    });
  });
}
