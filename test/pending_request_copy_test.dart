// The pending payment card was a fixed pair of sentences.
//
// `PendingRequest` parsed five facts off `pending_request` and the widget that
// should have shown them was constructed as `const _PendingCard()` — no
// arguments, so the object was never read. These tests pin the receipt the
// card now prints.
//
// **The rule every case here obeys: a fact that did not arrive is not printed.**
// The server owns this payload, so the risk is not a wrong word but a blank
// separator next to a man waiting to hear whether his transfer landed.
import 'dart:convert';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/pending_request_copy.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A `pending_request` wrapped in the full `GET /api/mobile/subscription`
/// payload — the shape `PendingRequest.fromJson` was already written against
/// and the card ignored.
Map<String, dynamic> _withPending(Map<String, dynamic> pending) => {
      'currency': 'DZD',
      'commission_percent': 0,
      'commission_per_order': 0,
      'note_ar': 'الاشتراك فقط: بدون عمولة',
      'auto_renew': false,
      'renew_note_ar': 'الدفع مسبق',
      'plans': [
        {
          'id': 'pro',
          'name_ar': 'محترف',
          'name_fr': 'Pro',
          'tagline_ar': 'للمقاول الذي يعمل كل يوم',
          'price_month': 3000,
          'price_year': 30000,
          'quote_limit': -1,
          'portfolio_limit': 60,
          'search_boost': 3,
          'wilaya_span': 2,
          'features': ['ترتيب متقدّم في نتائج البحث'],
        }
      ],
      'current': {
        'plan': 'free_trial',
        'name_ar': 'مجاني',
        'status': 'active',
        'starts_at': null,
        'expires_at': null,
        'quote_limit': 3,
        'portfolio_limit': 5,
        'quotes_used_this_month': 0,
        'renews_in_days': null,
      },
      'pending_request': pending,
      'payment': {
        'methods': [
          {
            'id': 'baridimob',
            'label_ar': 'بريدي موب (تحويل)',
            'instructions': null
          }
        ],
        'support_phone': null,
      },
    };

