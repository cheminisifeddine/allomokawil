// The profile form must not be editable when the profile never loaded.
//
// THE defect: `_load()` catches a failed read, sets `_loading = false` and
// `_error = <sentence>`, and then `build()` renders the **whole form** — every
// box empty. Nothing on that screen says "these boxes are not your values".
// So a contractor who opens «تعديل ملفي» with no signal, or a 500 from
// `/my/profile`, sees a blank form, types nothing but a name, taps
// «حفظ الملف», and the PATCH — which sends **every field unconditionally**,
// null included, by design — overwrites his own biography, his years of
// experience, his price range and his service radius with the empty strings and
// nulls of a form that never held his data. `ProfileSnapshot` then compares the
// server's fresh row against exactly the values that were just destroyed, finds
// no mismatch, and the app prints «تم حفظ ملفك بنجاح».
//
// The verification this screen is proud of cannot catch it: the PATCH and the
// re-read agree, because the phone destroyed the row and the server faithfully
// stored the destruction. A 200 cannot be wrong here, so nothing in
// `profile_write_outcome.dart` is asked to be clever.
//
// Every sibling screen that loads a body renders an `EmptyView` with a retry
// when the read fails (`worker_profile_screen.dart:151`,
// `project_detail_screen.dart:355`, `subscription_screen`). This one was the
// only form in the app that treated a failed read as a successful one.
//
// Run:  flutter test test/profile_load_failure_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/data/profile_write_outcome.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/screens/worker/profile_edit_screen.dart';

Map<String, Object?> _profileJson() => <String, Object?>{
      'id': 124,
      'user_id': 392,
      'full_name': '\u0639\u0645\u064a \u0631\u0634\u064a\u062f',
      'bio': '\u0628\u0646\u0627\u0621 \u0648\u062a\u0634\u0637\u064a\u0628',
      'specialties': ['painting'],
      'experience_years': 5,
      'price_range_min': 20000,
      'price_range_max': 60000,
      'service_radius_km': 30,
      'is_available': 1,
      'verification_status': 'verified',
      'avg_rating': 4.5,
      'total_reviews': 3,
      'total_completed_jobs': 7,
      'is_identity_verified': 1,
      'is_certificate_verified': 0,
      'user_wilaya': '16',
    };

/// An API whose `GET /my/profile` answers 500, and that records the PATCH.
ApiClient _brokenApi(List<Map<String, dynamic>> patches) => ApiClient(
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
        if (req.url.path.contains('/my/profile')) {
          if (req.method == 'PATCH') {
            patches.add(jsonDecode(req.body));
            return json(_profileJson());
          }
          // THE failure. The read the form is built from.
          return json({'error': 'boom'}, 500);
        }
        return json(<Object>[]);
      }),
    );

Future<AuthState> _auth(ApiClient a) async {
  SharedPreferences.setMockInitialValues({});
  final s = AuthState(a);
  await s.restore();
  await s.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return s;
}

