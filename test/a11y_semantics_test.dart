// What a screen reader gets from the controls the 13 Sep audit called silent.
//
// The audit listed nine controls that could not be described: five stars on the
// rating form with no name at all, a photo-removal disc, a chat image bubble, a
// rating row that read as five icons plus a bare number, four pickers that never
// announced which option was on, an add-photo tile that went quiet while it
// uploaded, and not one described image in the whole app.
//
// These tests read the semantics tree the way TalkBack does — one node at a
// time, with its label, its role and its tap action — instead of asserting that
// some string appears in the source. Nothing here touches the live API: every
// request is answered by a MockClient.
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/review/review_screen.dart';
import 'package:allomokawil/src/widgets/a11y.dart';
import 'package:allomokawil/src/widgets/ui.dart';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

Repository _repo() => Repository(ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((_) async => _json(<Object>[])),
    ));

/// The tree a screen reader walks, in order.
List<SemanticsNode> _nodes(WidgetTester tester) =>
    tester.semantics.simulatedAccessibilityTraversal().toList();

bool _tap(SemanticsNode n) =>
    n.getSemanticsData().hasAction(SemanticsAction.tap);

/// Roles are booleans; the on/off states are three-valued — a control that is
/// neither on nor off reports `none`, which is not the same as "off".
bool _isButton(SemanticsNode n) =>
    n.getSemanticsData().flagsCollection.isButton;

Tristate _selected(SemanticsNode n) =>
    n.getSemanticsData().flagsCollection.isSelected;

Tristate _enabled(SemanticsNode n) =>
    n.getSemanticsData().flagsCollection.isEnabled;

