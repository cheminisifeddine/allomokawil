// The payment sheet's term was re-read from the screen after the write.
//
// Sixth member of the write-vs-form class, and the first one on the screen
// where a mistake costs real money. The class is one sentence: **a write that
// is in flight must be described by what was on screen when it was pressed,
// not by whatever the form says afterwards.** Six screens shipped it —
// `project_new_screen` (title), `review_screen` (rating), `project_detail` and
// the bid sheet (the verdict), `chat_screen` (`_me` inside a recovery
// closure) — and the subscription screen did not.
//
// `_openPaymentSheet` snapshots the pending request when the sheet opens
// (`before: catalogue.pendingRequest`) precisely because "did it land" cannot
// be asked afterwards: a catalogue the screen happened to re-render in between
// must not forge the proof. That snapshot is correct, and it sits one line
// above the thing that is wrong. `_request` then reads `_period` **twice,
// after the POST**:
//
//     await _repo.requestSubscription(period: _period, …);   // ← sent
//     …
//     final dispute = PlanPriceDispute.between(
//       periodWire: _period.wire,                              // ← re-read
//       quotedDzd: plan.priceFor(_period),                     // ← re-read
//       chargedDzd: ack?.amountDzd,
//     );
//
// The period toggle is not disabled while the write is in flight — nothing
// takes `busy` — so the whole two lines is reachable with one thumb. The man
// taps «ادفع» on the **monthly** card, the POST is on the wire, and before the
// answer arrives he moves the toggle to «سنوي» because he wants to compare the
// annual price. The write was for a month. D1 charges the monthly figure, or
// whatever it computed, and the app files the dispute against `year`.
//
// The result is the exact screen the last two ticks were about, in the other
// direction: the **yearly** card draws a struck-through «30000 دج» and
// «المبلغ المعتمد 3000 دج» under it, while the monthly card he actually paid
// for is drawn clean. The band quotes a price that was never disputed, the
// man is told to confirm 3000 with support for a plan he bought for 30000,
// and the number on the card he is reading is a different purchase from the
// one the app is complaining about.
//
// The fix is the same one the other five screens got, and it is not "disable
// the toggle": he is allowed to change his mind about what he is *looking at*
// while a write he already committed to is in the air, and locking the screen
// would take away the comparison he is in the middle of. The fix is to
// **snapshot the term the write was made under, where the sheet is opened**,
// and describe the write by that.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/subscription_ack.dart';
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
          'features': <String>['ترتيب متقدّم في نتائج البحث'],
        },
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

