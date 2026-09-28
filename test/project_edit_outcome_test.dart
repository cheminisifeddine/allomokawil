// Proves an unconfirmed **edit** is told apart from a confirmed one.
//
// `S.errWriteUnconfirmed` ends with «تحقّق من القائمة قبل إعادة المحاولة» and
// eight write screens answer it by re-reading the server. The edit path did
// not have its own question — it reused the create path's
// `myProjects().any((p) => p.title == title)`, and on an edit that answer is
// true *before the PATCH is sent*: the row is already in the user's own list,
// under its old title.
//
// So every stalled edit was reported «وجدناه في القائمة — الطلب وصل بنجاح».
// A client who corrected a wrong phone number, fixed a mistyped budget or
// removed a photo was told the change saved; the screen then popped as it does
// on success and the project came back with the old values. Nothing duplicated
// — the roles are reversed from the chat and portfolio bugs, where the false
// sentence was the failure one and a retry would have made a second copy.
//
// Two halves, because a rule nothing is wired to passes clean:
//  * the snapshot, the predicate and the probe, pure and therefore testable
//    without a widget — including the decoy that the title predicate invites;
//  * the screen, driven over a real stalled PATCH, because "the screen asks the
//    right question" is not a property of the helper.
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
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart';

import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/core/l10n/write_outcome.dart';
import 'package:allomokawil/src/data/project_edit_outcome.dart';
import 'package:allomokawil/src/models/project.dart';

/// A row as the server holds it, for the pure half.
Project _row({
  String title = 'دهان شقة 3 غرف',
  List<String> categories = const <String>['painting'],
  String wilaya = '16',
  String? commune = 'حسين داي',
  int? budgetMin = 60000,
  int? budgetMax = 90000,
  UrgencyLevel urgency = UrgencyLevel.withinWeek,
  String? description = 'الوصف',
  List<String> images = const <String>[],
}) =>
    Project(
      id: 'p-1',
      customerId: 30,
      title: title,
      category: 'painting',
      categories: categories,
      wilaya: wilaya,
      commune: commune,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      urgency: urgency,
      status: ProjectStatus.open,
      description: description,
      images: images,
    );

/// What the form was sending: [row]'s values unless a test says otherwise.
ProjectEditSnapshot _sent({
  String title = 'دهان شقة 3 غرف',
  Set<String> categories = const <String>{'painting'},
  String? wilaya = '16',
  String? commune = 'حسين داي',
  int? budgetMin = 60000,
  int? budgetMax = 90000,
  UrgencyLevel urgency = UrgencyLevel.withinWeek,
  String? description = 'الوصف',
  List<String> images = const <String>[],
}) =>
    ProjectEditSnapshot.form(
      title: title,
      categories: categories,
      wilaya: wilaya,
      commune: commune,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      urgency: urgency,
      description: description,
      images: images,
    );

