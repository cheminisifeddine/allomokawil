// The price range on the browse card, with the pair the server really stored.
//
// The card is where a customer picks a tradesman, and the pair it is fed here
// is the one `PATCH /api/mobile/my/profile` produced on production this tick
// when a contractor filled in only the «من» box: `price_range_min: 7000,
// price_range_max: 7000`. That row used to render as «7000–7000 دج» — a band
// with equal ends, which is not a price range and not a string anyone writes.
//
// Run:  flutter test test/price_range_shot_test.dart   ->  /tmp/shots/
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/widgets/worker_card.dart';

const _outDir = '/tmp/shots';

/// Captured from `GET /api/mobile/my/profile` for worker `id 124` on
/// 28 Sep 2026, after the PATCH body `{"price_range_min":7000,
/// "price_range_max":null}`. The form sends `null` for an empty box; the
/// server answered by storing the max as the min too.
Map<String, dynamic> _collapsed() => {
      'id': 124,
      'user_id': 392,
      'full_name': 'حرفي 1200',
      'bio': null,
      'specialties': ['painting'],
      'experience_years': 5,
      'price_range_min': 7000,
      'price_range_max': 7000,
      'service_radius_km': 20,
      'is_available': 1,
      'is_identity_verified': 0,
      'is_certificate_verified': 0,
      'verification_status': 'pending',
      'avg_rating': 0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'response_time_hours': null,
      'cover_image_url': null,
      'avatar_url': null,
      'user_wilaya': '16',
    };

/// A real band, and the same contractor who typed a single maximum — the
/// second half of the defect: the card used to gate on `min != null` alone, so
/// this one had no price tag at all on the row he is chosen from.
Map<String, dynamic> _band() => {
      ..._collapsed(),
      'full_name': 'رشيد خليفي',
      'price_range_min': 7000,
      'price_range_max': 9000,
    };

Map<String, dynamic> _maxOnly() => {
      ..._collapsed(),
      'full_name': 'نبيل شريف',
      'price_range_min': null,
      'price_range_max': 9000,
    };

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
    {Size logical = const Size(392, 400)}) async {
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

  testWidgets('shot: the collapsed pair, and a real band above it',
      (tester) async {
    await _shoot(
      tester,
      'price_range_compare',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkerCard(
              worker: WorkerProfile.fromJson(_band()),
              variant: WorkerCardVariant.row,
            ),
          const SizedBox(height: 10),
          WorkerCard(
              worker: WorkerProfile.fromJson(_collapsed()),
              variant: WorkerCardVariant.row,
            ),
        ],
      ),
      logical: const Size(392, 520),
    );
  });

  testWidgets('shot: a contractor who typed only a maximum', (tester) async {
    await _shoot(
        tester,
        'price_range_max_only',
        WorkerCard(
          worker: WorkerProfile.fromJson(_maxOnly()),
          variant: WorkerCardVariant.row,
        ),
        logical: const Size(392, 300));
  });

  testWidgets('the collapsed card is not painted as a band with itself',
      (tester) async {
    // The proof that is not a screenshot: the string the card is built from.
    final card = WorkerCard(
        worker: WorkerProfile.fromJson(_collapsed()),
        variant: WorkerCardVariant.row,
      );
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: Scaffold(body: card),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('7000–7000'), findsNothing);
    expect(find.textContaining('7000-7000'), findsNothing);
    expect(find.textContaining('7000'), findsWidgets);
  });
}
