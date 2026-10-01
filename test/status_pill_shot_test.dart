// Renders the four project status pills with the real Cairo and the real
// MaterialIcons face, and writes them to /tmp/shots so the fix can be looked
// at rather than argued about.
//
// The defect this file came from was invisible in three ways at once: the word
// was wrong, the tint was wrong, and both were wrong *in the direction of
// looking normal* — «مفتوح» in amber is a perfectly ordinary pill. A unit test
// proves the label; only the raster proves the pill a contractor actually
// reads. Not a golden on purpose: this is a look-at-it artefact for this tick,
// and pinning it would freeze the design rather than the rule.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/project_status_copy.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _outDir = '/tmp/shots';

void main() {
  testWidgets('the four project status pills, side by side',
      (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(392, 260);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('ar'),
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: RepaintBoundary(
          key: key,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final status in ProjectStatus.values)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StatusPill.project(status),
                  ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_outDir).createSync(recursive: true);
      File('$_outDir/project_status_pills.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    // Each pill really did draw its shared word, read back off the tree.
    for (final status in ProjectStatus.values) {
      expect(find.text(projectStatusAr(status)), findsOneWidget);
    }
  });
}
