// "Your documents arrived" — to a contractor who never sent any.
//
// Found 28 Sep 2026 while auditing the write-outcome contract. The
// verification screen *had* the contract, and that is what hid the defect: it
// caught `errWriteUnconfirmed`, re-read the profile and printed a verdict, so
// every read of the file stopped at "it re-reads the server" and nobody asked
// what it compared.
//
// It compared `verificationStatus == pending || verified`. A brand-new
// contractor is stored as `pending`. So the re-read answered **true for a man
// with an empty form**, and the app printed «وجدناه في القائمة — الطلب وصل
// بنجاح» — *we found it in the list, the request arrived* — to someone whose
// ID card never left his gallery. He waits 48 hours for a review that nobody is
// doing, and every retry is called a landing too, so the app can be wrong as
// many times as he presses.
//
// Two halves, because a rule nothing is wired to passes clean:
//  * the predicate and the probe, pure and testable without a widget, including
//    the decoy (an unchanged profile must never read as a landing);
//  * the screen, driven over a real stalled POST, because "the screen compares
//    the right two rows" is not a property of the helper.
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
import 'package:allomokawil/src/core/l10n/write_outcome.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/verification_write_outcome.dart';
import 'package:allomokawil/src/models/worker.dart';
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
/// [pendingDocs] is the field the whole defect turns on: the untouched state
/// of every contractor in the product is `pending` with **zero** documents in
/// the queue, and a submitted dossier is `pending` with some.
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

WorkerProfile _row({
  String status = 'pending',
  int pendingDocs = 0,
  int identity = 0,
  int cert = 0,
}) =>
    WorkerProfile.fromJson(
        _profile(status: status, pendingDocs: pendingDocs, identity: identity, cert: cert));

/// The upload is stubbed because `http.MultipartRequest` builds its own client
/// instead of the one given to [ApiClient] — a `MockClient` never sees it, and
/// a real loopback socket deadlocks inside the fake-async zone. Same seam, same
/// reason, as `test/portfolio_write_outcome_test.dart`.
///
/// Everything else is the **real** transport, because that is what produces the
/// `errWriteUnconfirmed` under test: a hand-thrown exception would only prove
/// the screen handles an object, not that the failure reaches it.
class _RepoWithFakeUpload extends Repository {
  _RepoWithFakeUpload(super.api);

  @override
  Future<String> uploadDocument(File file) async =>
      'https://r2.test/docs/${file.path.hashCode}.jpg';
}

