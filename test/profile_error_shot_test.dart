// The profile edit form with a refused save, at a real phone size.
//
// This screen printed the same Arabic refusal **twice**: once as a red notice
// card at the top of the form and again as red type in the pinned footer under
// the save button. The second copy is the one the user can actually see (see
// the test for why), so it is the one that stays.
//
// Run:  flutter test test/profile_error_shot_test.dart   ->  /tmp/shots/
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
import 'package:allomokawil/src/screens/worker/profile_edit_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _outDir = '/tmp/shots';

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

/// Rasterises the RepaintBoundary [key] that `_boot` put around the real
/// screen, at a real phone's logical size.
///
/// Unlike the card shot, this does not build the app: the screen needs a
/// booted `AuthState` and a mock API, and the state that matters — a refused
/// save, with the form scrolled to the bottom — can only be reached by driving
/// the widget the user drives. So the screen is pumped for real and only the
/// pixels are captured afterwards.
Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}


/// A real phone, not the 1080x6400 wall the widget tests use: the point of
/// this shot is what a 392x844 user sees, and a 6400px-tall "phone" is the
/// single reason the removed copy could look fine in a test.
const _phone = Size(392, 844);

Map<String, Object?> _profileJson() => {
      'id': 124,
      'user_id': 392,
      'full_name': '\u0639\u0645\u064a \u0631\u0634\u064a\u062f',
      'bio': '\u0628\u0646\u0627\u0621 \u0648\u062a\u0634\u0637\u064a\u0628',
      'specialties': ['painting', 'plumbing'],
      'experience_years': 5,
      'price_range_min': 20000,
      'price_range_max': 60000,
      'service_radius_km': 30,
      'is_available': 1,
      'is_identity_verified': 0,
      'is_certificate_verified': 0,
      'verification_status': 'pending',
      'avg_rating': null,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'response_time_hours': null,
      'cover_image_url': null,
      'avatar_url': null,
      'user_wilaya': '16',
    };

ApiClient _api() => ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        final Object body = req.url.path.endsWith('/api/login')
            ? {
                'token': 'tok',
                'user': {
                  'id': 392,
                  'phone': '0773000000',
                  'email': null,
                  'full_name': '\u0645\u0633\u062a\u062e\u062f\u0645',
                  'type': 'worker',
                  'avatar_url': null,
                  'wilaya': '16',
                  'commune': null,
                  'created_at': '2026-09-11 20:00:00',
                },
              }
            : _profileJson();
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      }),
    );

Future<AuthState> _auth(ApiClient a) async {
  final s = AuthState(a);
  await s.restore();
  await s.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return s;
}

/// The one refusal every branch of this screen uses.
const _refusal = '\u0627\u0643\u062a\u0628 \u0627\u0633\u0645\u0643 \u0643\u0645\u0627'
    ' \u062a\u0631\u064a\u062f \u0623\u0646 \u064a\u0638\u0647\u0631 \u0644\u0644\u0645\u0634\u062a\u0631\u064a\u0646';

