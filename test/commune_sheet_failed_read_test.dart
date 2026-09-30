// The commune picker had no answer to give when the dataset failed — it gave a
// shimmer, forever.
//
// Found 30 Sep 2026 with 0 unchecked items, by sweeping the family the last
// items each named: **every** `.then(` in `lib/` writes state on the success
// arm with a guarded failure, and this was the one site in the app with no
// error arm at all. `project_new_screen.dart:1051` was:
//
//     CommuneIndex.instance.forWilaya(widget.wilayaId).then((list) {
//       if (!mounted) return;
//       setState(() { _loading = false; _total = list.length; });
//     });
//
// Two failures, and neither one is a colour bug.
//
// **The user got a permanent shimmer.** `CommuneIndex.load()` deliberately
// rethrows — its own doc says «the caller still sees the original error — it
// is rethrown, never swallowed — so the sheet that asked for the list still
// knows the dataset is unavailable». This sheet was the caller that never
// listened, so a failed read had no branch to run, `_loading` stayed `true`
// for the life of the State, and the bottom sheet sat on a grey skeleton with
// no sentence, no button and nothing to tap. The dataset is readable without a
// network, so the only causes are a corrupt build, a half-written asset or a
// decode failure — precisely the three `commune_reload_test.dart` exists for.
//
// **And every one of them wrote a phantom crash.** The rejected future had no
// listener, so it went to `Zone.unhandledError`, which in this app is the
// crash reporter. The same shape `worker_profile_screen.dart` already fixed
// for its two section reads by calling `.ignore()`.
//
// The shimmer is the visible half and the phantom crash is the quiet half, and
// the reason this survived is that the *common* path is a green one: the
// dataset almost always loads, so every ordinary run draws a working sheet and
// the missing arm is only ever seen on a broken build. `commune_reload_test`
// already proved the load can fail and then **recover**, so a State that had
// consumed a failure would be correct afterwards — which is why the case below
// drives a failing read and a *repairing* one through the same screen.
//
// What the fix does NOT put on screen, and why that is the harder half: a
// `danger: true` «تعذّر» card with «إعادة المحاولة» would be the obvious move
// and the wrong one. The commune is **optional** — the field behind this sheet
// reads «اختر البلدية (اختياري)» and the submit path sends `null` for it — so a
// missing list of 1,541 communes does not stop a client from posting the
// renovation they need. A red card teaches the opposite. The sheet therefore
// says the one true thing, names the escape that already works, and stays
// open, and the case below asserts the absence of the retry button as well as
// the presence of the sentence.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/communes.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/widgets/skeletons.dart';

const String _assetKey = 'assets/data/communes_dz.json';

/// A dataset good enough to open a sheet on: one wilaya, three communes.
///
/// **Wilaya 31, not 16** — `taxonomy.dart:40` is `(id: '31', name: 'وهران')`,
/// and `commune_count_copy_test.dart` had already swept the real asset for
/// exactly this. A fixture built on the wrong id does not fail loudly: the
/// sheet opens on a wilaya that simply has no communes, prints its honest
/// empty state, and the case would have gone green proving nothing. It is
/// caught here because the count line is asserted.
const String _good =
    '{"wilayas":{"31":{"ar":"وهران"}},"communes":{"31":[["وهران","ORAN"],'
    '["بئر الجير","EL BIR"],["عين الترك","AIN TURK"]]}}';

