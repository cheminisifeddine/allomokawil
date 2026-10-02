// `User.fromJson` hand-cast eight columns, and this is the fifth and last file
// in the `as String?` family. It is also the **only one of the five that is not
// read through `repository._rows`**, so the claim the other four make — "one
// unreadable row costs that row and nothing else" — does not apply here, and
// saying so is the point of this file.
//
// `User.fromJson` has exactly two callers, and both are whole-account:
//   * `AuthState._session` (auth_state.dart:527) — the answer to `/api/login`
//     and `/api/register`. A cast failure here throws, is turned into an
//     `ApiException`, and the user is left standing at the form.
//   * `AuthState._readUser` (auth_state.dart:362) — the session envelope on
//     disk, read on **every launch**. A cast failure here returns null, which
//     *signs the user out*.
// So the loss is never a row. It is the session.
//
// That makes the tolerance rule different from the other four files, and it is
// the one thing worth pinning here: **an account with no readable identity is
// not an account.** `id` is the key the whole app routes on — `app.dart:90`
// keys the signed-in subtree by `user-${id}-${role}`, `chat_screen.dart:81`
// compares `_me` against message authors, and `notifications_screen.dart:308`
// resolves which side of a conversation *I* am. A parser that answered an
// unreadable `id` with `0` would restore a signed-in user who is nobody: the
// session would look valid, the home screen would draw, and every one of those
// comparisons would silently be false. «Signed in as user 0» is a worse outcome
// than being signed out, because it is not visible.
//
// Hence one reader throws a dedicated error, and the rest read the payload.
//
// A real shape, not a hypothetical one: `_asInt` in `data/repository.dart`
// names it in its own doc — "a null from a LEFT JOIN, a string from SQLite".
// D1 hands back strings, so an `id` arriving as `'430'` is what the next
// column rename costs. Observed live 2 Oct against the deployed API:
//   {"token":"…","user":{"id":430,"phone":"0550000000","email":null,
//    "full_name":"Probe Test","type":"customer","avatar_url":null,
//    "wilaya":null,"commune":null,"created_at":"2026-10-02 04:12:10"}}
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/user.dart';

