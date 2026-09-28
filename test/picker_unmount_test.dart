// The OS gallery can outlive the screen that opened it.
//
// `chat_screen.dart` was given `mounted` guards after a red screen over a sent
// message (`8c9434a`, `test/chat_unmount_test.dart`). The same fix was never
// applied to the three screens that hand control to the **image picker** — and
// the picker is a strictly longer window than the chat screen's own
// `SharedPreferences` write: it is another app, so the user can background the
// app, have the OS reclaim the activity, swipe it from recents, or simply be
// gone by the time he answers it.
//
// All six of those `setState` calls were unguarded:
//
//   | # | file                      | the draw                    |
//   |---|---------------------------|-----------------------------|
//   | 1 | project_new_screen.dart   | `_images.addAll(...)`      |
//   | 2 | project_new_screen.dart   | wilaya + clears commune     |
//   | 3 | project_new_screen.dart   | `_commune.text = picked`   |
//   | 4 | verification_screen.dart  | `_certs[index] = file`     |
//   | 5 | verification_screen.dart  | `_docs[index] = (...)`     |
//   | 6 | my_portfolio_screen.dart  | `_busy = true` + `_error`  |
//
// Site 6 is the one to reason about: its draw is `_busy = true`, so a lost
// guard is not a red screen but a **permanently stuck spinner** if the upload
// then runs, and the contractor's gallery is closed to him for the rest of the
// session.
//
// The harness holds the picker open with a gated handler on the real
// `plugins.flutter.io/image_picker` channel — the same trick as
// `chat_unmount_test.dart`'s `OutboxStore` double, moved onto the OS seam. The
// route is then removed while the picker is still unanswered, and the handler is
// released **onto a disposed `State`**. Before the guards, each of these throws
// "setState() called after dispose()".
//
// On reachability, stated plainly rather than overclaimed: the in-app disposers
// cannot produce this — there is no `pushAndRemoveUntil`, no `popUntil` above
// these routes and no `navigatorKey` anywhere in `lib/`. The test uses
// `Navigator.removeRoute` because it is the only API that disposes a route
// **imperatively, in the same frame, with no exit animation** — which is what
// the OS does when it reclaims an activity, and what a `pop` only approximates.
// It is not a claim that a user can reach this from inside the app; it is a
// claim that the screens are not safe when it happens.
import 'dart:async';
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
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/screens/verify/verification_screen.dart';
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';

/// The real plugin channel, so the screens are driven exactly as a user drives
/// them rather than by calling a private method. The wire names are the ones the
/// plugin actually sends — `pickImage` and `pickMultiImage` on
/// `plugins.flutter.io/image_picker` — the same seam the three existing
/// write-outcome tests already use.
const MethodChannel _picker = MethodChannel('plugins.flutter.io/image_picker');

/// Holds the OS picker open for as long as the test needs.
///
/// This is the whole trick, and it is the same one `chat_unmount_test.dart`
/// uses on the outbox store: a real double that parks the `await` inside the
/// screen's own method. Releasing it is what makes the `setState` land on a
/// dead widget.
class _GatedPicker {
  final gate = Completer<void>();
  int calls = 0;
  final List<String> methods = <String>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_picker, (call) async {
      calls++;
      methods.add(call.method);
      await gate.future;
      if (call.method == 'pickMultiImage') {
        return <String>['/tmp/am-gated-$calls.png'];
      }
      return '/tmp/am-gated-$calls.png';
    });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_picker, null);
  }
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: <String, String>{'content-type': 'application/json'});

Map<String, Object?> _user({required String type, required int id}) =>
    <String, Object?>{
      'id': id,
      'phone': '0773000000',
      'email': null,
      'full_name': type == 'worker' ? 'مقاول تجربة' : 'زبون تجربة',
      'type': type,
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-26 10:00:00',
    };

