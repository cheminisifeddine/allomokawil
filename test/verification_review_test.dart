// "I uploaded everything and it says I uploaded nothing."
//
// That is the bug this file exists to prevent. A contractor files his three
// documents, the app shows him a blank form again, and he concludes the upload
// failed — so he does it again, and again.
//
// The trap underneath it: the database stores a brand-new profile as
// `verification_status = 'pending'`, exactly like a submitted dossier. So the
// status alone can never answer "did my papers arrive?", and a UI that keys off
// it will be wrong in one direction or the other. These tests pin both
// directions:
//   * a fresh contractor must still see the form (not a false "under review");
//   * a contractor with documents in the queue must see the receipt, and must
//     NOT see either the empty form or the word "غير موثّق".
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/screens/verify/verification_screen.dart';

/// A profile row shaped like `/api/mobile/my/profile` returns it.
Map<String, Object?> _profile({
  String status = 'pending',
  int pendingDocs = 0,
  int identity = 0,
  int cert = 0,
}) =>
    {
      'id': 5,
      'user_id': 9,
      'full_name': 'أحمد بن علي',
      'bio': 'دهان وترميم',
      'specialties': '["painting"]',
      'experience_years': 6,
      'price_range_min': 3000,
      'price_range_max': 9000,
      'service_radius_km': 25,
      'is_available': 1,
      'verification_status': status,
      'verification_pending_docs': pendingDocs,
      'is_identity_verified': identity,
      'is_certificate_verified': cert,
      'avg_rating': 4.5,
      'total_reviews': 3,
      'total_completed_jobs': 4,
      'user_wilaya': '16',
      'commune': 'حسين داي',
    };

ApiClient _api(Map<String, Object?> profile) => ApiClient(
      baseUrls: const ['https://api.test'],
      httpClient: MockClient((req) async => http.Response(
            jsonEncode(profile),
            200,
            headers: const {'content-type': 'application/json'},
          )),
    );

Widget _wrap(Widget child, ApiClient api) => AppScope(
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
        home: child,
      ),
    );

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(const VerificationScreen(), api));
  await tester.pumpAndSettle();
}

