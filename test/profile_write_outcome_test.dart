// Proves the profile save is not asserted on a 200 alone.
//
// The defect this pins: `updateMyProfile` built its body with
// `if (priceRangeMin != null)`, so a contractor who CLEARED the price range
// sent a body with no key in it. The PATCH returned 200, the screen printed
// «تم حفظ ملفك بنجاح», and the server kept 20000-60000 دج — a price range
// every browsing customer still saw, with nothing anywhere reporting a failure.
//
// Two halves, because they fail differently. The rule is pure and needs no
// widget; the screen is what has to obey it, and a correct helper wired to an
// unchanged `_save` passes the first half clean. That is the exact mistake the
// pricing-card tick made.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/l10n/write_outcome.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/data/profile_write_outcome.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/screens/worker/profile_edit_screen.dart';
import 'package:allomokawil/src/widgets/number_field.dart';

/// A worker row the server would answer with.
WorkerProfile _profile({
  String name = '\u0639\u0645\u064a \u0631\u0634\u064a\u062f',
  String? bio = '\u0628\u0646\u0627\u0621 \u0648\u062a\u0634\u064a\u0628',
  List<String> specs = const ['painting'],
  int years = 5,
  int? min = 20000,
  int? max = 60000,
  int radius = 30,
  bool available = true,
}) =>
    WorkerProfile(
      id: 16,
      userId: 31,
      fullName: name,
      bio: bio,
      specialties: specs,
      experienceYears: years,
      priceRangeMin: min,
      priceRangeMax: max,
      serviceRadiusKm: radius,
      isAvailable: available,
      verificationStatus: VerificationStatus.verified,
      avgRating: 4.5,
      totalReviews: 3,
      totalCompletedJobs: 7,
    );

ProfileSnapshot _sent({
  String name = '\u0639\u0645\u064a \u0631\u0634\u064a\u062f',
  String bio = '\u0628\u0646\u0627\u0621 \u0648\u062a\u0634\u064a\u0628',
  Set<String> specs = const {'painting'},
  int years = 5,
  int? min = 20000,
  int? max = 60000,
  int radius = 30,
  bool available = true,
}) =>
    ProfileSnapshot.form(
      fullName: name,
      bio: bio,
      specialties: specs,
      experienceYears: years,
      priceRangeMin: min,
      priceRangeMax: max,
      serviceRadiusKm: radius,
      isAvailable: available,
    );

Map<String, Object?> _json(Map<String, Object?> p) => <String, Object?>{
      'id': 16,
      'user_id': 31,
      'full_name': p['full_name'],
      'bio': p['bio'],
      'specialties': p['specialties'],
      'experience_years': p['experience_years'],
      'price_range_min': p['price_range_min'],
      'price_range_max': p['price_range_max'],
      'service_radius_km': p['service_radius_km'],
      'is_available': (p['is_available'] as bool? ?? true) ? 1 : 0,
      'verification_status': 'verified',
      'avg_rating': 4.5,
      'total_reviews': 3,
      'total_completed_jobs': 7,
      'is_identity_verified': 1,
      'is_certificate_verified': 0,
      'user_wilaya': '16',
    };

