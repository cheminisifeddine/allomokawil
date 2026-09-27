// Rasterizes the pending-payment card in the two states this change produces.
//
// The web+CDP path in the protocol needs Chrome and a JDK, and this box has
// neither (`/usr/lib/jvm` does not exist), so the bundle cannot be built here.
// These shots go through the same `RepaintBoundary` + `tester.runAsync`
// capture that `design_shots_test.dart` uses, which is the real rasterizer.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/pending_request_copy.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = '/tmp/shots';

/// The card body exactly as `_PendingCard` composes it, so the shot is the
/// shipped layout rather than a restatement of it.
Widget _card({
  required String? period,
  required int amount,
  required String method,
}) {
  final request = PendingRequest.fromJson({
    'id': 11,
    'plan': 'basic',
    'period': period,
    'amount_paid': amount,
    'payment_method': method,
    'created_at': '2026-09-26 15:00:00',
  });
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded, color: AppTheme.info),
          const SizedBox(width: AppTheme.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('طلبك قيد المراجعة', style: AppTheme.h2.copyWith(fontFamily: 'Cairo')),
                const SizedBox(height: AppTheme.s4),
                Text('استلمنا طلبك وسنؤكد الدفع.',
                    style: AppTheme.body.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.6,
                        fontFamily: 'Cairo')),
                if (pendingFactsAr(
                      planLabel: pendingPlanLabelAr(request.plan, 'أساسي'),
                      amountLabel: pendingAmountLabelAr(request.amountDzd),
                      methodLabel: pendingMethodLabelAr(
                          request.method, (id) => 'بريدي موب (تحويل)'),
                      dayLabel: formatPendingDay(request.createdAt),
                      periodLabel: pendingPeriodLabelAr(request.period),
                      numberLabel: pendingRequestNumberAr(request.id),
                    ) !=
                    null) ...[
                  const SizedBox(height: AppTheme.s12),
                  Text(
                    pendingFactsAr(
                      planLabel: pendingPlanLabelAr(request.plan, 'أساسي'),
                      amountLabel: pendingAmountLabelAr(request.amountDzd),
                      methodLabel: pendingMethodLabelAr(
                          request.method, (id) => 'بريدي موب (تحويل)'),
                      dayLabel: formatPendingDay(request.createdAt),
                      periodLabel: pendingPeriodLabelAr(request.period),
                      numberLabel: pendingRequestNumberAr(request.id),
                    )!,
                    key: const Key('facts'),
                    style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo'),
                  ),
                ],
                if (pendingPeriodMismatchNoteAr(request.period) != null) ...[
                  const SizedBox(height: AppTheme.s4),
                  Text(
                    pendingPeriodMismatchNoteAr(request.period)!,
                    key: const Key('note'),
                    style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.5,
                        fontFamily: 'Cairo'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

Future<void> _shoot(WidgetTester tester, String name, Widget child) async {
  final key = GlobalKey();
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: RepaintBoundary(
      key: key,
      child: AppScope(
        api: ApiClient(baseUrls: ['https://probe.invalid']),
        auth: AuthState(ApiClient(baseUrls: ['https://probe.invalid'])),
        child: Scaffold(
          backgroundColor: AppTheme.bg,
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(child: SizedBox(width: 360, child: child)),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await b.toImage(pixelRatio: 3.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Without this the flutter_test box font draws every Arabic glyph as a tofu
  // square and the shots prove nothing about the wording. The same loader
  // `font_probe_test.dart` uses to prove Cairo actually took effect.
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final loader = FontLoader('Cairo')..addFont(Future.value(reg));
    await loader.load();
  });

  testWidgets('the card names the filed term (year)', (t) async {
    await _shoot(t, 'zz_pending_term_year',
        _card(period: 'year', amount: 15000, method: 'baridimob'));
  });

  testWidgets('an unrecognised filed period warns instead of claiming a month',
      (t) async {
    await _shoot(t, 'zz_pending_term_mismatch',
        _card(period: '6month', amount: 8000, method: 'baridimob'));
  });

  testWidgets('no period on the payload prints the old receipt', (t) async {
    await _shoot(t, 'zz_pending_term_none',
        _card(period: null, amount: 1500, method: 'cash'));
  });
}
