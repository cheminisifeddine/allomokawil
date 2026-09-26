// Renders the search result as pixels, with the real Cairo faces.
//
// The claim a contractor would make is "when I type نجارة, the finishing job
// is on my screen" — and a widget assertion that a `Text` is in the tree is not
// that claim. So this captures the real screen in both directions: the query
// that finds the job, and the query that does not. A one-sided capture passes
// just as happily on a filter that returns the whole feed, which is the
// failure this file has to rule out.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/projects_screen.dart';

/// The real finishing job from the live API: six trades, and a `title` and
/// `description` of the literal string `test`. Nothing about carpentry appears
/// anywhere on the row except in `categories`, which is the field the old
/// filter did not read.
Map<String, Object?> _job({
  required String id,
  required String title,
  required String primary,
  required List<String> trades,
  String description = 'test',
}) =>
    <String, Object?>{
      'id': id,
      'customer_id': 336,
      'title': title,
      'description': description,
      'category': primary,
      'categories': trades,
      'images': <Object?>[],
      'wilaya': '04',
      'commune': 'أولاد قاسم',
      'budget_min': 6000,
      'budget_max': 7000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-19 20:39:41',
      'updated_at': '2026-09-19 20:39:41',
    };

final List<Map<String, Object?>> _projects = <Map<String, Object?>>[
  _job(
    id: '8cee95af91ebda3846132f183fe6141ead3a89fdf79d9c9cb26b59a8096ce601',
    title: 'تشطيب فيلا مع نجارة',
    primary: 'general_finishing',
    trades: const [
      'general_finishing',
      'painting',
      'renovation',
      'construction',
      'plumbing',
      'carpentry_aluminum',
    ],
  ),
  _job(
    id: '90dc904525441d7b687bb58460cbcb3e92caa66afd8e052da9c0b90b8e9a1e49',
    title: 'سباكة حمام',
    primary: 'plumbing',
    trades: const ['plumbing', 'electrical'],
  ),
];

String _body(String path) {
  if (path.endsWith('/api/login')) {
    return jsonEncode(<String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 336,
        'phone': '0773000000',
        'full_name': 'زبون',
        'type': 'customer',
        'wilaya': '04',
        'created_at': '2026-09-19 20:00:00',
      },
    });
  }
  if (path.contains('/my/projects')) return jsonEncode(_projects);
  if (path.contains('/my/profile')) {
    return jsonEncode(<String, Object?>{
      'id': 336,
      'user_id': 336,
      'full_name': 'زبون',
      'specialties': <Object?>[],
      'experience_years': 0,
    });
  }
  if (path.contains('/subscription')) {
    return jsonEncode(<String, Object?>{
      'currency': 'DZD',
      'note_ar': '',
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[],
      'current': <String, Object?>{
        'plan': 'free_trial',
        'name_ar': 'الخطة المجانية',
        'status': 'active',
        'starts_at': '2026-09-01 00:00:00',
        'expires_at': null,
        'quote_limit': 3,
        'portfolio_limit': 5,
        'quotes_used_this_month': 0,
      },
    });
  }
  return jsonEncode(<Object>[]);
}

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  expect(reg.lengthInBytes, greaterThan(10000),
      reason: 'Cairo-Regular.ttf did not load from the asset bundle');
  await (FontLoader('Cairo')
        ..addFont(Future.value(reg))
        ..addFont(Future.value(bold)))
      .load();

  var root = Platform.environment['FLUTTER_ROOT'];
  root ??= File(Platform.resolvedExecutable)
      .parent
      .parent
      .parent
      .parent
      .parent
      .parent
      .parent
      .parent
      .path;
  final icons = File('$root/bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf');
  expect(icons.existsSync(), isTrue,
      reason: 'MaterialIcons-Regular.otf not found under $root');
  final iconBytes = icons.readAsBytesSync();
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(iconBytes.buffer))))
      .load();
  stdout.writeln('FONTS: Cairo + MaterialIcons registered');
}

final GlobalKey _key = GlobalKey();

Future<void> _shoot(WidgetTester tester, String name, String query,
    {required String expectVisible, required String expectGone}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async => http.Response(
          _body(req.url.path),
          200,
          headers: {'content-type': 'application/json'},
        )),
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
      home: RepaintBoundary(
        key: _key,
        child: ProjectsScreen(repo: Repository(api)),
      ),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle(const Duration(seconds: 1));

  final visible = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
  expect(visible, contains(expectVisible),
      reason: 'the job that matches «$query» must be on screen');
  expect(visible, isNot(contains(expectGone)),
      reason: 'a job that does not match «$query» must not be on screen');

  final boundary =
      _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.75);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    File('/tmp/shots/multitrade_$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  stdout.writeln('SHOT: /tmp/shots/multitrade_$name.png');
  expect(tester.takeException(), isNull, reason: 'the screen threw');
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('a secondary trade finds the job, on screen', (tester) async {
    // «نجارة» appears in the row's `categories` and in its title. The title
    // would match even with the old filter, so the load-bearing assertion is
    // the one in the unit and live tests; this one proves the *screen* widens.
    await _shoot(tester, '01_najara_hit', 'نجارة',
        expectVisible: 'تشطيب فيلا مع نجارة', expectGone: 'سباكة حمام');
  });

  testWidgets('the mirror case: the other job by its own secondary trade',
      (tester) async {
    // «كهرباء» is the *second* trade of the plumbing job and appears nowhere
    // in that row's title or description. So this is the same defect seen from
    // the other side, and together the two shots show the filter following the
    // `categories` list rather than the title or the primary trade.
    await _shoot(tester, '02_kahraba_hit', 'كهرباء',
        expectVisible: 'سباكة حمام', expectGone: 'تشطيب فيلا مع نجارة');
  });
}
