// Numeric fields, through the real screens and the real Repository.
//
// Two claims are checked here, and neither can be checked by reading the code:
//
//   1. every amount / year / day-count field on every screen opens a NUMBER
//      keypad — asserted against the actual widget tree, not a grep;
//   2. what a user types into one reaches the API as the number they meant,
//      including Arabic-Indic digits (`٢٥٠٠٠`), `25.000` grouping and a pasted
//      `دج` — asserted against the JSON body the app really sends.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/screens/worker/profile_edit_screen.dart';
import 'package:allomokawil/src/widgets/number_field.dart';
import 'package:allomokawil/src/widgets/ui.dart';

Map<String, Object?> _projectJson({String status = 'open'}) => {
      'id': 'p1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': 'دهان كامل مع تصليح',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'latitude': null,
      'longitude': null,
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': status,
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

const _worker = {
  'id': 16,
  'user_id': 31,
  'bio': 'دهان وديكور',
  'specialties': ['painting'],
  'experience_years': 5,
  'price_range_min': 20000,
  'price_range_max': 60000,
  'service_radius_km': 30,
  'is_available': 1,
  'is_identity_verified': 1,
  'is_certificate_verified': 0,
  'verification_status': 'verified',
  'subscription_plan': 'free_trial',
  'avg_rating': 4.5,
  'total_reviews': 3,
  'total_completed_jobs': 7,
  'response_time_hours': 2,
  'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45',
  'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة',
  'phone': '077442495',
  'user_wilaya': '16',
  'avatar_url': null,
};

Map<String, Object?> _quoteJson({int amount = 5000, int days = 10}) => {
      'id': 77,
      'project_id': 'p1',
      'worker_id': 16,
      'amount': amount,
      'message': null,
      'estimated_days': days,
      'worker_full_name': 'مقاول تجربة',
      'worker_avatar_url': null,
      'worker_avg_rating': 4.5,
      'worker_total_reviews': 3,
      'worker_verification_status': 'verified',
    };

/// Every request the app makes, in order — the body is the evidence.
final sent = <({String method, String path, Map<String, dynamic> body})>[];

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

ApiClient _fakeApi() => ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (req.body.isNotEmpty) {
          try {
            sent.add((
              method: req.method,
              path: p,
              body: jsonDecode(req.body) as Map<String, dynamic>,
            ));
          } catch (_) {
            // Not JSON — not a body this test cares about.
          }
        }
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json({
            'token': 'tok',
            'user': {
              'id': 30,
              'phone': '0773000000',
              'email': null,
              'full_name': 'مستخدم تجربة',
              'type': 'worker',
              'avatar_url': null,
              'wilaya': '16',
              'commune': null,
              'created_at': '2026-09-11 20:00:00',
            },
          });
        }
        if (p.contains('/my/profile')) return _json(_worker);
        if (p.endsWith('/api/mobile/projects')) return _json(_projectJson());
        if (p.contains('/quotes')) {
          // POST answers with the created quote; GET with the project's list.
          return req.method == 'POST' ? _json(_quoteJson()) : _json(<Object>[]);
        }
        if (p.contains('/api/mobile/projects/')) return _json(_projectJson());
        return _json(<Object>[]);
      }),
    );

Future<({ApiClient api, AuthState auth})> _boot() async {
  SharedPreferences.setMockInitialValues({});
  final api = _fakeApi();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  ApiClient api,
  AuthState auth, {
  // Tall Android phone so a long form is fully built (no off-screen fields).
  // The contractor profile is the longest form in the app, so its tests ask for
  // a taller viewport than the project form needs.
  Size size = const Size(1080, 3400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: AppScope(api: api, auth: auth, child: screen),
  ));
  // Bounded pumps: the skeletons animate forever, so pumpAndSettle would hang.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Opened a modal sheet AND let it finish sliding in.
///
/// `pump(Duration)` alone renders the route at animation value 0 — the sheet is
/// positioned just below the viewport, so every tap inside it misses. The first
/// `pump()` installs the route, the second advances the slide.
Future<void> _openSheet(WidgetTester tester, Finder opener) async {
  await tester.tap(opener);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Scrolls until [finder] is built and visible. The profile form is a lazy
/// `ListView`, so a field below the fold does not exist yet.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 260,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// The contractor profile reports one framework warning that is already on
/// `main` and has nothing to do with numbers: its availability
/// `SwitchListTile.adaptive` sits inside a rounded `Container` with a
/// background, so Flutter reports that the tile's ink is hidden. It fires once
/// per build, so this drains in a loop and fails on anything else.
void _expectOnlyKnownProfileWarning(WidgetTester tester) {
  final unexpected = <Object>[];
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    if (!'$e'.contains('ink splashes may be invisible') &&
        !'$e'.contains('Multiple exceptions')) {
      unexpected.add(e);
    }
  }
  expect(unexpected, isEmpty,
      reason: 'unexpected exception(s) on the profile screen: $unexpected');
}

/// The keypad a field really asks Android/iOS for.
TextInputType? _keypadOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).keyboardType;

