// The dossier verdict was queued behind the recheck line it was replacing.
//
// Fifth member of the class four ticks have now measured: `ScaffoldMessenger`
// **queues**. A second `showSnackBar` while one is visible does not replace it —
// it waits for the first to time out, four seconds by default.
//
// `_submit` in `verification_screen.dart` is the worst of them, and not by a
// little. The line it queues behind is `S.writeUnconfirmedRecheck`, and the
// queued line is the *only* answer to the question a contractor who just picked
// three photos of his ID card out of his gallery is actually asking: «did my
// papers reach you?». So on the one path that exists when the files are in R2
// and the filing POST reaches the Worker and its answer never comes back, he is
// told a check is running for four seconds *after the check finished*, and the
// verdict lands last and alone.
//
// The screen had none of the discipline its siblings already have: two
// `showSnackBar` and **zero** `hideCurrentSnackBar` — the last screen in the
// app that hides nowhere. `project_detail_screen` grew `_showRechecking` /
// `_showCommitResult` on 30 Sep, the bid sheet and the notification centre were
// put onto them the same day, and none of it was applied here.
//
// The rule pinned here: **a line that is about to be replaced must be removed
// first**, so the verdict is on screen the moment the app knows it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:allomokawil/src/screens/verify/verification_screen.dart';

Map<String, dynamic> _user() => <String, dynamic>{
      'id': 31,
      'phone': '0773000000',
      'email': null,
      'full_name': 'مقاول تجربة',
      'type': 'worker',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: <String, String>{'content-type': 'application/json'});

/// A profile row shaped like `/api/mobile/my/profile` returns it.
///
/// [pendingDocs] is the field the verdict turns on: an untouched profile is
/// `pending` with **zero** documents queued, and a filed dossier is `pending`
/// with some. `after` is what the re-read returns, so the verdict can only read
/// as «landed» when the queue grew.
Map<String, Object?> _profile({
  String status = 'pending',
  int pendingDocs = 0,
  int identity = 0,
  int cert = 0,
}) =>
    <String, Object?>{
      'id': 5,
      'user_id': 9,
      'full_name': 'أحمد بن علي',
      'bio': 'دهان وترميم',
      'specialties': '["painting"]',
      'experience_years': 6,
      'is_available': 1,
      'verification_status': status,
      'verification_pending_docs': pendingDocs,
      'is_identity_verified': identity,
      'is_certificate_verified': cert,
      'total_reviews': 3,
      'total_completed_jobs': 4,
      'user_wilaya': '16',
      'commune': 'حسين داي',
    };

/// The upload is stubbed because `http.MultipartRequest` builds its own client
/// instead of the one given to [ApiClient] — a `MockClient` never sees it, and
/// a real loopback socket deadlocks inside the fake-async zone. Same seam and
/// same reason as `verification_write_outcome_test.dart`.
///
/// Everything else is the **real** transport, because that is what produces the
/// `errWriteUnconfirmed` under test.
class _RepoWithFakeUpload extends Repository {
  _RepoWithFakeUpload(super.api);

  @override
  Future<String> uploadDocument(File file) async =>
      'https://r2.test/docs/${file.path.hashCode}.jpg';
}

