// What actually reaches the API when the account form is filled in.
//
// **This file exists because the value a phone number takes on the wire was
// never observed by anything.** `phone_field.dart:30` promises, in a docstring
// a new screen copies:
//
// ```text
//   The controller is owned by the screen (the screens read it on submit), and
//   the digits it holds are grouped for display — always send
//   `DzPhone.canonical(controller.text)` to the API.
// ```
//
// A promise in a comment is enforced by the next person editing it. And the
// test that looks closest to enforcing it **defines the answer instead of
// reading it**: `dz_phone_keystrokes_test.dart:68` is
//
// ```dart
// String postedFor(String fieldText) => DzPhone.canonical(fieldText);
//
// … expect(postedFor(field), '0550123456', reason: 'this is the value that
//                                    reaches the API for "$form"');
// ```
//
// which is `expect(DzPhone.canonical(field), '0550123456')` wearing a comment
// that claims it is an end-to-end claim. It asserts that `canonical` behaves
// like `canonical`. **`auth_screen.dart` is not in that expression.** If the
// submit path posted `controller.text` raw — `'05 50 12 34 56'`, spaces and all
// — or `_phone.text.trim()`, or skipped the fold entirely, every assertion in
// that file stays green, because the file never asks the screen what it sends.
// It is the same defect `header_trust_wiring_test.dart` was written for: the
// mechanism was exercised by tests that constructed the wiring themselves
// instead of by the production path, so a green gate proved the function works,
// which is a different claim from "the function is connected".
//
// So the harness here is deliberately the **production path**: the real
// `AuthScreen`, the real `AuthState`, the real `ApiClient`, and a `MockClient`
// that **captures the request body it is handed**. The number under test is
// read off `req.body` — the bytes that would go to `/api/register` — and not
// recomputed from a helper this file also imports.
//
// Both halves are covered, because `auth_screen.dart` posts the number on two
// different lines (`:116` sign-in, `:158` sign-up) and a future screen may add a
// third: [every screen that posts a phone posts the canonical one] sweeps
// `lib/src` for `phone:` arguments and fails on any that is not canonicalised,
// so the rule is not just "the two shipped call sites happen to be right".
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/screens/auth/auth_screen.dart';

/// The customer row a successful auth answer has to carry.
const _user = {
  'id': 7,
  'phone': '0550123456',
  'email': '',
  'full_name': 'رقم الهاتف',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': null,
  'commune': null,
  'created_at': '2026-01-01 00:00:00',
};

/// Every way a real Algerian mobile reaches the field, typed in full by hand.
///
/// Deliberately the same table `dz_phone_keystrokes_test.dart` drives — this
/// file re-types them through the **screen**, so the two files are only worth
/// having if the answer on the wire is the same one the formatter produced.
const _ways = <String, String>{
  '0550123456': '0550123456',
  '550123456': '0550123456', // zero dropped, saved internationally
  '213550123456': '0550123456', // country code, no separator
  '00213550123456': '0550123456',
  '+213 550 12 34 56': '0550123456',
  '00213 550 12 34 56': '0550123456',
  '٠٥٥٠١٢٣٤٥٦': '0550123456', // Arabic-Indic keyboard
  '۰۵۵۰۱۲۳۴۵۶': '0550123456', // Extended-Arabic keyboard
};

/// A capture of the last auth body the API was handed.
class _Capture {
  String? path;
  Map<String, dynamic>? body;

  String? phone() => body?['phone'] as String?;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps the real [AuthScreen] over a client that records the auth POST.
  Future<_Capture> submit(
    WidgetTester tester, {
    required String typed,
    required AuthMode mode,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _Capture();

    final api = ApiClient(
      httpClient: MockClient((req) async {
        if (req.url.path == '/api/register' ||
            req.url.path == '/api/login') {
          capture.path = req.url.path;
          capture.body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'token': 'test-token', 'user': _user}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }),
      baseUrls: ['https://x.test'],
    );

    final auth = AuthState(api);
    await auth.restore();
    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
      child: MaterialApp(home: AuthScreen(mode: mode)),
    ));
    await tester.pumpAndSettle();

    // Through the **field**, not around it: the formatter runs, so what the
    // screen holds is what the user sees.
    await tester.enterText(find.byKey(const Key('dz-phone-input')), typed);
    if (mode == AuthMode.signUp) {
      await tester.enterText(
          find.byType(TextField).first, 'زبون تجريبي'); // the name field
    }
    await tester.enterText(
        find.byKey(const Key('auth-password')), 'secret123');
    await tester.pump();

    // The submit button sits below the fold of the default 800x600 test
    // surface, and `tap()` on an off-screen widget silently hits nothing: the
    // first run of this file reported `capture.path == null` for every entry
    // and looked like a fold failure rather than a tap that never landed.
    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();

