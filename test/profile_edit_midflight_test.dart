// `profile_edit_screen.dart` — the last file in the write-vs-form class.
//
// Two ticks ago the publish form was found sending whatever was on screen when
// the upload finished (`da876a3`); yesterday the review screen was found
// judging its recheck against the picker's **live** value (`62fe62c`). Both were
// invisible on a healthy connection and only appeared on the path where the
// write's answer is in doubt. This file is the third member of that class, and
// the backlog predicted — from reading the code — that this one would come out
// **correct**: `_save` reads the entire form in one synchronous block, builds
// `ProfileSnapshot.form` from those locals, and only then `await`s the PATCH.
//
// A prediction is not evidence, and a class this quiet is exactly the class
// where a wrong "it's fine" survives for a year. So this test drives the real
// screen against a real mid-flight edit and reads what the PATCH body held and
// which verdict the screen reached.
//
// The shape, if the screen ever regresses: `_save` builds `sent` *after* the
// PATCH returns, from live state. The contractor presses save with one name and
// changes his mind while the request is still open. The verification read then
// compares the server's stored row against a snapshot of the form he is no
// longer looking at, the name reads as a mismatch, and the screen refuses to
// close and tells him — in Arabic, about his own name — that the field was not
// saved. The save was fine. The measurement was not.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/screens/worker/profile_edit_screen.dart';

/// The name the form holds when the save button is pressed.
const _pressed = 'علي بن علي';
/// The name typed into the box **while the PATCH is still open**.
const _midflight = 'محمد amps';

/// A row as `WorkerProfile.fromJson` reads it.
Map<String, Object?> _row(String name, {String? bio = 'بناء وتشطيب'}) =>
    <String, Object?>{
      'id': 16,
      'user_id': 31,
      'full_name': name,
      'bio': bio,
      'specialties': const ['painting'],
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

void main() {
  testWidgets(
      'a name typed after the save was pressed cannot change what the PATCH '
      'sent, or which verdict the screen reaches', (tester) async {
    // Held open for as long as the test likes: this is the window in which the
    // form is still live and the answer is still in flight.
    final gate = Completer<void>();
    var name = 'عمي رشيد';
    final patches = <Map<String, dynamic>>[];

    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      // Long enough that the gate, not the clock, is what ends the request.
      timeout: const Duration(seconds: 30),
      httpClient: MockClient((req) async {
        http.Response json(Object b) => http.Response(
            jsonEncode(b), 200,
            headers: {'content-type': 'application/json'});
        if (req.url.path.endsWith('/api/login')) {
          return json({
            'token': 'tok',
            'user': {
              'id': 31,
              'phone': '0773000000',
              'email': null,
              'full_name': 'مستخدم',
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
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            patches.add(body);
            // The server stores what it was actually sent…
            name = body['full_name'] as String;
            // …and the answer is slow. Everything the contractor does to the
            // form in this window happens *after* the row is already decided.
            await gate.future;
          }
          return json(_row(name));
        }
        return json(<Object>[]);
      }),
    );

    SharedPreferences.setMockInitialValues({});
    final auth = AuthState(api);
    await auth.restore();
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);

    tester.view.physicalSize = const Size(1080, 6400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: AppScope(api: api, auth: auth, child: const ProfileEditScreen()),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    drainKnownWarnings(tester);

    // Type the name the save is about to be pressed with. The name field is the
    // first control on the form, so nothing has to be scrolled to reach it.
    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, _pressed);
    await tester.pump();
    drainKnownWarnings(tester);

    // The save button is pinned in `bottomNavigationBar`, so it is mounted from
    // the first frame and is never a descendant of the form's list.
    final save = find.text('حفظ الملف');
    expect(save, findsOneWidget);
    await tester.tap(save);
    await tester.pump();
    drainKnownWarnings(tester);

    // Mid-flight: the PATCH is open, the row is already stored, and the form is
    // still live. This is the whole test — everything above it is setup.
    expect(patches, hasLength(1), reason: 'the PATCH must be in flight now');
    await tester.enterText(nameField, _midflight);
    await tester.pump();
    drainKnownWarnings(tester);
    // Prove the edit really landed on a live form, so the rest cannot pass
    // because the tap missed an off-screen widget.
    expect(tester.widget<TextField>(nameField).controller!.text, _midflight,
        reason: 'the form must still accept input while the save is open');

    // The answer arrives, and the server answers with the row it stored.
    gate.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    drainKnownWarnings(tester);

    // What the server was sent is the name from the moment save was pressed.
    expect(patches.first['full_name'], _pressed,
        reason: 'the PATCH body is the row as the form held it at press time');

    // And the verdict is reached against that same capture, so a confirmed save
    // closes the form. Under a snapshot rebuilt from live state after the
    // await, the stored name reads as a mismatch: the screen would stay put and
    // name the field — «لم يحفظ الحقل: الاسم الظاهر» — about a save that
    // worked.
    expect(find.byType(ProfileEditScreen), findsNothing,
        reason: 'a verified save closes the form even if the box moved on');
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text(S.fieldName)),
      findsNothing,
      reason: 'the mid-flight edit must not be reported as an unsaved field',
    );
  });
}

/// The two framework warnings this screen already carries on main: the
/// availability `SwitchListTile` inside a decorated `Container` re-raises the
/// ink-splash warning whenever the form re-pumps, and the framework's own
/// aggregate message when it counted more than one. Both are on main, so both
/// are let through — and anything else fails the test rather than being
/// filtered into silence.
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