Map<String, Object?> _workerProfile() => <String, Object?>{
      'id': 5,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'bio': 'دهان',
      'specialties': '["painting"]',
      'experience_years': 6,
      'is_available': 1,
      'verification_status': 'pending',
      'verification_pending_docs': 0,
      'is_identity_verified': 0,
      'is_certificate_verified': 0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'user_wilaya': '16',
      'commune': 'حسين داي',
    };

Map<String, Object?> _subscription() => <String, Object?>{
      'currency': 'DZD',
      'note_ar': '',
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[],
      'current': <String, Object?>{
        'plan': 'free_trial',
        'name_ar': 'الخطة المجانية',
        'status': 'active',
        'starts_at': '2026-09-01 00:00:00',
        'expires_at': null,
        'quote_limit': 3,
        'portfolio_limit': 5,
        'quotes_used_this_month': 0,
      },
    };

/// The server half: a logged-in customer (the project form) and a logged-in
/// contractor (the two portfolio screens). Both answer `/my/profile` and
/// `/subscription`, because `MyPortfolioScreen` reads the plan's
/// `portfolio_limit` and a missing allowance is a different screen state.
Future<({ApiClient api, AuthState auth})> _bootCustomer() async =>
    _boot(type: 'customer', id: 30);

Future<({ApiClient api, AuthState auth})> _bootWorker() async =>
    _boot(type: 'worker', id: 31);

Future<({ApiClient api, AuthState auth})> _boot(
    {required String type, required int id}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{
          'token': 'tok',
          'user': _user(type: type, id: id),
        });
      }
      if (p.contains('/my/profile')) return _json(_workerProfile());
      if (p.contains('/subscription')) return _json(_subscription());
      return _json(<Object?>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123');
  return (api: api, auth: auth);
}

/// The strings the project form's two pickers are driven by, named so the
/// commune case reads as steps rather than as a wall of escaped Arabic.
const String wilayaHint = 'اختر الولاية';
const String communeHint = 'اختر البلدية (اختياري)';

/// A phone, so the form is taller than the screen and scrolling is real.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(392, 850) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
}

/// Mounts the screen **behind a route the test can pop**, which is the only
/// honest way to reproduce "he left the screen".
///
/// The first version of this harness mounted each screen as `home:`, which put
/// it on the navigator's only route: `canPop()` was false, `pop()` did nothing,
/// and `removeRoute` on the sole route emptied the navigator's history and
/// tripped an assertion in the framework itself. A screen the app can never
/// leave is not the screen under test, and neither is one the framework
/// refuses to remove. `test/chat_unmount_test.dart` already solved this with a
/// launcher route and the same shape is used here.
Widget _app(ApiClient api, AuthState auth, Widget screen) => AppScope(
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => screen),
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    );

/// The one tap that puts the screen on the stack.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('افتح'));
  await tester.pump();
}

