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
import 'package:allomokawil/src/data/price_range_copy.dart';
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

/// `experience_years: 0` on purpose, and it was the bug in this fixture.
///
/// This map inherited `5` from [_collapsed], which kept the outer gate's
/// `experienceYears > 0` arm true — so the tag appeared for the WRONG REASON.
/// The screenshot the founder was shown for this defect proved nothing: it
/// would have rendered identically with the price gate deleted. A brand-new
/// free contractor is the worse case and the more common one (nobody has
/// years on the day they register), and he is exactly the man with nothing but
/// a maximum typed, so he is what the fixture now carries.
Map<String, dynamic> _maxOnly() => {
      ..._collapsed(),
      'full_name': 'نبيل شريف',
      'experience_years': 0,
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

  testWidgets('a max-only contractor with no years still shows his price',
      (tester) async {
    // The regression, and it is the whole defect: the outer gate decided
    // whether this tag row was built at all, and it asked
    // `years > 0 || min != null`. With `min` empty and no years, it said no,
    // so a real, current, typed price was nowhere on the browse card — while
    // the profile page, gated the other way, showed it. Two surfaces of one
    // man, disagreeing, for a day.
    final card = WorkerCard(
        worker: WorkerProfile.fromJson(_maxOnly()),
        variant: WorkerCardVariant.row,
      );
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: Scaffold(body: card),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('9000'), findsOneWidget,
        reason: 'a typed maximum must be on the row he is chosen from');
    // And the gate is not merely true by accident of the years arm: the
    // fixture has none, which is asserted here rather than in a comment.
    final w = WorkerProfile.fromJson(_maxOnly());
    expect(w.experienceYears, 0);
    expect(hasPriceRange(w.priceRangeMin, w.priceRangeMax), isTrue);
    expect(find.textContaining('سنوات خبرة'), findsNothing);
  });

  testWidgets('a contractor with neither a price nor years has no tag row',
      (tester) async {
    // The other direction, and the reason the gate is not simply `true`: an
    // empty Wrap is a hole with padding in it. Zero on both price columns is
    // reachable from our own form (see price_range_zero_test.dart), so this
    // row must come out clean rather than holding an 8px gap.
    final empty = {
      ..._maxOnly(),
      'full_name': 'مقاول جديد',
      'price_range_min': 0,
      'price_range_max': 0,
    };
    final card = WorkerCard(
        worker: WorkerProfile.fromJson(empty),
        variant: WorkerCardVariant.row,
      );
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: Scaffold(body: card),
    ));
    await tester.pumpAndSettle();
    // No money on the row at all: not the tag, not the number, not the unit.
    expect(find.textContaining('9000'), findsNothing);
    expect(find.textContaining('دج'), findsNothing);
    expect(find.textContaining('خبرة'), findsNothing);
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
