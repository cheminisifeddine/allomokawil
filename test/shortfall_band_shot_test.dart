// The shortfall band as a PICTURE, in the state the server audit measured.
//
// `notification_shortfall_test.dart` proves the band is *built* in that state.
// It cannot prove the band is *readable* — that the wash carries the ink and
// the ink carries the sentence. A band that drew as an empty blue bar passes
// every case in that file, and the user sees a stripe.
//
// So this renders the real screen through the real font and counts pixels, the
// way `stale_notifications_shot_test.dart` counts the amber band above it.
// The difference this shot exists for: the stale band is amber and the unread
// pip wears the same amber, so a reader learns «amber = something is wrong».
// THIS band is the neutral `infoWash`/`info` pair on purpose — nothing here is
// in doubt, the server stated a count. Two bands in one colour would read as
// one doubled warning.
//
// The load-bearing assertion is the ordering: the band must be a **header** on
// the rows, not a replacement for them. A count cannot tell those two apart;
// only pixels can, and that is the picture's whole job.
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
import 'package:allomokawil/src/data/notification_count_trust.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';

const _out = '/tmp/shots';

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  await (FontLoader('Cairo')..addFont(Future.value(reg))).load();
  await (FontLoader('Cairo')..addFont(Future.value(bold))).load();
}