/// Brings a field into view, the way a thumb would before tapping it.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 220,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Pumps a fixed number of frames. `pumpAndSettle` is unusable here: the gated
/// handler never completes, so the tree is never quiet and it times out on the
/// very wait the test is holding open on purpose.
Future<void> _frames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Takes the screen off the stack and disposes its `State`.
///
/// Two things had to be got right here, and the first produced a test that
/// passed with and without the guards — the vacuous pass, which looks like
/// coverage and measures nothing:
///
///  * Only the **screen's** route may go. When another route sits on top of it
///    — the wilaya/commune bottom sheet — the entry below survives until the
///    one above is gone, so the screen's `State` lived on and its post-`await`
///    draw still had a live widget to land on. The stack comes down from the
///    top first.
///  * The pop has to be **pumped out** before the gate is released. A route
///    stays in the tree until its reverse transition finishes, so an
///    unpumped `pop()` leaves a widget that is still alive and the test passes
///    against a screen that is not actually dead.
///
/// `pumpAndSettle` is safe here despite the gated handler: a pending `Future`
/// belonging to a widget already off the stage schedules no frame, so the tree
/// really does go quiet. An earlier version of this helper avoided it out of
/// caution, and that is exactly what left the wilaya case vacuous.
/// Takes the screen off the stack, answering whatever it was waiting on.
///
/// This helper is the whole difficulty of the test, and its first four
/// versions each measured nothing while looking like coverage:
///
///  * **`pop()` on the screen alone disposed nothing.** The screens were
///    mounted as `home:`, so they sat on the navigator's only route,
///    `canPop()` was false, and `removeRoute` on the sole route emptied the
///    history and tripped a framework assertion. They are now pushed behind a
///    launcher route, as `chat_unmount_test.dart` already does it.
///  * **Removing the screen's route while a sheet sat on top disposed nothing
///    either.** An entry below a present route is kept, not disposed, so the
///    `State` survived and the post-`await` draw still found a live widget.
///  * **A plain pop answers `null`.** `if (picked == null) return;` took the
///    early exit and the guarded line never ran — a green test proving nothing.
///  * **Removing the sheet first delivered its answer too early.**
///    `removeRoute` hands the result to the waiting `Future` as part of the
///    history flush, which happens inside the *first* call, so the screen's
///    continuation ran — and drew — while the screen was still on the stack.
///
/// The order below is the one that works, and it is not the obvious one: the
/// **screen goes first, then the surface above it answers**. The screen's entry
/// is removed while the sheet is still present above it, so the sheet keeps it
/// alive; then the sheet is removed with its answer, and the flush that
/// delivers the answer finds the screen already disposed. No `await` sits
/// between the two, because a pump lets the continuation run in between and
/// puts the draw back on a live widget.
Future<void> _disposeRoute(WidgetTester tester, Type screen,
    {Object? answer}) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).last);

  final screenEl = find.byType(screen);
  expect(screenEl.evaluate().isNotEmpty, isTrue,
      reason: 'the screen must be on the tree to be disposed');
  final screenRoute = ModalRoute.of(tester.element(screenEl.first));
  expect(screenRoute, isNotNull, reason: 'the screen must be on a real route');

  // The surface on top, captured before the screen's element is unmounted.
  final sheet = find.byType(DraggableScrollableSheet);
  final sheetRoute = sheet.evaluate().isEmpty
      ? null
      : ModalRoute.of(tester.element(sheet.first));

  nav.removeRoute(screenRoute!);
  // The one pump between the two removals. A route entry's `dispose` is
  // deferred to a post-frame callback, so without this frame the screen's
  // `State` is still alive when the answer is delivered and the draw lands on
  // a live widget — the case goes green with the guards removed. With it, the
  // answer arrives at an already-disposed `State`.
  await tester.pump(const Duration(milliseconds: 50));
  if (sheetRoute != null) {
    nav.removeRoute(sheetRoute, answer);
  } else if (nav.canPop()) {
    nav.pop();
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 50));

  // The proof that the `State` is really gone, and not merely off-screen. If
  // this ever finds the screen, everything after it is a false green.
  expect(find.byType(screen), findsNothing,
      reason: 'the screen must actually be disposed, not just popped');
}

