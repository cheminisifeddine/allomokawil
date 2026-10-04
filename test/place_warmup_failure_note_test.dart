// The location failure note the launch promises, and never draws.
//
// `PlaceWarmup`'s own doc promises one thing above every other: a fix that
// failed for a reason the user can act on — the location toggle off, a
// permission blocked in Settings, no signal indoors — is *named*, and a
// settings trip is *offered*. Those three are not refusals, and the code says
// so at length in `PlaceState.askAndDetect`, which keeps `lastFailure` for
// exactly them and spends the one-shot for none of them.
//
// The widget then reads `place.lastFailure` in a second `.then`. It cannot see
// it. `place.askAndDetect()` at place_warmup.dart:57 is **not awaited**, so the
// second link of the chain runs when the first link's future completes — which
// is the instant the *asked* detect is still at its first `await`. And
// `askAndDetect` opens with `lastFailure = null;` **synchronously**, before any
// await. So the field the widget reads is null by construction, on every
// launch, for every failure it exists to report: the note is not
// "occasionally missing", it is unreachable.
//
// The cure is the shape the rest of the app already uses — arm the question,
// await the answer, read the field after. Measured below, not asserted from
// reading.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/location/locator.dart';
import 'package:allomokawil/src/core/location/place_state.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/widgets/place_warmup.dart';

/// The location toggle off — the one whose cure is a settings trip, so it is
/// also the one that must carry the «الإعدادات» action rather than a bare note.
const _toggleOff = LocationFailure(
  'خدمة الموقع مغلقة في الهاتف. شغّلها من الإعدادات ثم أعد المحاولة.',
  opensSettings: true,
);

/// No fix indoors — a plain note, no action.
const _noFix = LocationFailure(
  'تعذّر تحديد موقعك في الوقت المحدد. جرّب في مكان مفتوح، أو اختر الولاية يدوياً.',
);

/// Pumps the real widget with a real store whose detector fails with [failure],
/// and returns the number of completed frames so a case can settle the chain.
Future<int> _launch(
  WidgetTester tester,
  LocationFailure failure,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    httpClient: MockClient((_) async => throw StateError('no request here')),
    baseUrls: ['https://x.test'],
  );
  final auth = AuthState(api);
  await auth.restore();

  // `_asked` false and no place: the only state in which the launch asks.
  final place = PlaceState(
    detect: () async => throw failure,
    // The quiet gate is injected for the same reason the detector is: the real
    // one is a `static` over the Geolocator platform channel, so it answers
    // false in a widget test and `detectQuietly` exits before ever reaching the
    // detector. Mocking the whole plugin to prove this branch was possible, and
    // wrong — the seam belongs on the class that owns the call, which is what
    // shipped.
    canDetectQuietly: () async => true,
  );

  await tester.pumpWidget(MaterialApp(
    home: AppScope(
      api: api,
      auth: auth,
      place: place,
      child: Scaffold(
        body: PlaceWarmup(child: const Text('المحتوى')),
      ),
    ),
  ));

  // The widget kicks on `didChangeDependencies`, in a post-frame callback, so
  // the chain needs frames. Pump a generous fixed number rather than
  // `pumpAndSettle`: a detect that keeps failing means nothing ever settles.
  var frames = 0;
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    frames++;
  }
  return frames;
}

void main() {
  testWidgets(
    'a location fix that failed for a reason the user can act on is NAMED',
    (tester) async {
      await _launch(tester, _toggleOff);

      expect(
        find.textContaining('خدمة الموقع مغلقة'),
        findsWidgets,
        reason: 'the launch promises this sentence for a closed location '
            'service, and nothing else in the app can draw it',
      );
    },
  );

  testWidgets(
    'a settings trip carries the «الإعدادات» action, never a retry',
    (tester) async {
      await _launch(tester, _toggleOff);

      expect(
        find.widgetWithText(SnackBarAction, 'الإعدادات'),
        findsOneWidget,
        reason: 'the cure here is a trip to Settings, not another question',
      );
      expect(
        find.widgetWithText(SnackBarAction, 'إعادة المحاولة'),
        findsNothing,
        reason: 'a retry button would re-run a permission request the phone '
            'has already refused to show',
      );
    },
  );

  testWidgets('a failure with no settings cure is still named', (tester) async {
    await _launch(tester, _noFix);

    expect(
      find.textContaining('تعذّر تحديد موقعك'),
      findsWidgets,
      reason: 'indoors with no fix is a third non-refusal and was named as one',
    );
  });

  testWidgets(
    'a refusal stays silent: the user already answered',
    (tester) async {
      await _launch(tester, const LocationFailure(
        'لم تسمح بالوصول إلى موقعك. يمكنك اختيار الولاية يدوياً.',
        userRefused: true,
      ));

      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'a refusal is an answer, not a problem to report — nagging a '
            'user who said no is the defect `asked` exists to prevent',
      );
    },
  );
}
