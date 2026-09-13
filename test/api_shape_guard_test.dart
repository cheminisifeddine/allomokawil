import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/app.dart';
import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/error_copy.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// Every way a response can arrive in a shape the app did not ask for, and the
/// Arabic sentence the user must get instead of silence.
///
/// Before this file, `_decode` handed a non-JSON 2xx body back as a raw string
/// and the repository cast it with `as List` / `as Map<String, dynamic>`. A
/// drifted column — a missing `id`, a numeric `wilaya` — raised a `TypeError`,
/// which is an `Error` and therefore invisible to the nine `on Exception`
/// clauses on the action paths. The request died quietly: `_error` stayed null,
/// the spinner cleared in `finally`, and the user tapped the button and watched
/// nothing happen. These are the regression tests for the fix.

/// A captive portal / ISP notice: a 200 the Worker never wrote. Plain ASCII,
/// like the ones an Algerian ISP actually injects, and an Arabic variant that
/// arrives with its own charset.
const _portal = '<!DOCTYPE html><html><head><title>Connexion requise'
    '</title></head><body>Portail de l operateur</body></html>';
const _portalAr = '<!DOCTYPE html><html><body>يجب تسجيل الدخول إلى الشبكة'
    '</body></html>';

http.Response _html(int status) =>
    http.Response(_portal, status, headers: {'content-type': 'text/html'});

http.Response _htmlAr(int status) => http.Response(_portalAr, status,
    headers: {'content-type': 'text/html; charset=utf-8'});

http.Response _json(Object? body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

ApiClient _api(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(httpClient: MockClient(handler), baseUrls: ['https://x.test']);

/// The one Arabic sentence every shape failure must land on.
Matcher get _unexpectedArabic => throwsA(
      isA<ApiException>()
          .having((e) => e.message, 'message', S.errUnexpected)
          .having((e) => isArabicCopy(e.message), 'Arabic copy', isTrue),
    );

void main() {
  group('the network layer', () {
    test('a 2xx that is not JSON is a sentence, not a raw string', () async {
      final api = _api((_) async => _html(200));
      await expectLater(api.get('/api/mobile/workers/top?limit=1'),
          _unexpectedArabic);
    });

    test('an empty 2xx body is still null — the ack endpoints keep working',
        () async {
      final api = _api((_) async => http.Response('', 200));
      expect(await api.get('/api/ping'), isNull);
    });

    test('the failure keeps the status code for the caller', () async {
      final api = _api((_) async => _html(200));
      try {
        await api.get('/api/ping');
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 200);
        // The cause is the page itself, bounded, for logging only.
        expect((e.cause! as String).length, lessThanOrEqualTo(200));
      }
    });
  });

  group('the repository', () {
    test('a feed that answers an object where an array belongs', () async {
      final repo = Repository(_api((_) async => _json({'rows': <Object>[]})));
      await expectLater(repo.searchWorkers(), _unexpectedArabic);
    });

    test('a worker row missing its id (the TypeError repro)', () async {
      final repo = Repository(_api(
          (_) async => _json([
                {'full_name': 'مقاول بلا معرّف'}
              ])));
      await expectLater(repo.searchWorkers(), _unexpectedArabic);
    });

    test('a row whose wilaya column came back as a number', () async {
      final repo = Repository(_api(
          (_) async => _json([
                {'id': 1, 'user_id': 2, 'full_name': 'م', 'user_wilaya': 16}
              ])));
      await expectLater(repo.topWorkers(), _unexpectedArabic);
    });

    test('a page that is an HTML portal instead of JSON', () async {
      final repo = Repository(_api((_) async => _html(200)));
      await expectLater(repo.topWorkers(), _unexpectedArabic);
    });

    test('an Arabic portal page is not mistaken for server copy', () async {
      final repo = Repository(_api((_) async => _htmlAr(200)));
      await expectLater(repo.topWorkers(), _unexpectedArabic);
    });

    test('a conversation answer with no id', () async {
      final repo = Repository(_api((_) async => _json({'ok': true})));
      await expectLater(
          repo.openConversation(projectId: 'p1', otherUserId: 4),
          _unexpectedArabic);
    });

    test('a well-formed answer still parses exactly as before', () async {
      final repo = Repository(_api((_) async => _json([
            {
              'id': 7,
              'user_id': 9,
              'full_name': 'أحمد البناء',
              'specialties': ['بناء'],
              'avg_rating': 4.5,
              'total_reviews': 3,
            }
          ])));
      final workers = await repo.topWorkers();
      expect(workers, hasLength(1));
      expect(workers.single.id, 7);
      expect(workers.single.fullName, 'أحمد البناء');
    });
  });

  group('auth', () {
    test('a login answered with an ack instead of a session', () async {
      final api = _api((_) async => _json({'ok': true}));
      final auth = AuthState(api);
      await expectLater(
        auth.login(phone: '0550000000', password: 'secret123'),
        _unexpectedArabic,
      );
      // No half-session: a failed login must not leave a user behind.
      expect(auth.isAuthenticated, isFalse);
      expect(auth.user, isNull);
    });

    test('a login whose user row is missing a column', () async {
      final api = _api((_) async => _json({
            'token': 't',
            'user': {'full_name': 'بلا معرّف'},
          }));
      final auth = AuthState(api);
      await expectLater(
        auth.login(phone: '0550000000', password: 'secret123'),
        _unexpectedArabic,
      );
      expect(auth.isAuthenticated, isFalse);
    });
  });

  testWidgets(
      'the sign-in button comes back, with a sentence, on a broken 200',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    // The portal answers the sign-in POST with HTML and a 200.
    final client = MockClient((req) async {
      if (req.url.path == '/api/login') return _html(200);
      if (req.url.path == '/api/unread') return http.Response('0', 200);
      return _json(const <Object>[]);
    });
    final api = ApiClient(httpClient: client, baseUrls: ['https://x.test']);
    final auth = AuthState(api);
    await auth.restore();

    await tester.pumpWidget(
      AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('landing-create-account')));
    await tester.tap(find.byKey(const Key('landing-create-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role-guide-customer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-tab-signin')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('dz-phone-input')), '0550000000');
    await tester.enterText(
        find.byKey(const Key('auth-password')), 'secret123');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();

    // The sentence is on screen — the old failure left the form silent — and
    // the button is tappable again, so the user can retry.
    expect(find.text(S.errUnexpected), findsOneWidget);
    final button =
        tester.widget<PrimaryButton>(find.byKey(const Key('auth-submit')));
    expect(button.loading, isFalse);
    expect(button.onPressed, isNotNull);
    // Still on the auth screen: nothing was navigated away from.
    expect(find.byKey(const Key('auth-tab-signin')), findsOneWidget);
  });
}