void main() {
  group('the tautology this file exists to kill', () {
    // The old predicate, verbatim: `myProjects().any((p) => p.title.trim() ==
    // publishedTitle)`, where `publishedTitle` is the NEW title.
    //
    // It is not *always* true, and the two ways it lies are different, so both
    // are pinned. The common case is the first one: an edit that does not
    // touch the title at all — removing a photo, fixing a budget, correcting a
    // phone number in the description. The row is already in the user's own
    // list under exactly that title, the PATCH has not been sent, and the
    // answer is true anyway.
    test('an edit that does not touch the title reads as landed before it is sent',
        () {
      final rows = <Project>[_row(title: 'دهان شقة 3 غرف')];
      const publishedTitle = 'دهان شقة 3 غرف'; // unchanged by this edit
      final inList = rows.any((p) => p.title.trim() == publishedTitle);
      expect(inList, isTrue,
          reason: 'this is the defect: the recheck answers true before the write');
    });

    // The other direction, and the reason a title-only fix would not have been
    // enough. An edit that *does* rename the project makes the old predicate
    // answer false while the row is plainly in the user's own list — so the
    // app says «لم نجده في القائمة» about a project the user is looking at,
    // and offers a retry for a write that very likely landed.
    test('an edit that renames reads as missing while the row is right there',
        () {
      final rows = <Project>[_row(title: 'العنوان القديم')];
      const publishedTitle = 'العنوان الجديد';
      final inList = rows.any((p) => p.title.trim() == publishedTitle);
      expect(inList, isFalse,
          reason: 'the old predicate would deny a project that is on screen');
    });

    // And the fix, on the same two rows, answers both correctly.
    test('the edit predicate reads both halves from the row itself', () {
      // Renamed, not saved: the server still carries the old title.
      expect(
        ProjectEditSnapshot.of(_row(title: 'العنوان القديم'))
            .matches(_sent(title: 'العنوان الجديد')),
        isFalse,
      );
      // Renamed and saved: the server carries what the form sent.
      expect(
        ProjectEditSnapshot.of(_row(title: 'العنوان الجديد'))
            .matches(_sent(title: 'العنوان الجديد')),
        isTrue,
      );
    });
  });

  group('mismatches', () {
    test('a row carrying everything the form sent is a landing', () {
      expect(ProjectEditSnapshot.of(_row()).matches(_sent()), isTrue);
    });

    test('a cleared description is not a mismatch', () {
      // The form sends `null` for an empty box; the column may come back `null`
      // or `''`. Comparing with `==` would tell a client who removed text that
      // the removal did not save.
      for (final server in <String?>[null, '', '   ']) {
        expect(
          ProjectEditSnapshot.of(_row(description: server))
              .matches(_sent(description: null)),
          isTrue,
          reason: 'a cleared description read as a mismatch: $server',
        );
      }
    });

    test('a changed description IS a mismatch', () {
      expect(
        ProjectEditSnapshot.of(_row(description: 'القديم'))
            .matches(_sent(description: 'الجديد')),
        isFalse,
      );
    });

    test('the budget is one field, not two', () {
      // min and max are one number to the user and one pair of boxes on the
      // form, and a sentence naming two of them sends him nowhere useful.
      final m = ProjectEditSnapshot.of(_row()).mismatches(_sent(budgetMax: 120000));
      expect(m, <String>['budget']);
      expect(ProjectEditSnapshot.of(_row()).mismatches(_sent(budgetMin: 1)),
          <String>['budget']);
    });

    test('dropping a second trade is a mismatch, not a landing', () {
      // The form sends `_categories.first` as the primary *and* the whole set.
      // Comparing only the primary would call a write that dropped «سباكة» a
      // landing, and the client would lose a trade he explicitly removed.
      final server =
          ProjectEditSnapshot.of(_row(categories: const <String>['painting', 'plumbing']));
      expect(server.matches(_sent()), isFalse);
      // Adding one is a mismatch too — the same argument in the other direction.
      final added = ProjectEditSnapshot.of(_row());
      expect(
        added.matches(_sent(categories: const <String>{'painting', 'plumbing'})),
        isFalse,
      );
    });

    test('photo order is server-owned and never a mismatch', () {
      // The PATCH replaces the photo list wholesale, so the write is *which*
      // photos — not the order they sit in. The form never reorders them, and
      // a predicate comparing order would report a landing as a failure and
      // tell a client his gallery edit did not save when it had.
      const server = ProjectEditSnapshot(
        title: 'دهان شقة 3 غرف',
        category: 'painting',
        categories: <String>['painting'],
        wilaya: '16',
        commune: 'حسين داي',
        budgetMin: 60000,
        budgetMax: 90000,
        urgency: UrgencyLevel.withinWeek,
        description: 'الوصف',
        images: <String>['https://r2.test/b.jpg', 'https://r2.test/a.jpg'],
      );
      expect(
        server.matches(_sent(images: const <String>[
          'https://r2.test/a.jpg',
          'https://r2.test/b.jpg',
        ])),
        isTrue,
      );
    });

    // The decoy. A photo removed in the form is a *missing URL*, and the row on
    // the server still holds it — which is exactly what a lost PATCH looks
    // like, and exactly what a *landing* does not. If the predicate matched
    // loosely (a prefix, a tail, a bucket-stripped key) a photo the server
    // still has could be read as the one the user removed, and the app would
    // call the removal a landing while the photo stays in his project forever.
    test('a photo the server still holds is not the one that was removed', () {
      const removed = 'https://r2.test/projects/room-1.jpg';
      // The PATCH lost: the server still carries the photo.
      final stillHasIt =
          ProjectEditSnapshot.of(_row(images: const <String>[removed]));
      expect(stillHasIt.matches(_sent(images: const <String>[])), isFalse,
          reason: 'a lost removal was called a landing: the photo never went');

      // And the decoys a loose comparison would accept, in the shapes it would
      // take. The earlier version of this decoy only shared a prefix and a
      // predicate mutated to match on a substring passed everything.
      for (final decoy in const <String>[
        'https://r2.test/projects/room-1-copy.jpg', // a retry's new key
        'https://r2.test/projects/room-1.jpg.bak', // this key, suffixed
        'https://cdn.test/projects/room-1.jpg', // another host, same key
        'room-1.jpg', // the bare key
        '1.jpg', // a tail match on a shorter, unrelated key
        'room-',
        '.jpg',
      ]) {
        final server = ProjectEditSnapshot.of(_row(images: <String>[decoy]));
        expect(server.matches(_sent(images: const <String>[])), isFalse,
            reason: 'a loose match let the decoy through: $decoy');
      }
    });

    test('a duplicate photo is not "the same list"', () {
      // Two copies of one URL means the PATCH would store two rows. A real set
      // would fold them together and call it unchanged.
      final server = ProjectEditSnapshot.of(_row(
        images: const <String>['https://r2.test/a.jpg', 'https://r2.test/a.jpg'],
      ));
      expect(
        server.matches(_sent(images: const <String>['https://r2.test/a.jpg'])),
        isFalse,
      );
    });

    test('a null wilaya can never equal an empty one silently', () {
      // The form cannot submit without a wilaya, so a null here means the
      // re-read returned something the form never sent.
      expect(ProjectEditSnapshot.of(_row(wilaya: '')).matches(_sent()), isFalse);
    });
  });

  group('resolveProjectEditOutcome', () {
    test('the server now carries what the form sent: landed', () async {
      final r = await resolveProjectEditOutcome(
        sent: _sent(budgetMax: 120000),
        fetch: () async => _row(budgetMax: 120000),
      );
      expect(r.outcome, WriteOutcome.landed);
      expect(r.mismatched, isEmpty);
      // The server's own copy comes back, so the screen can show the real
      // values rather than a guess.
      expect(r.fresh?.budgetMax, 120000);
    });

    test('the server still carries the old budget: missing, and it says which',
        () async {
      final r = await resolveProjectEditOutcome(
        sent: _sent(budgetMax: 120000),
        fetch: () async => _row(budgetMax: 90000),
      );
      expect(r.outcome, WriteOutcome.missing);
      // The field name is the point: «الميزانية لم تتغيّر» puts the user's
      // finger on the box, «لم يُحفظ التعديل» sends him hunting.
      expect(r.mismatched, contains('budget'));
      expect(editOutcomeCopy(r), contains(S.fieldBudget));
    });

    // The phone is still offline. NOT proof the write failed, so never
    // `missing`: that would tell a client his edit is gone when it may be
    // saved, and he would re-enter the whole thing.
    test('a re-read that fails is unknown, never missing', () async {
      final r = await resolveProjectEditOutcome(
        sent: _sent(budgetMax: 120000),
        fetch: () async => throw StateError('offline'),
      );
      expect(r.outcome, WriteOutcome.unknown);
      expect(r.fresh, isNull);
      expect(editOutcomeCopy(r), S.editUnconfirmedUnknown);
    });
  });

  group('editOutcomeCopy', () {
    test('landed is its own sentence, not the create path\'s', () {
      // «وجدناه في القائمة» is a claim about *finding a row* — meaningless on
      // an edit, where the row was in the list the whole time.
      const landed = (
        outcome: WriteOutcome.landed,
        fresh: null,
        mismatched: <String>[],
        pendingPhotos: 0,
      );
      expect(editOutcomeCopy(landed), S.editUnconfirmedLanded);
      expect(editOutcomeCopy(landed), isNot(S.writeUnconfirmedLanded));
    });

    test('missing names a field and still offers the retry', () {
      const r = (
        outcome: WriteOutcome.missing,
        fresh: null,
        mismatched: <String>['wilaya'],
        pendingPhotos: 0,
      );
      final copy = editOutcomeCopy(r);
      expect(copy, contains(S.fieldWilaya));
      expect(copy, contains('أعد المحاولة'));
    });

    test('several mismatches speak the first, never a growing list', () {
      // A client who changed the budget and the description and heard
      // «الميزانية، الوصف» learns less than he did, and the sentence grows with
      // every field the form gains.
      const r = (
        outcome: WriteOutcome.missing,
        fresh: null,
        mismatched: <String>['budget', 'description', 'title'],
        pendingPhotos: 0,
      );
      final copy = editOutcomeCopy(r);
      expect(copy, contains(S.fieldBudget));
      expect(copy, isNot(contains(S.fieldDescription)));
      expect(copy, isNot(contains(S.fieldTitle)));
    });

    test('every field key the contract can emit has an Arabic name', () {
      // A field added to the snapshot without a name is a bug in the app, so
      // this is exhaustive over the keys, not a spot check.
      for (final key in const <String>[
        'title', 'category', 'wilaya', 'commune',
        'budget', 'urgency', 'description', 'images',
      ]) {
        expect(fieldCopy(key), isNotEmpty, reason: 'no Arabic name: $key');
        expect(fieldCopy(key), contains('ا'),
            reason: 'a Latin key leaked into the sentence: $key');
      }
    });
  });

  group('on the real screen', () {
    /// The app's own [Repository] with **only** the upload replaced.
    ///
    /// `uploadPhoto` is a `MultipartRequest` and builds its own `HttpClient`
    /// instead of the one handed to [ApiClient], so a `MockClient` can never
    /// see an upload. Stubbing it here — and nothing else — is what lets the
    /// PATCH and the re-read travel the *real* network layer, so the
    /// `errWriteUnconfirmed` under test is the one the transport actually
    /// throws rather than one this file handed to itself.
    ///
    /// [uploadFails] is the ambiguous case the whole file is about: a bare
    /// `POST /api/upload` is not idempotent, so an upload that left the phone
    /// and was never answered raises `S.errWriteUnconfirmed` — the exact shape
    /// `isWriteUnconfirmed` matches.
    Repository repoWithUpload(ApiClient api, {bool uploadFails = false}) =>
        _RepoStub(api, uploadFails: uploadFails);

    /// Drives the real edit form through a stalled upload and reports what the
    /// screen said, plus how many PATCHes the transport actually saw.
    ///
    /// [afterSave] is what the re-read answers: empty means the server still
    /// carries the pre-edit row, so the budget he changed did not save.
    Future<({List<String> said, int patches, int rereads})> driveEdit(
      WidgetTester tester, {
      required Map<String, Object?> afterSave,
      bool addPhoto = true,
      bool renames = false,
    }) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      var patches = 0;
      var rereads = 0;
      // The row as it stands BEFORE the edit: old budget, old title.
      final base = <String, Object?>{
        'id': 'p-1',
        'customer_id': 30,
        'title': 'دهان شقة 3 غرف',
        'description': 'الوصف',
        'category': 'painting',
        'images': <String>[],
        'wilaya': '16',
        'commune': 'حسين داي',
        'budget_min': 60000,
        'budget_max': 90000,
        'urgency': 'within_week',
        'status': 'open',
        'selected_worker_id': null,
        'created_at': '2026-09-28 08:00:00',
      };
      const json = <String, String>{'content-type': 'application/json'};

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (req.method == 'PATCH' && p.endsWith('/projects/p-1')) {
            patches++;
            // A **project row**, not an `ok`. `updateProject` runs the answer
            // through `Project.fromJson`, so `{'ok': true}` throws inside the
            // decode and the screen reports «حدث خطأ غير متوقع» — which reads as
            // a failure the fix caused, and is not one.
            return http.Response(
                jsonEncode(<String, Object?>{...base, ...afterSave}), 200,
                headers: json);
          }
          // The re-read: one project, by id — never the list. The old code asked
          // the list, which is precisely how the tautology stayed invisible.
          if (req.method == 'GET' && p.endsWith('/projects/p-1')) {
            rereads++;
            return http.Response(
                jsonEncode(<String, Object?>{...base, ...afterSave}), 200,
                headers: json);
          }
          if (p.endsWith('/login')) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'token': 'tok',
                'user': <String, Object?>{
                  'id': 30,
                  'phone': '0773000000',
                  'email': null,
                  'full_name': 'زبون تجربة',
                  'type': 'customer',
                  'avatar_url': null,
                  'wilaya': '16',
                  'commune': null,
                  'created_at': '2026-09-28 07:00:00',
                },
              }),
              200,
              headers: json,
            );
          }
          if (p.endsWith('/unread')) {
            return http.Response('{"unread":0}', 200, headers: json);
          }
          return http.Response('[]', 200, headers: json);
        }),
        timeout: const Duration(milliseconds: 25),
      );

      final auth = AuthState(api);
      await auth.login(phone: '0773000000', password: 'secret123');

      await tester.pumpWidget(AppScope(
        api: api,
        auth: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: ProjectNewScreen(
            repo: repoWithUpload(api, uploadFails: true),
            initial: Project.fromJson(base),
          ),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      if (addPhoto) {
        // The photo makes the upload loop run at all, and it is the only write
        // here that can be unconfirmed.
        const picker = MethodChannel('plugins.flutter.io/image_picker');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(picker, (call) async {
          if (call.method == 'pickMultiImage') return <String>[_onePixelPng()];
          return null;
        });
        addTearDown(() => TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(picker, null));

        // Asserted, not assumed: a tile that never picked leaves the upload
        // loop empty, the PATCH runs, and every assertion below would pass for
        // the wrong reason.
        // Scrolled to and tapped as the **InkWell**, not as the label's Text.
        // The label is 392 dp down a form that scrolls, so a tap on the text
        // hits whatever is at those coordinates and the picker never opens —
        // silently, with every assertion below still passing. The photo-limit
        // test drives the same screen and has to do the same.
        await tester.scrollUntilVisible(find.text('صور المشروع'), 240,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        final addTile =
            find.ancestor(of: find.text('أضف صورة'), matching: find.byType(InkWell));
        expect(addTile, findsWidgets,
            reason: 'the add-photo tile is not on screen');
        await tester.tap(addTile.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // The thumbnail is keyed by its own semantic label rather than by an
        // `Image`: `Image.file` is handed a path that does not exist, so it
        // renders an error box — present, but not a decoded picture, and a
        // finder on the widget type would be testing the wrong thing.
        expect(find.bySemanticsLabel('صورة المشروع 1'), findsOneWidget,
            reason: 'the picker produced no thumbnail: '
                'the upload loop would never run');
      }

      // The *max* box ('إلى') and a value above the existing min. Setting the
      // min instead would exceed the max the row already carries and the form's
      // own live validation would refuse to submit — correct behaviour, and it
      // made this harness fail silently once (no PATCH, no toast, no re-read,
      // every assertion passing for the wrong reason).
      await tester.enterText(find.widgetWithText(TextField, 'إلى'), '120000');
      if (renames) {
        await tester.enterText(
            find.widgetWithText(TextField, 'عنوان المشروع'), 'دهان شقة 4 غرف');
      }
      // The raised keyboard covers the sticky bar, so the tap is absorbed
      // unless focus is dropped first.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // Asserted rather than assumed: a silently disabled button makes every
      // assertion below pass for the wrong reason.
      final btn = find.widgetWithText(PrimaryButton, 'احفظ التعديل');
      expect(btn, findsOneWidget, reason: 'the save button is not on screen');
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);

      // Pumped in small steps and the toast read **as it appears**: a
      // `pumpAndSettle(seconds: 3)` advances far enough for a SnackBar to
      // auto-dismiss, so the sentence appears and the harness measures neither.
      // The window runs past the re-read rather than stopping on it: the
      // outcome sentence is a **second** toast, queued behind «نتحقّق الآن من
      // القائمة…», and stopping the moment the re-read lands measured the
      // first sentence and none of the answer.
      final said = <String>[];
      for (var i = 0; i < 60 && said.length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        said.addAll(tester
            .widgetList<SnackBar>(find.byType(SnackBar))
            .map((s) => (s.content as Text).data ?? ''));
      }
      await tester.pump(const Duration(milliseconds: 60));
      said.addAll(tester
          .widgetList<SnackBar>(find.byType(SnackBar))
          .map((s) => (s.content as Text).data ?? ''));

      return (
        said: <String>[
          ...said,
          ...tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? ''),
        ],
        patches: patches,
        rereads: rereads,
      );
    }

    /// True when any sentence the screen showed *contains* [needle].
    ///
    /// Not `said.contains(needle)`: `said` is a `List<String>`, so `contains`
    /// is element equality, and every sentence under test **embeds** the thing
    /// it is about — «ما زال المشروع يحمل: الميزانية — أعد المحاولة» is not
    /// the string `الميزانية`. Matching element-wise is a test that can only
    /// pass for a sentence that says nothing else at all, which is why the
    /// first run of this file failed against a screen that was already right.
    bool said(List<String> all, String needle) =>
        all.any((s) => s.contains(needle));

    // The half the fix exists for. The upload stalled and the server still
    // carries the old budget: the edit did NOT save. The old code asked "is
    // this title in myProjects?" — true before the write, since the row was
    // already in the user's own list — and reported «وجدناه في القائمة».
    testWidgets('an edit that did not save is never reported as saved',
        (tester) async {
      final r = await driveEdit(tester, afterSave: const <String, Object?>{});
      final spoken = r.said;

      expect(r.patches, 0,
          reason: 'the upload runs before the PATCH, so a stalled upload means '
              'the PATCH was never sent');
      expect(r.rereads, greaterThanOrEqualTo(1),
          reason: 'the project was never re-read: '
              'patches=${r.patches} rereads=${r.rereads} said=$spoken');
      // The field name is the point: it puts the user's finger on the box,
      // where «لم يُحفظ التعديل» alone sends him hunting.
      expect(said(spoken, S.fieldBudget), isTrue,
          reason: 'the app did not say which field is stale: $spoken');
      expect(said(spoken, S.writeUnconfirmedLanded), isFalse,
          reason: 'a lost edit was reported as saved: $spoken');
      expect(said(spoken, S.editUnconfirmedLanded), isFalse);
    });

    // The same stall, with a project that has no photo attached: the PATCH is
    // then the only write, and it succeeds. Nothing was lost, so the sentence
    // must not accuse a field of being stale.
    testWidgets('an edit with no photo never invents a stale field',
        (tester) async {
      final r = await driveEdit(
        tester,
        addPhoto: false,
        afterSave: const <String, Object?>{'budget_max': 120000},
      );
      final spoken = r.said;

      expect(r.patches, 1, reason: 'the PATCH was never attempted');
      // Matched against the **sentences**, not the whole tree: «الميزانية» is
      // also a section label on this form, so scanning every `Text` for it
      // finds the field the user filled in whether or not any sentence ever
      // named it. That was the first version of this assertion and it can only
      // ever fail, for a reason that has nothing to do with the write.
      expect(spoken.any((s) => s.contains('أعد المحاولة')), isFalse,
          reason: 'nothing failed, so no retry was offered: $spoken');
      expect(spoken.any((s) => s.contains('ما زال المشروع يحمل')), isFalse,
          reason: 'the app called a saved field stale: $spoken');
    });

    // A landed edit that also has a photo in flight. The fields reached the
    // server; the blob's fate is unknowable from the row, so the sentence must
    // not claim the whole edit saved.
    testWidgets('a saved edit with an unanswered photo does not claim all saved',
        (tester) async {
      final r = await driveEdit(
        tester,
        afterSave: const <String, Object?>{'budget_max': 120000},
      );
      final spoken = r.said;

      expect(said(spoken, S.editUnconfirmedLanded), isFalse,
          reason: 'claimed every part of the edit saved: $spoken');
      expect(said(spoken, 'لم يصلنا جوابها'), isTrue,
          reason: 'the photo was never mentioned: $spoken');
    });
  });
}

/// A real, decodable one-pixel PNG on disk.
///
/// Not decoration. `Image.file` is handed whatever path the picker returns, so
/// a path that does not exist throws inside the build and the thumbnail never
/// reaches the tree — which makes the upload loop empty, the PATCH run, and
/// every assertion in the screen group pass for the wrong reason. The first
/// version of this harness returned `/tmp/does-not-matter.png` and did exactly
/// that, quietly, for a whole run.
String _onePixelPng() {
  final dir = Directory.systemTemp.createTempSync('am_edit');
  final f = File('${dir.path}/p0.png');
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

/// The app's [Repository] with the one method a `MockClient` cannot reach.
class _RepoStub extends Repository {
  _RepoStub(super.api, {this.uploadFails = false});

  final bool uploadFails;

  @override
  Future<String> uploadDocument(File file) async {
    if (uploadFails) {
      // Exactly what the transport throws for a POST whose answer never came.
      throw ApiException(S.errWriteUnconfirmed);
    }
    return 'https://r2.test/photo.jpg';
  }
}