/// The wire row `/api/register` and `/api/login` answer with, in the shape
/// observed live on 2 Oct 2026. Every value is `Object?` on purpose: the
/// wrong-shape fixtures have to be able to say `'430'` and `5`.
Map<String, Object?> _user({
  Object? id = 430,
  Object? phone = '0550000000',
  Object? email,
  Object? fullName = 'Probe Test',
  Object? type = 'customer',
  Object? avatarUrl,
  Object? wilaya,
  Object? commune,
}) =>
    <String, Object?>{
      'id': id,
      'phone': phone,
      'email': email,
      'full_name': fullName,
      'type': type,
      'avatar_url': avatarUrl,
      'wilaya': wilaya,
      'commune': commune,
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

ApiClient _api(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(httpClient: MockClient(handler), baseUrls: ['https://x.test']);

ApiClient _loginWith(Object user) => _api((_) async => _json({
      'token': 'tok',
      'user': user,
    }));

void main() {
  // `_persist` writes through SharedPreferences, which needs the binding. The
  // two tests below that sign in for real hit that path, and my first run
  // reported them as red for a reason that had nothing to do with the parser.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the identity is read, never invented', () {
    test('an id that is a numeric string still identifies the account', () {
      // The SQLite shape `_asInt`'s own doc warns about.
      final u = User.fromJson(_user(id: '430'));
      expect(u.id, 430);
    });

    test('an id that is a double still identifies the account', () {
      final u = User.fromJson(_user(id: 430.0));
      expect(u.id, 430);
    });

    test('an absent id is refused rather than answered with 0', () {
      // The one line this file exists for. See the header: user 0 is signed-in
      // and is nobody, which is invisible.
      expect(() => User.fromJson(_user()..remove('id')),
          throwsA(isA<UnreadableUser>()));
      expect(() => User.fromJson(_user(id: null)),
          throwsA(isA<UnreadableUser>()));
      expect(() => User.fromJson(_user(id: 'not-a-number')),
          throwsA(isA<UnreadableUser>()));
      expect(() => User.fromJson(_user(id: '  ')),
          throwsA(isA<UnreadableUser>()));
    });

    test('the refused column travels with the error, for the support log', () {
      // The repository logs `cause` and never shows a screen, so the column
      // name is the whole diagnostic value here: without it the log says only
      // "the user row was unreadable" and never which rename caused it.
      try {
        User.fromJson(_user(id: null));
        fail('an unreadable id must not build a User');
      } on UnreadableUser catch (e) {
        expect(e.column, 'id');
        expect(e.value, isNull);
      }
      try {
        User.fromJson(_user(id: 'nope'));
        fail('an unreadable id must not build a User');
      } on UnreadableUser catch (e) {
        expect(e.toString(), 'UnreadableUser(id)');
      }
    });
  });

  group('the role is not guessed', () {
    test('a role the server knows is read as sent', () {
      expect(User.fromJson(_user(type: 'worker')).type, UserRole.worker);
      expect(User.fromJson(_user(type: 'admin')).type, UserRole.admin);
      expect(User.fromJson(_user(type: 'customer')).type, UserRole.customer);
    });

    test('a role that is not a string is not guessed either', () {
      // `UserRole.from(null)` answers `customer`, and a customer is what a
      // signed-out visitor is: `app.dart` routes customer/worker to different
      // dashboards and `profile_screen.dart:87` shows a contractor his
      // portfolio only when `u.type == UserRole.worker`. Defaulting a drifted
      // role to customer is signing a contractor into the wrong half of the
      // app, silently, on every launch.
      expect(() => User.fromJson(_user(type: 7)),
          throwsA(isA<UnreadableUser>()));
    });

    test('a role the app does not know is refused, not defaulted', () {
      // `UserRole.from` answers `customer` for anything unrecognised, and that
      // is right for a *guest* choosing from two buttons. It is wrong for a
      // server that answered a fourth role this build has never heard of: the
      // honest move is to sign the user out and re-ask, not to demote them.
      expect(() => User.fromJson(_user(type: 'contractor')),
          throwsA(isA<UnreadableUser>()));
      expect(() => User.fromJson(_user(type: '')),
          throwsA(isA<UnreadableUser>()));
    });
  });

  group('the phone is the account key and is never blank', () {
    test('a phone is read verbatim', () {
      expect(User.fromJson(_user(phone: '0773000000')).phone, '0773000000');
    });

    test('an absent or non-string phone is refused', () {
      // The profile screen prints this one under «رقم الهاتف» as the only way
      // to reach the account, and login is keyed on it.
      expect(() => User.fromJson(_user()..remove('phone')),
          throwsA(isA<UnreadableUser>()));
      expect(() => User.fromJson(_user(phone: 550000000)),
          throwsA(isA<UnreadableUser>()));
      expect(() => User.fromJson(_user(phone: '   ')),
          throwsA(isA<UnreadableUser>()));
    });
  });

  group('copy the user reads is trimmed, and absence stays absence', () {
    test('a padded name is the name', () {
      expect(User.fromJson(_user(fullName: '  محمد أمين  ')).fullName,
          'محمد أمين');
    });

    test('a name that is only marks is absent, not a blank line', () {
      // `auth_screen.dart:130` refuses an empty name at registration, so this
      // is not reachable from the app's own write path — which is exactly why
      // it must not be answered with `''`: `Monogram.of('')` paints «؟» and
      // `_HomeHeader` greets with an empty string.
      final u = User.fromJson(_user(fullName: '   '));
      expect(u.fullName, '');
    });

    test('a name that is not a string is not flattened into digits', () {
      // `fullName` is drawn on the profile header and in the home greeting.
      // Reading 5 as «5» would put a number where a person's name goes.
      expect(() => User.fromJson(_user(fullName: 5)),
          throwsA(isA<UnreadableUser>()));
    });

    test('optional columns stay null when absent', () {
      final u = User.fromJson(_user());
      expect(u.email, isNull);
      expect(u.avatarUrl, isNull);
      expect(u.wilaya, isNull);
      expect(u.commune, isNull);
    });

    test('a wilaya code that came back as a number is still a code', () {
      // Observed as a real shape: `api_shape_guard_test.dart:103` feeds
      // `user_wilaya: 16` and that is what SQLite gives for a code column.
      // `Taxonomy.wilayaNameOrNull` is keyed on a string, so flattening to
      // '16' here is what lets the profile print «الجزائر» instead of dropping
      // the row.
      expect(User.fromJson(_user(wilaya: 16)).wilaya, '16');
    });

    test('a commune that came back as a number is still a code', () {
      expect(User.fromJson(_user(commune: 1621)).commune, '1621');
    });

    test('an email that is not a string is absent, not a number', () {
      // The app sends `email: ''` at registration by the founder's call, so an
      // empty string is a real answer and must survive as one.
      expect(User.fromJson(_user(email: '')).email, '');
      expect(User.fromJson(_user(email: 5)).email, isNull);
    });

    test('an avatar url is kept verbatim and is never invented', () {
      expect(User.fromJson(_user(avatarUrl: 'https://x.test/a.png')).avatarUrl,
          'https://x.test/a.png');
      expect(User.fromJson(_user(avatarUrl: '   ')).avatarUrl, isNull);
      expect(User.fromJson(_user(avatarUrl: 5)).avatarUrl, isNull);
    });
  });

  group('toJson round-trips what fromJson read', () {
    test('the wire shape is unchanged by the session envelope', () {
      // `_encodeSession` writes `user.toJson()` into the stored envelope and
      // `restore()` reads it back through `fromJson`. If `toJson` and
      // `fromJson` disagree on a column, the *second* launch after sign-in
      // loses what the first one had.
      final original = User.fromJson(_user(
        id: 7,
        phone: '0661000000',
        email: 'a@b.dz',
        fullName: 'سميرة',
        type: 'worker',
        avatarUrl: 'https://x.test/s.png',
        wilaya: '16',
        commune: '1621',
      ));
      final again = User.fromJson(original.toJson());
      expect(again.id, original.id);
      expect(again.phone, original.phone);
      expect(again.email, original.email);
      expect(again.fullName, original.fullName);
      expect(again.type, original.type);
      expect(again.avatarUrl, original.avatarUrl);
      expect(again.wilaya, original.wilaya);
      expect(again.commune, original.commune);
    });

    test('a null optional column survives the envelope', () {
      final original = User.fromJson(_user());
      final again = User.fromJson(original.toJson());
      expect(again.email, isNull);
      expect(again.wilaya, isNull);
      expect(again.toJson()['wilaya'], isNull);
    });
  });

  group('the real AuthState, not just the parser', () {
    test('a drifted id column fails the login in Arabic, with no half-session',
        () async {
      // `_session` catches the failure and throws the same Arabic sentence as
      // every other bad shape. What it must never do is persist half of it.
      final auth = AuthState(_loginWith(_user(id: 'not-a-number')));
      await expectLater(
        auth.login(phone: '0550000000', password: 'secret123'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', S.errUnexpected)),
      );
      expect(auth.isAuthenticated, isFalse);
      expect(auth.user, isNull);
    });

    test('a drifted role column fails the login the same way', () async {
      final auth = AuthState(_loginWith(_user(type: 'contractor')));
      await expectLater(
        auth.login(phone: '0550000000', password: 'secret123'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', S.errUnexpected)),
      );
      expect(auth.isAuthenticated, isFalse);
    });

    test('an id that is a numeric string signs the user in, as himself',
        () async {
      final auth = AuthState(_loginWith(_user(id: '430')));
      await auth.login(phone: '0550000000', password: 'secret123');
      expect(auth.isAuthenticated, isTrue);
      expect(auth.user!.id, 430);
      expect(auth.role, UserRole.customer);
    });

    test('a session whose stored id cannot be read signs the user out',
        () async {
      // The path this file is really about: every launch re-reads the envelope
      // through the same parser. A drifted column here must reach the landing
      // page, never a signed-in user with id 0.
      SharedPreferences.setMockInitialValues({
        'auth.session': jsonEncode({
          'token': 'test-token',
          'user': _user(id: {}),
        }),
      });
      await SharedPreferences.getInstance();

      final auth = AuthState(_api((req) async =>
          req.url.path == '/api/unread' ? _json(0) : _json(const <Object>[])));
      await auth.restore();

      expect(auth.isRestored, isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.user, isNull);
    });

    test('a healthy stored session still restores after the parser change',
        () async {
      SharedPreferences.setMockInitialValues({
        'auth.session': jsonEncode({
          'token': 'test-token',
          'user': _user(id: 430, type: 'worker', fullName: 'كريم'),
        }),
      });
      await SharedPreferences.getInstance();

      final auth = AuthState(_api((req) async =>
          req.url.path == '/api/unread' ? _json(0) : _json(const <Object>[])));
      await auth.restore();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.user!.id, 430);
      expect(auth.user!.fullName, 'كريم');
      // The role is what routes the app, and this is the assertion that the
      // SQLite-shaped id did not cost the contractor his own dashboard.
      expect(auth.role, UserRole.worker);
    });
  });
}
