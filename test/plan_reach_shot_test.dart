import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/format/money.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/plan_reach_copy.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _outDir = '/tmp/shots';

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


/// One plan card, drawn the way `_PlanCard` draws it: name, tagline, price, the
/// computed discount hint, the new reach line, and the feature rows.
Widget _card(String id, String nameAr, String tagline, int month, int year,
    int span, {bool showReach = true}) {
  final plan = Plan.fromJson({
    'id': id,
    'name_ar': nameAr,
    'name_fr': id,
    'tagline_ar': tagline,
    'price_month': month,
    'price_year': year,
    'quote_limit': -1,
    'portfolio_limit': 60,
    'search_boost': 3,
    'wilaya_span': span,
    'features': const ['ترتيب متقدّم في نتائج البحث'],
  });
  const period = BillingPeriod.month;
  final reach = planReachLineAr(plan.wilayaSpan);
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
                Text(Money.dzd(plan.priceFor(period)), style: AppTheme.bar),
                Text('تدفع شهرياً',
                    style:
                        AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
              ],
            ),
          ],
        ),
        if (showReach && reach != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.travel_explore_rounded,
                  size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(reach,
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.textSecondary)),
              ),
            ],
          ),
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

void main() {
  setUpAll(_loadFonts);

  testWidgets('shot: «محترف», the plan the line was added for', (t) async {
    // `wilaya_span: 2` is the number the server prices this tier at and the app
    // used to print nowhere. The card is shot alone so every pixel below is
    // this one feature on the one screen a contractor reads it on.
    await _shoot(t, 'plan_reach_pro', _card(
        'pro', 'محترف', 'للمقاول الذي يعمل كل يوم', 3000, 30000, 2));
  });

  testWidgets('shot: «مؤسسة», the tier that was indistinguishable from it',
      (t) async {
    await _shoot(t, 'plan_reach_gold', _card(
        'gold', 'مؤسسة', 'للفرق التي تنمو', 6000, 60000, 3));
  });

  testWidgets('shot: «أساسي», the tier that reaches a single wilaya', (t) async {
    // The three live spans side by side, so the three sentences can be compared
    // as rendered text rather than as expected strings.
    await _shoot(t, 'plan_reach_basic', _card(
        'basic', 'أساسي', 'للمقاول المبتدئ', 1500, 15000, 1));
  });
}
