// Renders the browse card with and without a score, so the «0.0» fix is
// looked at rather than asserted about. Real Cairo faces, real widget tree.
// Run:  flutter test test/zero_score_shot_test.dart   ->  /tmp/shots/
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

/// Shape taken from the live `/api/mobile/workers/search` payload for a
/// contractor nobody has worked with yet (id 73, checked 26 Sep 2026).
Map<String, dynamic> _unrated() => {
      'id': 73,
      'user_id': 316,
      'full_name': 'مقاول جديد',
      'bio': null,
      'specialties': ['painting'],
      'experience_years': 6,
      'price_range_min': null,
      'price_range_max': null,
      'service_radius_km': 30,
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

Map<String, dynamic> _rated() => {
      ..._unrated(),
      'full_name': 'رشيد خليفي',
      'verification_status': 'verified',
      'is_identity_verified': 1,
      'is_certificate_verified': 1,
      'avg_rating': 4.7,
      'total_reviews': 30,
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

  testWidgets('shot: an unrated contractor on the browse row', (tester) async {
    await _shoot(tester, 'rating_unrated_row',
        WorkerCard(worker: WorkerProfile.fromJson(_unrated())));
  });

  testWidgets('shot: the same card with a real score', (tester) async {
    await _shoot(tester, 'rating_rated_row',
        WorkerCard(worker: WorkerProfile.fromJson(_rated())));
  });

  testWidgets('shot: the vertical strip card, unrated vs rated', (tester) async {
    await _shoot(
        tester,
        'rating_strip_compare',
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 176,
                child: WorkerCard(
                    worker: WorkerProfile.fromJson(_unrated()),
                    variant: WorkerCardVariant.vertical)),
            const SizedBox(width: 12),
            SizedBox(
                width: 176,
                child: WorkerCard(
                    worker: WorkerProfile.fromJson(_rated()),
                    variant: WorkerCardVariant.vertical)),
          ],
        ));
  });
}