void main() {
  late List<Map<String, dynamic>> patches;

  setUp(() => patches = []);

  Future<void> pumpScreen(WidgetTester tester, ApiClient a, AuthState au) async {
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

  /// The one framework warning this screen already carries on main: the
  /// availability `SwitchListTile` inside a decorated `Container`. It is a
  /// paint-order note, not a layout failure, and both existing profile tests
  /// drain it for the same reason. Filtered **only** so a real layout failure
  /// in the retry path stays loud.
  void drainKnownWarnings(WidgetTester tester) {
    for (Object? e = tester.takeException();
        e != null;
        e = tester.takeException()) {
      if (!'$e'.contains('ink splashes may be invisible') &&
          !'$e'.contains('Multiple exceptions')) {
        fail('unexpected exception on the profile screen: $e');
      }
    }
  }

  testWidgets('a failed load shows a retry, not an empty form to save',
      (tester) async {
    final a = _brokenApi(patches);
    await pumpScreen(tester, a, await _auth(a));

    // The sentence is on screen, so the user knows the form below it is not
    // showing his values. Red against the old screen: this text existed only in
    // the pinned footer, in `fsMeta` red type under a live save button, next to
    // a fully editable blank form.
    expect(find.text('\u062a\u0639\u0630\u0651\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0645\u0644\u0641'),
        findsOneWidget);

    // And the retry every sibling screen offers on a dead read.
    final retry = find.text('\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629');
    expect(retry, findsOneWidget);

    // THE invariant. Not one of these boxes is the user's data, so not one of
    // them may be editable: a form this screen knows it could not fill must not
    // accept a save.
    expect(find.text('\u0627\u0644\u0623\u0633\u0645 \u0627\u0644\u0638\u0627\u0647\u0631'), findsNothing,
        reason: 'an unfilled form must not present the profile field');
    expect(find.byType(TextField), findsNothing);
    expect(find.text('\u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641'), findsNothing,
        reason: 'a save the app cannot verify must not be offered');
  });

  test('the PATCH an unloaded form would send destroys the stored row',
      () async {
    // WHY the gate above exists, proven at the only level that can prove it.
    //
    // `updateMyProfile` sends every form field **unconditionally, null
    // included** -- a cleared box is a decision, and that is the behaviour the
    // PATCH-200 lie fix depends on. The consequence is the other half: a form
    // that never loaded is a form whose boxes are empty, so the same correct
    // behaviour writes '' and null over a real biography, a real experience
    // count, a real price range and a real service radius. There is no
    // client-side rule that can tell those two cases apart -- both are "the user
    // left the box empty" -- which is exactly why the refusal has to be the
    // screen refusing to offer a save at all.
    final sent = <String, dynamic>{};
    final a = ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        if (req.method == 'PATCH') {
          sent.addAll(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(_profileJson()), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode(_profileJson()), 200,
            headers: {'content-type': 'application/json'});
      }),
    );

    // Every value an unloaded `ProfileEditScreen` holds: empty controllers, the
    // canonical 30 km default, availability on, and no specialties picked.
    await Repository(a).updateMyProfile(
      fullName: 'x',
      bio: '',
      specialties: const [],
      experienceYears: 0,
      priceRangeMin: null,
      priceRangeMax: null,
      serviceRadiusKm: 30,
      isAvailable: true,
    );

    // The keys are PRESENT -- that is the design, and it is why the old screen
    // was destructive rather than merely useless. A missing key would have been
    // a no-op; an explicit null is an instruction to clear the column.
    expect(sent.containsKey('bio'), isTrue);
    expect(sent['bio'], '');
    expect(sent.containsKey('price_range_min'), isTrue);
    expect(sent['price_range_min'], isNull);
    expect(sent.containsKey('price_range_max'), isTrue);
    expect(sent['price_range_max'], isNull);
    expect(sent['experience_years'], 0);
    expect(sent['specialties'], isEmpty);
    expect(sent['is_available'], isTrue);

    // What that does to the row the server is holding: 5 years, 20000-60000 دج
    // and a biography, all replaced. `ProfileSnapshot` then re-reads and finds
    // the server agreeing with the phone -- the destruction *was* saved, so the
    // verification this screen is built on reports a clean save.
    final after = ProfileSnapshot.of(WorkerProfile.fromJson(_profileJson()));
    expect(after.mismatches(ProfileSnapshot.form(
      fullName: 'x',
      bio: '',
      specialties: const {},
      experienceYears: 0,
      priceRangeMin: null,
      priceRangeMax: null,
      serviceRadiusKm: 30,
      isAvailable: true,
    )), contains('price_range'));
  });

  testWidgets('the retry re-reads, and a good read restores the form',
      (tester) async {
    // The other half of a dead end: a retry that does not re-read would leave
    // the user with a button and no way back. This is the exact state
    // `worker_profile_screen` and `subscription_screen` already handle.
    var fail = true;
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
        if (req.url.path.contains('/my/profile')) {
          if (fail) return json({'error': 'boom'}, 500);
          return json(_profileJson());
        }
        return json(<Object>[]);
      }),
    );
    final au = await _auth(a);
    await pumpScreen(tester, a, au);
    expect(find.text('\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'), findsOneWidget);

    // The network comes back, and the user presses the one control he has.
    fail = false;
    await tester.tap(find.text('\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    drainKnownWarnings(tester);

    // The form is back, with **his** values in it, not empty ones.
    final name = tester.widget<TextField>(find.byType(TextField).first);
    expect(name.controller!.text, '\u0639\u0645\u064a \u0631\u0634\u064a\u062f');
    expect(find.text('\u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641'), findsOneWidget);
  });
}
