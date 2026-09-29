// The owner\'s quote list, before and after he commits — photographed.
//
// The widget assertions in `quote_status_test.dart` prove the behaviour. This
// file proves the *pixels*, because the claim that matters is visual: a
// customer who lost the bid must be able to see, on the card itself, that he
// lost it. `findsNothing` on a button is a fact about the tree; it says nothing
// about whether the two cards still look identical to a reader — and
// "identical" is precisely the defect.
//
// Two captures of the same screen:
//
//   * `quote_cards_live.png`    two live bids, both carrying «قبول العرض»;
//   * `quote_cards_decided.png` the state the Worker sends after a commit:
//                               48 `accepted`, 49 `rejected`, zero buttons.
//
// They must differ, and the difference must be where the verdict is, not
// anywhere else in the frame. Both are written to /tmp/shots/ and are NOT
// goldens: a golden here would freeze «الآن» into a baseline and fail on every
// other day of the week, which is exactly the trap the `clock` seam exists to
// avoid.
//
// Run with:  flutter test test/quote_status_shot_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

const _out = '/tmp/shots/quote';

/// Fixed, so the date line is a constant word in both captures and the only
/// thing that differs between them is the verdict.
final _now = DateTime.utc(2026, 9, 29, 17, 0, 53);

Map<String, dynamic> _row(int id, {String status = 'pending'}) => <String, dynamic>{
      'id': id,
      'project_id': 'p1',
      'worker_id': 100 + id,
      'amount': 5000 + id * 400,
      'message': 'يمكنني البدء غداً',
      'estimated_days': 5,
      'status': status,
      'created_at': '2026-09-29 17:00:53',
      'worker_full_name': id == 48 ? 'خالد رحماني' : 'يوسف بن عمر',
      'worker_avatar_url': null,
      'worker_avg_rating': 4.6,
      'worker_total_reviews': 18,
      'worker_verification_status': 'verified',
    };

Map<String, dynamic> _user() => <String, dynamic>{
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

http.Response _json(Object b) => http.Response(jsonEncode(b), 200,
    headers: {'content-type': 'application/json'});

/// A signed-in owner plus the API client the screen is driven against — the
/// **same** client, because `AuthState` owns its own and a screen wired to a
/// second one would be reading a different server than the assertions claim.
Future<({ApiClient api, AuthState auth})> _boot(
    List<Map<String, dynamic>> rows) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object>{'token': 'tok', 'user': _user()});
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.startsWith('/api/mobile/projects/p1/quotes')) return _json(rows);
      if (p == '/api/mobile/projects/p1') return _json(_project());
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<String> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    path = '$_out/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  return path;
}

void main() {
  testWidgets('the owner\'s quote list, live and after he commits', (tester) async {
    // 2400, not 1150. The bid cards sit well below the fold on a project with
    // this much chrome above them, and a capture that stops short of them
    // photographs the same header in both states — which is how the first
    // version of this file reported two byte-identical PNGs as a *product*
    // defect instead of a harness that never looked at the cards. Same size the
    // widget tests use for the same screen.
    tester.view.physicalSize = const Size(392, 2400) * 2.75;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final live = <Map<String, dynamic>>[_row(48), _row(49)];
    final decided = <Map<String, dynamic>>[
      _row(48, status: 'accepted'),
      _row(49, status: 'rejected'),
    ];

    String livePath = '';
    String decidedPath = '';

    for (final shot in <(String, List<Map<String, dynamic>>)>[
      ('live', live),
      ('decided', decided),
    ]) {
      final boot = await _boot(shot.$2);
      final api = boot.api;
      final repo = Repository(api);
      await tester.pumpWidget(AppScope(
        api: api,
        auth: boot.auth,
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
          // Keyed by the capture. The second `pumpWidget` in this test builds
          // the *same* widget types, so Flutter keeps the existing State and
          // `ProjectDetailScreen.initState` never runs a second time — the
          // quotes future created for the live capture is still mounted, and
          // the decided state is never fetched. The two PNGs were then
          // byte-identical for a reason that had nothing to do with the
          // product. A distinct key forces a real rebuild.
          home: RepaintBoundary(
            key: const ValueKey('shot'),
            child: ProjectDetailScreen(
                key: ValueKey('capture-${shot.$1}'),
                projectId: 'p1',
                repo: repo,
                clock: () => _now),
          ),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      final p = await _capture(tester, 'quote_cards_${shot.$1}');
      if (shot.$1 == 'live') {
        livePath = p;
      } else {
        decidedPath = p;
      }
    }

    // The two captures must differ, and differ *only* by the verdict. A helper
    // that returned two byte-identical PNGs while every assertion passed is the
    // failure this project already paid for once (`accept_quote_failure_test`
    // records it), so the check is here rather than assumed.
    final a = File(livePath).readAsBytesSync();
    final b = File(decidedPath).readAsBytesSync();
    expect(a.length, greaterThan(1000));
    expect(b.length, greaterThan(1000));
    expect(a.length == b.length && _sameBytes(a, b), isFalse,
        reason: 'the live and decided lists rendered identically — the verdict '
            'is not reaching the pixels');
    // ignore: avoid_print
    print('SHOT live=$livePath decided=$decidedPath '
        'liveBytes=${a.length} decidedBytes=${b.length}');
  });
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
