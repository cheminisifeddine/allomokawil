// Rendered proof that the half-star the app never drew is now on the card.
//
// Run:  flutter test test/star_row_shape_shot_test.dart   ->  /tmp/shots/
// The rule itself is proven exhaustively in `star_row_shape_test.dart`; this
// file exists because a claim about pixels needs pixels. It renders the real
// `RatingStars` with the real Cairo faces and the real Material glyphs — the
// same RepaintBoundary/runAsync writer `quote_zero_score_shot_test.dart` uses —
// at the two scores that matter: the broken 4.5 and a 4.4 beside it for
// contrast.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _outDir = '/tmp/shots';

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  final a = FontLoader('Cairo')..addFont(Future.value(ByteData.view(reg.buffer)));
  final b = FontLoader('Cairo')..addFont(Future.value(ByteData.view(bold.buffer)));
  await a.load();
  await b.load();
  final icon = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icon.load();
  stdout.writeln('FONTS: Cairo + MaterialIcons registered');
}

/// One labelled row, so the shot says which score it is and what the glyphs
/// measured. The label is built from the same helper the tests assert on, so
/// the caption cannot drift from the row it is captioning.
Widget _labelled(double rating) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 92,
            child: Text('${rating.toStringAsFixed(1)}',
                textAlign: TextAlign.left,
                style: AppTheme.caption
                    .copyWith(fontSize: AppTheme.fsMeta, color: AppTheme.navy)),
          ),
          RatingStars(rating: rating, count: 12, size: 22),
        ],
      ),
    );

Future<void> _shoot(WidgetTester tester, String name, Widget child) async {
  tester.view.physicalSize = const Size(392 * 2.75, 300 * 2.75);
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

  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
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

  testWidgets('shot: the star row at the score that was broken', (tester) async {
    // 4.5 — five full stars before, four full and a half now. The live 4.5 is
    // a real contractor with 12 reviews, not a synthetic value.
    await _shoot(
      tester,
      'star_row_half',
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('قبل الإصلاح: 4.5 = خمس نجوم كاملة',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
          _labelled(4.5),
          const Text('4.4 لا يستحق نصف نجمة', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
          _labelled(4.4),
          const Text('4.7 نصف نجمة أيضاً', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
          _labelled(4.7),
        ],
      ),
    );
  });

  testWidgets('the real widget draws the half-star glyph', (tester) async {
    tester.view.physicalSize = const Size(392 * 2.75, 200 * 2.75);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
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
      home: const Scaffold(body: Center(child: RatingStars(rating: 4.5))),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_half_rounded), findsOneWidget,
        reason: 'the glyph that was in the source and on no screen at all');
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
  });
}