/// Boots the real screen on a Worker that **stores the files and then never
/// answers the filing**.
///
/// The stall is on the POST after the uploads, not a fake 500: a 5xx decodes to
/// `errServer` and correctly skips the re-read. Only the ambiguous middle —
/// files in R2, filing never answered — reaches the code under test.
Future<ApiClient> _boot(
  WidgetTester tester, {
  Map<String, Object?> Function(int read)? after,
}) async {
  tester.view.physicalSize = const Size(420, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  var reads = 0;
  var posts = 0;
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (req.method == 'POST' && p.contains('/verification')) {
        posts++;
        // Outlasts the client's own patience (500 ms, below), so the failure is
        // ambiguous rather than a refusal.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return _json(<String, Object?>{'ok': true});
      }
      if (p.contains('/my/profile')) {
        reads++;
        // A real phone's re-read is a network round trip. Answering it
        // synchronously resolves the whole exchange faster than the recheck
        // line's entrance animation, so the bar is built and removed without
        // ever being painted and the sampler below never sees it. That is a
        // fixture bug the previous tick paid for on the notification centre.
        if (posts > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        return _json((after ?? (read) => _profile())(reads));
      }
      if (p.endsWith('/api/login')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user()});
      }
      return _json(<Object>[]);
    }),
    // 500 ms, and this number is load-bearing twice over. The filing POST
    // stalls 700 ms so it outruns it and the branch under test is reached at
    // all; and the re-read below takes 300 ms of real round trip, which it must
    // **survive** or the verdict classifies as `unknown` and the test measures a
    // different sentence. The first draft of this file set 25 ms — copied from
    // the sibling file — and the probe then reported
    // «تعذّر الاتصال للتحقّق» for a re-read that had in fact succeeded. A
    // timeout is not a detail here: it decides which sentence the user is shown.
    timeout: const Duration(milliseconds: 500),
  );

  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');

  // The real picker channel, so `_pickFor` is driven as a user drives it.
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(picker, (call) async {
    if (call.method == 'pickImage') return '/tmp/does-not-matter.png';
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(picker, null));

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
      home: VerificationScreen(repo: _RepoWithFakeUpload(api)),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // The three required slots, then the send button.
  for (final label in const <String>[
    'بطاقة المقاول (auto-entrepreneur)',
    'صورة شخصية (سيلفي)',
    'بطاقة التعريف (وجه)',
  ]) {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }
  await tester.scrollUntilVisible(
    find.text('إرسال المستندات'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.tap(find.text('إرسال المستندات'));

  // A tap is not a run. `_submit` is async — three stubbed uploads, then a POST
  // that has to outlast the client's own 25 ms patience before the transport
  // gives up — and a pending timer schedules no frame, so nothing above this
  // line advances the clock. Sampling here returns an empty tree and every
  // assertion below measures a screen that never ran. Two earlier drafts of
  // this loop's sibling files failed exactly this way, and both were filed as
  // "the verdict never appears" rather than "the test never got there".
  //
  // Pushed forward until the recheck line is actually on screen, which is the
  // branch under test, and no further: the timing the cases care about is the
  // wait *after* it, and draining the whole queue here would measure nothing.
  for (var i = 0; i < 400; i++) {
    final line = _visibleLine(tester);
    if (line == S.writeUnconfirmedRecheck || line == S.dossierUnconfirmedLanded) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 10));
  }
  return api;
}

/// The sentence the user is actually looking at right now.
///
/// Exactly one [SnackBar] is ever *built*, whether it is the only one or the
/// head of a queue — `ScaffoldMessenger` holds the rest as pending requests and
/// builds them only when their turn arrives. So this returns the line on screen,
/// and the timing below is what says whether another one is waiting behind it.
/// Counting SnackBars in the tree cannot see a queue at all.
String? _visibleLine(WidgetTester tester) {
  final bars = tester.widgetList<SnackBar>(find.byType(SnackBar));
  if (bars.isEmpty) return null;
  final c = bars.first.content;
  return c is Text ? (c.data ?? '') : null;
}

/// Fake-clock milliseconds from now until [line] is the one on screen.
///
/// Pumped in 10 ms steps and **never** `pumpAndSettle`: settling advances until
/// nothing is scheduled, which drains the still-animating recheck bar before the
/// next sample — so on the fixed screen the user-visible line the cases exist to
/// prove becomes invisible to the sampler, and the cases fail with the app
/// behaving *better*. (The notification-centre file had the same bug with 250 ms
/// steps and it was the queue that made the line observable at that rate.)
Future<int> _millisUntilVisible(
  WidgetTester tester,
  String line, {
  Duration step = const Duration(milliseconds: 10),
  int capMs = 8000,
}) async {
  var elapsed = 0;
  while (elapsed <= capMs) {
    if (_visibleLine(tester) == line) return elapsed;
    await tester.pump(step);
    elapsed += step.inMilliseconds;
  }
  return _visibleLine(tester) == line ? elapsed : -1;
}

