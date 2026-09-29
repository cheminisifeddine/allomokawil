// A typo in the wilaya picker locked the customer out of posting their
// project, and the sheet that locked them in said only «لا توجد نتائج».
//
// Found 29 Sep 2026 by an audit of the two sibling pickers. The **commune**
// picker, thirty lines below in the same file, got this right:
//
//   * a «مسح البحث» clear button on the search field,
//   * an empty state that names the actual situation
//     («لا توجد بلدية بهذا الاسم»),
//   * and a «استعمل "…" كما كتبتها» escape hatch, because "the dataset must
//     never be the reason a project cannot be posted" (the file's own words).
//
// The **wilaya** picker had none of the three. No clear button, so the search
// text cannot be undone without dismissing the sheet and reopening it; a bare
// «لا توجد نتائج» heading; no escape. And unlike the commune, the wilaya is
// **required** — `project_new_screen.dart:247` refuses to post while
// `_wilaya == null`. So the trap is total: the user types a typo (a Latin
// keyboard, a missing hamza, a dotless ي), the list empties, and the one field
// standing between them and posting their project has no way out and no
// explanation of what went wrong.
//
// The same sheet is the app's first-run path — 58 wilayas is too many to hunt
// through blind, which is why it is a searchable sheet at all — so a
// mistyped search is an ordinary thing to do, not an edge case.
//
// These tests pin the three ways out.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

const _user = {
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'عميل تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': null,
  'commune': null,
  'created_at': '2026-09-11 20:00:00',
};

ApiClient _fakeApi() => ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/api/login') ||
            req.url.path.endsWith('/api/register')) {
          return _json({'token': 'tok', 'user': _user});
        }
        return _json(<Object>[]);
      }),
    );

Future<({ApiClient api, AuthState auth})> _boot() async {
  SharedPreferences.setMockInitialValues({});
  final api = _fakeApi();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _pump(WidgetTester tester, ApiClient api, AuthState auth) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: AppScope(api: api, auth: auth, child: const ProjectNewScreen()),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 260,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Opens the wilaya sheet, types [query] into it and leaves it in the state
/// the user is actually looking at: an empty list.
Future<void> _trap(WidgetTester tester, ApiClient api, AuthState auth,
    String query) async {
  await _pump(tester, api, auth);
  await _reveal(tester, find.text('اختر الولاية'));
  await tester.tap(find.text('اختر الولاية'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.enterText(
    find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(TextField)),
    query,
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('the empty wilaya search names the situation, not "no results"',
      (tester) async {
    final s = await _boot();
    await _trap(tester, s.api, s.auth, 'alger');

    // `alger` is a Latin-keyboard guess at الجزائر, and it matches nothing.
    // («الجزاير» would NOT reach this state: the folder folds the hamza away
    // by design, so a hamza typo is already handled. The trap needs a query
    // that genuinely misses — which on a French/Latin keyboard in Algeria is
    // the common one.)
    //
    // Before: «لا توجد نتائج» — a claim that a search was run against
    // something, for a list of 58 names the user was looking at a second ago.
    expect(find.text('لا توجد نتائج'), findsNothing);
    expect(find.text('لا توجد ولاية بهذا الاسم'), findsOneWidget);
  });

  testWidgets('the wilaya search can be cleared from inside the sheet',
      (tester) async {
    final s = await _boot();
    await _trap(tester, s.api, s.auth, 'alger');

    // The commune picker already ships this control (tooltip «مسح البحث»).
    // Without it the only way back to 58 names is dismiss-and-reopen.
    final clear = find.byIcon(Icons.close_rounded);
    expect(clear, findsOneWidget,
        reason: 'a search the user cannot undo is a one-way door');
  });

  testWidgets('clearing the search brings all 58 wilayas back',
      (tester) async {
    final s = await _boot();
    await _trap(tester, s.api, s.auth, 'alger');

    // Trapped: no wilaya row is built, because the fold matches nothing.
    expect(find.text('الجزائر'), findsNothing);
    expect(find.byType(ListTile), findsNothing);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(const Duration(milliseconds: 200));

    // Not just «a button that exists» — both halves of what it promised: the
    // query is gone from the field, and the 58 names are back.
    final field = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field.controller.text, isEmpty);
    expect(find.text('لا توجد ولاية بهذا الاسم'), findsNothing);
    expect(find.text('الجزائر'), findsOneWidget);
  });
}
