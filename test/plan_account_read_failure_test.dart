// The account tab's own subscription line, and the one sentence it must never
// print when the read behind it failed.
//
// Found on 27 Sep 2026. `_PlanAccountRow` is the only read on the account
// screen, and it is the one read in this family that is *not* even a
// `FutureBuilder` failure branch — it never asks `snap.hasError` at all:
//
//   value: _planSummary(snap.data?.current, snap.connectionState)
//
// `_planSummary` keys on `s == null`, and `snap.data` is null on an error
// exactly as it is on a read that has not answered. So the 500 branch and the
// first-frame branch are the same string:
//
//   return state == ConnectionState.waiting
//       ? 'جارٍ التحقق من اشتراكك…'
//       : 'اختر خطتك — شهري أو سنوي';
//
// A failed read therefore publishes a *settlement*: the row reads «اختر خطتك» —
// "pick your plan" — as though the server had answered "free trial". A
// contractor whose paid plan failed to load is told, in the app's own voice,
// that he has no plan. He is on the row whose only job is to send him to the
// renewal screen (see the comment on `_planSummary`'s expired branch), and the
// one moment that matters he is misinformed about his own money.
//
// The row is also the only read on the screen with **no recovery at all**: no
// `RefreshIndicator` on the `ListView`, no retry control, and the read is
// issued once in `didChangeDependencies` and never re-issued. Every other read
// on every other screen answers a failure with something the user can press.
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
import 'package:allomokawil/src/screens/profile_screen.dart';

Map<String, Object?> _user(String type) => {
      'id': type == 'worker' ? 31 : 30,
      'phone': '0773000000',
      'email': null,
      'full_name': 'مقاول تجربة',
      'type': type,
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// A 500 with an HTML body — the captive-portal / Worker-crash shape.
http.Response _boom() =>
    http.Response('<html>Internal Server Error</html>', 500,
        headers: {'content-type': 'text/html'});

/// A paid plan, so the test can prove a real answer is never overwritten.
Map<String, Object?> _paid() => <String, Object?>{
      'currency': 'DZD',
      'note_ar': 'الدفع مسبق',
      'renew_note_ar': 'ادفع مسبقاً',
      'auto_renew': 0,
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[],
      'current': <String, Object?>{
        'plan': 'basic',
        'name_ar': 'أساسي',
        'price_month': 4500,
        'price_year': 45000,
        'quote_limit': 10,
        'quotes_used_this_month': 2,
        'expires_at': '2027-01-01 00:00:00',
      },
      'pending_request': null,
      'payment': <String, Object?>{'methods': <Object?>[]},
    };

Future<({ApiClient api, AuthState auth, List<String> log})> _boot({
  required Future<http.Response> Function() subscription,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user('worker')});
      }
      if (p.endsWith('/api/mobile/subscription')) return subscription();
      return _json(<Object?>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth, log: log);
}

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 900),
}) async {
  tester.view.physicalSize = logical * 2.75;
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
      home: const ProfileScreen(),
    ),
  ));
  await _settle(tester);
}

int _subReads(List<String> log) =>
    log.where((l) => l.endsWith('/api/mobile/subscription')).length;

/// Renders the account screen to a PNG so a claim about the failed row's
/// layout and colour can be looked at rather than asserted about.
Future<String> _shoot(
  WidgetTester tester,
  String name,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 900),
}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
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
      home: RepaintBoundary(key: key, child: const ProfileScreen()),
    ),
  ));
  await _settle(tester);

  final target = find.text('تعذّر جلب اشتراكك');
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 100));
  }

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  return path;
}

