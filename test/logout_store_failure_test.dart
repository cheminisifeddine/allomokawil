// Signing out must not throw when the device's preference store refuses.
//
// The defect this pins, found in a read-only audit of `auth_state.dart` on
// 27 Sep. Every other method in that class is careful about a store that will
// not answer:
//
//   * `restore()` wraps the whole read in a try and lands the user on the
//     login form rather than throwing out of `main()` before `runApp`;
//   * `_discardSession()` catches around the key removal;
//   * `enterAsGuest()` and `leaveGuest()` each catch their own write;
//   * `_clearOutbox()` catches, and the comment says why: "a queue that cannot
//     be cleared is a privacy problem to report, not a reason to leave a dead
//     session on screen."
//
// `logout()` is the one method in the file with no `try` around any of it. It
// is also the method the 401 handler calls, from an async callback nobody
// awaits, so an exception thrown here is not caught by the screen that made
// the request — it becomes an unhandled asynchronous error. On the sign-out
// button it is worse: `AppCard.onTap` is a `VoidCallback`, so a throw out of
// the handler is a red screen and a console trace, with the user still looking
// at a signed-in home whose keys were already removed from the in-memory cache
// but never cleared on disk.
//
// What that means for the founder's actual bug, «انتهت جلستك» over a dead
// session: the recovery path itself is the thing that crashes. The user's
// token is stale, the app correctly decides to sign him out, and the sign-out
// throws while the store is unhappy — so the phone is left *still signed out
// in memory* with the dead token still written on disk. The next launch
// restores it and the same 401 comes back. The recovery never completes, and
// the user is stuck in a loop with no way forward but reinstalling.
//
// The fix is the invariant the rest of the file already keeps: drop the
// in-memory session first, because that is the part the user is looking at,
// then attempt each key removal independently so one refused write cannot
// strand the others, then the queue, then notify. Never throws.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The refusing store is built by extending the plugin's own in-memory
// implementation, which lives in the platform-interface package. It is
// referenced rather than depended on because the test seam needs exactly that
// class and nothing else, and adding a dependency to production pubspec for a
// test-only subclass is the wrong trade.
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/data/chat_outbox.dart';

const _customer = {
  'id': 1,
  'phone': '0550000000',
  'email': null,
  'full_name': 'Test Client',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
};

const _words = 'العنوان: حسين داي، الطابق الثالث';

/// A store that is healthy for reads and refuses every write.
///
/// This is the real failure: on a full disk, a corrupt preferences file, or an
/// OS that has revoked the app's storage, `remove` is a platform call that
/// throws. It is not a hypothetical — `_clearOutbox` and `restore` both exist
/// precisely because the app already decided it has to survive it.
class _RefusingStore extends InMemorySharedPreferencesStore {
  // A super parameter cannot express this: the plugin's constructor is named
  // `withData`, and super parameters match the *super* constructor's name.
  // ignore: use_super_parameters
  _RefusingStore(Map<String, Object> seed) : super.withData(seed);

  @override
  Future<bool> remove(String key) async =>
      throw StateError('preferences storage is unavailable');

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      throw StateError('preferences storage is unavailable');
}

ApiClient _api(int status) => ApiClient(
      httpClient: MockClient((req) async => http.Response(
            jsonEncode({'error': 'انتهت الجلسة'}),
            status,
            headers: {'content-type': 'application/json'},
          )),
      baseUrls: ['https://x.test'],
    );

/// The live in-memory store `restore` ran against, captured once so the
/// refusing store can be layered over exactly the values on the phone.
SharedPreferences? _instance;

/// Those values, keyed the way the platform layer holds them.
Map<String, Object> _seed() =>
    <String, Object>{for (final k in _instance!.getKeys()) k: _instance!.get(k)!};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('signing out survives a store that refuses to write', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth.token': 'dead-token',
        'auth.user': jsonEncode(_customer),
        chatOutboxKey: jsonEncode([
          {
            'id': '5.1700000000000000.0',
            'conversation_id': 5,
            'text': _words,
            'created_at': 1700000000000,
          }
        ]),
      });
    });

    tearDown(() {
      // Hand the real in-memory store back so no other file inherits a store
      // that throws.
      SharedPreferences.setMockInitialValues({});
      SharedPreferences.resetStatic();
    });

    test('logout() does not throw when the store refuses every removal',
        () async {
      _instance = await SharedPreferences.getInstance();
      final auth = AuthState(_api(200));
      await auth.restore();
      expect(auth.isAuthenticated, isTrue, reason: 'restored from storage');

      // Swap in the refusing store *after* restore, so the read path is real
      // and only the write path is hostile.
      SharedPreferencesStorePlatform.instance = _RefusingStore(_seed());

      // The whole contract: no exception escapes the sign-out.
      await expectLater(auth.logout(), completes);

      // And the session is gone from the part the user is looking at, even
      // though the disk refused. This is the half that must never be lost.
      // (`role` is deliberately not asserted: it falls back to the customer
      // dashboard when there is no user, which is the signed-out state, so it
      // would pass whether or not the sign-out happened.)
      expect(auth.isAuthenticated, isFalse);
      expect(auth.user, isNull);
    });

    test('a 401 on a store that refuses still signs the user out', () async {
      // This is the founder's reported bug: the token goes stale, the server
      // answers 401, and the recovery must complete. Before the fix, the
      // throw happened inside the un-awaited handler and the user was left
      // signed out in memory with a dead token still on disk — the same
      // «انتهت جلستك» loop, forever.
      _instance = await SharedPreferences.getInstance();
      final auth = AuthState(_api(401));
      await auth.restore();
      expect(auth.isAuthenticated, isTrue, reason: 'restored from storage');

      SharedPreferencesStorePlatform.instance = _RefusingStore(_seed());

      await expectLater(
        auth.handleUnauthorized(),
        completes,
        reason: 'the recovery path must not throw out of the 401 handler',
      );

      expect(auth.isAuthenticated, isFalse);
      expect(auth.sessionExpired, isTrue,
          reason: 'the landing page explains the sign-out with this flag');
    });

    test('listeners are still told, so the screen returns to the landing page',
        () async {
      // The third harm, and the one the user actually sees. `notifyListeners`
      // is the last statement of `logout()`, so a throw from the removals
      // above skipped it: the user tapped «تسجيل الخروج», `isAuthenticated`
      // was already false, and yet the root gate never heard about it, so the
      // signed-in home stayed on screen. The sign-out had happened and the
      // screen did not know.
      _instance = await SharedPreferences.getInstance();
      final auth = AuthState(_api(200));
      await auth.restore();

      var told = 0;
      auth.addListener(() => told++);

      SharedPreferencesStorePlatform.instance = _RefusingStore(_seed());

      await expectLater(auth.logout(), completes);
      expect(told, greaterThan(0),
          reason: 'a sign-out the screen cannot hear is a sign-out that did not '
              'happen as far as the user is concerned');
    });
  });
}
