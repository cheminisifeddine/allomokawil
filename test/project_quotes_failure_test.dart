// The owner's quote list, and the one sentence it must never print on a
// failed read.
//
// Found on 27 Sep 2026, one tick after the same class of lie was fixed twice
// over in the contractor's gallery (`«لم يضف صوراً بعد»` on the public
// profile, `«أضف صوراً»` on his own dashboard). Both were "a failed read is
// published as an empty one". This is the third screen in that family, and
// the worst of the three, because the thing it gets wrong is not decoration —
// it is demand:
//
//   _QuotesSection:  final quotes = snap.data ?? const <Quote>[];
//                    if (quotes.isEmpty) return EmptyView('لا عروض بعد', …);
//
// `snap.data` is null on an error exactly as it is on a genuinely empty list,
// so the FutureBuilder cannot tell them apart and this code never asked. One
// 500 — one dropped connection, one host not answering, one captive portal —
// and the owner of a posted project is told «لا عروض بعد» with a direct link to
// the contractor directory, i.e. "nobody wants your job, go fish for pros
// yourself".
//
// That is the one list in the app where a false "empty" costs money. Every
// other instance of this class hides a cosmetic count. This one tells a
// customer who paid to advertise a project that the market has ignored him,
// and points him at the most expensive possible response to that belief.
//
// The screen already has the two halves of the fix within reach: `_reload()`
// re-issues the read, and `EmptyView` already takes a `danger` flag and an
// `actionIcon`. Neither was used.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

Map<String, Object?> _user(String type) => {
      'id': type == 'worker' ? 31 : 30,
      'phone': '0773000000',
      'email': null,
      'full_name': type == 'worker' ? 'مقاول تجربة' : 'زبون تجربة',
      'type': type,
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// The owner's own project — `customer_id` matches the signed-in user so
/// `_isOwner` is true and the empty state under test is the one he sees.
final _project = <String, Object?>{
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
  'status': 'open',
  'selected_worker_id': null,
  'created_at': '2026-09-11 20:23:44',
  'updated_at': '2026-09-11 20:23:44',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// A 500 with an HTML body — the captive-portal / Worker-crash shape the API
/// client turns into an [ApiException] rather than into empty data.
http.Response _boom() => http.Response('<html>Internal Server Error</html>', 500,
    headers: {'content-type': 'text/html'});

/// A quote as `GET /api/mobile/projects/p1/quotes` really returns it. Used only
/// to prove the success path is untouched: the fix must not turn a real list
/// into an error, nor an error into a list.
Map<String, Object?> _quote(int id) => <String, Object?>{
      'id': id,
      'project_id': 'p1',
      'worker_id': 16,
      'amount': 70000,
      'message': 'يمكنني البدء غداً',
      'estimated_days': 5,
      'worker_full_name': 'مقاول تجربة',
      'worker_avatar_url': null,
      'worker_avg_rating': 0,
      'worker_total_reviews': 0,
      'worker_verification_status': 'verified',
    };

/// Boots a signed-in project owner against a fake API whose quotes endpoint
/// answers [quotes] and logs every request, so a test can count the reads.
Future<({ApiClient api, AuthState auth, List<String> log})> _boot({
  required http.Response Function() quotes,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object>{
          'token': 'tok',
          'user': _user('customer'),
        });
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.startsWith('/api/mobile/projects/p1/quotes')) return quotes();
      if (p == '/api/mobile/projects/p1') return _json(_project);
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'customer', reason: 'the fixture must land on the owner');
  return (api: api, auth: auth, log: log);
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 1500),
}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
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
      home: ProjectDetailScreen(projectId: 'p1', repo: Repository(api)),
    ),
  ));
  await _settle(tester);
}

/// Bounded pumps: the loading skeleton animates forever, so pumpAndSettle
/// would never return.
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Scrolls a label into the viewport, then taps it. The quote list sits well
/// below the fold on a phone-sized view, and a tap that missed would "pass" on
/// a button no user could reach either.
Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await _settle(tester);
}

/// Renders the screen to a PNG so a layout claim about the error state can be
/// looked at rather than asserted about.
Future<String> _shoot(
  WidgetTester tester,
  String name,
  Widget screen,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 850),
}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
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
      home: RepaintBoundary(key: key, child: screen),
    ),
  ));
  await _settle(tester);

  // Bring the error state itself into frame before capturing: the quote list
  // sits below the fold, and a capture of the top of the page would prove
  // nothing about it.
  final target = find.text('تعذّر تحميل العروض');
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 100));
  }

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  expect(File(path).lengthSync(), greaterThan(20000),
      reason: 'a $name shot this small means nothing rendered');
  return path;
}

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