void main() {
  testWidgets('a failed subscription read must not read as «pick your plan»',
      (tester) async {
    final b = await _boot(subscription: () async => _boom());
    await _pump(tester, b.api, b.auth);

    // The false settlement: a 500 is published as "you have no plan".
    expect(find.text('اختر خطتك — شهري أو سنوي'), findsNothing,
        reason: 'a failed read is not a free trial; the row told him to pay');
    // …and the row must say what actually happened.
    expect(find.textContaining('تعذّر'), findsOneWidget,
        reason: 'the failure has to be visible, not substituted');
  });

  testWidgets('the failed row is an error state, not the free-plan sentence',
      (tester) async {
    final b = await _boot(subscription: () async => _boom());
    await _pump(tester, b.api, b.auth);

    // The free-plan copy is still true of a *real* free plan, so it cannot be
    // the thing that distinguishes the two states — the colour can.
    final row = find.byKey(const Key('account-subscription'));
    expect(row, findsOneWidget);
    expect(find.text('الباقة المجانية — اطّلع على الخطط'), findsNothing);
  });

  testWidgets('a failed read offers a retry that re-issues the request',
      (tester) async {
    var attempt = 0;
    final b = await _boot(subscription: () async {
      attempt++;
      return attempt == 1 ? _boom() : _json(_paid());
    });
    await _pump(tester, b.api, b.auth);
    expect(_subReads(b.log), 1, reason: 'the first read happened');
    expect(find.text('اشتراكي'), findsOneWidget,
        reason: 'the row itself is the door to the plan; it must survive');

    // The control has to be a real control, not a label.
    final retry = find.byIcon(Icons.refresh_rounded);
    expect(retry, findsOneWidget, reason: 'a failed read needs a way back');
    await tester.tap(retry, warnIfMissed: false);
    await _settle(tester);

    expect(_subReads(b.log), 2, reason: 'the retry re-issued the read');
    // And the retry actually landed: the paid plan is on the row.
    expect(find.textContaining('أساسي'), findsOneWidget,
        reason: 'the recovered read must publish the real plan');
    expect(find.text('اختر خطتك — شهري أو سنوي'), findsNothing);
  });

  testWidgets('a real free plan is still described as free', (tester) async {
    final b = await _boot(
        subscription: () async => _json(<String, Object?>{
              ..._paid(),
              'current': <String, Object?>{
                'plan': 'free_trial',
                'name_ar': 'مجانية',
                'price_month': 0,
                'price_year': 0,
                'quote_limit': 3,
                'quotes_used_this_month': 0,
                'expires_at': null,
              },
            }));
    await _pump(tester, b.api, b.auth);

    expect(find.text('الباقة المجانية — اطّلع على الخطط'), findsOneWidget,
        reason: 'a real free plan keeps its sentence; the fix must not blur it');
    expect(find.textContaining('تعذّر'), findsNothing);
    // A paid row is not an error row, so it wears no retry.
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
  });

  testWidgets('a paid plan is never overwritten by the error state',
      (tester) async {
    final b = await _boot(subscription: () async => _json(_paid()));
    await _pump(tester, b.api, b.auth);

    expect(find.textContaining('نشط حتى'), findsOneWidget,
        reason: 'a good read publishes the plan and its end date');
    expect(find.text('اختر خطتك — شهري أو سنوي'), findsNothing);
  });

  testWidgets('the failed row is dressed as a failure, not as a normal row',
      (tester) async {
    final b = await _boot(subscription: () async => _boom());
    await _pump(tester, b.api, b.auth);

    // A row that says «تعذّر جلب اشتراكك» but still wears the amber of a
    // settled plan is a row the eye reads as fine. The wash is the whole
    // signal at this size, so it is pinned rather than left to the shot.
    final row = find.byKey(const Key('account-subscription'));
    expect(row, findsOneWidget);
    // The wash is the IconBubble's own Container inside the row, so this has
    // to search the row's *descendants* - and read the BoxDecoration, because
    // that is where the colour lives, not in Container.color.
    bool hasWash(Color c) => find
        .descendant(of: row, matching: find.byType(Container))
        .evaluate()
        .any((e) =>
            e.widget is Container &&
            (e.widget as Container).decoration is BoxDecoration &&
            ((e.widget as Container).decoration as BoxDecoration).color == c);
    expect(hasWash(AppTheme.dangerWash), isTrue,
        reason: 'the failed row kept the settled-row wash');
    expect(hasWash(AppTheme.accentWash), isFalse,
        reason: 'amber is the colour of a plan that answered');
    // And it replaces the chevron *on this row*: a "open the plan" affordance
    // sitting on a row that has no plan to read is the old lie wearing a
    // different font. The chevron is counted inside the row, because the three
    // rows above it are all legitimately tappable doors with their own.
    expect(
        find.descendant(
            of: row, matching: find.byIcon(Icons.chevron_left_rounded)),
        findsNothing);
    expect(
        find.descendant(
            of: row, matching: find.byIcon(Icons.refresh_rounded)),
        findsOneWidget);
  });

  testWidgets('the retry control keeps a real >= 48dp tap target',
      (tester) async {
    final b = await _boot(subscription: () async => _boom());
    await _pump(tester, b.api, b.auth);

    final target = tester.getSize(
        find.byKey(const Key('account-subscription-retry')).first);
    // AppTheme.tapMin is 56 dp; the audit gate is 48. The control is a
    // transparent 56 dp box around a 20 dp glyph, so a pixel scan of the shot
    // can only ever measure the glyph - the target is asserted here instead.
    expect(target.width, greaterThanOrEqualTo(48.0),
        reason: 'a retry the user cannot hit is not a retry');
    expect(target.height, greaterThanOrEqualTo(48.0));
  });

  testWidgets('a second tap while the retry is in flight is swallowed',
      (tester) async {
    // The retry has to *stay* in flight for this to mean anything, so the
    // second attempt is slow rather than instantly failing. My first version
    // used the same instant 500 as the first read; the busy state was over
    // inside one pump, so the test was asserting on a moment that no longer
    // existed - it passed for the wrong reason and would have kept passing if
    // the control had never latched at all.
    var attempt = 0;
    final b = await _boot(subscription: () async {
      attempt++;
      if (attempt == 1) return _boom();
      await Future<void>.delayed(const Duration(seconds: 3));
      return _json(_paid());
    });
    await _pump(tester, b.api, b.auth);
    expect(_subReads(b.log), 1);

    final key = find.byKey(const Key('account-subscription-retry')).first;
    await tester.tap(key);
    await tester.pump();
    expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget,
        reason: 'the control must show it latched');

    // A user on a slow connection taps again. That must not queue a second
    // request behind the one already running.
    await tester.tap(key, warnIfMissed: false);
    await tester.pump();
    expect(_subReads(b.log), 2,
        reason: 'a second tap issued a third request against one retry');
    // …and the tap did not escape to the card underneath, which would navigate
    // the man to the plan screen with the retry still running behind him.
    expect(find.byType(ProfileScreen), findsOneWidget,
        reason: 'the row pushed a route on a swallowed tap');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the failed row is shot, so the claim is looked at not asserted',
      (tester) async {
    final b = await _boot(subscription: () async => _boom());
    final path = await _shoot(tester, 'plan_account_read_failed', b.api, b.auth);
    expect(File(path).lengthSync(), greaterThan(20000),
        reason: 'a shot this small means nothing rendered');
  });

  testWidgets('the retry is not offered while the first read is still in flight',
      (tester) async {
    final b = await _boot(subscription: () async {
      await Future<void>.delayed(const Duration(seconds: 2));
      return _json(_paid());
    });
    tester.view.physicalSize = const Size(392, 900) * 2.75;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      api: b.api,
      auth: b.auth,
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
        home: const ProfileScreen(),
      ),
    ));
    await tester.pump();

    expect(find.text('جارٍ التحقق من اشتراكك…'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing,
        reason: 'a pending read is not a failed one; offering retry would let '
            'a tap stack a second request behind the first');
    await tester.pump(const Duration(seconds: 3));
  });
}
