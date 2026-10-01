// The project card's budget row, as pixels, with the real Cairo faces.
//
// Found 1 Oct 2026, alongside `budget_zero_label_test.dart`. That file pins the
// *string*; this one pins the fact that the string reaches the **card a
// contractor scrolls to pick a job** — `ProjectCard`, the widget the feed and
// the search results both draw. A label that is correct in a unit test and
// absent from the card is the failure the repo's own shot files exist for.
//
// Two shots, because the defect had two faces:
//
//   01 — `budget_min: 0, budget_max: 50000`, the row a client publishes by
//        typing `0` into the «من» box. Drawn before this fix as
//        «من 0 إلى 50000 دج».
//   02 — the control: a real band, so the capture proves the fix did not blank
//        the row it was meant to leave alone.
//
// The Arabic must be rendered by Cairo, or the capture is a row of identical
// empty boxes and proves nothing — the failure mode the 29 Sep renewal shot
// recorded.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/widgets/project_card.dart';

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  expect(reg.lengthInBytes, greaterThan(10000),
      reason: 'Cairo-Regular.ttf did not load from the asset bundle');
  final loader = FontLoader('Cairo')
    ..addFont(Future.value(reg))
    ..addFont(Future.value(bold));
  await loader.load();

  var root = Platform.environment['FLUTTER_ROOT'];
  root ??= File(Platform.resolvedExecutable)
      .parent
      .parent
      .parent
      .parent
      .parent
      .parent
      .path;
  final icons = File('$root/bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf');
  expect(icons.existsSync(), isTrue,
      reason: 'MaterialIcons-Regular.otf not found under $root');
  final iconBytes = icons.readAsBytesSync();
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(iconBytes.buffer))))
      .load();
}

Project _project(Object? min, Object? max) => Project.fromJson({
      'id': 'a1b2c3',
      'customer_id': 1,
      'title': min == 0 ? 'دهان شقة' : 'تركيز كهرباء',
      'category': min == 0 ? 'painting' : 'electricity',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'budget_min': min,
      'budget_max': max,
      'urgency': 'flexible',
      'status': 'open',
    });

Future<void> _shootCard(WidgetTester tester, String name, Project p) async {
  const logical = Size(392, 260);
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
    home: RepaintBoundary(
      key: key,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceAlt,
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: ProjectCard(project: p),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    File('/tmp/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  tester.takeException();
  FlutterError.onError = previous;
  expect(errors, isEmpty,
      reason: 'the card threw while drawing $name:\n'
          '${errors.map((e) => e.toString()).join('\n')}');
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('a zero floor is not printed as a price on the card',
      (tester) async {
    await _shootCard(tester, 'budget_zero_01_zero_floor', _project(0, 50000));
    expect(find.text('حتى 50000 دج'), findsOneWidget);
    // Exact match, never `find.textContaining('0 دج')`: the zero is a substring
    // of «50000 دج», so a substring assertion here would fail on the very
    // sentence this fix produces. The first test of this fix had exactly that
    // bug in the unit file, and it is recorded there rather than repeated.
    expect(find.text('من 0 إلى 50000 دج'), findsNothing);
    expect(find.text('0 دج'), findsNothing);
  });

  testWidgets('the real band beside it is untouched', (tester) async {
    await _shootCard(tester, 'budget_zero_02_real_band', _project(60000, 90000));
    expect(find.text('من 60000 إلى 90000 دج'), findsOneWidget);
  });
}