List<String> _shown(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

/// Does the screen offer the upload slots at all?
bool _hasUploadForm(WidgetTester tester) =>
    _shown(tester).any((s) => s.contains('اضغط للإضافة'));

void main() {
  group('the model tells uploads apart from a fresh profile', () {
    test('pending with nothing in the queue is NOT under review', () {
      final fresh = WorkerProfile.fromJson(_profile());
      expect(fresh.verificationStatus, VerificationStatus.pending);
      expect(fresh.verificationPendingDocs, 0);
      expect(fresh.dossierUnderReview, isFalse);
    });

    test('pending with documents in the queue IS under review', () {
      final filed = WorkerProfile.fromJson(_profile(pendingDocs: 3));
      expect(filed.dossierUnderReview, isTrue);
    });

    test('verified and rejected are never "under review"', () {
      expect(
        WorkerProfile.fromJson(_profile(status: 'verified', pendingDocs: 3))
            .dossierUnderReview,
        isFalse,
      );
      expect(
        WorkerProfile.fromJson(_profile(status: 'rejected')).dossierUnderReview,
        isFalse,
      );
    });

    test('a backend that does not send the count cannot break the screen', () {
      final legacy = WorkerProfile.fromJson(_profile()..remove(
        'verification_pending_docs',
      ));
      expect(legacy.verificationPendingDocs, 0);
      expect(legacy.dossierUnderReview, isFalse);
    });

    // The reviewer approves documents one row at a time, so a profile can sit
    // in `pending` with its identity already accepted and its contractor card
    // refused. `verification_status` cannot describe that; these two flags can.
    test('the two per-part flags are read off the wire', () {
      final part = WorkerProfile.fromJson(_profile(identity: 1, cert: 0));
      expect(part.identityVerified, isTrue);
      expect(part.certificateVerified, isFalse);
      expect(part.verificationStatus, VerificationStatus.pending,
          reason: 'a half-accepted dossier is still pending, not verified');
    });

    test('a backend that omits the flags can never claim a part is verified',
        () {
      final legacy = WorkerProfile.fromJson(_profile()
        ..remove('is_identity_verified')
        ..remove('is_certificate_verified'));
      expect(legacy.identityVerified, isFalse);
      expect(legacy.certificateVerified, isFalse);
    });
  });

  group('what the contractor actually reads', () {
    testWidgets('a fresh contractor gets the upload form, not a false receipt',
        (tester) async {
      await _pump(tester, _api(_profile()));
      final shown = _shown(tester).join('\n');
      expect(_hasUploadForm(tester), isTrue,
          reason: 'a man who has sent nothing must be asked for documents');
      expect(shown.contains('مستنداتك قيد المراجعة'), isFalse,
          reason: 'never claim to be reviewing documents that do not exist');
    });

    testWidgets('a submitted dossier gets the receipt and no empty form',
        (tester) async {
      await _pump(tester, _api(_profile(pendingDocs: 3)));
      final shown = _shown(tester).join('\n');
      expect(shown.contains('مستنداتك قيد المراجعة'), isTrue);
      expect(shown.contains('تم الاستلام'), isTrue,
          reason: 'he must see that each document arrived');
      expect(_hasUploadForm(tester), isFalse,
          reason: 'asking him to upload again is the bug being fixed');
      expect(shown.contains('تحديث الحالة'), isTrue,
          reason: 'he needs a way to check without resending');
    });

    testWidgets('a rejected dossier explains itself and re-offers the form',
        (tester) async {
      await _pump(tester, _api(_profile(status: 'rejected')));
      final shown = _shown(tester).join('\n');
      expect(shown.contains('لم تُقبل مستنداتك'), isTrue);
      expect(_hasUploadForm(tester), isTrue,
          reason: 'a rejection must be fixable');
    });

    testWidgets('a verified contractor is told he is verified', (tester) async {
      await _pump(tester, _api(_profile(status: 'verified')));
      final shown = _shown(tester).join('\n');
      expect(shown.contains('حسابك موثّق'), isTrue);
      expect(_hasUploadForm(tester), isFalse);
    });

    // The founder's report, pinned: he made a brand-new contractor account,
    // uploaded nothing, and the app told him both halves were «بانتظار التحقق» —
    // a review status invented out of the fact that a fresh profile row holds
    // the same 'pending' default as a submitted dossier. Waiting is something
    // the app may only say when documents have actually arrived.
    testWidgets('a contractor who sent nothing is not told he is under review',
        (tester) async {
      await _pump(tester, _api(_profile()));
      final shown = _shown(tester).join('\n');
      expect(shown.contains('حالة ملفك'), isTrue);
      expect(shown.contains('الهوية'), isTrue);
      expect(shown.contains('لم تُرسل'), isTrue,
          reason: 'nothing arrived, so nothing is waiting');
      expect(shown.contains('بانتظار التحقق'), isFalse,
          reason: 'an empty dossier is not a queue');
      expect(shown.contains('موثّقة'), isFalse,
          reason: 'nothing has been accepted yet');
    });

    // The bug this closes: an all-or-nothing status made a half-accepted
    // dossier look identical to one that was never sent, so the man who had
    // already proved his identity was asked for all three documents again with
    // no explanation and no way to tell what was wrong.
    testWidgets('a half-accepted dossier names the accepted half', (tester) async {
      await _pump(tester, _api(_profile(identity: 1, cert: 0)));
      final shown = _shown(tester).join('\n');
      expect(shown.contains('حالة ملفك'), isTrue);
      expect(shown.contains('موثّقة'), isTrue,
          reason: 'the accepted half must be named as accepted');
      expect(shown.contains('لم تُرسل'), isTrue,
          reason: 'the refused half is not queued, so it is not "waiting"');
      expect(shown.contains('بانتظار التحقق'), isFalse,
          reason: 'only the queue may say that');
      expect(_hasUploadForm(tester), isTrue,
          reason: 'the refused half must stay re-uploadable');
      expect(shown.contains('مستنداتك قيد المراجعة'), isFalse,
          reason: 'he is not waiting on a queue, he has work to redo');
    });

    testWidgets('a dossier in the queue keeps its per-part table', (tester) async {
      await _pump(tester, _api(_profile(pendingDocs: 3, identity: 1, cert: 0)));
      final shown = _shown(tester).join('\n');
      expect(shown.contains('مستنداتك قيد المراجعة'), isTrue);
      expect(shown.contains('حالة ملفك'), isTrue,
          reason: 'it must still say which half is already accepted');
      expect(shown.contains('موثّقة'), isTrue);
      expect(shown.contains('بانتظار التحقق'), isTrue);
      expect(shown.contains('إعادة رفعه من الأسفل'), isFalse,
          reason: 'under review there is nothing to re-upload');
    });

    testWidgets('a fully verified contractor gets no per-part table',
        (tester) async {
      await _pump(tester, _api(_profile(status: 'verified', identity: 1, cert: 1)));
      final shown = _shown(tester).join('\n');
      expect(shown.contains('حسابك موثّق'), isTrue);
      expect(shown.contains('حالة ملفك'), isFalse,
          reason: 'the green banner already says it, twice is noise');
      expect(shown.contains('بانتظار التحقق'), isFalse);
    });
  });
}