void main() {
  testWidgets('the shortfall band carries its sentence and sits above the rows',
      (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 140 unread on the server, 100 rows drawn, EVERY visible row already read:
    // the measured production state, and the one where the single-field defect
    // suppressed the band entirely.
    final api = ApiClient(
      baseUrls: const ['https://api.test'],
      httpClient: MockClient((req) async {
        if (req.url.path == '/api/unread') {
          return http.Response(jsonEncode({'unread': 140}), 200,
              headers: const {'content-type': 'application/json'});
        }
        if (req.url.path == '/api/notifications') {
          return http.Response(
              jsonEncode([
                for (var i = 0; i < 8; i++)
                  {
                    'id': i + 1,
                    'type': 'new_quote',
                    'title': 'عنوان $i',
                    'body': 'نص',
                    'link': null,
                    'is_read': 1, // every drawn row already read
                    'created_at': '2026-10-10 09:00:00',
                  }
              ]),
              200,
              headers: const {'content-type': 'application/json'});
        }
        return http.Response('{}', 200,
            headers: const {'content-type': 'application/json'});
      }),
    );

    SharedPreferences.setMockInitialValues({
      'auth.token': 't',
      'auth.user': jsonEncode(const {
        'id': 7,
        'phone': '0550000000',
        'email': null,
        'full_name': 'Test User',
        'type': 'customer',
        'avatar_url': null,
        'wilaya': '16',
        'commune': null,
        'created_at': '2026-01-01 00:00:00',
      }),
    });
    final auth = AuthState(api);
    await auth.restore();

    await tester.runAsync(_loadFonts);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: AppScope(
        api: api,
        auth: auth,
        trust: NotificationCountTrust(),
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
          home: NotificationsScreen(repo: Repository(api)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // It is on screen at all, in the state the defect suppressed.
    expect(find.byKey(const Key('short-notifications')), findsOneWidget);

    // THE ORDERING. A count cannot distinguish "a header on the list" from
    // "a banner that ate the list"; pixels can, and this is the assertion the
    // shot exists to carry. `notification-1` is the first row, which must sit
    // BELOW the band and must not be overlapped by it.
    final bandTop =
        tester.getTopLeft(find.byKey(const Key('short-notifications'))).dy;
    final bandH =
        tester.getSize(find.byKey(const Key('short-notifications'))).height;
    final rowTop =
        tester.getTopLeft(find.byKey(const Key('notification-1'))).dy;
    expect(bandTop, lessThan(rowTop),
        reason: 'the band must be a header: above the rows, not over them');
    expect(bandTop + bandH, lessThanOrEqualTo(rowTop),
        reason: 'the band must not overlap the first row it annotates');

    // The rows are still there — a header does not consume them. Counted by
    // what the viewport actually built, NOT by the 8 the server sent:
    // `ListView` builds lazily, so a row below the fold is absent by design
    // and asserting it would be asserting the wrong thing. The first draft
    // pinned `notification-8` and failed for exactly this reason.
    //
    // The real claim is that MORE THAN ONE row is built and the band is not
    // one of them: a banner that replaced the list would leave 1.
    final built = [
      for (var i = 1; i <= 8; i++)
        if (find.byKey(Key('notification-$i')).evaluate().isNotEmpty) i
    ];
    expect(built.length, greaterThan(1),
        reason: 'the band left ${built.length} row(s) on screen — a header '
            'that consumed the list would leave one');
    expect(find.byKey(const Key('notification-1')), findsOneWidget);

    // THE PIXELS. Read in raw RGBA rather than from the written PNG, which is
    // what `stale_notifications_shot_test.dart` does and why it can count ink
    // at all -- a decoded PNG round-trip on this box loses what these counts
    // are looking for, and the first draft of this file trusted the written
    // file and read an all-white frame.
    //
    // Two facts, and they are the two the band could be wrong in:
    //
    //   * the wash is `infoWash` (**EAF2FB**) and NOT the amber **FDF3E3** the
    //     stale band wears. Two bands in one colour would read as one doubled
    //     warning, and amber already means "something is broken" on seven
    //     other screens;
    //   * ink sits INSIDE the wash. A band that drew as an empty blue stripe
    //     satisfies every geometry assertion above and shows the user nothing.
    final counts = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = data!.buffer.asUint8List();
      final stride = (boundary.size.width * 3.0).round();
      final total = (boundary.size.height * 3.0).round();
      int washFirst = -1, washLast = -1, inkInBand = 0, amber = 0;
      bool near(int o, int r, int g, int b, int tol) =>
          (rgba[o] - r).abs() <= tol &&
          (rgba[o + 1] - g).abs() <= tol &&
          (rgba[o + 2] - b).abs() <= tol;
      for (var y = 0; y < total; y++) {
        final rowStart = y * stride * 4;
        if (rowStart + stride * 4 > rgba.length) break;
        for (var x = 0; x < stride; x += 3) {
          final o = rowStart + x * 4;
          if (near(o, 0xEA, 0xF2, 0xFB, 4)) {
            if (washFirst < 0) washFirst = y;
            washLast = y;
          } else if (near(o, 0xFD, 0xF3, 0xE3, 4)) {
            amber++;
          }
          // Blue ink on the wash, inside the band only.
          if (washFirst >= 0 &&
              y >= washFirst &&
              y <= washLast + 8 &&
              near(o, 0x2C, 0x6F, 0xBB, 60)) {
            inkInBand++;
          }
        }
      }
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/22_notifications_shortfall_band.png')
          .writeAsBytesSync(png!.buffer.asUint8List());
      return (
        washFirst: washFirst,
        washLast: washLast,
        inkInBand: inkInBand,
        amber: amber,
      );
    });

    // The wash must actually be in the frame.
    expect(counts!.washFirst, greaterThanOrEqualTo(0),
        reason: 'the band wash was not found in the frame at all');
    // And the sentence must be on it.
    expect(counts.inkInBand, greaterThan(2000),
        reason: 'the band drew ${counts.inkInBand} ink pixels: a wash-coloured '
            'stripe with no sentence on it shows the user nothing, and every '
            'geometry assertion above would still pass');
    // THE NEUTRAL PAIR, not the amber the stale band already owns.
    //
    // Both banners are legitimately on screen here -- this fixture fails the
    // rows read as well as the count being short, so the stale band is a
    // second true fact -- which is why the claim cannot be "there is no amber".
    // It is **the two bands are different colours**: the shortfall band
    // carries `infoWash` ink and the stale one carries `accentWash`, and a
    // reader who sees them merge has been taught amber = one doubled warning.
    //
    // The first draft compared an amber PIXEL COUNT against a y-coordinate,
    // which is two different kinds of number and would have passed or failed
    // for no reason at all. Counting the amber wash proves it is present; the
    // washFirst/washLast span proves the shortfall band is a band of its own.
    expect(counts.amber, greaterThan(0),
        reason: 'the stale band should still be on screen in this fixture -- '
            'if it vanished, the fixture stopped being the measured state');
    expect(counts.washLast, greaterThan(counts.washFirst),
        reason: 'the shortfall band occupies no vertical span, so it is not '
            'rendered as a band at all');
  });
}
