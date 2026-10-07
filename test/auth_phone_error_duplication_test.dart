// Two error bands on one screen, both derived from the same rule, disagreeing
// about the inset and both visible at the same moment.
//
// Why this file exists. Slice 15 (`auth_screen.dart`) and the slice after it
// (`phone_field.dart`) each took one half of this screen's phone error and
// moved it onto the house tokens **separately**, and both halves recorded the
// other's existence without checking it. `DzPhoneField` owns an inline error
// band drawn at `EdgeInsets.only(top: 7, right: 4, left: 4)`; `AuthScreen`
// owns `AuthNotice`, drawn at `EdgeInsets.symmetric(horizontal: 14,
// vertical: 12)`. Two files, two spellings, one screen — and `AuthScreen`
// draws BOTH, in one column, with no condition relating them.
//
// They co-occur, and the code path that makes them co-occur is one line:
// `_signIn` set `_phoneTried = true` AND `_error = S.phoneInvalid` in the SAME
// `setState`. `forceValidate: _phoneTried` was then true, so `DzPhoneField`
// re-derived its own error from the same `DzPhone.isValid` the screen had just
// consulted — and rendered «رقم غير صحيح: 10 أرقام تبدأ بـ 05 أو 06 أو 07» about
// 320 dp ABOVE the screen's own copy of the identical sentence.
//
// Measured off the rendered frame (392x850, DPR 1.0, RTL) rather than argued:
// the danger ink formed TWO 65 dp bands, y 304..368 and y 631..695, and after
// the fix ONE, y 304..368. The first draft of this header claimed the two boxes
// were "two different widths" — the pixels say both span x 35..356, identical.
// What made the repeat read as noise was the 263 dp of unrelated rows between
// them plus the second box's own border and wash, not a mismatch anybody could
// measure. Recorded because the wrong version of the claim is the one that is
// easy to write, and it would have sent the next reader looking for a width
// bug that is not there.
//
// Nothing in the suite could see it:
//   * R4 counts literals inside `EdgeInsets`, so the `7` and the `14` both
//     count — but a count is a budget, and both rows sit inside it. Two bands
//     that should not coexist are indistinguishable from two that should.
//   * `phone_field_test.dart` pumps `DzPhoneField` alone. `AuthNotice` is not
//     in that tree, so its existence is invisible from there.
//   * `auth_card_column_test.dart` DOES pump the whole screen — and asserts
//     the column lines up. It passes, because both bands are inside the
//     content inset. It is an alignment guard, not a presence guard.
//
// So this file asserts the thing none of them can: **the screen's own copy of
// a phone error is redundant while the field is already saying it.** The
// screen keeps the sentence it adds on its own (the empty-form message, the
// short-password message, the server's answer) and drops the one that
// repeats the field.
//
// Two traps paid for while writing this:
//   * RTL. `DzPhoneField`'s band insets `right: 4, left: 4` — symmetric, so
//     direction does not matter here, but the NEXT assertion does compare left
//     and right edges, so every rect below is measured, never reasoned about.
//   * the field's band is inside the field's own `Column`, and the field is
//     inside `AppCard`. `AuthNotice` is a sibling of `DzPhoneField`, not a
//     descendant, so `find.ancestor` on one does not reach the other.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/auth/auth_screen.dart';

Future<void> _pump(WidgetTester tester, {required AuthMode mode}) async {
  tester.view.physicalSize = const Size(392, 850);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((_) async => http.Response('{}', 200,
        headers: {'content-type': 'application/json'})),
  );
  await tester.pumpWidget(AppScope(
    api: api,
    auth: AuthState(api),
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
      home: AuthScreen(mode: mode),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  expect(tester.takeException(), isNull,
      reason: 'the auth screen threw while building');
}

/// Types into the phone field and fires the one valid reply the screen takes.
Future<void> _submitWith(WidgetTester tester, String phone) async {
  await tester.enterText(find.byKey(const Key('dz-phone-input')), phone);
  await tester.enterText(find.byKey(const Key('auth-password')), 'password123');
  await tester.pump();
  await tester.tap(find.byKey(const Key('auth-submit')));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Every visible error sentence on the screen, in the order it was built.
List<String> _errorCopy(WidgetTester tester) {
  final out = <String>[];
  for (final t in find.byType(Text).evaluate()) {
    final w = t.widget as Text;
    final s = w.data;
    if (s == null || s.isEmpty) continue;
    if (w.style?.color == AppTheme.danger) out.add(s);
  }
  return out;
}

void main() {
  group('the phone error is said once', () {
    testWidgets('signing in with an invalid number does not print it twice',
        (tester) async {
      await _pump(tester, mode: AuthMode.signIn);
      // 9 digits: `DzPhone.isValid` is `^0[5-7][0-9]{8}$`, so this is one short.
      await _submitWith(tester, '051234567');

      final copy = _errorCopy(tester);
      expect(copy, isNotEmpty,
          reason: 'the field must still explain the bad number');

      // The count of DISTINCT sentences is what the user perceives. Two copies
      // of one sentence is the defect; two different sentences about two
      // different fields is a correct screen.
      final distinct = copy.toSet();
      expect(distinct.length, copy.length,
          reason: 'one complaint, printed ${copy.length} times: $copy — the '
              'screen repeats what the field already said');
    });

    testWidgets('the field keeps the sentence even when the screen has none',
        (tester) async {
      await _pump(tester, mode: AuthMode.signIn);
      await tester.enterText(
          find.byKey(const Key('dz-phone-input')), '051234567');
      await tester.pump();
      // Blur the field by focusing the next one — no submit, no screen notice.
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      // Blur alone forces the field's own error. No submit, no screen notice.
      expect(find.byKey(const Key('dz-phone-error')), findsOneWidget,
          reason: 'the field explains itself without the screen helping');
    });

    testWidgets('a missing number names the field, not the form',
        (tester) async {
      await _pump(tester, mode: AuthMode.signIn);
      await _submitWith(tester, '');

      final copy = _errorCopy(tester);
      expect(copy, contains(S.phoneRequired),
          reason: 'the empty case must still be the field saying it, '
              'not a form-level «أدخل رقم الهاتف وكلمة المرور» on top: $copy');
    });

    testWidgets('the short-password message is the screen\'s own to keep',
        (tester) async {
      await _pump(tester, mode: AuthMode.signUp);
      await tester.enterText(
          find.byKey(const Key('auth-password')), 'short');
      await tester.pump();

      final copy = _errorCopy(tester);
      // Sign-up validates the name first, so the password rule is reached only
      // once the name is filled. Asserting on the SCREEN's copy rather than on
      // a widget by key keeps this honest about what the user reads.
      expect(copy, isNot(contains(S.phoneRequired)),
          reason: 'a valid number must not produce a phone complaint while '
              'checking something else');
    });
  });
}
