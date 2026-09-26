// The cap on how many photos one project may carry.
//
// Found on 26 Sep 2026 while auditing the attach-strip count that shipped the
// previous cycle. The count was right. The cap behind it was not, and it was
// wrong in a way the count's own comment had asserted the opposite of:
//
//     pickMultiImage(limit: 6)      // a limit on ONE selection
//     if (images.length < 6)        // a test of the NEW picks only
//
// Neither one bounds the project. Pick 5, tap add again, pick 6 → eleven photos,
// and on the edit path the tile never saw the photos the project already had, so
// a project with six kept photos still offered «أضف صورة» to the client editing
// it. The previous cycle's shipped comment called the 11+ grammar arm
// "unreachable from this screen today". It was reachable, and this test is the
// reason the next person does not have to re-derive that by reading a build
// method.
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
import 'package:allomokawil/src/data/project_photo_limit.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';

const MethodChannel _picker = MethodChannel('plugins.flutter.io/image_picker');

String _onePixelPng(String name) {
  final dir = Directory.systemTemp.createTempSync('am_cap');
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
    httpClient: MockClient((req) async => http.Response(
          jsonEncode(<Object>[]),
          200,
          headers: {'content-type': 'application/json'},
        )),
  );
  final auth = AuthState(api);
  await auth.restore();
  return (api: api, auth: auth);
}

Project _projectWith(int photos) => Project(
      id: 'p1',
      customerId: 1,
      title: 'توسعة kitchen',
      category: 'plumbing',
      wilaya: '16',
      status: ProjectStatus.open,
      urgency: UrgencyLevel.flexible,
      images: [for (var i = 0; i < photos; i++) 'https://x/$i.jpg'],
    );

/// Mounts the real publish screen in **edit** mode over a project that already
/// has [kept] photos, and returns the record of every pick the screen made.
Future<({int picks, List<int?> limits, List<String> texts})> editAndPick(
  WidgetTester tester, {
  required int kept,
  required List<int> batches,
}) async {
  final boot = await _boot();
  final limits = <int?>[];
  var pick = 0;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_picker, (call) async {
    if (call.method == 'pickMultiImage') {
      limits.add((call.arguments as Map?)?['limit'] as int?);
      final n = batches[pick++];
      return <String>[for (var i = 0; i < n; i++) _onePixelPng('p$i')];
    }
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
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
      home: ProjectNewScreen(initial: _projectWith(kept)),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await tester.scrollUntilVisible(find.text('صور المشروع'), 240,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();

  final addTile =
      find.ancestor(of: find.text('أضف صورة'), matching: find.byType(InkWell));
  if (addTile.evaluate().isEmpty) {
    return (
      picks: 0,
      limits: limits,
      texts: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList()
    );
  }
  for (var round = 0; round < batches.length; round++) {
    final tile = find.ancestor(
      of: find.text('أضف صورة'),
      matching: find.byType(InkWell),
    );
    if (tile.evaluate().isEmpty) break;
    await tester.tap(tile.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  return (
    picks: pick,
    limits: limits,
    texts: tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList()
  );
}

void main() {
  group('the cap is arithmetic, not a hope', () {
    test('a fresh project can take the whole cap', () {
      expect(projectPhotoRoom(0, 0), kMaxProjectPhotos);
    });

    test('kept and picked are counted together, not separately', () {
      // The old tile gate was `images.length < 6`: it never saw `kept` at all.
      expect(projectPhotoRoom(6, 0), 4);
      expect(projectPhotoRoom(0, 6), 4);
      expect(projectPhotoRoom(4, 3), 3);
    });

    test('a full project has no room, and says so with a zero not a negative', () {
      expect(projectPhotoRoom(kMaxProjectPhotos, 0), 0);
      // `limit: 0` means "no limit" to image_picker, and a negative is a crash
      // on a real device — the floor is load-bearing, not cosmetic.
      expect(projectPhotoRoom(kMaxProjectPhotos, 3), 0);
      expect(projectPhotoRoom(20, 5), 0);
    });
  });

  group('on the real screen, editing a project that already has photos', () {
    testWidgets('the add tile is gone when the kept photos fill the cap',
        (tester) async {
      final r = await editAndPick(tester, kept: kMaxProjectPhotos, batches: []);
      expect(r.picks, 0, reason: 'the gallery must not open on a full project');
      expect(r.limits, isEmpty);
      expect(r.texts, isNot(contains('أضف صورة')),
          reason: 'a full project must not offer the add tile');
    });

    testWidgets('the picker is handed the ROOM, not a constant six',
        (tester) async {
      // 4 kept + 3 picked = 7, so the next pick may be at most 3. The old call
      // passed 6 here and let the total run to 10 kept-plus-picked.
      final r = await editAndPick(tester, kept: 4, batches: [3, 4]);
      expect(r.limits, [6, 3],
          reason: 'second pick got ${r.limits}, expected the remaining room');
    });

    testWidgets('a client who picks past the cap in one go is trimmed, not refused',
        (tester) async {
      // The OS picker is handed a limit, but a mis-wired or malicious one can
      // still hand back more. What must not happen is an unbounded project.
      final r = await editAndPick(tester, kept: 0, batches: [40]);
      expect(r.picks, 1);
      final lines = r.texts.where((t) => t.contains('مضافة'));
      expect(lines, isNotEmpty, reason: '$r');
    });
  });
}
