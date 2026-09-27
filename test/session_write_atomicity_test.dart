// Signing in must not be able to write half a session to the phone.
//
// Found in a read-only audit of `auth_state.dart` on 27 Sep, immediately after
// the sign-out fix in the same file. `_persist` was the last method in the
// class that wrote the session as **two** values:
//
//     await prefs.setString(_tokenKey, token);
//     await prefs.setString(_userKey, jsonEncode(user.toJson()));
//
// Each of those is a platform call that reaches the disk. A process that dies
// between them — the OS reclaiming memory, a battery pull, the user swiping
// the app out of the switcher on a phone that is out of RAM — leaves
// `auth.token` written and no user beside it.
//
// That is the exact state `restore()` classifies as "half a session": it
// discards the pair and opens the login form. So the failure the founder would
// see is a user who signed in correctly, got a signed-in home, and was signed
// out again by the *next* launch, with no error, no notice, and no session
// notice either — nothing that says a write died halfway. The user's account
// on the server is fine; the phone simply forgot it, and no amount of
// re-typing the password explains the second sign-out.
//
// It is worth being precise about why this is a real defect and not a
// theoretical one: it is the one place in the app that *manufactures* the
// corrupt input that `restore()` and `_discardSession()` were written to
// survive. Everything else in this file is defending against a bad file; this
// was writing one.
//
// The fix is to store the session as a single value. One write cannot be
// half-completed, so the window does not exist — a value that is not a
// complete session is discarded on the next boot rather than half-restored.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The in-memory store the death is simulated against lives in the
// platform-interface package; it is a dev dependency for exactly this reason.
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';

const _customer = {
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

/// A store whose writes die after the first one succeeds.
///
/// This is the shape of the real failure, not a mock of it: the process is
/// alive long enough to complete one platform write and is gone before the
/// second. Modelling it as "every write throws" would test the *refusing*
/// store, which is a different failure — that one is covered, and it is
/// handled, because a sign-in the server accepted is never refused on the
/// strength of a disk.
///
/// The kill happens after [writesBeforeDeath] successful `setValue` calls, so
/// the two-key write left the token on disk and died reaching the user, which
/// is the state that produced the second sign-out.
class _DyingStore extends InMemorySharedPreferencesStore {
  // A super parameter cannot express this: the plugin's constructor is named
  // `withData`, and super parameters match the *super* constructor's name.
  // ignore: use_super_parameters
  _DyingStore(Map<String, Object> seed) : super.withData(seed);

  int _accepted = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (_accepted >= writesBeforeDeath) {
      throw StateError('the process was killed mid-write');
    }
    _accepted++;
    return super.setValue(valueType, key, value);
  }
}

/// How many writes the phone completes before it dies. One, so the failure
/// lands in the window the old code opened.
var writesBeforeDeath = 1;

/// The platform layer holds every key under a `flutter.` prefix — that is how
/// `SharedPreferences.setMockInitialValues` seeds it and how `getAll` reports
/// it — while the app only ever names `auth.token`. This is the one place the
/// two vocabularies meet, so the test reads and writes in the app's names and
/// lets this do the translation. Getting this wrong is not subtle: it made the
/// upgrade tests fail on the *old* code too, which is how it was caught.
Map<String, Object> _logical(Map<String, Object> stored) => <String, Object>{
      for (final entry in stored.entries)
        entry.key.startsWith('flutter.')
            ? entry.key.substring('flutter.'.length): entry.key: entry.value,
    };

