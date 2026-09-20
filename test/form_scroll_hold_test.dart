// A picker is a detour, not a new page: coming back must land where the reader
// was standing.
//
// The founder, verbatim:
//   «2 when i choise a wilaya or city i get scrolled up to the top of the page
//    fix it stay at the dame place after i shouse»
//
// Two mechanisms hold the place, and each has its own test below:
//   * the form's text field is unfocused before the sheet opens — a returning
//     focus is what made Flutter scroll that field (the form's first one, at the
//     top) back into view when the sheet closed;
//   * the offset is measured before the sheet and put back after it, so even a
//     keyboard that resized the page mid-detour cannot move the reader.
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

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

Future<({ApiClient api, AuthState auth})> _boot() async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p == '/api/unread') return _json(0);
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  return (api: api, auth: auth);
}

Future<void> _pumpForm(WidgetTester tester, ApiClient api, AuthState auth) async {
  // A real phone: the form is taller than the screen, which is the only reason
  // scrolling (and therefore losing the place) is possible at all.
  tester.view.physicalSize = const Size(392, 850) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: AppScope(api: api, auth: auth, child: const ProjectNewScreen()),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// The live offset of the form itself, read off its own controller.
double _offset(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
    .controller!
    .offset;

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 220,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Taps the wilaya picker and lets the sheet finish sliding in.
///
/// Bringing the field into view is the caller's job: that scroll is part of
/// what the form is allowed to do, and the offset is read after it.
Future<void> _openWilayaSheet(WidgetTester tester) async {
  await tester.tap(find.text('اختر الولاية'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('choosing a wilaya leaves the form exactly where it was',
      (tester) async {
    final s = await _boot();
    await _pumpForm(tester, s.api, s.auth);

    // Scroll a good way down the form, the way a thumb would, then bring the
    // picker back into view — and only then read the place to hold on to.
    await _reveal(tester, find.text('اختر الولاية'));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -260));
    await tester.pump();
    await tester.ensureVisible(find.text('اختر الولاية'));
    await tester.pump();
    final before = _offset(tester);
    expect(before, greaterThan(0),
        reason: 'the form has to actually be scrolled for this to mean anything');

    await _openWilayaSheet(tester);

    // Filtering is how a 58-item list is used; it also keeps the tap honest.
    await tester.enterText(find.byType(TextField).last, 'وهران');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('وهران').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(_offset(tester), closeTo(before, 0.5),
        reason: 'the sheet is a detour: the form stays where the reader left it');
  });

  testWidgets('the picker opens with the form field unfocused', (tester) async {
    final s = await _boot();
    await _pumpForm(tester, s.api, s.auth);

    final title = find.byType(TextField).first;
    await tester.tap(title);
    await tester.pump();
    final node = tester
        .state<EditableTextState>(
            find.descendant(of: title, matching: find.byType(EditableText)))
        .widget
        .focusNode;
    expect(node.hasFocus, isTrue, reason: 'the tap must focus the title field');

    await _reveal(tester, find.text('اختر الولاية'));
    await _openWilayaSheet(tester);

    expect(node.hasFocus, isFalse,
        reason: 'a field that keeps focus is what scrolls the form back to the '
            'top the moment the sheet closes');
  });
}