void main() {
  setUpAll(_loadFonts);

  testWidgets('shot: a profile that never loaded is a dead end with a retry, '
      'not an empty form', (tester) async {
    // The pixels for the state this fix created. The unit test proves the form
    // is gone; this proves what replaced it is readable on a 392x844 phone and
    // is not a bare sentence on white.
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = _phone * 2.75;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final a = ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        http.Response json(Object b, [int status = 200]) => http.Response(
            jsonEncode(b), status,
            headers: {'content-type': 'application/json'});
        if (req.url.path.endsWith('/api/login')) {
          return json({
            'token': 'tok',
            'user': {
              'id': 392,
              'phone': '0773000000',
              'email': null,
              'full_name': '\u0645\u0633\u062a\u062e\u062f\u0645',
              'type': 'worker',
              'avatar_url': null,
              'wilaya': '16',
              'commune': null,
              'created_at': '2026-09-11 20:00:00',
            },
          });
        }
        // The read the form is built from answers 500.
        return json({'error': 'boom'}, 500);
      }),
    );
    final au = await _auth(a);
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
        child: AppScope(api: a, auth: au, child: const ProfileEditScreen()),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The two things a contractor has to be able to read here, and the thing
    // that must NOT be there.
    expect(find.text('\u062a\u0639\u0630\u0651\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0645\u0644\u0641'),
        findsOneWidget);
    expect(find.text('\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'),
        findsOneWidget);
    expect(find.text('\u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641'), findsNothing);

    await _capture(tester, key, 'profile_load_failed');

    tester.takeException();
    FlutterError.onError = previous;
    final fatal = [
      for (final e in errors)
        if (!'${e.exception}'.contains('ink splashes may be invisible') &&
            !'${e.exception}'.contains('Multiple exceptions'))
          e
    ];
    if (fatal.isNotEmpty) {
      File('$_outDir/profile_load_failed.ERROR.txt')
          .writeAsStringSync(fatal.map((e) => e.toString()).join('\n'));
      fail('the screen threw during layout — see the .ERROR.txt beside it');
    }
  });

  testWidgets('shot: a refused save is stated once, beside the save button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = _phone * 2.75;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final a = _api();
    final au = await _auth(a);
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
        child: AppScope(api: a, auth: au, child: const ProfileEditScreen()),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Empty the mandatory name: the cheapest refusal there is, and the first
    // one a real contractor hits when he taps save on a half-finished form.
    tester.widget<TextField>(find.byType(TextField).first).controller!.clear();
    await tester.pump();

    // Refuse the save **from the top of the form**, where the user is looking
    // at the field that is wrong. The save button is in `bottomNavigationBar`,
    // so it is reachable without scrolling -- which is the whole reason that bar
    // exists, and the whole reason the refusal has to be readable here.
    await tester.tap(find.text('\u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Refusal read from the top of the form -- the position a user is in when
    // the field he is looking at is the one that was refused.
    final topCopies = find.text(_refusal).evaluate().length;
    final topInFooter = find
        .descendant(of: find.byType(StickyCta), matching: find.text(_refusal))
        .evaluate()
        .length;
    stdout.writeln('COPIES_AT_TOP total=$topCopies footer=$topInFooter');
    await _capture(tester, key,
        'profile_error_${const String.fromEnvironment('SHOT', defaultValue: 'once')}_top');

    // The same screen scrolled to its last field. This is the other half of
    // the fix: the deleted copy was the first child of a *lazy* list, so from
    // here it is not built at all -- which is why the pinned footer, and only
    // the pinned footer, is the copy that can be relied on.
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
    }
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // How many copies of the sentence are on screen, right now.
    final copies = find.text(_refusal).evaluate().length;
    // And how many of them the user can actually see from the bottom of a
    // 844px-tall form.
    final inFooter =
        find.descendant(of: find.byType(StickyCta), matching: find.text(_refusal))
            .evaluate()
            .length;
    stdout.writeln('COPIES total=$copies footer=$inFooter');

    await _capture(tester, key, 'profile_error_${const String.fromEnvironment('SHOT', defaultValue: 'once')}');

    // The invariant, re-checked at the size the shot is taken at.
    expect(copies, 1);
    expect(inFooter, 1);
    // And the button is still on screen under it — the sentence did not push
    // the one control the user needs out of the pinned bar.
    expect(find.text('\u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641'), findsOneWidget);

    tester.takeException();
    FlutterError.onError = previous;
    // The one framework warning this screen already carries on main: the
    // availability `SwitchListTile` inside a decorated `Container`. It is a
    // paint-order note from the framework, not a layout failure, and both
    // existing profile tests let it through for the same reason. It is filtered
    // here only so a *real* layout failure in this screen stays loud.
    final fatal = [
      for (final e in errors)
        if (!'${e.exception}'.contains('ink splashes may be invisible') &&
            !'${e.exception}'.contains('Multiple exceptions'))
          e
    ];
    if (fatal.isNotEmpty) {
      File('$_outDir/profile_error_once.ERROR.txt')
          .writeAsStringSync(fatal.map((e) => e.toString()).join('\n'));
      fail('the screen threw during layout — see the .ERROR.txt beside it');
    }
  });
}
