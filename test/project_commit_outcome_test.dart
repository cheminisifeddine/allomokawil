// The three owner writes on the project detail screen now answer for
// themselves, and the decoy that made the fix look unnecessary.
//
// Found 28 Sep 2026. Seven write paths re-read the server after
// `errWriteUnconfirmed` and say which of three things is true. `_accept`,
// `_complete` and `_cancel` — the three buttons that commit a contract, close a
// job and withdraw one, on the same screen whose bid form already had the
// contract forty lines down — did not. Each caught the failure, called
// `errorCopy(e)` and returned, so the owner was told «تحقّق من القائمة قبل
// إعادة المحاولة» about a list that was never re-read and could not be checked
// by eye without knowing what the server would have said.
//
// Two halves, because a rule nothing is wired to passes clean:
//  * the predicate and the copy, pure and testable without a widget;
//  * the screen, over a real stalled POST, because "the screen asks the
//    question at all" is not a property of the helper.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:allomokawil/src/data/project_commit_outcome.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

/// The contractor whose bid is under test. A different value per test would be
/// the same discipline as the portfolio decoy, but the decoy that matters here
/// is the *worker's* id, so the number is fixed and the decoy is built around it.
const int worker = 16;
const int otherWorker = 77;

Map<String, Object?> _user() => <String, Object?>{
      'id': 30,
      'phone': '0773000000',
      'email': null,
      'full_name': 'زبون تجربة',
      'type': 'customer',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

Map<String, Object?> _wire({
  String status = 'open',
  int? selectedWorker,
}) =>
    <String, Object?>{
      'id': 'p1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': 'دهان كامل مع تصليح',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': status,
      'selected_worker_id': selectedWorker,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

Map<String, Object?> _quote(int id, {int workerId = worker}) => <String, Object?>{
      'id': id,
      'project_id': 'p1',
      'worker_id': workerId,
      'amount': 70000,
      'message': 'يمكنني البدء غداً',
      'estimated_days': 5,
      'worker_full_name': 'مقاول تجربة',
      'worker_avatar_url': null,
      'worker_avg_rating': 0,
      'worker_total_reviews': 0,
      'worker_verification_status': 'verified',
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  int projectReads(List<String> log) =>
      log.where((e) => e == 'GET /api/mobile/projects/p1').length;


void main() {
  // ── The rule ─────────────────────────────────────────────────────────────
  group('projectCommitHolds', () {
    test('the accept landed: in progress, committed to this worker', () {
      expect(
        projectCommitHolds(
            Project.fromJson(_wire(status: 'in_progress', selectedWorker: worker)),
            ProjectCommit.accept,
            workerId: worker),
        isTrue,
      );
    });

    // The decoy this whole item turns on. A stalled accept, re-read: the
    // project IS in progress — status alone would call that a landed contract —
    // but the worker is somebody else's. A predicate that read only `status`
    // would tell a client his bid won when a competitor's won, which is the one
    // answer on this screen that costs him a contract he can see happening.
    test('in progress, but committed to another worker, is not my accept', () {
      expect(
        projectCommitHolds(
            Project.fromJson(
                _wire(status: 'in_progress', selectedWorker: otherWorker)),
            ProjectCommit.accept,
            workerId: worker),
        isFalse,
        reason: 'status alone would call a rival\'s contract mine',
      );
    });

    // The same row, read by the same rule, when the phone never learned which
    // worker the bid belonged to. Naming a worker we cannot name is not
    // evidence; a conservative false is a «missing» the owner may retry, and
    // the alternative is «landed» for a hire that may not exist.
    test('an accept with no worker to name is never a landing', () {
      expect(
        projectCommitHolds(
            Project.fromJson(
                _wire(status: 'in_progress', selectedWorker: worker)),
            ProjectCommit.accept),
        isFalse,
      );
    });

    test('an open project accepted nothing', () {
      expect(
        projectCommitHolds(Project.fromJson(_wire()),
            ProjectCommit.accept,
            workerId: worker),
        isFalse,
      );
      // A `selected_worker_id` left over from an earlier run does not make an
      // open project hired.
      expect(
        projectCommitHolds(
            Project.fromJson(_wire(selectedWorker: worker)),
            ProjectCommit.accept,
            workerId: worker),
        isFalse,
      );
    });

    test('complete and cancel each answer to their own status', () {
      final done = Project.fromJson(_wire(status: 'completed'));
      final gone = Project.fromJson(_wire(status: 'cancelled'));
      expect(projectCommitHolds(done, ProjectCommit.complete), isTrue);
      expect(projectCommitHolds(gone, ProjectCommit.cancel), isTrue);
      // Cross-wired: a closed job is not a withdrawal, and one must not be
      // allowed to vouch for the other.
      expect(projectCommitHolds(done, ProjectCommit.cancel), isFalse);
      expect(projectCommitHolds(gone, ProjectCommit.complete), isFalse);
    });
  });

  group('classifyProjectCommit', () {
    test('landed, with no stall, when the row agrees', () {
      final r = classifyProjectCommit(
          Project.fromJson(_wire(status: 'in_progress', selectedWorker: worker)),
          ProjectCommit.accept,
          workerId: worker);
      expect(r.outcome, WriteOutcome.landed);
      expect(r.stall, isNull);
    });

    test('missing when the row is untouched — the answer that may be retried', () {
      final r = classifyProjectCommit(Project.fromJson(_wire()),
          ProjectCommit.accept,
          workerId: worker);
      expect(r.outcome, WriteOutcome.missing);
      expect(r.stall, isNull);
    });

    // The two answers that must never be `missing`, because the missing
    // sentence ends in «أعد المحاولة» and neither is retryable.
    test('assigned to somebody else is a stall, not a retry', () {
      final r = classifyProjectCommit(
          Project.fromJson(
              _wire(status: 'in_progress', selectedWorker: otherWorker)),
          ProjectCommit.accept,
          workerId: worker);
      expect(r.stall, CommitStall.reassigned);
      expect(r.outcome, isNot(WriteOutcome.missing));
    });

    test('a cancelled project cannot be completed, and must not say retry', () {
      final r = classifyProjectCommit(
          Project.fromJson(_wire(status: 'cancelled')),
          ProjectCommit.complete);
      expect(r.stall, CommitStall.uncancellable);
      expect(r.outcome, isNot(WriteOutcome.missing));
    });

    // Ordering, and it is not incidental: a cancelled project *is* a landed
    // cancel, so the stall must not be reached first and describe a withdrawal
    // that happened as one that cannot happen.
    test('a landed cancel is landed, not stalled', () {
      final r = classifyProjectCommit(
          Project.fromJson(_wire(status: 'cancelled')), ProjectCommit.cancel);
      expect(r.outcome, WriteOutcome.landed);
      expect(r.stall, isNull);
    });

    // A completed project carries no worker, so the reassigned check must not
    // fire on a complete at all.
    test('a completed job is never described as reassigned', () {
      final r = classifyProjectCommit(
          Project.fromJson(_wire(status: 'completed')), ProjectCommit.complete);
      expect(r.stall, isNull);
      expect(r.outcome, WriteOutcome.landed);
    });
  });

  group('projectCommitCopy', () {
    test('each commit names itself, so three buttons are never conflated', () {
      for (final what in ProjectCommit.values) {
        final landed = projectCommitCopy(
            (outcome: WriteOutcome.landed, stall: null), what);
        final missing = projectCommitCopy(
            (outcome: WriteOutcome.missing, stall: null), what);
        // Six sentences, six distinct ones. A shared string here is how three
        // writes start claiming each other's outcome.
        expect({landed, missing}.length, 2,
            reason: 'landed and missing must differ for $what');
        expect({
          for (final w in ProjectCommit.values)
            projectCommitCopy((outcome: WriteOutcome.landed, stall: null), w),
        }.length, ProjectCommit.values.length,
            reason: 'two commits share one landed sentence');
        expect({
          for (final w in ProjectCommit.values)
            projectCommitCopy((outcome: WriteOutcome.missing, stall: null), w),
        }.length, ProjectCommit.values.length,
            reason: 'two commits share one missing sentence');
        expect(landed, isNot(matches(RegExp('[A-Za-z]'))),
            reason: 'a Latin letter in $landed');
        expect(missing, contains('أعد المحاولة'),
            reason: 'the only retryable answer must offer the retry: $missing');
      }
    });

    test('a stall never promises a retry, because there is none', () {
      for (final stall in CommitStall.values) {
        final copy = projectCommitCopy(
            (outcome: WriteOutcome.unknown, stall: stall),
            ProjectCommit.accept);
        expect(copy, isNot(contains('أعد المحاولة')),
            reason: 'a stalled write is not retryable: $copy');
      }
    });

    test('the unknown sentence is not the generic one, and says what to do', () {
      expect(projectCommitCopy((outcome: WriteOutcome.unknown, stall: null),
          ProjectCommit.accept), S.commitUnconfirmedUnknown);
      expect(S.commitUnconfirmedUnknown, isNot(S.writeUnconfirmedUnknown),
          reason: '«تحقّق من القائمة» is the instruction this screen cannot follow '
              '— the project is the screen');
    });
  });

  // ── Proof: the screen asks ───────────────────────────────────────────────
  //
  // [recheckFails] is the other half of the defect: the re-read is what makes
  // the answer honest, so a re-read that fails must not be read as «not saved».
  Future<({ApiClient api, AuthState auth, List<String> log})> boot({
    required FutureOr<http.Response> Function() onAccept,
    required String statusAfterReread,
    int? selectedAfterReread,
    bool recheckFails = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final log = <String>[];
    var rereads = 0;
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        log.add('${req.method} $p');
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json(<String, Object>{'token': 'tok', 'user': _user()});
        }
        if (p.endsWith('/api/unread')) return _json(0);
        if (p.startsWith('/api/mobile/projects/p1/quotes/') &&
            p.endsWith('/accept')) {
          return onAccept();
        }
        if (p.startsWith('/api/mobile/projects/p1/quotes')) {
          return _json(<Object>[_quote(9)]);
        }
        if (p == '/api/mobile/projects/p1') {
          // The FIRST read is the pre-accept row. Every read after it answers
          // the state the stalled write may or may not have produced, which is
          // what makes the re-read a real probe rather than a replay.
          if (rereads++ == 0) return _json(_wire());
          if (recheckFails) return http.Response('boom', 500);
          return _json(_wire(
              status: statusAfterReread, selectedWorker: selectedAfterReread));
        }
        return _json(<Object>[]);
      }),
    );
    final auth = AuthState(api);
    await auth.restore();
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);
    return (api: api, auth: auth, log: log);
  }

  Future<void> pump(WidgetTester tester, ApiClient api, AuthState auth) async {
    tester.view.physicalSize = const Size(392, 1900) * 2.75;
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
    await settle(tester);
  }

  testWidgets(
      'a stalled accept re-reads the project and says the contract was signed',
      (tester) async {
    // The stall is produced by the transport, not thrown by a fake repo: an
    // `ApiException` carrying `S.errWriteUnconfirmed` is exactly what a POST
    // whose answer never arrived raises, and a hand-thrown object would have
    // proved the screen handles a type rather than that the failure reaches it.
    final b = await boot(
      onAccept: () => throw ApiException(S.errWriteUnconfirmed),
      statusAfterReread: 'in_progress',
      selectedAfterReread: worker,
    );
    await pump(tester, b.api, b.auth);

    final before = projectReads(b.log);
    final finder = find.text('قبول العرض').first;
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(finder);
    await settle(tester, frames: 25);

    // The whole point: the project was read again. Before the fix this counter
    // never moved — the screen caught the failure, showed a sentence about a
    // list and returned.
    expect(projectReads(b.log), greaterThan(before),
        reason: 'an unconfirmed accept must re-read the project');
    expect(find.text(S.acceptUnconfirmedLanded), findsOneWidget);
  });

  testWidgets('a stalled accept that lost to a rival says so, and never says retry',
      (tester) async {
    final b = await boot(
      onAccept: () => throw ApiException(S.errWriteUnconfirmed),
      statusAfterReread: 'in_progress',
      selectedAfterReread: otherWorker,
    );
    await pump(tester, b.api, b.auth);

    final finder = find.text('قبول العرض').first;
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(finder);
    await settle(tester, frames: 25);

    expect(find.text(S.commitUnconfirmedReassigned), findsOneWidget);
    // The sentence a client would act on by pressing the button again.
    for (final t in tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')) {
      expect(t, isNot(contains('أعد المحاولة')));
    }
  });

  testWidgets(
      'a stalled accept the server never got is told he may retry — and once',
      (tester) async {
    final b = await boot(
      onAccept: () => throw ApiException(S.errWriteUnconfirmed),
      statusAfterReread: 'open',
    );
    await pump(tester, b.api, b.auth);

    final finder = find.text('قبول العرض').first;
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(finder);
    await settle(tester, frames: 25);

    expect(find.text(S.acceptUnconfirmedMissing), findsOneWidget);
    // A retry here cannot duplicate a contract — the server refuses every other
    // quote on the first accept — but it must not be sent twice by the app
    // either, so the guard still holds through the failed probe.
    expect(
        b.log.where((e) => e.endsWith('/accept') && e.startsWith('POST')).length,
        1);
  });

  testWidgets('a stalled accept whose re-read also failed claims nothing',
      (tester) async {
    final b = await boot(
      onAccept: () => throw ApiException(S.errWriteUnconfirmed),
      statusAfterReread: 'open',
      recheckFails: true,
    );
    await pump(tester, b.api, b.auth);

    final finder = find.text('قبول العرض').first;
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(finder);
    await settle(tester, frames: 25);

    // NOT `acceptUnconfirmedMissing`. The phone could not read the row, which is
    // not proof the accept failed, and «أعد المحاولة» is the one instruction
    // that would have the owner hire a second contractor if it landed.
    expect(find.text(S.commitUnconfirmedUnknown), findsOneWidget);
    expect(find.text(S.acceptUnconfirmedMissing), findsNothing);
  });
}
