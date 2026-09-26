// Renders the pricing card on the yearly arm, so the computed discount
// sentence is *looked at* rather than asserted about: a plan priced at ten
// months (the live shape), a plan priced at eleven (the case the old
// hand-written constant got wrong), and a year that is not a whole number of
// months (the case that must print nothing at all).
// Run:  flutter test test/plan_yearly_hint_shot_test.dart   ->  /tmp/shots/
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/format/money.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/plan_renewal_copy.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _outDir = '/tmp/shots';

/// The live `/api/mobile/subscription` plan shape with the two prices the
/// case is about, so nothing else in the card has to be re-invented.
Plan _plan(int month, int year) => Plan.fromJson({
      'id': 'pro',
      'name_ar': 'محترف',
      'name_fr': 'Pro',
      'tagline_ar': 'للمقاول الذي يعمل كل يوم',
      'price_month': month,
      'price_year': year,
      'quote_limit': -1,
      'portfolio_limit': 60,
      'search_boost': 3,
      'wilaya_span': 2,
      'features': const ['ترتيب متقدّم في نتائج البحث'],
    });

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  final a = FontLoader('Cairo')
    ..addFont(Future.value(ByteData.view(reg.buffer)));
  final b = FontLoader('Cairo')
    ..addFont(Future.value(ByteData.view(bold.buffer)));
  await a.load();
  await b.load();
  final icon = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icon.load();
  stdout.writeln('FONTS: Cairo family registered');
}

/// The plan card exactly as `_PlanCard` draws it on the yearly arm: price,
/// the "you save" line, the computed term hint, and one feature row.
Widget _card(int month, int year) {
  final plan = _plan(month, year);
  const period = BillingPeriod.year;
  final hint = yearlyTermHintAr(plan);
  final saving = plan.savingFor(period);
  return AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.nameAr, style: AppTheme.h2),
                  if (plan.taglineAr != null && plan.taglineAr!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(plan.taglineAr!,
                        style: AppTheme.caption
                            .copyWith(color: AppTheme.textSecondary)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Money.dzd(plan.priceFor(period)),
                    style: AppTheme.bar),
                Text('تدفع سنوياً',
                    style:
                        AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
              ],
            ),
          ],
        ),
        if (saving > 0) ...[
          const SizedBox(height: 8),
          Text('توفّر ${Money.dzd(saving)} في السنة',
              style: AppTheme.caption.copyWith(
                  color: AppTheme.success, fontWeight: FontWeight.w700)),
        ],
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint,
              key: const Key('hint'),
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
        ],
        const SizedBox(height: 16),
        for (final feature in plan.features)
          Row(
            children: [
              const Icon(Icons.check_rounded, size: 16, color: AppTheme.success),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(feature,
                      style: AppTheme.caption
                          .copyWith(color: AppTheme.textSecondary))),
            ],
          ),
      ],
    ),
  );
}

Future<void> _shoot(WidgetTester tester, String name, Widget child,
    {Size logical = const Size(392, 300)}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;

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
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  tester.takeException();
  FlutterError.onError = previous;
  if (errors.isNotEmpty) {
    File('$_outDir/$name.ERROR.txt')
        .writeAsStringSync(errors.map((e) => e.toString()).join('\n'));
    fail('$name threw during layout — see $_outDir/$name.ERROR.txt');
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('shot: ten months (live) vs eleven (the old constant)', (t) async {
    await _shoot(
      t,
      'plan_yearly_hint_ten_vs_eleven',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(3000, 30000),
          const SizedBox(height: 12),
          _card(3000, 33000),
        ],
      ),
      logical: const Size(392, 420),
    );
  });

  testWidgets('shot: a 10.5-month year prints no discount at all', (t) async {
    // The line the old constant would have filled in with «ten months».
    await _shoot(t, 'plan_yearly_hint_fractional', _card(2000, 21000));
  });
}