void main() {
  group('verificationLanded', () {
    // The half the defect exists for. Before the fix this was the predicate,
    // and it answered true here: `pending` is the state a brand-new profile is
    // stored in, so a contractor who sent nothing was told his papers arrived.
    test('a profile that did not move at all is NOT a landing', () {
      expect(verificationLanded(before: _row(), after: _row()), isFalse);
    });

    // The ordinary, successful case: three documents reached the queue.
    test('a queue that grew is a landing', () {
      expect(
        verificationLanded(
          before: _row(pendingDocs: 0),
          after: _row(pendingDocs: 3),
        ),
        isTrue,
      );
    });

    // A reviewer moved first, the write landed second, and the queue came back
    // the same size — the status is what proves it here.
    test('a status that moved off pending is a landing', () {
      expect(
        verificationLanded(
          before: _row(pendingDocs: 3),
          after: _row(status: 'verified', pendingDocs: 3),
        ),
        isTrue,
      );
      expect(
        verificationLanded(
          before: _row(pendingDocs: 3),
          after: _row(status: 'rejected', pendingDocs: 3),
        ),
        isTrue,
      );
    });

    // The API approves a dossier one document at a time, so a half-accepted
    // dossier is a real intermediate state and not a theoretical one.
    test('one half being accepted is a landing', () {
      expect(
        verificationLanded(
          before: _row(pendingDocs: 2),
          after: _row(pendingDocs: 2, identity: 1),
        ),
        isTrue,
      );
      expect(
        verificationLanded(
          before: _row(pendingDocs: 2),
          after: _row(pendingDocs: 2, cert: 1),
        ),
        isTrue,
      );
    });

    // The decoy the model file warns about: the only fields that moved are
    // ones a dossier has nothing to do with. A predicate that compared the
    // whole row would call this a landing.
    test('only the business fields moving is not a landing', () {
      final before = _row();
      final after = WorkerProfile.fromJson(
          _profile()..['experience_years'] = 9);
      expect(verificationLanded(before: before, after: after), isFalse);
    });

    // A queue that **shrank** is a reviewer acting, not this write: rows were
    // approved and consumed between the two reads. It is counted as landed
    // only when something else moved too; on its own it is movement the
    // predicate above already covers through the status/flags.
    test('a queue that shrank with a verdict is a landing', () {
      expect(
        verificationLanded(
          before: _row(pendingDocs: 3),
          after: _row(status: 'verified', pendingDocs: 0),
        ),
        isTrue,
      );
    });

    test('a queue that shrank with nothing else moving is not a landing', () {
      expect(
        verificationLanded(
          before: _row(pendingDocs: 3),
          after: _row(pendingDocs: 1),
        ),
        isFalse,
      );
    });
  });

  group('resolveVerificationWriteOutcome', () {
    test('a moved profile is landed', () async {
      expect(
        await resolveVerificationWriteOutcome(
          before: _row(),
          fetch: () async => _row(pendingDocs: 3),
        ),
        WriteOutcome.landed,
      );
    });

    test('an unchanged profile is missing, never landed', () async {
      expect(
        await resolveVerificationWriteOutcome(
          before: _row(),
          fetch: () async => _row(),
        ),
        WriteOutcome.missing,
      );
    });

    // The phone is still offline. NOT proof the write failed, and «did not
    // arrive» is how a man deletes the only copy of his ID card.
    test('a re-read that fails is unknown, never missing', () async {
      expect(
        await resolveVerificationWriteOutcome(
          before: _row(),
          fetch: () async => throw StateError('offline'),
        ),
        WriteOutcome.unknown,
      );
    });
  });

  group('dossierOutcomeCopy', () {
    test('the landed line claims the dossier, not a found row', () {
      expect(dossierOutcomeCopy(WriteOutcome.landed),
          S.dossierUnconfirmedLanded);
      // The shared line says «وجدناه في القائمة» — meaningless here, the
      // profile was on screen the whole time.
      expect(dossierOutcomeCopy(WriteOutcome.landed),
          isNot(S.writeUnconfirmedLanded));
    });

    test('the missing line is retryable, the unknown one is not', () {
      expect(dossierOutcomeCopy(WriteOutcome.missing),
          S.dossierUnconfirmedMissing);
      expect(dossierOutcomeCopy(WriteOutcome.missing), contains('أعد'));
      expect(dossierOutcomeCopy(WriteOutcome.unknown),
          S.writeUnconfirmedUnknown);
    });
  });

  group('on the real screen', () {
    /// Renders [VerificationScreen] against a server that answers profile reads
    /// with [profile] and stalls the dossier POST.
    ///
    /// Exposed on its own so the `setState` regression can be proved without
    /// driving the whole submit flow — that test is about the refresh, and
    /// making it depend on three picks and a scroll would couple it to the
    /// picker for no reason.
    Future<ApiClient> pumpVerification(
      WidgetTester tester,
      Map<String, Object?> profile,
    ) async {
      tester.view.physicalSize = const Size(420, 3400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.contains('/my/profile')) return _json(profile);
          if (p.endsWith('/api/login')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          return _json(<Object>[]);
        }),
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
      return api;
    }

    /// The stall is on the POST after the uploads, not a fake 500: a 5xx
    /// decodes to `errServer` and correctly skips the re-read. Only the
    /// ambiguous middle — files in R2, filing never answered — reaches the new
    /// code.
    Future<({List<String> said, int posts, int reads})> stalledDossier(
      WidgetTester tester, {
      required Map<String, Object?> Function(int read) after,
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
            // Outlasts the client's own patience, so the failure is ambiguous
            // rather than a refusal.
            await Future<void>.delayed(const Duration(milliseconds: 120));
            return _json(<String, Object?>{'ok': true});
          }
          if (p.contains('/my/profile')) {
            reads++;
            return _json(after(reads));
          }
          if (p.endsWith('/api/login')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          return _json(<Object>[]);
        }),
        timeout: const Duration(milliseconds: 25),
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

      // Pump in steps until the queue has drained, rather than one long pump.
      //
      // `ScaffoldMessenger` **queues** the verdict behind the «نتحقّق الآن من
      // القائمة…» line, which lasts four seconds — so a single 3-second pump
      // reads the placeholder and never the answer, and this file's first
      // draft asserted the placeholder twice while passing against a screen
      // that had just lied to the user. Outlast the first line, or the test
      // measures the queue rather than the verdict.
      //
      // **Sampled as it goes, not read at the end.** A SnackBar leaves the tree
      // when it times out, and the verdict lands about four seconds after the
      // recheck line — so collecting the tree after the queue has drained
      // returns an empty list and the test passes against a screen that said
      // nothing at all. The first draft of this file did exactly that, and it
      // is worth naming: a green widget test that measured nothing is worse
      // than a red one.
      final said = <String>[];
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        for (final bar in tester.widgetList<SnackBar>(find.byType(SnackBar))) {
          final text = (bar.content as Text).data;
          if (text != null && !said.contains(text)) said.add(text);
        }
      }

      return (
        said: <String>[
          ...said,
          ...tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? ''),
        ],
        posts: posts,
        reads: reads,
      );
    }

    // The screen case the pure rule cannot prove. Before the fix this printed
    // «وجدناه في القائمة» for a contractor whose profile never changed.
    testWidgets('an unchanged profile is not reported as a landing',
        (tester) async {
      final r = await stalledDossier(tester, after: (_) => _profile());
      final said = r.said;

      expect(r.posts, 1, reason: 'the dossier was never filed');
      expect(r.reads, greaterThanOrEqualTo(2),
          reason: 'the profile was never re-read after the stalled write');
      expect(said, contains(S.dossierUnconfirmedMissing),
          reason: 'nothing moved and the app claimed the documents arrived: $said');
      expect(said, isNot(contains(S.dossierUnconfirmedLanded)));
      expect(said, isNot(contains(S.writeUnconfirmedLanded)));
    });

    // The second defect, found by the same red run and on the line this tick
    // was already editing.
    //
    // `setState(() => _profile = _repo.myProfile())` hands the *Future* back to
    // `setState` as the result of the state change, which trips Flutter's
    // "setState() callback argument returned a Future" assert. It was on both
    // the retry button and the unconfirmed path — so the two ways a
    // verification screen re-reads itself both threw on the way, and the second
    // one threw on the exact line whose repair this file is about.
    testWidgets('refreshing the profile does not hand setState a Future',
        (tester) async {
      await pumpVerification(tester, _profile());
      // The retry button is the one a user reaches after a failed read.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        tester.takeException(),
        isNull,
        reason: 'a profile refresh tripped a Flutter assert: the refresh '
            'path throws on the way to repairing a failed read',
      );
    });

    // The positive half: the queue really did grow, so the receipt is true and
    // the screen must be allowed to say so.
    testWidgets('a grown queue is reported as a landing', (tester) async {
      final r = await stalledDossier(
        tester,
        after: (read) => read <= 1 ? _profile() : _profile(pendingDocs: 3),
      );
      final said = r.said;

      expect(r.reads, greaterThanOrEqualTo(2),
          reason: 'the profile was never re-read after the stalled write');
      expect(said, contains(S.dossierUnconfirmedLanded),
          reason: 'the queue grew and the app refused to say the papers arrived: $said');
    });
  });
}