/// Closes the bar the way a user closes it, then drains the overlay.
///
/// Without this the teardown assertion `!timersPending` fires with every
/// assertion above it already green: the fix makes the verdict arrive while the
/// *old* bar's timer is still counted, so the tree can be disposed with the new
/// bar's four-second timer live. The sentence is correct — the bar is simply
/// still up — and it reads like an app bug. `header_trust_wiring_test.dart`
/// paid this exact cost yesterday and wrote down the same fix.
Future<void> _closeBar(WidgetTester tester) async {
  final messenger =
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first);
  messenger.hideCurrentSnackBar();
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(SnackBar).evaluate().isEmpty) break;
  }
}

void main() {
  testWidgets(
      'the verdict on a filing whose answer never came is drawn without '
      'waiting out the line it replaces', (tester) async {
    await _boot(tester,
        after: (read) => read <= 1 ? _profile() : _profile(pendingDocs: 3));

    // Proof the screen reached the branch under test at all. Asserted *before*
    // the timing, so the test cannot pass by measuring nothing: the POST outran
    // its timeout, so either the recheck line is up or — once the fix is in —
    // it has already been replaced by the verdict.
    expect(
        _visibleLine(tester),
        anyOf(S.writeUnconfirmedRecheck, S.dossierUnconfirmedLanded),
        reason: 'the filing must outrun its timeout and enter the recheck '
            'path, or the timing below measures a screen that never got there');

    final took = await _millisUntilVisible(tester, S.dossierUnconfirmedLanded);

    expect(took, isNot(-1),
        reason: 'the Worker queued the documents, so the app must eventually '
            'say so');
    expect(
        took,
        lessThan(2000),
        reason: 'the verdict waited $took ms to reach the screen. It is the '
            'only answer to «did my papers reach you?» — the trust gate of the '
            'whole marketplace — and it must not sit behind the recheck line '
            'for its full default four-second duration.');

    await _closeBar(tester);
  });

  testWidgets('the recheck line is removed, so one verdict is ever on screen',
      (tester) async {
    await _boot(tester,
        after: (read) => read <= 1 ? _profile() : _profile(pendingDocs: 3));

    final took = await _millisUntilVisible(tester, S.dossierUnconfirmedLanded);
    expect(took, isNot(-1), reason: 'the verdict must exist to judge this');

    // One failure, one line: once the verdict arrives the progress note about a
    // check that has already finished must not be on screen, and nothing may be
    // queued behind the answer either.
    expect(_visibleLine(tester), S.dossierUnconfirmedLanded,
        reason: 'the answer replaces the recheck line; it does not join it');
    expect(_visibleLine(tester), isNot(S.writeUnconfirmedRecheck));

    await _closeBar(tester);
  });

  testWidgets('the empty-queue verdict is answered the same single line',
      (tester) async {
    // Nothing moved, so the honest sentence is the retryable one — «nothing
    // arrived, send it again». It is still the verdict, and it must replace the
    // recheck line exactly as the landing does, or a contractor who is told to
    // retry waits four seconds for the instruction that tells him to.
    await _boot(tester, after: (_) => _profile());

    final took = await _millisUntilVisible(tester, S.dossierUnconfirmedMissing);
    expect(took, isNot(-1),
        reason: 'an unchanged profile must classify as missing, never landed');
    expect(took, lessThan(2000),
        reason: 'the retry instruction waited $took ms behind a recheck line '
            'about a check that had already finished');
    expect(_visibleLine(tester), S.dossierUnconfirmedMissing);

    await _closeBar(tester);
  });
}