    return capture;
  }

  group('the number on the wire is the one the field promised', () {
    for (final mode in AuthMode.values) {
      for (final way in _ways.entries) {
        testWidgets('${mode.name}: "${way.key}" posts ${way.value}',
            (tester) async {
          final capture =
              await submit(tester, typed: way.key, mode: mode);

          expect(capture.path, isNotNull,
              reason: 'the form never reached the API — the account was not '
                  'created or the sign-in was not attempted.');
          expect(capture.phone(), way.value,
              reason: 'this is the number that would be stored against the '
                  'account. The field shows one number, so the API must receive '
                  'that number, not a spaced or folded variant of it.');
        });
      }
    }
  });

  group('a number the field refuses never reaches the wire', () {
    // The other half of the promise, and the one that was never written down:
    // the screen's own `isValid` gate. If the field is showing «رقم الهاتف غير
    // صحيح», the POST must not happen — a rejected number posted anyway is how a
    // user ends up with «الرقم مسجل مسبقاً» for a number they were told was
    // wrong. `auth_screen.dart` gates both submit paths on
    // `DzPhone.isValid(_phone.text)`, and nothing below tests that.
    for (final bad in <String, String>{
      '0212345678': 'landline (02x) \u2014 the API takes mobiles only',
      '0850123456': 'not an Algerian operator prefix',
      '055012345': 'one digit short',
    }.entries) {
      testWidgets('${bad.key} (${bad.value}) is never posted', (tester) async {
        SharedPreferences.setMockInitialValues({});
        var posts = 0;
        final api = ApiClient(
          httpClient: MockClient((req) async {
            if (req.url.path == '/api/register' ||
                req.url.path == '/api/login') {
              posts++;
            }
            return http.Response('[]', 200,
                headers: {'content-type': 'application/json'});
          }),
          baseUrls: ['https://x.test'],
        );
        final auth = AuthState(api);
        await auth.restore();
        await tester.pumpWidget(AppScope(
          api: api,
          auth: auth,
          child: const MaterialApp(home: AuthScreen()),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(
            find.byKey(const Key('dz-phone-input')), bad.key);
        await tester.enterText(
            find.byType(TextField).first, 'زبون تجريبي');
        await tester.enterText(
            find.byKey(const Key('auth-password')), 'secret123');
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();

        expect(posts, 0,
            reason: 'a number the app itself calls invalid (${bad.value}) was '
                'posted anyway. The server would answer with a second, different '
                'sentence about a number the user was already told is wrong.');
      });
    }
  });

  group('no screen posts a phone it did not canonicalise', () {
    // The rule as a property of `lib/`, so a **third** screen inherits it. A
    // test that only drives the two shipped call sites is a test that goes green
    // the moment somebody adds a third one wrong.
    //
    // `phone_field.dart:30` is a comment; this is the reader that makes the
    // comment true on every future screen that posts a number.
    test('every `phone:` argument is folded through DzPhone', () {
      final offenders = <String>[];
      final seen = <String>[];

      final dirs = Directory('lib/src');
      final files = dirs
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Comments are not call sites, and `dz_phone.dart`'s own docstring
          // quotes the rule at length — reading prose as code is the mistake
          // `app_source_scope_test.dart` documents twice.
          final code = line.trim();
          if (code.isEmpty || code.startsWith('//')) continue;
          final m = RegExp(r'^\s*phone:\s*(.+?),?\s*$').firstMatch(line);
          if (m == null) continue;
          final value = m.group(1)!.replaceAll(RegExp(r',$'), '').trim();
          // The reading of a JSON column is not an outgoing phone.
          if (value.contains("json[")) continue;
          seen.add('${file.path}:${i + 1}  phone: $value');
          if (!RegExp(r'DzPhone\.canonical\w*\s*\(').hasMatch(value)) {
            offenders.add('${file.path}:${i + 1}\n'
                '    phone: $value\n'
                '    this is not folded through DzPhone, so whatever it holds is '
                'what the server receives.');
          }
        }
      }

      expect(seen, isNotEmpty,
          reason: 'the sweep found no `phone:` argument at all, so it is '
              'reading nothing and would pass on a tree that posts raw numbers '
              'everywhere.');
      expect(offenders, isEmpty,
          reason: 'these call sites post a phone number without canonicalising '
              'it. `phone_field.dart` asks for `DzPhone.canonical`; a raw '
              '`controller.text` carries the display spaces, and a bare field '
              'string is what the field only *promises* is foldable:\n'
              '${offenders.join('\n')}\n'
              'Seen:\n${seen.join('\n')}');
    });
  });
}
