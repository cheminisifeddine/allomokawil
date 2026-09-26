// A dead session must not hand the phone's unsent messages to the next person.
//
// The defect this pins, found in a read-only audit on 26 Sep:
// `profile_screen.dart` clears the chat outbox before `auth.logout()` — and only
// the profile screen does. But `AuthState.logout()` is not a private helper the
// profile screen owns. It is what `handleUnauthorized()` calls when the server
// answers 401, and 401 is the *common* case on a phone whose token went stale:
// it is exactly the failure the founder already photographed («انتهت جلستك» over
// an empty home). So the most frequent way to lose a session never touched the
// outbox at all.
//
// What that leaves on the device: user A types «العنوان: حسين داي» into a dead
// connection, the message lands in the outbox, the session dies, the app returns
// to the login form. User B — a family member, a second shop on the same phone —
// signs in. The inbox now carries A's badge, and opening that thread *auto-sends*
// A's words under B's token, to A's contractor, with B's name on them.
//
// The fix puts the clear inside `AuthState` so every path out of a session takes
// it, and the profile screen no longer has to remember. This file proves the
// invariant holds on the 401 path, not just on the tap-the-button path.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The queue as the app would read it back from the device.
Future<List<PendingMessage>> _stored() async {
  final prefs = await SharedPreferences.getInstance();
  return decodeOutbox(prefs.getString(chatOutboxKey));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 401 leaves no unsent message behind for the next account', () async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'dead-token',
      'auth.user': jsonEncode(_customer),
      // User A's message, already owed to the server, sitting on the phone.
      chatOutboxKey: jsonEncode([
        {
          'id': '5.1700000000000000.0',
          'conversation_id': 5,
          'text': _words,
          'created_at': 1700000000000,
        }
      ]),
    });

    // Every request answers 401: the server no longer knows this token.
    final api = ApiClient(
      httpClient: MockClient((req) async => http.Response(
            jsonEncode({'error': 'انتهت الجلسة'}),
            401,
            headers: {'content-type': 'application/json'},
          )),
      baseUrls: ['https://x.test'],
    );
    final auth = AuthState(api);
    await auth.restore();
    expect(auth.isAuthenticated, isTrue, reason: 'restored from storage');
    expect(await _stored(), hasLength(1), reason: 'the fixture must be queued');

    await expectLater(
      api.get('/api/mobile/my/profile'),
      throwsA(isA<ApiException>()),
    );
    // The handler is installed by the constructor, so this needs no wiring here:
    // the point is that the invariant lives in AuthState.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(auth.isAuthenticated, isFalse);
    expect(await _stored(), isEmpty,
        reason: 'a session that died must not leave its messages on the phone '
            'for whoever signs in next');
  });

  test('a wrong password on the login form is not a session loss', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(
      httpClient: MockClient((req) async => http.Response(
            jsonEncode({'error': 'بيانات خاطئة'}),
            401,
            headers: {'content-type': 'application/json'},
          )),
      baseUrls: ['https://x.test'],
    );
    final auth = AuthState(api);
    await auth.restore();

    await expectLater(
      api.post('/api/login', body: {'phone': '0550000000', 'password': 'x'}),
      throwsA(isA<ApiException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(auth.sessionExpired, isFalse);
  });
}