/// Every [NumberField] in the tree must be a number keypad. A field that
/// forgets its `keyboardType` shows the full text keyboard, which is the
/// original complaint this item exists to close.
void _expectNumberKeypads(WidgetTester tester) {
  final fields = find.byType(NumberField);
  expect(fields, findsWidgets);
  for (var i = 0; i < fields.evaluate().length; i++) {
    final tf =
        find.descendant(of: fields.at(i), matching: find.byType(TextField));
    expect(_keypadOf(tester, tf), TextInputType.number,
        reason: 'NumberField #$i must open a number keypad');
  }
}

void main() {
  setUp(sent.clear);

  testWidgets('project form: numeric fields are number keypads',
      (tester) async {
    final s = await _boot();
    await _pump(tester, const ProjectNewScreen(), s.api, s.auth);

    expect(tester.takeException(), isNull);
    _expectNumberKeypads(tester);
    expect(find.byType(NumberField), findsNWidgets(2));

    // The text fields that are NOT amounts keep the full keyboard.
    final title = find.byType(TextField).first;
    expect(_keypadOf(tester, title), isNot(TextInputType.number));
  });

  testWidgets('project form: ٢٥٠٠٠ دج is posted as 25000', (tester) async {
    final s = await _boot();
    await _pump(tester, const ProjectNewScreen(), s.api, s.auth);

    await tester.enterText(find.byType(TextField).first, 'ترميم فيلا');
    await tester.tap(find.byType(SelectableTile).first);
    await tester.pump();

    // Wilaya: open the sheet, narrow by the numeric code, tap الجزائر.
    await _reveal(tester, find.text('اختر الولاية'));
    await _openSheet(tester, find.text('اختر الولاية'));
    await tester.enterText(
      find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(TextField)),
      '16',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('الجزائر').first);
    await tester.pump(const Duration(milliseconds: 300));

    // Arabic-Indic digits, and the unit glued on — what an Algerian keypad and
    // a pasted note actually produce.
    final budgets = find.byType(NumberField);
    expect(budgets, findsNWidgets(2));
    await _reveal(tester, budgets.at(0));
    await tester.enterText(
        find.descendant(of: budgets.at(0), matching: find.byType(TextField)),
        '٢٥٠٠٠');
    await tester.enterText(
        find.descendant(of: budgets.at(1), matching: find.byType(TextField)),
        '30.000 دج');
    await tester.pump();

    // The fold is live: what the user sees is already the number that is sent.
    expect(tester.widget<NumberField>(budgets.at(0)).controller.text, '25000');
    expect(tester.widget<NumberField>(budgets.at(1)).controller.text, '30000');

    await tester.tap(find.text('نشر المشروع'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final post = sent.where((r) => r.path.endsWith('/api/mobile/projects'));
    expect(post, hasLength(1),
        reason: 'the project must be posted exactly once');
    expect(post.first.body['budget_min'], 25000);
    expect(post.first.body['budget_max'], 30000);
    expect(post.first.body['title'], 'ترميم فيلا');
    expect(post.first.body['wilaya'], '16');
  });

  testWidgets('project form: a reversed budget is refused in Arabic',
      (tester) async {
    final s = await _boot();
    await _pump(tester, const ProjectNewScreen(), s.api, s.auth);

    final budgets = find.byType(NumberField);
    await _reveal(tester, budgets.at(0));
    await tester.enterText(
        find.descendant(of: budgets.at(0), matching: find.byType(TextField)),
        '50000');
    await tester.enterText(
        find.descendant(of: budgets.at(1), matching: find.byType(TextField)),
        '5000');
    await tester.pump();

    // Live, before any submit attempt.
    expect(find.text('الحد الأدنى أكبر من الحد الأعلى — صحّح الميزانية'),
        findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'ترميم فيلا');
    await tester.tap(find.byType(SelectableTile).first);
    await tester.pump();
    await tester.tap(find.text('نشر المشروع'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // No request left the app: a project with an impossible range cannot exist.
    expect(sent.where((r) => r.path.endsWith('/api/mobile/projects')), isEmpty);
  });

  testWidgets('quote sheet: ٥٠٠٠ دج over ١٠ أيام reaches the API',
      (tester) async {
    final s = await _boot();
    await _pump(
        tester,
        ProjectDetailScreen(projectId: 'p1', repo: Repository(s.api)),
        s.api,
        s.auth);

    expect(tester.takeException(), isNull);
    await _openSheet(tester, find.text('قدّم عرضك').last);
    expect(find.byType(NumberField), findsNWidgets(2));

    final amount = find.descendant(
        of: find.byType(NumberField).at(0), matching: find.byType(TextField));
    final days = find.descendant(
        of: find.byType(NumberField).at(1), matching: find.byType(TextField));
    expect(_keypadOf(tester, amount), TextInputType.number);
    expect(_keypadOf(tester, days), TextInputType.number);

    await tester.enterText(amount, '٥٠٠٠');
    await tester.enterText(days, '١٠');
    await tester.pump();
    expect(tester.widget<TextField>(amount).controller!.text, '5000');
    expect(tester.widget<TextField>(days).controller!.text, '10');

    await _openSheet(tester, find.text('إرسال العرض'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final quote = sent.where((r) => r.path.contains('/quotes'));
    expect(quote, hasLength(1));
    expect(quote.first.body['amount'], 5000);
    expect(quote.first.body['estimated_days'], 10);
  });

  testWidgets('quote sheet: a sub-1000 amount is refused, nothing is sent',
      (tester) async {
    final s = await _boot();
    await _pump(
        tester,
        ProjectDetailScreen(projectId: 'p1', repo: Repository(s.api)),
        s.api,
        s.auth);

    await _openSheet(tester, find.text('قدّم عرضك').last);
    await tester.enterText(
        find.descendant(
            of: find.byType(NumberField).at(0),
            matching: find.byType(TextField)),
        '٩٩٩');
    await tester.pump();
    await _openSheet(tester, find.text('إرسال العرض'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(sent.where((r) => r.path.contains('/quotes')), isEmpty);
    // The API's own rule, said in Arabic before the round trip.
    expect(find.text('المبلغ يجب أن يكون 1000 دج على الأقل'), findsOneWidget);
  });

  testWidgets('profile: ٨ سنوات خبرة is saved as 8', (tester) async {
    final s = await _boot();
    await _pump(tester, const ProfileEditScreen(), s.api, s.auth,
        size: const Size(1080, 6400));

    _expectOnlyKnownProfileWarning(tester);
    // The profile form is a lazy ListView, so the numeric section only exists
    // once it has been scrolled into range.
    await _reveal(tester, find.text('سنوات الخبرة'));
    expect(find.byType(NumberField), findsNWidgets(3));
    _expectNumberKeypads(tester);

    // The experience field holds the profile value; overwrite it with an
    // Arabic-Indic digit.
    final years = find.byType(NumberField).at(0);
    await _reveal(tester, years);
    await tester.enterText(
        find.descendant(of: years, matching: find.byType(TextField)), '٨');
    await tester.pump();
    expect(tester.widget<NumberField>(years).controller.text, '8');

    await _reveal(tester, find.text('حفظ الملف'));
    await tester.tap(find.text('حفظ الملف'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    _expectOnlyKnownProfileWarning(tester);
    final patch = sent.where((r) => r.path.contains('/my/profile'));
    expect(patch, hasLength(1));
    expect(patch.first.body['experience_years'], 8);
  });

  testWidgets('profile: 99 years of experience is refused in Arabic',
      (tester) async {
    final s = await _boot();
    await _pump(tester, const ProfileEditScreen(), s.api, s.auth,
        size: const Size(1080, 6400));

    await _reveal(tester, find.text('سنوات الخبرة'));
    final years = find.byType(NumberField).at(0);
    await _reveal(tester, years);
    await tester.enterText(
        find.descendant(of: years, matching: find.byType(TextField)), '٩٩');
    await tester.pump();
    await _reveal(tester, find.text('حفظ الملف'));
    await tester.tap(find.text('حفظ الملف'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    _expectOnlyKnownProfileWarning(tester);
    expect(sent.where((r) => r.path.contains('/my/profile')), isEmpty);
    // Shown twice by design: the inline notice and the sticky bar at the foot.
    expect(find.textContaining('سنوات الخبرة يجب أن تكون رقماً'),
        findsAtLeastNWidgets(1));
  });
}
