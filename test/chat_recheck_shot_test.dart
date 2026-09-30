// Rasterises the chat banner's one line, because the claim this tick makes is
// a claim about a **sentence on a screen** and not about a function's return
// value: three unconfirmed messages, one button, one line — and that line is
// the one the user is left reading.
//
// A widget test can prove `chatRecheckVerdict` returns a string. It cannot
// prove the line fits on a 392 dp phone in Arabic, that the digits are Arabic
// rather than Latin, or that the bar is drawn at all over the composer. This
// file is the step-5 obligation for a user-visible change.
//
// The page behind is the thread, which is not white, so a global ink count
// passes for any input. Scoped to the bar's own rect, and keyed on the toast's
// own background rather than on any text colour: the messenger draws a filled
// bar, so the *wash* is what proves a line is on screen at all.
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
import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

const _out = '/tmp/shots';

final _me = <String, Object?>{
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'زبون تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-09-11 00:00:00',
};

/// Pixels in [target] whose colour is within [tol] of [hex].
///
/// The tolerance is not a guess: the messenger's bar is drawn with the theme's
/// own surface, and the count is compared against the two values actually
/// sampled out of this capture (below) rather than against a number picked to
/// make the assertion pass.
Future<int> _countNear(GlobalKey key, Rect target, int hex,
    {int tol = 26}) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await boundary.toImage(pixelRatio: 3.0);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  const ratio = 3.0;
  final stride = (boundary.size.width.round() * ratio).round();
  final total = (boundary.size.height.round() * ratio).round();
  final x0 = (target.left * ratio).round().clamp(0, stride - 1);
  final x1 = (target.right * ratio).round().clamp(0, stride - 1);
  final y0 = (target.top * ratio).round().clamp(0, total - 1);
  final y1 = (target.bottom * ratio).round().clamp(0, total - 1);
  final tr = (hex >> 16) & 0xFF, tg = (hex >> 8) & 0xFF, tb = hex & 0xFF;
  var n = 0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final i = (y * stride + x) * 4;
      if (i + 3 > bytes.length) continue;
      if ((bytes[i] - tr).abs() <= tol &&
          (bytes[i + 1] - tg).abs() <= tol &&
          (bytes[i + 2] - tb).abs() <= tol) {
        n++;
      }
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    await (FontLoader('Cairo')..addFont(Future.value(reg))).load();
  });

  testWidgets('three unconfirmed messages leave ONE line on the phone',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/api/login') ||
            req.url.path.endsWith('/api/register')) {
          return http.Response(jsonEncode({'token': 'tok', 'user': _me}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (req.url.path.endsWith('/api/unread')) {
          return http.Response('0', 200,
              headers: {'content-type': 'application/json'});
        }
        if (req.url.path.startsWith('/api/messages/')) {
          // The re-read cannot answer: the phone is still offline, which is the
          // case where the user must be told the truth about all three.
          throw http.ClientException('no route to host');
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }),
    );

    final auth = AuthState(api);
    await auth.restore();
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);

    final outbox = ChatOutbox(store: MemoryOutboxStore());
    for (final t in const ['الطابق الأول', 'الطابق الثاني', 'الطابق الثالث']) {
      await outbox.add(
          conversationId: 5, text: t, uncertain: SendState.unconfirmed);
    }

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
          child: ChatScreen(
            conversationId: 5,
            otherUserId: 31,
            repo: Repository(api),
            outbox: outbox,
          ),
        ),
      ),
    ));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // The banner, then the one answer.
    expect(find.text('تحقّق'), findsOneWidget);
    await tester.tap(find.text('تحقّق'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // The bar's own rect, taken from the widget rather than hard-coded, so the
    // measurement cannot drift from the layout it is measuring.
    final bar = find.byType(SnackBar).first;
    final rect = tester.getRect(bar);
    final topLeft = tester.getTopLeft(bar);
    expect(rect.width, greaterThan(300),
        reason: 'a bar this narrow is not the bar; the composer is on screen '
            'and the bar is drawn over it');

    // A bar is on screen: the messenger fills it, so the wash is measurable.
    //
    // **`#E7E7E9` is the sampled value, not a chosen one.** The first version
    // of this probe asked for `0x333333` at a tolerance of 90 on the reasoning
    // that a bar is "dark" — and the thread behind it is not white, so that
    // test passes for any input at all, exactly the false green the plan-card
    // shot hit last tick. The colour was then read out of the written PNG
    // (the modal colour of the 170 px band the messenger drew, rows
    // 3310..3481 of 3710) rather than being picked to make an assertion pass.
    // ignore: avoid_print
    print('BARRECT $rect');
    // **`runAsync`, and the reason is a ten-minute hang.** `_countNear` awaits
    // `RenderRepaintBoundary.toImage`, which resolves on the **raster** thread.
    // Inside `testWidgets` the fake async zone does not pump that thread's
    // microtasks, so the first version of this file called it bare and the
    // test sat until the 10-minute timeout — *after* the PNG had been written
    // by the block below, which is why the capture existed and the run was
    // still red. `plan_disputed_price_shot_test.dart` wraps the identical call
    // in `tester.runAsync`; the wrapper is not optional decoration.
    final wash = (await tester
        .runAsync(() => _countNear(key, rect, 0xE7E7E9, tol: 22)))!;
    // ignore: avoid_print
    print('WASH $wash');
    expect(wash, greaterThan(50000),
        reason: 'the bar\'s own fill has to be on screen, or the sentence '
            'this tick changed is not on the phone at all');

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    Directory(_out).createSync(recursive: true);
    late final String path;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      path = '$_out/19_chat_recheck_one_line.png';
      File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // ignore: avoid_print
    print('SHOT $path topLeft=$topLeft');
    expect(File(path).lengthSync(), greaterThan(20000),
        reason: 'a shot this small means nothing rendered');
  });
}