/// Boots the screen, opens the monthly sheet, taps submit, and then moves the
/// term toggle **while the POST is still on the wire**.
///
/// The gate is the whole test: the mocked POST waits on a completer the test
/// holds, so the toggle tap provably happens between the press and the
/// answer. Nothing here is a race the test hopes to win.
Future<void> _payThenToggle(
  WidgetTester tester, {
  required int charged,
  required GlobalKey key,
}) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  // The gate is held across ~10 s of pumped fake time, and `pump` advances the
  // clock, so the default 20 s write ceiling would fire and the POST would
  // throw `errWriteUnconfirmed` before the test ever let it answer. Long enough
  // that only the gate decides when the write lands.
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    timeout: const Duration(minutes: 5),
    httpClient: MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/subscription')) {
        // Parked on the **fake** clock for 4 s of pumped time, and the test
        // toggles the term inside that window. A fake-async `delayed` and not
        // an externally completed `Completer`: the handler runs in the test's
        // fake zone, so its continuation is drained by `pump` like every other
        // one. A gate completed from the test body left the whole chain —
        // handler, MockClient, the client's own `.timeout`, the repository —
        // parked in a queue the fake clock never reached, and the write simply
        // never came back. That is a harness trap, and it reads exactly like a
        // passing test if you do not check that the answer ever arrived.
        await Future<void>.delayed(const Duration(seconds: 4));
        return http.Response(
          jsonEncode({
            'ok': true,
            'request_id': 42,
            'status': 'pending',
            'period': 'month',
            'months': 1,
            'amount_dzd': charged,
            'plan': {'id': 'pro'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path.endsWith('/api/mobile/subscription')) {
        return http.Response(jsonEncode(_catalogue()), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(<String, Object?>{}), 200,
          headers: {'content-type': 'application/json'});
    }),
  );

  // The **parameter's** key, not a fresh one: a local declared here shadows
  // it, the widget is built with the local, and the test that passed the
  // parameter in then holds a key attached to nothing — so the raster step
  // dies on `key.currentContext!` with a null check error and no picture,
  // after every assertion above it has already passed.
  await tester.pumpWidget(AppScope(
    api: api,
    auth: AuthState(api),
    child: RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: const SubscriptionScreen(),
      ),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  await tester.tap(find.byKey(const Key('plan-pro-month')));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.byKey(const Key('plan-submit')), findsOneWidget,
      reason: 'the payment sheet never opened');
  await tester.tap(find.byKey(const Key('plan-submit')));
  // One frame: the sheet is closing and the POST is now parked on the gate.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a write in flight is described by the term it was made under',
      (tester) async {
    final key = GlobalKey();
    await _payThenToggle(tester, charged: 4500, key: key);

    // The man decides he wants to compare the annual price while his
    // transfer is being declared. One thumb, and the toggle is not disabled
    // during a write.
    await tester.tap(find.text('سنوي'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Let the write answer.
    // Let the answer land: past the handler's 4 s and past the reload the
    // write triggers afterwards.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    // He bought a month for 3000 and D1 charged 4500. The **monthly** card is
    // the one in dispute.
    //
    // The term the toggle is on when this runs is the harness's whole
    // difficulty, and it is not a detail: the monthly and yearly cards are
    // **different widgets** (`plan-pro-month` vs `plan-pro-year`), so exactly
    // one of them is in the tree at a time on a lazy `ListView`. Scrolling to
    // the one that is not there fails with `Bad state: No element`. So each
    // card is inspected on the term the toggle is already on, and the toggle
    // moves only between them.
    //
    // The band, first and **without scrolling**, because it is the reason
    // the ordering matters: it sits at the top of a lazy `ListView`, so a
    // `scrollUntilVisible` down to a plan card disposes it, and an earlier
    // version of this file asserted the band *after* scrolling and read its
    // absence as a missing dispute. Reading the screen is not the same as
    // reading whatever is still in the tree.
    //
    // The toggle is on «سنوي» and the write was for a month. The band is
    // correctly gone: its sentence quotes "the price displayed", and the
    // price displayed is 30000 دج. That is the term-scoping rule working, and
    // asserting its presence here would be testing against it.
    expect(find.byKey(const Key(planPriceMismatchKey)), findsNothing,
        reason: 'the band survived a term change, so it is quoting a price '
            'that is not on screen');

    // The term nobody bought. This is the whole defect in one assertion:
    // 30000 دج was never disputed, and stamping «المبلغ المعتمد 4500 دج»
    // under it tells a man to confirm with support a payment he never made.
    await tester.scrollUntilVisible(
        find.byKey(const Key('plan-price-pro-year')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final yearly = tester
        .widget<Text>(find.byKey(const Key('plan-price-pro-year')));
    expect(yearly.style!.decoration, TextDecoration.none,
        reason: 'the dispute for a MONTH was painted on the YEAR: 30000 دج is '
            'marked wrong for a purchase nobody made');
    expect(find.text('المبلغ المعتمد 4500 دج'), findsNothing,
        reason: 'the amount D1 charged for the month is being charged to the '
            'yearly card as well');

    // Now the term he actually paid for. The band returns, which is what
    // proves the dispute was filed on `month` rather than merely hidden.
    await tester.tap(find.text('شهري'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byKey(const Key(planPriceMismatchKey)), findsOneWidget,
        reason: 'the dispute is not on the monthly term, so a real 4500/3000 '
            'disagreement on the term he paid for is silent');
    await tester.scrollUntilVisible(
        find.byKey(const Key('plan-price-pro-month')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final monthly = tester
        .widget<Text>(find.byKey(const Key('plan-price-pro-month')));
    expect(monthly.style!.decoration, TextDecoration.lineThrough,
        reason: 'the card for the term he paid for is drawn clean, so the '
            'price he reads at the bottom of his eye is the wrong one');
    expect(find.text('المبلغ المعتمد 4500 دج'), findsOneWidget,
        reason: 'the monthly card does not say what D1 charged');

    // ── the picture ──────────────────────────────────────────────────────
    // A widget test proves the strike is in the tree. It does not prove the
    // card drew it *legibly*, and the sibling shot file exists because
    // printing the amount under the price once pushed this same card's row
    // 53 px past its edge — a red that overflowed is still a red the finder
    // can see. So the frame is captured here, with the card fully on screen.
    //
    // Scrolled back to the top first, so the shot shows the whole state: the
    // band, the receipt and the marked card, which is the screen the man reads
    // and not a crop of one widget.
    await tester.ensureVisible(find.byKey(const Key('plan-pro-month')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(tester.takeException(), isNull,
        reason: 'the marked price column overflowed its Row');
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('/tmp/shots').createSync(recursive: true);
      File('/tmp/shots/22_payment_term_snapshot.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