void main() {
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  // ── 1. The lie ───────────────────────────────────────────────────────────
  //
  // The whole item in one assertion: a 500 must not produce the sentence that
  // tells the owner the market has ignored his project.
  testWidgets('a failed quote read is never published as an empty list',
      (tester) async {
    final s = await _boot(quotes: _boom);
    await _pump(tester, s.api, s.auth);

    final texts = _texts(tester);
    // Guard the guard: a screen stuck on its skeleton renders no text at all,
    // and every negative assertion below would then be vacuously true.
    expect(texts, contains('العروض'),
        reason: 'the quotes section never rendered — $texts');
    expect(texts, isNotEmpty, reason: 'no text: $texts');

    expect(find.text('لا عروض بعد'), findsNothing,
        reason: '«لا عروض بعد» on a 500 is a false claim about demand, and it '
            'ships the owner to the directory to fish for pros himself; $texts');
    expect(find.text('ابحث عن مقاول'), findsNothing,
        reason: 'the remedy for a false empty is the opposite of a remedy for a '
            'failed read; $texts');
  });

  // ── 2. It must say what happened, in the colour that means failure ───────
  testWidgets('a failed quote read says so and is styled as a failure',
      (tester) async {
    final s = await _boot(quotes: _boom);
    await _pump(tester, s.api, s.auth);

    expect(find.text('تعذّر تحميل العروض'), findsOneWidget,
        reason: 'the failure must be named, not implied: ${_texts(tester)}');
    // The body is the curated copy for this status, not a raw exception: the
    // 500's own sentence is already Arabic and already actionable, and the
    // point of `errorCopy` is that the screen never invents a second wording.
    expect(find.text(S.errServer), findsOneWidget,
        reason: 'the read failed with a 500, so the body must be the curated '
            '500 copy: ${_texts(tester)}');

    // The title is the one string on the screen that changed, so it is the one
    // string whose colour carries the meaning. `AppTheme.danger`, read off the
    // live widget — not a guess at a constant.
    final title = tester.widget<Text>(find.text('تعذّر تحميل العروض'));
    expect(
      title.style?.color,
      AppTheme.danger,
      reason: 'a failure must not be painted in the neutral text colour, and '
          'must not be painted in the action colour either',
    );
  });

  // ── 3. The retry must be a real request, not a redraw ────────────────────
  //
  // The retry here is the screen's own `_reload()`, which is the one that
  // re-issues the read. A button that redraws the same failure forever is the
  // third way this screen can waste a man's time.
  testWidgets('the retry re-issues the read and recovers when the API returns',
      (tester) async {
    var failing = true;
    final s = await _boot(quotes: () => failing ? _boom() : _json(<Object>[]));
    await _pump(tester, s.api, s.auth);

    expect(find.text('تعذّر تحميل العروض'), findsOneWidget);

    int reads(String path) => s.log
        .where((r) => r.endsWith(path) && r.startsWith('GET'))
        .length;

    final before = reads('/api/mobile/projects/p1/quotes');
    expect(before, greaterThan(0), reason: 'no read was issued at all');

    // The API comes back; the button must notice.
    failing = false;
    await _tap(tester, 'أعد المحاولة');

    expect(reads('/api/mobile/projects/p1/quotes'), greaterThan(before),
        reason: '«أعد المحاولة» must issue a real request, not just redraw');
    expect(find.text('تعذّر تحميل العروض'), findsNothing,
        reason: 'the failure must clear once the read succeeds');
    expect(find.text('لا عروض بعد'), findsOneWidget,
        reason: 'a genuinely empty list must still read as empty — the fix '
            'must not turn every empty quote list into an error');
  });

  // ── 4. The genuine empty state must be untouched ─────────────────────────
  //
  // The mirror of test 1. If this one fails, the fix has over-corrected and
  // every new project on the platform now shows a server error to its owner.
  testWidgets('a genuinely empty quote list still reads as empty',
      (tester) async {
    final s = await _boot(quotes: () => _json(<Object>[]));
    await _pump(tester, s.api, s.auth);

    final texts = _texts(tester);
    expect(find.text('لا عروض بعد'), findsOneWidget,
        reason: 'the real empty state was replaced by the error state: $texts');
    expect(find.text('تعذّر تحميل العروض'), findsNothing,
        reason: 'a server answering `[]` is not a failure: $texts');
    // And the owner's next step survives: the directory link.
    expect(find.text('ابحث عن مقاول'), findsOneWidget);
  });

  // ── 5. A real quote list renders, and still renders ──────────────────────
  testWidgets('a real quote list is unaffected by the failure branch',
      (tester) async {
    final s = await _boot(
        quotes: () => _json(<Object?>[_quote(1), _quote(2)]));
    await _pump(tester, s.api, s.auth);

    expect(find.text('مقاول تجربة'), findsWidgets,
        reason: 'the success path stopped rendering: ${_texts(tester)}');
    expect(find.text('تعذّر تحميل العروض'), findsNothing);
    expect(find.text('لا عروض بعد'), findsNothing);
  });

  // ── Visual pass: the pixels, for the gate ─────────────────────────────
  // A layout claim about the error state is only worth anything if the error
  // state was actually rendered and looked at.
  testWidgets('the failed quote read rasterises with its retry visible',
      (tester) async {
    final s = await _boot(quotes: _boom);
    final path = await _shoot(tester, 'quotes_read_failed',
        ProjectDetailScreen(projectId: 'p1', repo: Repository(s.api)),
        s.api, s.auth, logical: const Size(392, 1700));
    stdout.writeln('SHOT $path ${File(path).lengthSync()}b');
  });
}