void main() {
  group('pendingPlanLabelAr', () {
    test("uses the catalogue's Arabic name when there is one", () {
      expect(pendingPlanLabelAr('pro', 'محترف'), 'محترف');
    });

    test('falls back to the raw id so support can still be given something', () {
      // A plan renamed or withdrawn server-side must stay identifiable — the
      // id is exactly what support asks the man to quote.
      expect(pendingPlanLabelAr('gold', null), 'gold');
      expect(pendingPlanLabelAr('gold', '   '), 'gold');
    });

    test('a blank id is the only thing that prints a dash', () {
      expect(pendingPlanLabelAr('', null), '—');
    });
  });

  group('pendingAmountLabelAr', () {
    test('prints dinars without separators, as the founder asked', () {
      expect(pendingAmountLabelAr(15000), '15000 دج');
    });

    test('an unknown amount is absent, never «0 دج»', () {
      // The defect this whole item is about: a man who already transferred the
      // money must never be shown a zero for it.
      expect(pendingAmountLabelAr(null), isNull);
      expect(pendingAmountLabelAr(0), isNull);
      expect(pendingAmountLabelAr(-1), isNull);
    });
  });

  group('formatPendingDay', () {
    test('reads the day in the phone timezone, not bare UTC wall-clock', () {
      // D1 writes UTC. 23:30 UTC on the 12th is already the 13th in Algiers
      // (UTC+1), and the contractor is looking at his own clock.
      final utc = DateTime.utc(2026, 9, 12, 23, 30);
      final local = utc.toLocal();
      final expected = '${local.day.toString().padLeft(2, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-${local.year}';
      expect(formatPendingDay(utc), expected);
    });

    test('an unreadable timestamp drops the clause', () {
      expect(formatPendingDay(null), isNull);
    });
  });

  group('pendingMethodLabelAr', () {
    test("resolves through the catalogue's own wording", () {
      String lookup(String id) => id == 'baridimob' ? 'بريدي موب (تحويل)' : id;
      expect(pendingMethodLabelAr('baridimob', lookup), 'بريدي موب (تحويل)');
    });

    test('an unknown method keeps the raw id rather than vanishing', () {
      String lookup(String id) => id;
      expect(pendingMethodLabelAr('edahabia', lookup), 'edahabia');
    });

    test('absent method is absent', () {
      expect(pendingMethodLabelAr(null, (id) => id), isNull);
      expect(pendingMethodLabelAr('  ', (id) => id), isNull);
    });
  });

  group('pendingFactsAr', () {
    test('joins every fact that arrived', () {
      expect(
        pendingFactsAr(
          planLabel: 'محترف',
          amountLabel: '30000 دج',
          methodLabel: 'بريدي موب (تحويل)',
          dayLabel: '12-09-2026',
        ),
        'محترف · 30000 دج · بريدي موب (تحويل) · 12-09-2026',
      );
    });

    test('a payload with nothing in it returns null, not a bare separator', () {
      // This is the exact shape that would have shipped a row of « · · » to a
      // man waiting on his own money.
      expect(pendingFactsAr(), isNull);
      expect(
        pendingFactsAr(planLabel: null, amountLabel: null,
            methodLabel: null, dayLabel: null),
        isNull,
      );
    });

    test('a cash payment with no amount still reads, on two clauses', () {
      // Amount and method are separate parts precisely because a request with
      // a method but no amount is real (agreed over the phone).
      expect(
        pendingFactsAr(planLabel: 'أساسي', methodLabel: 'نقداً'),
        'أساسي · نقداً',
      );
    });

    test('no clause ever leaves a leading or trailing separator', () {
      expect(pendingFactsAr(dayLabel: '12-09-2026'), '12-09-2026');
      expect(pendingFactsAr(planLabel: 'مجاني'), 'مجاني');
      final all = pendingFactsAr(
          planLabel: 'p', amountLabel: 'a', methodLabel: 'm', dayLabel: 'd');
      expect(all!.startsWith('·'), isFalse);
      expect(all.endsWith('·'), isFalse);
      expect(all.contains('··'), isFalse);
    });
  });

  group('PendingRequest.fromJson', () {
    test('parses the full payload the server sends', () {
      final r = PendingRequest.fromJson({
        'id': 7,
        'plan': 'pro',
        'amount_paid': 30000,
        'payment_method': 'baridimob',
        'created_at': '2026-09-12 10:00:00',
      });
      expect(r.id, 7);
      expect(r.plan, 'pro');
      expect(r.amountDzd, 30000);
      expect(r.method, 'baridimob');
      expect(r.createdAt, isNotNull);
    });

    test('an absent amount stays null through the model, not 0', () {
      // The model is the second place this could go wrong; the test asserts the
      // parsed value the card will actually be handed.
      final r = PendingRequest.fromJson({
        'id': 7,
        'plan': 'pro',
        'payment_method': 'baridimob',
      });
      expect(r.amountDzd, isNull);
      expect(pendingAmountLabelAr(r.amountDzd), isNull);
    });

    test('an explicitly zero amount is also not printed as money', () {
      final r = PendingRequest.fromJson({
        'id': 7,
        'plan': 'pro',
        'amount_paid': 0,
      });
      expect(pendingAmountLabelAr(r.amountDzd), isNull);
    });

    test('the amount survives as a number in a string, as D1 sometimes writes', () {
      final r = PendingRequest.fromJson({
        'id': 7,
        'plan': 'pro',
        'amount_paid': '15000',
      });
      expect(r.amountDzd, 15000);
    });

    test('an unreadable amount is null, not 0', () {
      final r = PendingRequest.fromJson({
        'id': 7,
        'plan': 'pro',
        'amount_paid': 'beaucoup',
      });
      expect(r.amountDzd, isNull);
    });

    test('an unreadable timestamp is null, not a raw string', () {
      final r = PendingRequest.fromJson({
        'id': 7,
        'plan': 'pro',
        'created_at': 'not-a-date',
      });
      expect(r.createdAt, isNull);
      expect(formatPendingDay(r.createdAt), isNull);
    });

    test('a bare payload still yields a renderable card', () {
      // What the old card rendered, and what the new one must still render.
      final r = PendingRequest.fromJson({'id': 1});
      expect(
        pendingFactsAr(
          planLabel: r.plan.trim().isEmpty
              ? null
              : pendingPlanLabelAr(r.plan, null),
          amountLabel: pendingAmountLabelAr(r.amountDzd),
          methodLabel: pendingMethodLabelAr(r.method, (id) => id),
          dayLabel: formatPendingDay(r.createdAt),
        ),
        isNull,
      );
    });
  });

  group('PaymentOptions.labelFor', () {
    PaymentOptions options() => PaymentOptions.fromJson({
          'methods': [
            {
              'id': 'baridimob',
              'label_ar': 'بريدي موب (تحويل)',
              'instructions': null
            }
          ],
          'support_phone': null,
        });

    test('returns the operator wording for a known id', () {
      expect(options().labelFor('baridimob'), 'بريدي موب (تحويل)');
    });

    test('unknown id is null, and the caller falls back to the id itself', () {
      final o = options();
      expect(o.labelFor('edahabia'), isNull);
      expect(pendingMethodLabelAr('edahabia', (id) => o.labelFor(id) ?? id),
          'edahabia');
    });

    test('an empty catalogue resolves nothing rather than throwing', () {
      expect(PaymentOptions.fromJson(null).labelFor('baridimob'), isNull);
    });
  });

  group('the receipt on the real screen', () {
    // A model field can be parsed and never shown — that was the entire defect.
    // These drive SubscriptionScreen itself and read what build() produced,
    // because "the card could not answer how much I sent" is a claim about a
    // rendered screen, not about a getter.

    Future<List<String>> rendered(
      WidgetTester tester, {
      required Map<String, dynamic> payload,
    }) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/api/mobile/subscription')) {
            return http.Response(jsonEncode(payload), 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
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

      // Guard the guard: if the screen never loaded, every assertion below
      // would pass vacuously on an empty list.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(
        texts.any((t) => t.contains('أعد المحاولة')),
        isFalse,
        reason: 'the screen never loaded, so the card was never rendered: $texts',
      );
      return texts;
    }

    testWidgets('a paid request shows the plan, the amount and the day',
        (tester) async {
      final texts = await rendered(
        tester,
        payload: _withPending({
          'id': 7,
          'plan': 'pro',
          'amount_paid': 30000,
          'payment_method': 'baridimob',
          'created_at': '2026-09-12 10:00:00',
        }),
      );

      // Before this tick the card printed two fixed sentences and none of this.
      // The finder is scoped to the receipt key so it cannot accidentally match
      // the plan list's own «محترف».
      final receipt = find.byKey(const Key('pendingFacts'));
      expect(receipt, findsOneWidget,
          reason: 'the card still shows no receipt: $texts');

      final line = tester.widget<Text>(receipt).data!;
      expect(line, contains('محترف'));
      expect(line, contains('30000 دج'));
      expect(line, contains('بريدي موب (تحويل)'));
      expect(line, contains('2026'));
    });

    testWidgets('the receipt is absent when the server sent nothing usable',
        (tester) async {
      final texts = await rendered(tester, payload: _withPending({'id': 7}));
      // The old card is still correct for "we know nothing yet" — it must not
      // regress into printing separators with nothing between them.
      expect(find.byKey(const Key('pendingFacts')), findsNothing);
      expect(texts.any((t) => t.contains('طلبك قيد المراجعة')), isTrue);
    });

    testWidgets('an unknown amount does not print «0 دج» on the card',
        (tester) async {
      await rendered(
        tester,
        payload: _withPending({
          'id': 7,
          'plan': 'pro',
          'created_at': '2026-09-12 10:00:00',
        }),
      );
      // Scoped to the receipt line, deliberately. A first cut asserted this
      // against every `Text` on the screen and failed on `3000 دج` — the plan's
      // own price, where «0 دج» is a substring of a perfectly correct 3000. The
      // assertion has to name the line it is about, or it is testing the plan
      // card and calling it the payment card.
      final receipt =
          tester.widget<Text>(find.byKey(const Key('pendingFacts'))).data!;
      expect(receipt, isNot(contains('دج')),
          reason: 'a payment with no amount on the payload was shown as money: '
              '$receipt');
      // The plan is still named — the known fact survives the unknown one.
      expect(receipt, contains('محترف'));
      // ...and the single separator is the one joining the two real facts.
      expect('·'.allMatches(receipt).length, 1, reason: receipt);
    });
  });
}