/// Serves [body] for the dataset asset, or nothing at all when it is null, and
/// counts every read so a case can prove a **second** attempt really happened.
///
/// The counter is the point: without it a "the retry is real" assertion would
/// pass against a State that silently reused the first failure.
void _serveAsset(String? body, List<int> reads) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
    if (message == null) return null;
    if (utf8.decode(message.buffer.asUint8List()) != _assetKey) return null;
    reads.add(1);
    if (body == null) throw Exception('asset missing');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(body)));
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', null));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The index is a process-wide singleton, so a case that parks it on a
    // failure would hand the next case a State the app never reaches in
    // production — exactly what `resetForTest` exists for.
    CommuneIndex.instance.resetForTest();
  });

  /// A phone with no network at all — the publish form is a POST screen, and
  /// the commune sheet must open without one.
  ApiClient deadApi() => ApiClient(
        baseUrls: const ['https://offline.test'],
        httpClient: MockClient((_) async {
          throw const SocketException('network is unreachable');
        }),
      );

  /// Pumps the real screen, picks a wilaya by hand and opens the real sheet.
  ///
  /// The sheet is private, so it is reached the only way a user reaches it:
  /// the form's own «اختر البلدية» field. A case that constructed the widget
  /// directly would be testing a constructor, not the app.
  Future<void> openSheet(WidgetTester tester, ApiClient api) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AppScope(
        api: api,
        auth: AuthState(api),
        child: const ProjectNewScreen(),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    final wilayaField = find.text('اختر الولاية');
    await tester.ensureVisible(wilayaField);
    await tester.pump();
    await tester.tap(wilayaField);
    await tester.pumpAndSettle();
    // The sheet lists all 58 wilayas and only the first screenful is inflated,
    // so «وهران» is not in the tree until the search narrows it. Skipping this
    // step fails the case in the *harness* with «Bad state: No element» —
    // which is a fixture fault, not the defect, and is recorded here because it
    // is the same trap `offline_taxonomy_test.dart` already documents.
    await tester.enterText(find.byType(TextField).last, 'وهرا');
    await tester.pumpAndSettle();
    await tester.tap(find.text('وهران'));
    await tester.pumpAndSettle();

    final communeField = find.text('اختر البلدية (اختياري)');
    await tester.ensureVisible(communeField);
    await tester.pump();
    await tester.tap(communeField);
    await tester.pump();
    // The sheet's read runs in the real zone; the fake clock cannot complete
    // an asset read, so give the continuation a real event-loop turn.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a failed dataset read is answered, not left as a shimmer',
      (tester) async {
    final reads = <int>[];
    _serveAsset(null, reads);

    await openSheet(tester, deadApi());

    expect(reads, isNotEmpty, reason: 'the sheet must actually read the asset');

    // The defect, asserted: the old code cleared `_loading` only on the success
    // arm, so a failed read kept the SkeletonRowList on screen for the life of
    // the State. `SkeletonRowList` appears nowhere else on this sheet, so its
    // presence is the failure itself.
    expect(find.byType(SkeletonRowList), findsNothing,
        reason: 'a failed dataset read left the sheet on a permanent shimmer');

    // And the sentence that answers it.
    expect(find.text('تعذّر تحميل قائمة البلديات'), findsOneWidget);
  });

  testWidgets('a failed read is reported as a failure, not as an empty wilaya',
      (tester) async {
    _serveAsset(null, <int>[]);
    await openSheet(tester, deadApi());

    // The two states look identical and mean opposite things. A failure that
    // printed the empty-search sentence («لا توجد بلدية بهذا الاسم») would be
    // telling the user his wilaya has no communes, which is false and which no
    // amount of retrying would fix.
    expect(find.text('لا توجد بلدية بهذا الاسم'), findsNothing);

    // And it must not claim a count either: `communeCountAr(0)` is silence by
    // design, so a failed read cannot print «0 بلدية».
    expect(find.textContaining('0 بلدية'), findsNothing);
  });

  testWidgets('the failed sheet offers the escape, not a red retry button',
      (tester) async {
    _serveAsset(null, <int>[]);
    await openSheet(tester, deadApi());

    // The commune is optional — the field behind the sheet says so and the
    // submit path sends null for it — so a retry button here would tell a
    // client that his project cannot be posted without a list he never needed.
    // Every sibling that loads a *body* does offer one; this sheet does not
    // load the body of the page.
    expect(find.text('إعادة المحاولة'), findsNothing,
        reason: 'an optional field must not be dressed as a blocker');

    // The one affordance that is true, and it is the same one the
    // empty-search branch already offered.
    expect(find.text('اكتب اسم البلدية يدوياً'), findsOneWidget);
  });

  testWidgets('a repaired dataset answers the next open, so the state is not '
      'stuck on the failure', (tester) async {
    final reads = <int>[];
    _serveAsset(null, reads);
    await openSheet(tester, deadApi());
    expect(find.text('تعذّر تحميل قائمة البلديات'), findsOneWidget);
    final afterFirst = reads.length;

    // The dataset becomes readable — a repaired build, or the second half of
    // `commune_reload_test`'s "a failed attempt is forgotten". Close the sheet
    // and open it again: the new State must read the asset rather than replay
    // the remembered failure.
    _serveAsset(_good, reads);
    await tester.tap(find.text('اكتب اسم البلدية يدوياً'));
    await tester.pumpAndSettle();

    final communeField = find.text('اختر البلدية (اختياري)');
    await tester.ensureVisible(communeField);
    await tester.pump();
    await tester.tap(communeField);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(reads.length, greaterThan(afterFirst),
        reason: 'the second open must really re-read the asset, not replay it');
    expect(find.byType(SkeletonRowList), findsNothing);
    expect(find.text('تعذّر تحميل قائمة البلديات'), findsNothing);
    // The list tile, not the form's own «وهران» field behind the sheet.
    expect(find.text('EL BIR'), findsOneWidget);
  });

  testWidgets('the escape button does not wear the retry icon', (tester) async {
    _serveAsset(null, <int>[]);
    await openSheet(tester, deadApi());

    // `EmptyView` defaults `actionIcon` to `Icons.refresh_rounded` and its own
    // doc requires a non-retry action to pass its own "so the button does not
    // lie" (ui.dart:624). This sheet's position is that there is nothing to
    // retry — the card above it already says the retry button was left out on
    // purpose — so a refresh glyph on its only button would contradict the
    // argument the screen makes in words, on the one control the user can
    // actually press.
    //
    // Asserting the **absence** of the retry glyph is the load-bearing half:
    // a test that only checks the edit icon is green until someone reverts the
    // property and the default comes back. Both are checked, and the second
    // one is what the first one is for.
    // `EmptyView` draws its action through [PrimaryButton], which builds an
    // `ElevatedButton` — **not** the `OutlinedButton` a first reading of the
    // widget would suggest. Asserting on the wrong button type fails the case
    // in the *harness* with a finder error, which reads as a real regression.
    final action = find.ancestor(
      of: find.text('اكتب اسم البلدية يدوياً'),
      matching: find.byType(ElevatedButton),
    );
    expect(action, findsOneWidget);

    expect(
      find.descendant(of: action, matching: find.byIcon(Icons.edit_rounded)),
      findsOneWidget,
      reason: 'the escape writes the name by hand, so it wears the write icon',
    );
    expect(
      find.descendant(of: action, matching: find.byIcon(Icons.refresh_rounded)),
      findsNothing,
      reason: 'a retry glyph here would promise the retry this screen refuses',
    );
  });

  testWidgets('a good dataset still draws the list and the count',
      (tester) async {
    // The regression the fix could have cost: a sheet that always draws a
    // sentence would pass every case above and be useless to a user.
    final reads = <int>[];
    _serveAsset(_good, reads);
    await openSheet(tester, deadApi());

    expect(find.byType(SkeletonRowList), findsNothing);
    expect(find.text('تعذّر تحميل قائمة البلديات'), findsNothing);
    expect(find.text('وهران'), findsWidgets);
    expect(reads, hasLength(1), reason: 'one dataset read per open of the sheet');
    // The count line, printed by the shared `communeCountAr` rule — **twice**,
    // and correctly so: once in the sheet's header (the wilaya's total) and
    // once as the list's own first row (the match count). `findsOneWidget` was
    // a false red here: the two are different sentences that happen to agree
    // when the query is empty.
    expect(find.text('3 بلديات'), findsNWidgets(2));
    // The list tile, identified by its **Latin subtitle**. The form's own
    // «وهران» field sits behind the sheet, so a bare name assertion is
    // satisfied by the form and proves nothing about the list.
    expect(find.text('EL BIR'), findsOneWidget);
  });
}
