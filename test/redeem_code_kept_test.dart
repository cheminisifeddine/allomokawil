// The screen told the man to retype a code it had just deleted.
//
// `_redeem` runs `_codeController.clear()` on the way out of the `try`,
// *before* it knows whether the redemption happened. On the one branch that
// matters most — a 200 whose body carries no `plan` object — it then prints
// `S.planCodeNoPlan`:
//
//     لم يُرجع الخادم تفاصيل التفعيل — تحقّق من اشتراكك قبل إعادة إدخال الرمز
//
// …which instructs him to re-enter the code. The field he would re-enter it
// into is empty, and there is nothing on the screen holding what he typed: no
// history, no undo, no copy. An activation code is bought in cash against a
// paper receipt, typed in by hand, and it is **single-use** —
// `redeem_outcome.dart` opens by saying a code the server may already have
// burned must never be typed into a box that will refuse it. So the two halves
// of this screen contradict each other: the sentence asks for the one thing
// the screen has just made impossible, and the man has to go find a receipt to
// retype a string from memory, letter by letter, before deciding whether the
// first one even worked.
//
// Note what is *not* being proposed. Clearing the field is right, and is what
// a correct redemption should do — the code is spent and the man must not be
// able to press «تفعيل» on it again. The defect is only that the clear was
// unconditional while the sentence it sits next to is conditional: the app
// cannot tell whether the code is spent, so it must not destroy it on the one
// path where it is explicitly telling him to use it again.
//
// Both halves are tested, because they fail in opposite directions and a fix
// that simply never clears the field would pass the first and leave a spent
// code sitting in a box under a live «تفعيل».
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

Map<String, dynamic> _catalogue() => {
      'currency': 'DZD',
      'note_ar': 'الاشتراك فقط: بدون عمولة',
      'auto_renew': false,
      'plans': [
        {
          'id': 'pro',
          'name_ar': 'محترف',
          'price_month': 3000,
          'price_year': 30000,
          'quote_limit': -1,
          'portfolio_limit': 60,
          'features': ['ترتيب متقدّم في نتائج البحث'],
        }
      ],
      'current': {'plan': 'free_trial', 'status': 'active'},
      'pending_request': null,
      'payment': {
        'methods': [
          {'id': 'baridimob', 'label_ar': 'بريدي موب (تحويل)'}
        ],
        'support_phone': null,
      },
    };

/// The screen, a code typed into it, and «تفعيل» pressed — the real card, the
/// real field and the real button, by their stable keys.
///
/// Returns everything the screen is saying afterwards, so a test can ask what
/// it told the man and what it left him holding.
Future<String> redeemAndReport(
  WidgetTester tester, {
  required Map<String, dynamic> redeemBody,
  bool unconfirmed = false,
}) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/subscription/redeem')) {
        if (unconfirmed) {
          // The transport's own shape for an unanswered write, not a faked
          // status code: it refuses to retry a POST whose answer did not
          // arrive, and a 5xx would decode to `errServer` and take a different
          // branch entirely.
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        return http.Response(jsonEncode(redeemBody), 200,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path.endsWith('/api/mobile/subscription')) {
        return http.Response(jsonEncode(_catalogue()), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(<String, Object?>{}), 200,
          headers: {'content-type': 'application/json'});
    }),
    timeout: const Duration(milliseconds: 25),
  );

  await tester.pumpWidget(AppScope(
    api: api,
    auth: AuthState(api),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: const SubscriptionScreen(),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  expect(find.byKey(const Key('plan-code')), findsOneWidget,
      reason: 'the redemption card never rendered');
  await tester.enterText(find.byKey(const Key('plan-code')), 'ALOMOK-2026');
  await tester.tap(find.byKey(const Key('plan-redeem')));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Read the text off the `EditableText` the key's field renders, not off a
  // `Text`: the controller belongs to the field, and asserting on the rendered
  // string is what the man actually sees.
  final field = find.byKey(const Key('plan-code'));
  return tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  ).controller.text;
}

/// The catalogue with the plan it is reporting, so a re-read can show the row
/// actually moving.
Map<String, dynamic> _catalogueWith({
  String plan = 'free_trial',
  String? expiresAt,
}) {
  final c = _catalogue();
  (c['current'] as Map<String, dynamic>)['plan'] = plan;
  if (expiresAt != null) {
    (c['current'] as Map<String, dynamic>)['expires_at'] = expiresAt;
  }
  return c;
}

void main() {
  testWidgets('a code the screen cannot account for is still there to retype',
      (tester) async {
    final left = await redeemAndReport(tester, redeemBody: {'ok': true});

    // The sentence on screen, and the thing it is asking for. Both halves are
    // asserted because the copy is only honest if it is *actionable*, and this
    // is the one branch where the app is handing the problem back to the user.
    expect(find.text(S.planCodeNoPlan), findsOneWidget,
        reason: 'a plan-less answer stopped saying it cannot confirm');

    expect(left, 'ALOMOK-2026',
        reason: 'the screen told the man to retype the code and then deleted it');
  });

  testWidgets('a code the server confirmed is spent, and is gone for good',
      (tester) async {
    // The control, and it fails in the opposite direction. A fix that simply
    // never clears the field would pass the test above clean and leave a burned
    // code sitting in a box under a live «تفعيل» — a second press the server
    // will refuse, on a purchase the man has already paid for. The clear is
    // not the defect; the *unconditional* clear was.
    final left = await redeemAndReport(tester, redeemBody: {
      'plan': {'id': 'pro'},
    });

    expect(find.textContaining(S.planCodeOk), findsWidgets,
        reason: 'a real redemption stopped claiming activation');
    expect(left, isEmpty,
        reason: 'a confirmed redemption left its spent code in the field');
  });

  testWidgets('a code the re-read proves landed is spent, and is gone for good',
      (tester) async {
    // The third branch, and the one that arrives by a completely different
    // route: no answer, so the app re-reads, and the re-read finds the plan the
    // code bought. Here the app *has* the evidence — the same evidence the
    // `plan == null` branch lacks — so the code is spent and must go. Asserted
    // separately because clearing on the answer and clearing on the re-read are
    // two edits, and a fix applied to only one of them is invisible to the
    // other.
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    var reads = 0;
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        if (req.method == 'POST' && req.url.path.endsWith('/subscription/redeem')) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          return http.Response(jsonEncode({'ok': true}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (req.url.path.endsWith('/api/mobile/subscription')) {
          reads++;
          final landed = reads > 1;
          return http.Response(
              jsonEncode(_catalogueWith(
                plan: landed ? 'pro' : 'free_trial',
                expiresAt: landed ? '2026-12-01 00:00:00' : null,
              )),
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode(<String, Object?>{}), 200,
            headers: {'content-type': 'application/json'});
      }),
      timeout: const Duration(milliseconds: 25),
    );

    await tester.pumpWidget(AppScope(
      api: api,
      auth: AuthState(api),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: const SubscriptionScreen(),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(find.byKey(const Key('plan-code')), 'ALOMOK-2026');
    await tester.tap(find.byKey(const Key('plan-redeem')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final left = tester
        .widget<EditableText>(find.descendant(
          of: find.byKey(const Key('plan-code')),
          matching: find.byType(EditableText),
        ))
        .controller
        .text;

    expect(reads, greaterThanOrEqualTo(2),
        reason: 'the screen never re-read after the unconfirmed write');
    expect(left, isEmpty,
        reason: 'a redemption the re-read proved landed kept its spent code');
  });
}