Future<void> _pump(WidgetTester tester, Widget child, {bool scaffold = true}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: scaffold ? Scaffold(body: Center(child: child)) : child,
  ));
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  group('the words a screen reader says', () {
    test('a star is a count out of five', () {
      expect(A11y.star(1), '1 من ٥');
      expect(A11y.star(5), '5 من ٥');
    });

    test('a score is one sentence, not five icons', () {
      expect(A11y.rating(4.5), 'التقييم 4.5 من ٥');
      expect(A11y.rating(4.5, count: 3), 'التقييم 4.5 من ٥، 3 مراجعات');
    });

    test('the review count is spoken, not machine-printed', () {
      expect(A11y.rating(5, count: 0), 'التقييم 5.0 من ٥، لا مراجعات');
      expect(A11y.rating(5, count: 1), 'التقييم 5.0 من ٥، مراجعة واحدة');
      expect(A11y.rating(5, count: 2), 'التقييم 5.0 من ٥، مراجعتان');
      expect(A11y.rating(5, count: 7), 'التقييم 5.0 من ٥، 7 مراجعات');
      expect(A11y.rating(5, count: 12), 'التقييم 5.0 من ٥، 12 مراجعة');
    });
  });

  group('A11y.tap: one node carries the name, the role and the action', () {
    testWidgets('an icon-only control is named and stays tappable',
        (tester) async {
      final handle = tester.ensureSemantics();
      // `WidgetTester` verifies the handles at the end of the body, before
      // `addTearDown` runs: the handle has to be disposed here or the test
      // fails with "A SemanticsHandle was active at the end of the test".
      var taps = 0;
      await _pump(
        tester,
        Material(
          child: A11y.tap(
            label: 'حذف الصورة 1',
            selected: true,
            child: InkWell(
              onTap: () => taps++,
              child: const Icon(Icons.close_rounded),
            ),
          ),
        ),
      );

      final hit = _nodes(tester).where((n) => n.label == 'حذف الصورة 1').toList();
      expect(hit, hasLength(1),
          reason: 'exactly one node may carry the name — two would read twice');
      expect(_tap(hit.single), isTrue,
          reason: 'a named control the reader cannot activate is the bug itself');
      expect(_isButton(hit.single), isTrue);
      expect(_selected(hit.single), Tristate.isTrue);

      await tester.tap(find.bySemanticsLabel('حذف الصورة 1'));
      await tester.pump();
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('a control that prints its own name is not named twice',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Material(
          child: A11y.button(
            selected: true,
            child: InkWell(onTap: () {}, child: const Text('سباكة')),
          ),
        ),
      );

      final hit = _nodes(tester).where((n) => n.label.contains('سباكة')).toList();
      expect(hit, hasLength(1));
      expect(hit.single.label, 'سباكة',
          reason: 'the visible text is the name; adding it again reads it twice');
      expect(_tap(hit.single), isTrue);
      expect(_isButton(hit.single), isTrue);
      expect(_selected(hit.single), Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('a disabled control says so', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Material(
          child: A11y.button(
            enabled: false,
            child: InkWell(onTap: null, child: const Text('أضف صورة')),
          ),
        ),
      );
      final node = _nodes(tester).firstWhere((n) => n.label.contains('أضف'));
      expect(_enabled(node), Tristate.isFalse);
      expect(_tap(node), isFalse);
      handle.dispose();
    });
  });

  group('RatingStars', () {
    testWidgets('is one sentence, with no stray icons or bare number',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const RatingStars(rating: 4.5, count: 3));

      final named = _nodes(tester).where((n) => n.label.isNotEmpty).toList();
      expect(named, hasLength(1),
          reason: 'five icons and a bare 4.5 are what this replaced');
      expect(named.single.label, 'التقييم 4.5 من ٥، 3 مراجعات');
      expect(_tap(named.single), isFalse, reason: 'a rating is not a button');
      handle.dispose();
    });

    testWidgets('drops the count when there is none', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const RatingStars(rating: 5));
      final named = _nodes(tester).where((n) => n.label.isNotEmpty).toList();
      expect(named, hasLength(1));
      expect(named.single.label, 'التقييم 5.0 من ٥');
      handle.dispose();
    });
  });

  group('the rating form', () {
    Future<void> pumpReview(WidgetTester tester) => _pump(
          tester,
          ReviewScreen(projectId: '7', workerId: 16, repo: _repo()),
          scaffold: false,
        );

    testWidgets('five stars, each named and tappable', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpReview(tester);

      final stars = _nodes(tester)
          .where((n) => n.label.endsWith('من ٥') && n.label.length <= 6)
          .toList();
      expect(stars, hasLength(5),
          reason: 'the picker used to expose an unnamed tap target per star');
      expect(stars.map((n) => n.label).toList(),
          ['1 من ٥', '2 من ٥', '3 من ٥', '4 من ٥', '5 من ٥']);
      for (final s in stars) {
        expect(_tap(s), isTrue, reason: '${s.label} must be actionable');
        expect(_isButton(s), isTrue);
      }
      expect(stars.where((n) => _selected(n) == Tristate.isTrue), isEmpty,
          reason: 'the form opens with no vote cast');
      handle.dispose();
    });

    testWidgets('the chosen stars say they are on', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpReview(tester);

      await tester.tap(find.bySemanticsLabel('4 من ٥'));
      await tester.pump();

      final stars = _nodes(tester)
          .where((n) => n.label.endsWith('من ٥') && n.label.length <= 6)
          .toList();
      final on = stars
          .where((n) => _selected(n) == Tristate.isTrue)
          .map((n) => n.label)
          .toList();
      expect(on, ['1 من ٥', '2 من ٥', '3 من ٥', '4 من ٥']);
      expect(stars.map((n) => _selected(n) == Tristate.isTrue).toList(),
          [true, true, true, true, false]);
      handle.dispose();
    });

    testWidgets('nothing on this screen is an unnamed tap target',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpReview(tester);
      final silent = _nodes(tester).where((n) => _tap(n) && n.label.isEmpty);
      expect(silent, isEmpty,
          reason: 'a reader can reach these but cannot say what they are');
      handle.dispose();
    });
  });
}
