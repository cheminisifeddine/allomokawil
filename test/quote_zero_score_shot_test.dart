// Renders the bid card with and without a score, so the quote-side «0.0» fix
// is looked at rather than asserted about. Real Cairo faces, real widget tree.
// Run:  flutter test test/quote_zero_score_shot_test.dart   ->  /tmp/shots/
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/worker_stats_copy.dart';
import 'package:allomokawil/src/models/quote_review.dart';
import 'package:allomokawil/src/widgets/quote_worker_trust.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _outDir = '/tmp/shots';

const _projectId = 'b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551';

/// Straight off `GET /api/mobile/projects/{id}/quotes` for a contractor nobody
/// has worked with yet — the same `worker_avg_rating: 0` sentinel the browse
/// card was fixed for last cycle.
Map<String, dynamic> _unrated() => <String, dynamic>{
      'id': 13,
      'project_id': _projectId,
      'worker_id': 16,
      'amount': 75000,
      'message': 'جاهز للبدء فوراً',
      'estimated_days': 5,
      'status': 'pending',
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
      'worker_full_name': 'مقاول جديد',
      'worker_avatar_url': null,
      'worker_avg_rating': 0,
      'worker_total_reviews': 0,
      'worker_verification_status': 'pending',
    };

Map<String, dynamic> _rated() => <String, dynamic>{
      ..._unrated(),
      'worker_full_name': 'رشيد خليفي',
      'worker_avg_rating': 4.7,
      'worker_total_reviews': 30,
      'worker_verification_status': 'verified',
    };

/// The payload the old `workerTotalReviews > 0` guard got wrong: the count says
/// he has reviews, the score is absent. It used to print five empty stars and
/// «0.0» for a tradesman somebody did rate.
Map<String, dynamic> _countOnly() => <String, dynamic>{
      ..._unrated(),
      'worker_full_name': 'مقاول مُقيَّم',
      'worker_total_reviews': 7,
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

/// The name, photo, verification badge and the score row exactly as
/// `_QuoteCard` draws them, so the shot shows the pixels a customer reads and
/// not a reconstruction of them. The accept button is left out: it is the same
/// on every card and would only push the score row out of the frame.
Widget _card(Map<String, dynamic> json) {
  final q = Quote.fromJson(json);
  return AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            QuoteWorkerTrust(quote: q, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.workerFullName,
                      style: AppTheme.h2.copyWith(fontSize: AppTheme.fsLead),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (q.hasRating)
                    RatingStars(
                        rating: q.workerAvgRating!,
                        count: q.workerTotalReviews,
                        size: 14)
                  else
                    Text(noRatingAr(),
                        style: AppTheme.caption
                            .copyWith(color: AppTheme.textSecondary)),
                ],
              ),
            ),
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

  testWidgets('shot: the bid card, unrated vs rated', (tester) async {
    await _shoot(
        tester,
        'quote_rating_compare',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _card(_unrated()),
            const SizedBox(height: 12),
            _card(_rated()),
          ],
        ),
        logical: const Size(392, 300),
    );
  });

  testWidgets('shot: the payload the old guard got wrong', (tester) async {
    // 7 reviews, no score. This is the card the old count-check printed «0.0»
    // on; the fix must draw the honest sentence here as well.
    await _shoot(tester, 'quote_rating_count_only', _card(_countOnly()));
  });
}
