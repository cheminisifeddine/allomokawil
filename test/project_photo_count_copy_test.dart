// The photo counter under the attach strip on the publish screen.
//
// Found on 26 Sep 2026 while auditing what the quote-duration fix left. Same
// vein, sixth cycle down: a count is either delegated to `arabicCounted` or
// spelled out by hand, and every hand-written one so far has been wrong.
//
// The strip built its line out of string interpolation and two fixed words:
//
//     '${images.length} صورة مضافة'
//
// That is **two agreements in one line**, and the old text got both wrong on the
// second photo — which is the second photo a client ever attaches, on the first
// screen a real project is published from:
//
//   * the noun — «صورة» is the singular, wrong for the dual and for 3-10. The
//     same trap `photo_count_copy.dart` already documents and already gets right
//     on the contractor's portfolio, so the app knew the rule and did not use it
//     here;
//   * the adjective — «مضافة» is feminine singular, so a feminine dual noun drags
//     the adjective to feminine dual with it («مضافتان»). The old line printed
//     «2 صورة مضافة»: a singular noun, with a number the dual does not take,
//     under a singular adjective that cannot modify either.
//
// The counts are read off the **real screen**, driven through the **real
// method channel** the plugin uses, because "a client attaching his second photo
// reads «2 صورة مضافة»" is a claim about pixels on a rendered screen, not about
// a function's return value — and a copy function can be correct while the strip
// still prints the old string.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/photo_count_copy.dart';
import 'package:allomokawil/src/data/project_photo_count_copy.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';

/// The channel `image_picker`'s Android/iOS implementation actually calls. The
/// platform interface is a *transitive* dependency, so importing it here would
/// trip `depend_on_referenced_packages`; the channel name is the stable contract
/// instead, and driving it exercises the production path rather than a fake.
const MethodChannel _picker = MethodChannel('plugins.flutter.io/image_picker');

/// A real 1x1 PNG on disk, so `Image.file` has something to decode.
String _onePixelPng(String name) {
  final dir = Directory.systemTemp.createTempSync('am_photos');
  final f = File('${dir.path}/$name.png');
  f.writeAsBytesSync(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, //
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
  return f.path;
}

Future<({ApiClient api, AuthState auth})> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path == '/api/unread') {
        return http.Response(jsonEncode(0), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(<Object>[]), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  return (api: api, auth: auth);
}

/// Mounts the real publish screen, taps the real add tile, and returns every
/// string it printed.
///
/// [n] photos are handed back by the picker on the first tap, exactly as the
/// gallery would. The tap goes through the widget tree rather than through a
/// key, so a strip that stops being tappable fails here instead of passing.
Future<List<String>> attachN(WidgetTester tester, int n) async {
  final boot = await _boot();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_picker, (call) async {
    if (call.method == 'pickMultiImage') {
      return <String>[for (var i = 0; i < n; i++) _onePixelPng('p$i')];
    }
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_picker, null));

  tester.view.physicalSize = const Size(392, 850) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(AppScope(
    api: boot.api,
    auth: boot.auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: const ProjectNewScreen(),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Reveal the attach strip — it is step 7 of 7, below the fold on a real phone.
  await tester.scrollUntilVisible(find.text('صور المشروع'), 240,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();

  // The add tile is the only tappable thing in the strip that is not a remove
  // button, and it carries this exact label.
  final addTile = find.ancestor(
    of: find.text('أضف صورة'),
    matching: find.byType(InkWell),
  );
  expect(addTile, findsWidgets, reason: 'the add tile did not render');
  await tester.tap(addTile.first);
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
  // Guard the guard: a strip that never rendered would make every negative
  // assertion below pass for the wrong reason.
  expect(texts, isNotEmpty, reason: 'the publish screen rendered no text');
  return texts;
}

void main() {
  group('the two agreements in one line', () {
    test('1 / 2 / 3-10 / 11+ take the noun AND the adjective together', () {
      expect(addedPhotosLineAr(1), 'صورة مضافة');
      expect(addedPhotosLineAr(2), 'صورتان مضافتان');
      expect(addedPhotosLineAr(3), '3 صور مضافة');
      expect(addedPhotosLineAr(10), '10 صور مضافة');
      expect(addedPhotosLineAr(11), '11 صورة مضافة');
    });

    test('the dual drags the adjective with it', () {
      // The line the old code printed for the second photo, stated as the bug.
      expect(addedPhotosLineAr(2), isNot('2 صورة مضافة'));
      expect(addedAdjectiveAr(2), 'مضافتان');
    });

    test('the noun is the one the portfolio already prints', () {
      for (final n in [1, 2, 3, 5, 10, 11]) {
        expect(addedPhotosLineAr(n), contains(photosAr(n)),
            reason: '$n photos must not drift from the portfolio wording');
      }
    });

    test('zero is silence, never «0 صور مضافة»', () {
      expect(addedPhotosLineAr(0), '');
      expect(addedAdjectiveAr(0), '');
    });
  });

  group('on the screen a client actually publishes from', () {
    testWidgets('the second photo reads «صورتان مضافتان»', (tester) async {
      final texts = await attachN(tester, 2);
      expect(texts, contains('صورتان مضافتان'), reason: '$texts');
      // The old line, in full.
      expect(texts.any((t) => t.contains('2 صورة مضافة')), isFalse,
          reason: '$texts');
      // And the singular adjective never modifies a dual noun.
      expect(texts.any((t) => t.contains('صورتان مضافة')), isFalse,
          reason: '$texts');
    });

    testWidgets('the first photo keeps the bare singular', (tester) async {
      final texts = await attachN(tester, 1);
      expect(texts, contains('صورة مضافة'), reason: '$texts');
    });

    testWidgets('a batch of five reads «5 صور مضافة»', (tester) async {
      final texts = await attachN(tester, 5);
      expect(texts, contains('5 صور مضافة'), reason: '$texts');
      expect(texts.any((t) => t.contains('5 صورة مضافة')), isFalse,
          reason: '$texts');
    });

    testWidgets('an empty strip keeps its own copy and prints no count',
        (tester) async {
      final boot = await _boot();
      tester.view.physicalSize = const Size(392, 850) * 2.75;
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(
        api: boot.api,
        auth: boot.auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: const ProjectNewScreen(),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(texts, contains('أضف صوراً لعملك — الصور الجيدة تجلب عروضاً أكثر'),
          reason: '$texts');
      expect(texts.any((t) => t.contains('مضافة')), isFalse, reason: '$texts');
    });
  });
}