void main() {
  group('ProfileSnapshot', () {
    test('the row the form sent matches the row the server kept', () {
      expect(ProfileSnapshot.of(_profile()).mismatches(_sent()), isEmpty);
    });

    test('a price range the server refused to clear is named', () {
      // THE defect. The form sent no price; the server still holds 20000-60000.
      final m = ProfileSnapshot.of(_profile(min: 20000, max: 60000))
          .mismatches(_sent(min: null, max: null));
      expect(m, contains('price_range'));
    });

    test('the price range is one name, never two', () {
      final m = ProfileSnapshot.of(_profile())
          .mismatches(_sent(min: 2500, max: 2500));
      expect(m, <String>['price_range']);
    });

    test('a cleared bio is not a mismatch against a null column', () {
      expect(ProfileSnapshot.of(_profile(bio: null)).mismatches(_sent(bio: '')),
          isEmpty);
      expect(ProfileSnapshot.of(_profile(bio: '  ')).mismatches(_sent(bio: '')),
          isEmpty);
    });

    test('a legacy slug dialect is not an unsaved profile', () {
      // `_load` canonicalises, the server may answer with a hyphen variant.
      final server = ProfileSnapshot.of(
          _profile(specs: const ['venetian-plaster']));
      expect(server.mismatches(_sent(specs: const {'venetian_plaster'})),
          isEmpty);
    });

    test('a stored radius of 0 is the server\u2019s unset sentinel, not a value', () {
      // The slider's floor is 1, so 0 is not a value this app can send.
      final server = ProfileSnapshot.of(_profile(radius: 0));
      // A stored 0 reads as absent, not as a radius of zero. The comparison
      // that matters follows from it: a server holding 0 and a form that sent
      // 30 really did disagree, and reporting that is correct — the mapping
      // exists so the 0 is never *equal* to a real slider value, not so the
      // two become interchangeable.
      expect(server.serviceRadiusKm, isNull);
      expect(server.mismatches(_sent(radius: 30)), contains('radius'));
      // Two profiles that both store 0 must not disagree with each other.
      expect(
        ProfileSnapshot.of(_profile(radius: 0))
            .mismatches(ProfileSnapshot.form(
          fullName: 'x',
          bio: '',
          specialties: const {},
          experienceYears: 0,
          priceRangeMin: null,
          priceRangeMax: null,
          serviceRadiusKm: 1,
          isAvailable: false,
        )),
        contains('radius'),
      );
    });

    test('every field is caught, in a fixed order', () {
      final server = ProfileSnapshot.of(_profile(
        name: '\u0627\u062e\u0631 \u0627\u0633\u0645',
        bio: null,
        specs: const ['plumbing'],
        years: 1,
        min: 1,
        max: 2,
        radius: 5,
        available: false,
      ));
      expect(
        server.mismatches(_sent()),
        <String>[
          'name',
          'specialties',
          'bio',
          'experience',
          'price_range',
          'radius',
          'availability',
        ],
      );
    });

    test('every field has an Arabic name, and an unknown key throws', () {
      for (final k in const [
        'name',
        'specialties',
        'bio',
        'experience',
        'price_range',
        'radius',
        'availability',
      ]) {
        expect(profileFieldCopy(k), isNotEmpty);
      }
      expect(() => profileFieldCopy('nope'), throwsArgumentError);
    });
  });

  group('resolveProfileWriteOutcome', () {
    test('the server kept everything: landed', () async {
      final r = await resolveProfileWriteOutcome(
        sent: _sent(),
        fetch: () async => _profile(),
      );
      expect(r.outcome, WriteOutcome.landed);
      expect(r.mismatched, isEmpty);
      expect(r.fresh, isNotNull);
    });

    test('the server kept an old value: missing, and the field is named',
        () async {
      final r = await resolveProfileWriteOutcome(
        sent: _sent(min: null, max: null),
        fetch: () async => _profile(min: 20000, max: 60000),
      );
      expect(r.outcome, WriteOutcome.missing);
      expect(r.mismatched, contains('price_range'));
      expect(profileWriteOutcomeCopy(r), contains(S.fieldPriceRange));
    });

    test('a failed verification read is unknown, never missing', () async {
      // The PATCH answered 200. Calling that "not saved" would be a lie.
      final r = await resolveProfileWriteOutcome(
        sent: _sent(),
        fetch: () async => throw Exception('offline'),
      );
      expect(r.outcome, WriteOutcome.unknown);
      expect(r.fresh, isNull);
      expect(profileWriteOutcomeCopy(r), S.profileSavedUnverified);
    });

    test('the copy never claims the write did not arrive', () {
      final r = (
        outcome: WriteOutcome.missing,
        fresh: _profile(),
        mismatched: const ['price_range'],
      );
      final copy = profileWriteOutcomeCopy(r);
      // "لم يصل" is a claim about delivery. This PATCH was delivered.
      expect(copy.contains('\u0644\u0645 \u064a\u0635\u0644'), isFalse);
      expect(copy, contains(S.fieldPriceRange));
    });
  });

  group('the screen', () {
    late List<({String method, String path, Map<String, dynamic> body})> sent;
    late List<({String path, Map<String, Object?> profile})> reads;
    // Initialised at declaration, not `late`: the closures below read it and
    // Dart's definite-assignment analysis rejects a captured `late` local.
    WorkerProfile stored = _profile();
    /// Fails reads only *after* the PATCH has been sent, so the form still
    /// loads. Breaking the first read would prove nothing about the save: the
    /// screen would be showing its failed-load state instead of a save result.
    bool failReadsAfterPatch = false;
    bool patched = false;

    setUp(() {
      sent = [];
      reads = [];
      stored = _profile();
      failReadsAfterPatch = false;
      patched = false;
    });

    ApiClient api() => ApiClient(
          baseUrls: ['https://x.test'],
          httpClient: MockClient((req) async {
            final p = req.url.path;
            if (req.body.isNotEmpty && p.contains('/my/profile')) {
              sent.add((method: req.method, path: p, body: jsonDecode(req.body)));
            }
            http.Response json(Object b) => http.Response(
                jsonEncode(b), 200,
                headers: {'content-type': 'application/json'});
            if (p.endsWith('/api/login')) {
              return json({
                'token': 'tok',
                'user': {
                  'id': 31,
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
            if (p.contains('/my/profile')) {
              if (req.method == 'PATCH') patched = true;
              reads.add((path: p, profile: _json({
                'full_name': stored.fullName,
                'bio': stored.bio,
                'specialties': stored.specialties,
                'experience_years': stored.experienceYears,
                'price_range_min': stored.priceRangeMin,
                'price_range_max': stored.priceRangeMax,
                'service_radius_km': stored.serviceRadiusKm,
                'is_available': stored.isAvailable,
              })));
              // The PATCH itself must still answer 200 -- that is the whole
              // premise of this file. Only the **verification read** that
              // follows it fails, and only when the test asked for it.
              if (req.method != 'PATCH' &&
                  failReadsAfterPatch &&
                  patched) {
                throw http.ClientException('offline');
              }
              return json(_json({
                'full_name': stored.fullName,
                'bio': stored.bio,
                'specialties': stored.specialties,
                'experience_years': stored.experienceYears,
                'price_range_min': stored.priceRangeMin,
                'price_range_max': stored.priceRangeMax,
                'service_radius_km': stored.serviceRadiusKm,
                'is_available': stored.isAvailable,
              }));
            }
            return json(<Object>[]);
          }),
        );

    Future<AuthState> auth(ApiClient a) async {
      SharedPreferences.setMockInitialValues({});
      final s = AuthState(a);
      await s.restore();
      await s.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      return s;
    }

    Future<void> pump(WidgetTester tester, ApiClient a, AuthState au) async {
      tester.view.physicalSize = const Size(1080, 6400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: AppScope(api: a, auth: au, child: const ProfileEditScreen()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    /// Brings [f] into view on this long, lazy form.
    ///
    /// Pinned to the **outer** scrollable, not `Scrollable.first`: once a field
    /// has focus this form nests further scrollables (the number keypad's own
    /// hint strip on a real device), and `first` can then resolve to one of
    /// them, where the target is not a descendant at all — `scrollUntilVisible`
    /// then dies with «Bad state: No element» on the element it is scrolling.
    /// The form's own list is the one with the `ListView` ancestor.
    Future<void> reveal(WidgetTester tester, Finder f) async {
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(f, 260,
            scrollable: find.byType(Scrollable).first);
      }
      await tester.ensureVisible(f);
      await tester.pump();
    }

    /// Empties a numeric field the way a user empties it: focus it, select all,
    /// delete.
    ///
    /// Deliberately **not** `tester.enterText(f, '')`. That call re-pumps the
    /// whole form, and the availability `SwitchListTile` inside a decorated
    /// `Container` re-raises the framework's ink-splash warning while doing it,
    /// so the warning lands in the middle of the test and arrives wrapped in
    /// the aggregate "Multiple exceptions" message. The product change is not
    /// involved: the same thing happens on a clean tree. Filtering it out here
    /// would be hiding a real signal, and the repo's own profile test lets the
    /// aggregate through for the same reason.
    Future<void> clearField(WidgetTester tester, Finder f) async {
      final text = find.descendant(of: f, matching: find.byType(TextField));
      await tester.tap(text);
      await tester.pump();
      await tester.enterText(text, '1');
      await tester.pump();
      final ctrl = tester.widget<TextField>(text).controller;
      ctrl!.clear();
      await tester.pump();
    }

    /// The one framework warning this screen already carries on main.
    void onlyKnownWarning(WidgetTester tester) {
      for (Object? e = tester.takeException();
          e != null;
          e = tester.takeException()) {
        // Two, both already on main: the availability `SwitchListTile` inside
        // a decorated `Container` (the framework's own ink-splash warning), and
        // the aggregate message the framework raises when it counted more than
        // one. Draining the aggregate leaves the individual one next, so both
        // have to be let through.
        if (!'$e'.contains('ink splashes may be invisible') &&
            !'$e'.contains('Multiple exceptions')) {
          fail('unexpected exception on the profile screen: $e');
        }
      }
    }

    testWidgets(
        'clearing a field puts it in the PATCH body, so the server can clear it',
        (tester) async {
      // Red against the old body builder: the body had no `price_range_min`
      // key at all, so the key was never asserted and the row kept 20000-60000.
      final a = api();
      await pump(tester, a, await auth(a));

      await reveal(tester, find.text('\u0623\u0633\u0639\u0627\u0631\u0643 (\u062f\u062c)'));
      // Three NumberFields on this form, in declaration order: experience,
      // then the price pair. Index 0 is years, so clearing the price range
      // means indices 1 and 2.
      final prices = find.byType(NumberField);
      expect(prices, findsNWidgets(3));
      await clearField(tester, prices.at(1));
      await clearField(tester, prices.at(2));
      onlyKnownWarning(tester);

      // The save button lives in `bottomNavigationBar`, so it is mounted from
      // the first frame and never needs scrolling to. `reveal` would try to
      // scroll to it and throw «Bad state: No element», because a pinned
      // action is not a descendant of the list it does not live inside.
      final save = find.text('\u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641');
      expect(save, findsOneWidget);
      await tester.tap(save);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      onlyKnownWarning(tester);

      final patch = sent.where((r) => r.method == 'PATCH');
      expect(patch, hasLength(1));
      // The key must be PRESENT and null. A missing key is a silent no-op.
      expect(patch.first.body.containsKey('price_range_min'), isTrue,
          reason: 'clearing a field must send an explicit null');
      expect(patch.first.body['price_range_min'], isNull);
      expect(patch.first.body['price_range_max'], isNull);
    });

    testWidgets('a save the server did not take is never reported as saved',
        (tester) async {
      // The server keeps the old price range and answers 200 to the PATCH.
      stored = _profile(min: 20000, max: 60000);
      final a = api();
      await pump(tester, a, await auth(a));

      await reveal(tester, find.text('\u0623\u0633\u0639\u0627\u0631\u0643 (\u062f\u062c)'));
      // Same off-by-one as the case above: the price pair is 1 and 2.
      final prices = find.byType(NumberField);
      await clearField(tester, prices.at(1));
      await clearField(tester, prices.at(2));
      onlyKnownWarning(tester);

      // The save button lives in `bottomNavigationBar`, so it is mounted from
      // the first frame and never needs scrolling to. `reveal` would try to
      // scroll to it and die with «Bad state: No element», because a pinned
      // action is not a descendant of the list it does not live inside.
      final save = find.text('\u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641');
      expect(save, findsOneWidget);
      await tester.tap(save);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      onlyKnownWarning(tester);

      // Red against the old screen: it printed «تم حفظ ملفك بنجاح».
      expect(find.text(S.profileSavedOk), findsNothing);
      // Scoped to the toast: the section header above the two boxes reads
      // «أسعارك (دج)» and contains the same two words, so a bare
      // `textContaining` matches it as well and the assertion would pass for
      // the wrong reason -- or fail while the screen is in fact correct.
      final snack = find.descendant(
          of: find.byType(SnackBar), matching: find.textContaining(S.fieldPriceRange));
      expect(snack, findsOneWidget);
      expect(find.descendant(of: find.byType(SnackBar), matching: find.text(S.profileSavedOk)),
          findsNothing);
    });

    testWidgets('a save the server took is confirmed and the screen pops',
        (tester) async {
      final a = api();
      await pump(tester, a, await auth(a));

      // The save button lives in `bottomNavigationBar`, so it is mounted from
      // the first frame and never needs scrolling to. `reveal` would try to
      // scroll to it and throw «Bad state: No element», because a pinned
      // action is not a descendant of the list it does not live inside.
      final save = find.text('\u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641');
      expect(save, findsOneWidget);
      await tester.tap(save);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      onlyKnownWarning(tester);

      // The save re-reads the row; a screen that never does would pass the
      // two cases above for the wrong reason.
      expect(reads.length, greaterThanOrEqualTo(2),
          reason: 'the save must verify against the server');
      // The form closes on a confirmed save, so the toast that reported it goes
      // with the route. This case therefore asserts the two things that
      // survive the pop; the two cases below assert the sentence, because those
      // screens stay put and the sentence is the whole point of them.
      expect(find.byType(ProfileEditScreen), findsNothing,
          reason: 'a confirmed save closes the form');
      expect(find.text(S.profileSavedOk), findsNothing);
    });

    testWidgets('a verification read that fails never claims a clean save',
        (tester) async {
      // The PATCH answers; the re-read does not. The app must not guess.
      failReadsAfterPatch = true;
      final a = api();
      await pump(tester, a, await auth(a));

      // The save button lives in `bottomNavigationBar`, so it is mounted from
      // the first frame and never needs scrolling to. `reveal` would try to
      // scroll to it and throw «Bad state: No element», because a pinned
      // action is not a descendant of the list it does not live inside.
      final save = find.text('\u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641');
      expect(save, findsOneWidget);
      await tester.tap(save);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      onlyKnownWarning(tester);

      expect(find.text(S.profileSavedUnverified), findsOneWidget);
      expect(find.text(S.profileSavedOk), findsNothing);
    });
  });
}