void main() {
  group('the project form, gallery still open', () {
    // Site 1: `pickMultiImage` -> `_images.addAll(...)`.
    testWidgets('a photo chosen after the form is gone does not throw',
        (tester) async {
      final boot = await _bootCustomer();
      final gate = _GatedPicker()..install();
      addTearDown(gate.remove);
      _phone(tester);

      await tester.pumpWidget(
          _app(boot.api, boot.auth, const ProjectNewScreen()));
      await _frames(tester);
      await _open(tester);
      await _frames(tester);

      await tester.scrollUntilVisible(find.text('أضف صورة'), 240,
          scrollable: find.byType(Scrollable).first);
      await _frames(tester, n: 4);

      final tile = find.ancestor(
        of: find.text('أضف صورة'),
        matching: find.byType(InkWell),
      );
      expect(tile, findsWidgets, reason: 'the add-photo tile must be reachable');

      await tester.tap(tile.first);
      await tester.pump();
      await _frames(tester, n: 3);

      expect(gate.calls, greaterThanOrEqualTo(1),
          reason: 'the OS picker was never actually opened');
      expect(gate.methods, contains('pickMultiImage'),
          reason: 'the multi picker is the one this screen uses');

      // The user swipes the app away while the gallery is in front of it.
      await _disposeRoute(tester, ProjectNewScreen);
      await _frames(tester, n: 4);

      // ...and the gallery answers, onto a disposed State.
      gate.gate.complete();
      await _frames(tester, n: 8);

      expect(tester.takeException(), isNull,
          reason: 'a photo chosen after the form is gone must not throw');
    });

    // Sites 2 and 3: the wilaya and commune sheets, which are the same shape —
    // an `await` on another surface followed by a draw. The sheet is the app's
    // own, so this one the user *can* leave: the OS rotates the phone, the app
    // is killed and restored, the sheet's route is gone and the answer lands
    // anyway.
    testWidgets('a wilaya chosen after the form is gone does not throw',
        (tester) async {
      final boot = await _bootCustomer();
      _phone(tester);

      await tester.pumpWidget(
          _app(boot.api, boot.auth, const ProjectNewScreen()));
      await _frames(tester);
      await _open(tester);
      await _frames(tester);

      await tester.scrollUntilVisible(find.text('اختر الولاية'), 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('اختر الولاية'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The sheet is up.
      expect(find.byType(DraggableScrollableSheet), findsWidgets,
          reason: 'the wilaya sheet must be open before the route is removed');

      await _disposeRoute(tester, ProjectNewScreen, answer: '31');
      await _frames(tester, n: 4);

      expect(tester.takeException(), isNull,
          reason: 'a wilaya chosen after the form is gone must not throw');
    });

    // Site 3, the other sheet: the commune. Same `await`, different draw — it
    // writes straight into a `TextEditingController` the form is showing, so
    // without a guard it paints into a screen nobody is looking at.
    testWidgets('a commune chosen after the form is gone does not throw',
        (tester) async {
      final boot = await _bootCustomer();
      _phone(tester);

      await tester.pumpWidget(
          _app(boot.api, boot.auth, const ProjectNewScreen()));
      await _frames(tester);
      await _open(tester);
      await _frames(tester);

      // The commune field is inert until a wilaya is chosen, which is the
      // screen's own rule and not a test convenience.
      await _reveal(tester, find.text(wilayaHint));
      await tester.tap(find.text(wilayaHint));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Fixed frames rather than `pumpAndSettle`: the sheet's search field runs
      // a cursor blink, so the tree never goes quiet and settling times out.
      await _frames(tester, n: 6);
      expect(find.byType(DraggableScrollableSheet), findsWidgets,
          reason: 'the wilaya sheet must be open');

      await tester.enterText(
          find.descendant(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(TextField)),
          'وهران');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('وهران').last);
      await _frames(tester, n: 8);

      // The screen's own rule, asserted rather than assumed: the commune
      // picker is only live once a wilaya exists. Without this the next tap
      // would bounce off a snack bar and the case would pass for the wrong
      // reason.
      expect(find.text(communeHint), findsWidgets,
          reason: 'the commune field must be live once a wilaya is chosen');

      await tester.tap(find.text(communeHint));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _frames(tester, n: 6);
      expect(find.byType(DraggableScrollableSheet), findsWidgets,
          reason: 'the commune sheet must be open');

      await _disposeRoute(tester, ProjectNewScreen,
          answer: 'وهران المدينة');
      await _frames(tester, n: 4);

      expect(tester.takeException(), isNull,
          reason: 'a commune chosen after the form is gone must not throw');
    });
  });

  group('the verification form, gallery still open', () {
    // Sites 4 and 5: the same method, twice — a required document and an
    // optional certificate. One test covers both because they are the same
    // `await` and the same draw, and a guard that covered one and not the other
    // would be a copy-paste away.
    testWidgets('a document chosen after the screen is gone does not throw',
        (tester) async {
      final boot = await _bootWorker();
      final gate = _GatedPicker()..install();
      addTearDown(gate.remove);
      _phone(tester);

      await tester.pumpWidget(_app(boot.api, boot.auth,
          VerificationScreen(repo: _RepoWithFakeUpload(boot.api))));
      await _frames(tester);
      await _open(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // A required document — `_pickFor`, site 5. Brought into view
      // first: the dossier list is taller than the phone, and a tap on an
      // off-screen card hits nothing while still reading as a tap that
      // landed.
      await tester.scrollUntilVisible(
          find.text('بطاقة المقاول (auto-entrepreneur)'), 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('بطاقة المقاول (auto-entrepreneur)'));
      await tester.pump();
      await _frames(tester, n: 3);
      expect(gate.methods, contains('pickImage'),
          reason: 'the required-document picker was never opened');

      await _disposeRoute(tester, VerificationScreen);
      await _frames(tester, n: 4);
      gate.gate.complete();
      await _frames(tester, n: 8);

      expect(tester.takeException(), isNull,
          reason: 'a required document chosen after the screen is gone must not '
              'throw');
    });

    testWidgets('a certificate chosen after the screen is gone does not throw',
        (tester) async {
      final boot = await _bootWorker();
      final gate = _GatedPicker()..install();
      addTearDown(gate.remove);
      _phone(tester);

      await tester.pumpWidget(_app(boot.api, boot.auth,
          VerificationScreen(repo: _RepoWithFakeUpload(boot.api))));
      await _frames(tester);
      await _open(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The optional certificate slots live below the required ones, so the
      // form has to be scrolled for the tap to land on the card and not on the
      // viewport edge.
      await tester.scrollUntilVisible(find.text('شهادة تكوين أو دبلوم'), 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('شهادة تكوين أو دبلوم'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('شهادة تكوين أو دبلوم'));
      await tester.pump();
      await _frames(tester, n: 3);
      expect(gate.methods, contains('pickImage'),
          reason: 'the certificate picker was never opened');

      await _disposeRoute(tester, VerificationScreen);
      await _frames(tester, n: 4);
      gate.gate.complete();
      await _frames(tester, n: 8);

      expect(tester.takeException(), isNull,
          reason: 'a certificate chosen after the screen is gone must not throw');
    });
  });

  group('the portfolio gallery, picker still open', () {
    // Site 6, and the one whose failure is not a red screen. `_busy = true` is
    // the draw, so a lost guard leaves the contractor staring at a spinner that
    // never clears — a screen that no longer accepts a photo — for as long as
    // the session lasts.
    testWidgets('a photo chosen after the screen is gone does not throw',
        (tester) async {
      final boot = await _bootWorker();
      final gate = _GatedPicker()..install();
      addTearDown(gate.remove);
      _phone(tester);

      await tester.pumpWidget(_app(boot.api, boot.auth,
          MyPortfolioScreen(repo: _RepoWithFakeUpload(boot.api))));
      await _frames(tester);
      await _open(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The add button, then the sheet's gallery option — the two taps a
      // contractor makes.
      await tester.tap(find.byKey(const Key('portfolio-add')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text('من معرض الصور'));
      await tester.pump();
      await _frames(tester, n: 3);

      expect(gate.methods, contains('pickImage'),
          reason: 'the portfolio picker was never opened');

      await _disposeRoute(tester, MyPortfolioScreen);
      await _frames(tester, n: 4);
      gate.gate.complete();
      await _frames(tester, n: 8);

      expect(tester.takeException(), isNull,
          reason: 'a portfolio photo chosen after the screen is gone must not '
              'throw');
    });
  });
}

/// `Repository.uploadDocument` is a `MultipartRequest`, which builds its own
/// `HttpClient` instead of the one handed to [ApiClient] — a `MockClient` never
/// sees it, and a real loopback socket deadlocks inside the fake-async zone.
/// The same seam, for the same reason, as
/// `test/portfolio_write_outcome_test.dart` and
/// `test/verification_write_outcome_test.dart`.
class _RepoWithFakeUpload extends Repository {
  _RepoWithFakeUpload(super.api);

  @override
  Future<String> uploadDocument(File file) async =>
      'https://r2.test/portfolio/gated.jpg';
}
