// A refused queue write was reported to the user as a saved message.
//
// The outbox is a promise of durability: it exists so a man who typed his
// address into a dead 3G connection can close the app and find his words still
// there. Every failure sentence on the send path leans on that promise —
// «تعذّر الإرسال — الرسالة محفوظة في الهاتف، اضغط عليها لإعادة المحاولة» is
// the app telling the user his words are safe on the device, and telling him to
// believe the retry button.
//
// But the promise was never checked. `PrefsOutboxStore.write` called
// `prefs.setString` and **threw away the bool it returns**. The plugin answers
// `false` — not an exception — when the platform declines to store the value: a
// full disk, a revoked storage grant, a rejected commit. So a write that never
// reached the disk completed normally, `ChatOutbox` saw a clean future, and the
// app went on to promise durability it did not have. The user reads the line,
// closes the app or lets Android kill it in the background, and the words are
// gone with nothing on screen that was ever true.
//
// The bug is worse than the one it looks like, because the *degradation* was
// built and documented. `add` reports a record evicted by the bound through
// `lastDropped` and the screen toasts «حُذفت أقدم رسالة» — and on a refused
// write nothing was ever evicted, because the disk still holds the old queue.
// The app announced a deletion that did not happen, while staying silent about
// the arrival that did not.
//
// Two failures in one, both from the same swallowed bool, so this file pins
// both: the honest sentence on the way out, and silence about a deletion that
// never occurred.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

const _words = 'العنوان: حسين داي، الطابق الثالث';

/// A store that accepts every value and **reports it stored** — the healthy
/// case, and the only one that was ever simulated.
///
/// If this is the only store in the suite, the defect is untestable: every
/// writer that throws looks identical to a writer that succeeds, and the
/// difference the user sees cannot be observed. So the suite needs a store that
/// declines too, and the question this file asks is what the app says in that
/// case.
///
/// It is layered over the values a **live** instance is holding, captured before
/// the swap. That is not a detail: the platform layer stores every key under a
/// `flutter.` prefix, so a hand-built map in the app's own vocabulary is filtered
/// out and the phone comes back empty — the thread then never signs in, never
/// reaches the send, and the test hangs instead of failing. An earlier version of
/// this file seeded it that way.
class _DecliningStore extends InMemorySharedPreferencesStore {
  // A super parameter cannot express this: the plugin's constructor is named
  // `withData`, and super parameters match the *super* constructor's name.
  // ignore: use_super_parameters
  _DecliningStore(Map<String, Object> seed) : super.withData(seed);

  /// `false` is what the platform really answers on a refused write — a full
  /// disk, a revoked storage grant, a rejected commit. Nothing is thrown.
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.contains(chatOutboxKey)) return false;
    return super.setValue(valueType, key, value);
  }
}

