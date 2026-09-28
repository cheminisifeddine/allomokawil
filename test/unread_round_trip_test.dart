// The pip the user comes back to must be the pip he leaves with.
//
// Two screens compute the unread number independently, and until this file
// nothing pinned that they agree: `NotificationsBell._refresh` reads
// `/api/unread`, and `_NotificationsScreenState._unread` counts the rows the
// centre drew. The user meets both — the pip on the home header, the row pips
// in the centre — and he is owed one number from them.
//
// The previous cycle's "next" note put it exactly here: *the bell guards a stale
// count on resume; what is untested is the mark-read -> pop-back -> pip round
// trip when the write was refused.*
//
// `_refresh` opens with a guard that throws the request away:
//
//     Future<void> _refresh() async {
//       if (_refreshing) return;          // <-- the defect
//       _refreshing = true;
//       try { final n = await _repo.unreadCount(); ... }
//
// That guard is right for a *lifecycle resume*: two resumes in the same frame
// ask the same question, and the answer already in flight is the answer to
// that same question, so spending a second request only risks a slower answer
// winning `setState` and painting a badge that goes backwards.
//
// It is wrong for the read that follows coming back from the centre, because
// that is not the same question. The user has just marked notifications read.
// The read in flight was issued **before** that write, so its answer is a
// snapshot of the world as it was when the phone asked — and the call that
// would correct it is the one the guard deletes. So the sequence is:
//
//   1. the app is resumed, `resumed` fires, a read opens and is still in
//      flight on a 3G bar;
//   2. the user opens the centre, marks everything read — the server's count
//      is now zero;
//   3. he taps back, and `_open` asks for a fresh count;
//   4. that ask is dropped, because a read is already in flight;
//   5. the in-flight read answers with the **pre-write** number and the header
//      paints a pip over a centre the user just emptied.
//
// Nothing re-reads afterwards, so the pip is wrong until he next leaves and
// returns to the app — which is the one thing the resume refresh exists to
// prevent. The centre and the pip then disagree in public, on the same screen,
// one gesture apart.
import 'dart:async';
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
import 'package:allomokawil/src/widgets/notifications_bell.dart';

const _user = {
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

String _stamp(Duration ago) {
  final t = DateTime.now().toUtc().subtract(ago);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

Map<String, Object?> _row({required int id, int isRead = 0}) => {
      'id': id,
      'type': 'new_message',
      'title': 'رسالة جديدة',
      'body': 'لديك رسالة',
      'link': null,
      'is_read': isRead,
      'created_at': _stamp(const Duration(hours: 1)),
    };

/// A backend whose `/api/unread` can be held open, and which answers with the
/// count **as it stood when the request arrived**.
///
/// The snapshot is the whole point. A real request that sat in a queue while
/// the user marked everything read is answered by whatever the server had when
/// it handled the line — that is what "stale" means, and a fake that reads
/// `unread` at response time would answer with the *new* number and quietly
/// make the bug look harmless. It is the mistake `notification_center_test`
/// already made once, and its own comment records it.
class _Held {
  _Held(this.rows) : unread = rows.length;

  List<Map<String, Object?>> rows;
  int unread;
  final List<String> log = [];

  /// Opened by a `/api/unread` request, closed by [release].
  final gate = Completer<void>();
  bool get held => !gate.isCompleted;

  /// How many reads were issued, and how many the server has answered — the
  /// second read must actually land, not merely be requested.
  int requests = 0;
  int served = 0;

  ApiClient get client => ApiClient(
        baseUrls: const ['https://api.test'],
        httpClient: MockClient((req) async {
          final path = req.url.path;
          log.add('${req.method} $path');
          switch (path) {
            case '/api/notifications':
              return _json(rows);
            case '/api/unread':
              requests++;
              final snapshot = unread;
              await gate.future;
              served++;
              return _json({'unread': snapshot});
            case '/api/notifications/read':
              final decoded = req.body.isEmpty
                  ? const <String, Object?>{}
                  : jsonDecode(req.body) as Map<String, Object?>;
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
              return _json(const <Object>[]);
          }
        }),
      );

  void release() {
    if (!gate.isCompleted) gate.complete();
  }
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

Future<void> _pump(WidgetTester tester, _Held h) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'auth.token': 'test-token',
    'auth.user': jsonEncode(_user),
  });
  final auth = AuthState(h.client);
  await auth.restore();
  await tester.pumpWidget(
    AppScope(
      api: h.client,
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
        home: NotificationsBell(repo: Repository(h.client)),
      ),
    ),
  );
  // One pump only. `pumpAndSettle` would spin on the held request forever.
  await tester.pump();
}

/// Pumps until [done] or the budget runs out. `pumpAndSettle` cannot be used
/// while a SnackBar is up, and the centre's rows settle through real futures.
Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  int steps = 40,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < steps; i++) {
    if (done()) return;
    await tester.pump(step);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The one case the previous family never covered. Everything before it tested
  // the *centre* in isolation, with the bell on a screen of its own where the
  // only thing that could go wrong was the row.
  testWidgets('a pip is not left standing over a centre the user just emptied',
      (tester) async {
    final h = _Held([_row(id: 1), _row(id: 2)]);

    await _pump(tester, h);
    expect(h.requests, 1, reason: 'the launch read opened and is in flight');
    expect(h.held, isTrue);
    expect(find.byKey(const Key('notifications-badge')), findsNothing,
        reason: 'nothing has answered yet, so no pip may be claimed');

    // Open the centre while that read is still open, and clear it.
    await tester.tap(find.byKey(const Key('notifications-bell')));
    await _until(tester, () => find
        .byKey(const Key('notifications-mark-all'))
        .evaluate()
        .isNotEmpty);
    expect(find.byKey(const Key('notifications-mark-all')), findsOneWidget);
    await tester.tap(find.byKey(const Key('notifications-mark-all')));
    await _until(tester, () => h.unread == 0);
    expect(h.unread, 0, reason: 'the server cleared everything');

    // Back to the home header. This is the ask the guard throws away.
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Only now does the slow read answer — with the number from before the
    // write, because that is what it was asked, and the flag the pop-back set
    // is what makes the pip **not** flash that number on the way past.
    h.release();
    await _until(tester, () => h.requests >= 2);
    expect(h.requests, 2,
        reason: 'the pop-back must spend the read the guard deleted');
    await _until(tester, () => h.requests >= 2);

    expect(find.byKey(const Key('notifications-badge')), findsNothing,
        reason: 'the in-flight read held the pre-write number and it is known '
            'to be behind, so it must never reach the header at all');
    expect(find.byKey(const Key('notifications-bell')), findsOneWidget);

    // And the number it ends on is the server's, not the phone's memory.
    await _until(tester, () => h.served == 0);
    expect(find.byKey(const Key('notifications-badge')), findsNothing,
        reason: 'he emptied the centre, so the pip he comes home to is nothing');
    expect(find.text('0'), findsNothing);
  });

  // The guard's original purpose must survive the fix. Two resumes inside one
  // frame ask the same question, and the read already in flight is that
  // answer — spending a second request only risks the slower one landing last
  // and painting a badge that goes backwards. If the fix dropped this test's
  // sibling in `notification_center_test`, this is what it broke.
  testWidgets('two resumes in one frame still spend one request', (tester) async {
    final h = _Held([_row(id: 1)]);

    await _pump(tester, h);
    expect(h.requests, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    h.release();
    await _until(tester, () =>
        find.byKey(const Key('notifications-badge')).evaluate().isNotEmpty);
    expect(find.text('1'), findsOneWidget);
    expect(h.requests, 1, reason: 'the same question is not asked twice');
  });
}
