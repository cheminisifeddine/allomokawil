import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/app.dart';
import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/boot.dart';
import 'package:allomokawil/src/core/diagnostics/boot_trace.dart';
import 'package:allomokawil/src/core/diagnostics/crash_reporter.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/widgets/skeletons.dart';

/// The half of the cold-start audit that lives in Dart: `main()` no longer
/// awaits storage before `runApp`, so this file pins both halves of that
/// trade — the session still restores, and the frame it used to block on is
/// painted first.
const _customer = <String, Object?>{
  'id': 1,
  'phone': '0550000000',
  'email': null,
  'full_name': 'Test Client',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-01-01 00:00:00',
};

http.Response _ok(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    );

ApiClient _api() => ApiClient(
      httpClient: MockClient((req) async {
        if (req.url.path == '/api/unread') return _ok('0');
        return _ok('[]');
      }),
      baseUrls: const ['https://x.test'],
    );

/// A store that keeps the lines in memory, so a previous run can be simulated
/// without a platform channel.
class _MemoryStore implements CrashStore {
  _MemoryStore([List<String>? seed]) : lines = <String>[...?seed];

  List<String> lines;

  @override
  Future<List<String>> read() async => List<String>.of(lines);

  @override
  Future<void> write(List<String> next) async {
    lines = List<String>.of(next);
  }
}

/// A session restore that fails hard, to prove the guard still catches it now
/// that nobody awaits the call.
class _ExplodingAuth extends AuthState {
  _ExplodingAuth(super.api);

  @override
  Future<void> restore() async => throw StateError('storage gone');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('warmup restores the stored session after the frame, and says so',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.token': 'test-token',
      'auth.user': jsonEncode(_customer),
    });
    final auth = AuthState(_api());
    final crashes = CrashReporter(store: _MemoryStore());
    var now = 0;
    final trace = BootTrace(nowMs: () => now);

    now = 96;
    await Boot.warmup(auth: auth, crashes: crashes, trace: trace);

    expect(auth.isRestored, isTrue);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.role, UserRole.customer);
    expect(auth.user!.fullName, 'Test Client');
    // Both reads are marked, so the boot line reports what ran off-path. They
    // start together, so which one lands first is the scheduler's business —
    // what must hold is that neither is missing and that the pair accounts for
    // all the elapsed time rather than inventing or losing any of it.
    expect(trace.phases.map((p) => p.name).toList(),
        containsAll(<String>['session', 'crash-log']));
    expect(trace.msFor('session') + trace.msFor('crash-log'), 96);
  });

  test("the previous run's crashes land behind this run's, not on top of them",
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _MemoryStore(<String>[
      jsonEncode(<String, Object?>{
        'at': '2026-09-13T08:00:00.000Z',
        'kind': 'flutter',
        'message': 'previous run',
        'detail': '',
      }),
    ]);
    final crashes = CrashReporter(store: store);

    // A crash caught while the skeleton was on screen, before the read lands —
    // the ordering this change had to keep true.
    crashes.capture(StateError('this run'), StackTrace.current,
        kind: 'startup', context: 'unit test');
    await Boot.warmup(auth: AuthState(_api()), crashes: crashes);

    expect(crashes.log.length, 2);
    expect(crashes.log.records.first.message, contains('previous run'));
    expect(crashes.log.latest?.message, contains('this run'));
  });

  test('a restore that throws is captured and the app stays logged out',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final crashes = CrashReporter(store: _MemoryStore());

    await Boot.restoreSession(_ExplodingAuth(_api()), crashes);

    expect(crashes.log.latest?.message, contains('storage gone'));
    expect(crashes.log.latest?.kind, 'startup');
  });

  testWidgets('the gate paints the boot skeleton before storage answers, '
      'then the landing page', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The sweep never settles, so the tree is pumped by hand.
    SkeletonMotion.enabled = false;
    addTearDown(() => SkeletonMotion.enabled = true);

    final api = _api();
    final auth = AuthState(api);
    final crashes = CrashReporter(store: _MemoryStore());

    await tester.pumpWidget(
      AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
    );
    await tester.pump();

    // Frame one, exactly as `main()` now leaves it: storage has not answered.
    expect(auth.isRestored, isFalse);
    expect(find.byType(AppBootSkeleton), findsOneWidget);
    expect(find.byKey(const Key('landing-role-customer')), findsNothing);

    // The reads `main()` used to await now run behind the frame.
    await Boot.warmup(auth: auth, crashes: crashes, trace: BootTrace());
    await tester.pump();

    expect(auth.isRestored, isTrue);
    expect(find.byType(AppBootSkeleton), findsNothing);
    expect(find.byKey(const Key('landing-role-customer')), findsOneWidget);
  });
}
