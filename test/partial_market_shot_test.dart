// Rasterizes the stale-market band, because the step-5 rule is that a layout
// claim needs a picture and not an argument.
//
// Same path every other member of the failed-read family uses
// (`stale_home_strip_shot_test.dart`, `stale_projects_shot_test.dart`,
// `stale_directory_shot_test.dart`, `stale_inbox_shot_test.dart`,
// `stale_catalogue_shot_test.dart`, `stale_notifications_shot_test.dart`) and
// for the same reason: the real rasterizer with the real Cairo loaded through
// `FontLoader`, because a bare widget test draws Arabic as tofu and tofu still
// measures as "there is ink on screen". The web+CDP path needs a Chrome build
// this box does not have (`which chromium` -> nothing), so the capture is taken
// in-test instead of saying so and asserting nothing.
//
// **The measurement here is a y-ordering claim, like the notification centre's
// and unlike the five before it.** The band sits *above* a list of open
// projects, and those rows carry their own ink — a title, a specialty, a
// budget, a status pill. So a global ink count proves nothing: "there are dark
// pixels below the band" is true whether the band heads the list or replaced
// it. The only assertion that separates those two cases is that the wash ends
// *above* the first row:
//
//   * the wash is a band, not a sliver;
//   * dark ink sits inside the wash — the Arabic sentence, and a band that
//     drew as an empty amber bar passes every `find.byKey`;
//   * the first project row starts below the last wash row, so the band is a
//     header and not a page.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

const _out = '/tmp/shots';

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  await (FontLoader('Cairo')..addFont(Future.value(reg))).load();
  await (FontLoader('Cairo')..addFont(Future.value(bold))).load();
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );


Map<String, Object?> _project(String id, String title) => {
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': 'أعمال جافة',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'باب الوادي',
      'latitude': null,
      'longitude': null,
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

/// The band the amber wash occupies, and the ink on this screen.
///
/// Four numbers, each a different claim:
///
///   * `washFirst`/`washLast` — the band's own rows, found by their wash
///     (`accentWash` = FDF3E3).
///   * `darkInBand` — **dark pixels inside those rows**, the Arabic sentence.
///     Counting globally would be a mistake here: the contractor header and
///     the navy section title are dark-on-white and sit *above* the band, so a
///     global first-ink lands on the header and says nothing about the band.
///   * `inkLast` — the last dark row in the frame, which is the market's own
///     text *under* the band.
///
/// **[top, bottom] is the band's own box in the frame, and it is a parameter
/// for a reason that cost this file two runs.** The other six shots scan the
/// whole frame for the wash and take the first and last rows that match, which
/// is exact on their screens because the band is the *only* `accentWash`
/// widget in the picture. It is not exact here: this screen wears the same
/// wash in three other places — the **selected filter chip**
/// (`worker_home_screen.dart:1697`) and the **status pill on every project
/// card** (`project_card.dart:92`). A whole-frame scan therefore reported
/// `wash=216..2414` and a `darkInBand` of 45123, which is the band plus two
/// chips plus a pill, and `inkLast` landed *inside* the band so the
/// "something is drawn below the band" ordering assertion failed at 2391 < 2414.
///
/// The lesson is the transferable one and it generalises past this file: on a
/// screen that reuses the stale tone for ordinary UI, a **whole-frame colour
/// scan cannot measure the band at all**, no matter how the thresholds are
/// tuned. The band has to be located by its own geometry — the render box of
/// the widget under test — and the pixels counted inside it.
void main() {
  testWidgets('the partial-market band rasterizes above the rows it annotates',
      (tester) async {
    // The step-5 rule: a layout claim needs a picture. This band is new, and
    // the claim being made is the one the whole file's siblings make — that it
    // heads the results it annotates and is not a page in their place.
    await _loadFonts();
    SharedPreferences.setMockInitialValues(<String, Object>{});

    const lostPages = <int>{2, 4};
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/unread')) return _json(0);
        if (p.endsWith('/api/mobile/my/profile')) return _json(<String, Object?>{});
        final qp = req.url.queryParameters['page'];
        if (qp != null && qp != '1') {
          if (lostPages.contains(int.parse(qp))) {
            return http.Response('{"error":"boom"}', 500,
                headers: const {'content-type': 'application/json'});
          }
          return _json(<Object>[]);
        }
        return _json(<Object>[
          _project('p1', 'دهان شقة 3 غرف'),
          _project('p2', 'سباكة حمام'),
        ]);
      }),
    );
    final auth = AuthState(api);
    await auth.restore();

    tester.view.physicalSize = const Size(1176, 2550);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
      child: MaterialApp(
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
              body: MarketplaceView(repo: Repository(api), guest: true)),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));

    // Type a query that matches one row on the pages that answered, so the
    // frame carries BOTH the band and the results — the case that is easy to
    // get wrong and the one the band exists for.
    await tester.enterText(find.byType(TextField).first, 'دهان');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('partial-market')), findsOneWidget);
    expect(find.text('دهان شقة 3 غرف'), findsOneWidget);

    // Still a header, not a page: the band ends above the first result.
    expect(
        tester.getTopLeft(find.byKey(const Key('partial-market'))).dy +
            tester.getSize(find.byKey(const Key('partial-market'))).height,
        lessThanOrEqualTo(
            tester.getTopLeft(find.text('دهان شقة 3 غرف')).dy),
        reason: 'the band annotates the rows; it must not replace them');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/23_worker_market_partial.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(tester.takeException(), isNull);
  });
}