/// The `/api/login` answer that starts the sign-in.
ApiClient _api() => ApiClient(
      httpClient: MockClient((req) async => http.Response(
            jsonEncode({
              'token': 'fresh-token',
              'user': _customer,
            }),
            200,
            headers: {'content-type': 'application/json'},
          )),
      baseUrls: ['https://x.test'],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('signing in cannot leave half a session on the phone', () {
    test('a process death after the first write still boots a whole session',
        () async {
      // An empty phone: the thing at risk here is the session being written
      // for the first time, which is the sign-in itself.
      SharedPreferences.setMockInitialValues({});

      writesBeforeDeath = 1;
      SharedPreferencesStorePlatform.instance =
          _DyingStore(<String, Object>{});

      final auth = AuthState(_api());
      // The sign-in completes for the user: the account exists on the server,
      // and the token is attached, so the app shows them their home.
      //
      // `completes` is part of the contract, not a formality. `_persist` sets
      // the in-memory session *before* it writes, so a store that dies
      // mid-write used to leave the user signed in on screen with an error
      // dialog over them — `login()` threw, the auth screen caught it and
      // showed `errorCopy(e)`, which for a `StateError` is the raw framework
      // string, in English, on an Arabic form. On the old code this is the
      // failure you see first; the half-pair is what is left behind after.
      await expectLater(
        auth.login(phone: '0550000000', password: 'secret'),
        completes,
        reason: 'the server accepted the sign-in, so a store that dies '
            'mid-write must not turn it into an error on the form',
      );
      expect(auth.isAuthenticated, isTrue);
      expect(auth.user!.fullName, 'Test Client');

      // Read what the dead process actually left on the phone. The dying store
      // is still installed, and it answers reads.
      final stored =
          _logical(await SharedPreferencesStorePlatform.instance.getAll());

      // The contract, and the whole point: there is no state on this phone in
      // which half a session exists. The old two-key write died here — token
      // written, user not — and left precisely a 'half a session' for
      // restore() to throw away.
      final halfPair = (stored.containsKey('auth.token') ||
              stored.containsKey('auth.user')) &&
          !(stored.containsKey('auth.token') && stored.containsKey('auth.user'));
      expect(halfPair, isFalse,
          reason: 'a token with no user beside it is what restore() discards, '
              'so writing one is the same as signing the user out: $stored');

      // And the next launch must reach the same conclusion the phone reached
      // before it died, rather than the opposite one.
      // `setMockInitialValues` installs a fresh in-memory store over whatever
      // the dying one left behind, which is exactly the next launch: a new
      // process, the same disk. (Seeding a *second* store by hand here is what
      // this line replaced — the hand-seeded map was already in the app's key
      // vocabulary, so the platform's `flutter.` filter hid every value from
      // it and the relaunched app saw an empty phone. A harness failure that
      // looked exactly like a product failure.)
      SharedPreferences.setMockInitialValues(stored);
      final relaunched = AuthState(_api());
      await relaunched.restore();

      expect(relaunched.isRestored, isTrue);
      expect(relaunched.user, isNotNull,
          reason: 'a whole session survived the crash, so the user stays '
              'signed in — the old code signed them out here, silently');
      expect(relaunched.user!.phone, '0550000000');
    });

    test('the whole session lands in one value, not two keys', () async {
      // The shape assertion behind the fix: with the pair gone, there is no
      // pair to be half-written. A reader of this test should be able to see
      // the two-key write it replaced.
      SharedPreferences.setMockInitialValues({});
      writesBeforeDeath = 99; // Let every write through.
      SharedPreferencesStorePlatform.instance = _DyingStore({});

      final auth = AuthState(_api());
      await auth.login(phone: '0550000000', password: 'secret');

      final stored =
          _logical(await SharedPreferencesStorePlatform.instance.getAll());
      expect(stored.containsKey('auth.session'), isTrue);
      expect(stored.containsKey('auth.token'), isFalse);
      expect(stored.containsKey('auth.user'), isFalse);

      // The envelope really does carry both halves.
      final envelope = jsonDecode(stored['auth.session']! as String);
      expect(envelope['token'], 'fresh-token');
      expect((envelope['user'] as Map)['phone'], '0550000000');
    });

    test('a phone signed in by the old build keeps its session', () async {
      // The upgrade path. A device that signed in before this change has the
      // split pair on disk, and the fix must not sign those users out — that
      // would be a far worse bug than the one it fixes.
      SharedPreferences.setMockInitialValues({
        'auth.token': 'legacy-token',
        'auth.user': jsonEncode(_customer),
      });

      final auth = AuthState(_api());
      await auth.restore();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.user!.phone, '0550000000');
    });

    test('the legacy pair is rewritten as one value after the upgrade', () async {
      // Read once, then migrated, so the next launch is the new world and the
      // window cannot reopen on the phone that had it.
      SharedPreferences.setMockInitialValues({
        'auth.token': 'legacy-token',
        'auth.user': jsonEncode(_customer),
      });

      final auth = AuthState(_api());
      await auth.restore();

      final stored =
          _logical(await SharedPreferencesStorePlatform.instance.getAll());
      expect(stored.containsKey('auth.session'), isTrue);
      expect(stored.containsKey('auth.token'), isFalse,
          reason: 'two copies of a session on one phone is one more thing to '
              'go out of step with the other');
      expect(stored.containsKey('auth.user'), isFalse);
    });
  });
}
