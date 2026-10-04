// «تم إرسال مستنداتك، بانتظار المراجعة» was printed on a 200 that stored
// nothing — and the sentence is the only answer to the trust gate.
//
// Found 4 Oct 2026 on the live API, by asking the Worker the question this app
// asks on every filing. `verification_screen.dart:_submit` re-reads the profile
// **only** when the POST throws `errWriteUnconfirmed`. A filing that answers
// 200 is taken at its word:
//
//   POST /api/mobile/workers/146/verification
//     {"documents":[{"document_type":"selfie"}]}      -> 200 {"ok":true}
//   GET  /api/mobile/my/profile                       -> verification_pending_docs: 0
//
// Three documents were on that phone. The queue went **to zero** and the app
// said "sent, awaiting review". This is not a shape the fixture invented — the
// Worker answers exactly this for a document it cannot read a URL out of, and
// `{"ok":true}` is a 200 with no body field the app could check. Measured on
// production, `verification_pending_docs` went 3 -> 0 across that call.
//
// **Why this is the trust gate and not a cosmetic gap.** `verification_pending_docs`
// is the ONLY thing separating a man who filed his papers from a man who
// touched nothing: `verification_status` is `pending` for both, and the model
// says so in so many words (`WorkerProfile.dossierUnderReview`). A false
// "awaiting review" tells a contractor his ID card is with a reviewer, he waits,
// and nobody ever looks at it — and re-submitting does not help, because the
// second filing replaces the first identically. The app already owns the honest
// machinery for this (`resolveVerificationWriteOutcome`, `dossierOutcomeCopy`),
// and the 200 branch simply never enters it.
//
// The rule pinned here: **a filing is not proven by its status code.** The only
// proven arrival is a moved row, which is what the re-read decides.
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
      'id': 431,
      'phone': '0555000000',
      'email': null,
      'full_name': 'مقاول تجربة',
      'type': 'worker',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-10-04 06:11:05',
    };

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: <String, String>{'content-type': 'application/json'});

/// [pendingDocs] is the whole point: the re-read answers with the queue the
/// server actually holds, and [stored] is whether that queue moved at all.
Map<String, Object?> _profile({int pendingDocs = 0}) => <String, Object?>{
      'id': 146,
      'user_id': 431,
      'full_name': 'مقاول تجربة',
      'bio': null,
      'specialties': <Object>[],
      'experience_years': 0,
      'service_radius_km': 30,
      'is_available': 1,
      'verification_status': 'pending',
      'verification_pending_docs': pendingDocs,
      'is_identity_verified': 0,
      'is_certificate_verified': 0,
      'avg_rating': 0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'phone': '0555000000',
      'user_wilaya': '16',
      'commune': null,
      'avatar_url': null,
    };

/// The upload is stubbed for the reason
/// `verification_dossier_queued_test.dart` documents: `http.MultipartRequest`
/// builds its own client, so a [MockClient] never sees it.
class _RepoWithFakeUpload extends Repository {
  _RepoWithFakeUpload(super.api);

  @override
  Future<String> uploadDocument(File file) async =>
      'https://r2.test/docs/${file.path.hashCode}.jpg';
}

/// Boots the real screen against a Worker that answers the filing **200 and
/// stores nothing** — the case measured on production.
Future<ApiClient> _boot(WidgetTester tester, {required bool stored}) async {
  tester.view.physicalSize = const Size(420, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  var posts = 0;
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (req.method == 'POST' && p.contains('/verification')) {
        posts++;
        // 200 with no body field the app can check. Exactly what production
        // answered for a document it could not read a URL out of.
        return _json(<String, Object?>{'ok': true});
      }
      if (p.contains('/my/profile')) {
        // A real round trip, so the re-read has to survive the client's own
        // patience or the verdict classifies as `unknown` and this test would
        // measure a different sentence than the defect does.
        if (posts > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        // The FIRST read is always an untouched profile — otherwise the screen
        // opens on the under-review branch, which has no form and no send
        // button, and the test measures a screen that was never driven.
        // `stored` only decides what the **re-read** answers: 3 is the landing,
        // 0 is the measured server that accepted the filing and kept nothing.
        return _json(_profile(pendingDocs: posts > 0 && stored ? 3 : 0));
      }
      if (p.endsWith('/api/login')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user()});
      }
      return _json(<Object>[]);
    }),
    timeout: const Duration(milliseconds: 500),
  );

  final auth = AuthState(api);
  await auth.login(phone: '0555000000', password: 'secret123');

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
  return api;
}

/// The sentence the user is actually looking at right now.
String? _visibleLine(WidgetTester tester) {
  final bars = tester.widgetList<SnackBar>(find.byType(SnackBar));
  if (bars.isEmpty) return null;
  final c = bars.first.content;
  return c is Text ? (c.data ?? '') : null;
}

/// Pumps forward until [line] is on screen, or gives up. Never `pumpAndSettle`:
/// settling drains the still-animating recheck line before the next sample.
Future<bool> _untilVisible(
  WidgetTester tester,
  String line, {
  int capMs = 8000,
}) async {
  for (var i = 0; i * 10 <= capMs; i++) {
    if (_visibleLine(tester) == line) return true;
    await tester.pump(const Duration(milliseconds: 10));
  }
  return _visibleLine(tester) == line;
}

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
      'a filing the server accepted with 200 but stored nothing is NOT told '
      'to the user as sent and awaiting review', (tester) async {
    await _boot(tester, stored: false);

    // The honest sentence must arrive, and it is the one that tells him to
    // send again: the re-read proved nothing moved, so nothing was stored.
    final told = await _untilVisible(tester, S.dossierUnconfirmedMissing);

    expect(
        told,
        isTrue,
        reason: 'The queue came back empty after the filing, so nothing '
            'arrived. The app must say so instead of printing '
            '"تم إرسال مستنداتك، بانتظار المراجعة" — a man told his papers '
            'are with a reviewer waits 48 hours and nobody ever looks at them.');

    // And the false claim must never have been made, even transiently.
    expect(
        _visibleLine(tester),
        isNot('تم إرسال مستنداتك، بانتظار المراجعة'),
        reason: 'the unproven success sentence must not reach the screen');

    await _closeBar(tester);
  });

  testWidgets(
      'a filing the server really did store is still reported as sent, so '
      'the re-read does not talk a man out of a landing', (tester) async {
    await _boot(tester, stored: true);

    final told = await _untilVisible(tester, S.dossierUnconfirmedLanded);

    expect(told, isTrue,
        reason: 'the queue grew from 0 to 3, which is the only proof of '
            'arrival this app trusts. Reporting a real landing as missing '
            'would send a contractor round the form for nothing.');

    await _closeBar(tester);
  });
}