final _me = <String, Object?>{
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

String _json(Object? body) =>
    jsonEncode(body);

/// Every message the server actually received, in order.
final List<String> posted = <String>[];

/// [refuseSend] makes the server answer a settled refusal, so the bubble lands
/// in the `failed` state whose toast is the one that promises durability.
ApiClient _api({bool refuseSend = false}) {
  final client = MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
      return http.Response(_json({'token': 'tok', 'user': _me}), 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.endsWith('/api/unread')) {
      return http.Response(_json(0), 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.endsWith('/api/mobile/conversations')) {
      return http.Response(_json({'id': 5}), 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.startsWith('/api/messages/')) {
      if (req.method == 'GET') {
        return http.Response(_json(<Object>[]), 200,
            headers: {'content-type': 'application/json'});
      }
      if (refuseSend) {
        return http.Response(_json({'error': 'مرفوض'}), 400,
            headers: {'content-type': 'application/json'});
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      posted.add('${body['content']}');
      return http.Response(
          _json({
            'id': 900,
            'conversation_id': 5,
            'sender_id': 30,
            'content': body['content'],
            'image_url': null,
            'message_type': 'text',
            'is_read': 0,
            'created_at': '2026-09-27 10:00:00',
          }),
          200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('{}', 404,
        headers: {'content-type': 'application/json'});
  });
  return ApiClient(baseUrls: ['https://x.test'], httpClient: client);
}

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return auth;
}


/// The live in-memory store, captured once so the declining store can be
/// layered over exactly the values on the phone.
SharedPreferences? _instance;

Map<String, Object> _seed() =>
    <String, Object>{for (final k in _instance!.getKeys()) k: _instance!.get(k)!};

/// Mounts the thread and types [text] into the composer, then taps send.
Future<void> _typeAndSend(
  WidgetTester tester, {
  required ApiClient api,
  required AuthState auth,
  required String text,
}) async {
  tester.view.physicalSize = const Size(1080, 3400);
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
      home: ChatScreen(
        conversationId: 5,
        otherUserId: 31,
        otherName: 'مقاول',
        repo: Repository(api),
        outbox: ChatOutbox(),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }

  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => posted.clear());

  tearDown(() {
    // Hand the real in-memory store back, so no other file inherits one that
    // declines writes.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
  });

  group('the queue write the phone declined', () {
    testWidgets('is told to the user instead of being called saved',
        (tester) async {
      // The session goes on the phone first, through a healthy store, so the
      // refusal below applies to the queue alone — a full disk would not stop
      // the session being written, and a test that failed the login would be
      // testing a different thing.
      final api = _api(refuseSend: true);
      final auth = await _boot(api);
      _instance = await SharedPreferences.getInstance();

      SharedPreferencesStorePlatform.instance = _DecliningStore(_seed());

      await _typeAndSend(tester, api: api, auth: auth, text: _words);

      // The sentence that would have told the user his words are safe. Its
      // presence is the defect: the phone refused the write, so this is a lie.
      expect(find.textContaining('الرسالة محفوظة في الهاتف'), findsNothing,
          reason: 'the phone refused to store the message, so the app must not '
              'tell the user it is saved on the phone');

      // The truth instead, and it carries the one action that still works.
      // Written as literal copy, not as a reference to the new constant: a
      // test that cannot compile against the source it is written for has
      // proven nothing, and the run against the reverted file is the only
      // thing that tells us whether this test can fail.
      expect(find.textContaining('انسخها قبل'), findsOneWidget,
          reason: 'a message the phone did not take has to be said out loud, '
              'and the user has to be told what to do about it');
    });

    testWidgets('still reaches the contractor', (tester) async {
      // The point of not unwinding on a refused write: a storage failure must
      // not become a lost message. The words still go on the wire.
      final api = _api();
      final auth = await _boot(api);
      _instance = await SharedPreferences.getInstance();
      SharedPreferencesStorePlatform.instance = _DecliningStore(_seed());

      await _typeAndSend(tester, api: api, auth: auth, text: _words);

      expect(posted, <String>[_words],
          reason: 'a phone that would not store the message must still send '
              'it — the write is the last statement, and nothing it refuses '
              'may stop the delivery');
    });
  });

  group('the bound reports only what the disk agrees with', () {
    test('a refused write invents no deletion', () async {
      // The second half of the same swallowed bool, and the more embarrassing
      // one: `add` reports a record evicted by the bound through `lastDropped`,
      // and the screen toasts «امتلأت قائمة الانتظار — حُذفت أقدم رسالة».
      // On a refused write the disk still holds the *old* queue: nothing was
      // evicted and nothing was added. The user was told a message of his own
      // was deleted when it was still on the phone, while the one he just
      // typed was never stored — and the app said nothing about that.
      final store = _ControllableStore();
      final outbox = ChatOutbox(store: store);

      // chatOutboxMax + 1, not chatOutboxMax: the bound fires when the queue
      // would exceed it, so exactly sixty adds never evict anything. The first
      // run of this test used sixty and failed for that reason alone.
      for (var i = 0; i < chatOutboxMax + 1; i++) {
        await outbox.add(conversationId: 5, text: 'رسالة $i');
      }
      expect(outbox.lastDropped, isNotNull,
          reason: 'the queue is genuinely full here, so a healthy write does '
              'report the eviction');
      final before = outbox.lastDropped;
      // The disk now declines. The eviction is still computed in memory, so
      // this is precisely the case where the old code announced a deletion that
      // the disk never made.
      store.refuse = true;
      await outbox.add(conversationId: 5, text: 'الرسالة الأخيرة');
      expect(outbox.lastDropped, isNull,
          reason: 'nothing was evicted — the old queue is still on the disk, '
              'so announcing a deletion would be inventing one. Previous '
              'value: ${before?.text}');
    });

    test('a healthy write still reports the eviction it made', () async {
      // The other direction, and the one that would catch a "fix" that simply
      // stopped reporting. Quietness on a real eviction is exactly the silence
      // the bound was written to avoid.
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      for (var i = 0; i < chatOutboxMax; i++) {
        await outbox.add(conversationId: 5, text: 'رسالة $i');
      }
      await outbox.add(conversationId: 5, text: 'الرسالة الأخيرة');
      expect(outbox.lastDropped?.text, 'رسالة 0');
    });
  });
}

/// A healthy store that the test can turn hostile at an exact moment.
///
/// The refusal is *switched on*, not counted: a store that refused its first
/// write would never have accumulated a queue in the first place, so the bound
/// would never have been reached and the test would have failed for a reason
/// that has nothing to do with the defect. Which is exactly what it did on the
/// first run — a wrong failure, fixed rather than investigated away.
class _ControllableStore implements OutboxStore {
  Object? raw;

  /// The device stops taking writes when this is set, and reports it by
  /// refusing: `ChatOutbox` must survive that on its own.
  bool refuse = false;

  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async {
    if (refuse) throw StateError('preferences refused to store the queue');
    raw = value;
  }
}
