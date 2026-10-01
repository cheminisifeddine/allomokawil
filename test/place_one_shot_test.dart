// The founder's brief, verbatim:
//   «ask for gps fird thing when the user open the app so you show related
//    offers to him. And get accurate offers too»
//
// The question is asked once per install, and that promise is the whole feature:
// `PlaceWarmup` asks only `if (!place.asked)`, and `asked` is persisted in
// shared preferences. So whatever writes that flag true is not a preference — it
// is the difference between a phone that gets asked on the next launch and one
// that never is again.
//
// `Locator.detect` fails four ways. Exactly ONE of them is a user refusing:
//   * the location toggle is off in the phone      — the phone's state
//   * permission blocked in Settings (deniedForever) — the phone's state
//   * no fix indoors / GPS error (timeout)          — the phone's state
//   * the permission prompt shown and dismissed     — a refusal
//
// The first three are cured by changing something and coming back. Burning the
// one-shot on them made the app permanently silent to a user who had done nothing
// wrong: they turn GPS on, relaunch, and the app never asks again — because the
// flag that gates the question was already spent on a failure that was not an
// answer.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/location/locator.dart';
import 'package:allomokawil/src/core/location/place_state.dart';

const _algiers = DetectedPlace(
  wilayaId: '16',
  wilayaName: 'الجزائر',
  commune: 'باب الوادي',
  lat: 36.75,
  lng: 3.06,
  seatKm: 2.1,
  communeFromDevice: true,
);

/// The three failures that are the phone's state, not the user's decision.
/// Each one is a real [LocationFailure] with a real sentence from `Locator`.
const _environmentFailures = <({String why, LocationFailure failure})>[
  (
    why: 'location toggle off',
    failure: LocationFailure(
      'خدمة الموقع مغلقة في الهاتف. شغّلها من الإعدادات ثم أعد المحاولة.',
      opensSettings: true,
    ),
  ),
  (
    why: 'permission blocked in Settings',
    failure: LocationFailure(
      'الوصول إلى الموقع ممنوع لهذا التطبيق. اسمح به من الإعدادات ثم أعد المحاولة.',
      opensSettings: true,
    ),
  ),
  (
    why: 'no fix indoors',
    failure: LocationFailure(
      'تعذّر تحديد موقعك في الوقت المحدد. جرّب في مكان مفتوح، أو اختر الولاية يدوياً.',
    ),
  ),
];

/// A store whose detector always fails with [failure], and counts the calls so a
/// case can prove a *second* launch really reaches the phone.
PlaceState _alwaysFails(LocationFailure failure, [_Counter? counter]) {
  return PlaceState(detect: () async {
    counter?.hit();
    throw failure;
  });
}

/// A call count. A box, not an `int*`, because Dart has no pointer params.
class _Counter {
  int calls = 0;
  void hit() => calls++;
}

Future<void> _freshPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
}

void main() {
  setUp(_freshPrefs);

  test('a refused permission prompt DOES spend the one-shot', () async {
    // The one failure that is an answer. Recording it is correct: the phone
    // must not nag a user who said no.
    final place = _alwaysFails(const LocationFailure(
      'لم تسمح بالوصول إلى موقعك. يمكنك اختيار الولاية يدوياً.',
      userRefused: true,
    ));

    expect(await place.askAndDetect(), isFalse);
    expect(place.asked, isTrue,
        reason: 'a refusal is an answer, so the question is spent');
  });

  for (final c in _environmentFailures) {
    test('a failure that is not a refusal keeps the one-shot: ${c.why}',
        () async {
      final place = _alwaysFails(c.failure);

      expect(await place.askAndDetect(), isFalse);
      expect(place.asked, isFalse,
          reason:
              'the user was never asked about this; "${c.why}" is the phone\'s '
              'state, and "not asked" is what lets the next launch try again');
    });

    test('the next launch really does ask again: ${c.why}', () async {
      // The defect's whole weight: before the fix the flag was persisted true,
      // so `PlaceWarmup`'s `if (!place.asked)` was false forever. Proved by
      // restoring a NEW store from the SAME storage, exactly as a relaunch
      // would — not by re-reading a field.
      final counter = _Counter();
      final first = _alwaysFails(c.failure, counter);
      await first.askAndDetect();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('place.asked.v1'), isNull,
          reason: 'nothing may persist that suppresses the next launch');

      final second = _alwaysFails(c.failure, counter);
      await second.restore();
      expect(second.asked, isFalse);
      expect(await second.askAndDetect(), isFalse);
      expect(counter.calls, 2,
          reason: 'the second launch must reach the phone, not skip the ask');
    });
  }

  test('a non-refusal failure keeps the cure reachable', () async {
    // The sentence is written for the person holding the phone, so a failure
    // with a cure must be able to reach them rather than dying in a `catch (_)`.
    final place = _alwaysFails(_environmentFailures.first.failure);
    await place.askAndDetect();

    final failure = place.lastFailure;
    expect(failure, isNotNull,
        reason: 'a failure the user can act on must not be swallowed');
    expect(failure!.messageAr, _environmentFailures.first.failure.messageAr);
    expect(failure.opensSettings, isTrue,
        reason: 'the cure here is a trip to the system Settings');
  });

  test('the timeout failure is not a settings trip', () async {
    // The third failure's cure is to move somewhere with a signal, so it must
    // not offer a Settings button that cannot help.
    final place = _alwaysFails(_environmentFailures[2].failure);
    await place.askAndDetect();

    expect(place.lastFailure!.opensSettings, isFalse);
  });

  test('a successful detection spends the question and keeps no failure',
      () async {
    final place = PlaceState(detect: () async => _algiers);

    expect(await place.askAndDetect(), isTrue);
    expect(place.hasPlace, isTrue);
    expect(place.wilayaId, '16');
    expect(place.asked, isTrue, reason: 'asked and answered: spent');
    expect(place.lastFailure, isNull,
        reason: 'a success must not leave a stale cure on screen');
  });

  test('a refusal keeps no failure line', () async {
    // A refusal is an answer, not a problem to report. Drawing a card there
    // would argue with a decision the user just made.
    final place = _alwaysFails(const LocationFailure(
      'لم تسمح بالوصول إلى موقعك. يمكنك اختيار الولاية يدوياً.',
      userRefused: true,
    ));
    await place.askAndDetect();

    expect(place.lastFailure, isNull);
  });

  test('a foreign exception does not spend the one-shot either', () async {
    // A platform channel throwing something outside `Locator.detect`'s own
    // vocabulary is still not an answer from the user.
    final place = PlaceState(detect: () async => throw StateError('boom'));

    expect(await place.askAndDetect(), isFalse);
    expect(place.asked, isFalse);
    expect(place.lastFailure, isNull,
        reason: 'nothing here is a sentence anyone should read');
  });

  test('a retry that succeeds after a transient failure recovers', () async {
    // The user cures the setting and relaunches: this is the path the defect
    // closed. It must now end in a wilaya.
    var attempt = 0;
    final place = PlaceState(detect: () async {
      attempt++;
      if (attempt == 1) throw _environmentFailures[2].failure;
      return _algiers;
    });

    expect(await place.askAndDetect(), isFalse);
    expect(place.asked, isFalse);

    expect(await place.askAndDetect(force: true), isTrue);
    expect(place.hasPlace, isTrue);
    expect(place.asked, isTrue);
  });

  test('clearing the fix drops the stale failure line', () async {
    final place = _alwaysFails(_environmentFailures.first.failure);
    await place.askAndDetect();
    expect(place.lastFailure, isNotNull);

    await place.clear();
    expect(place.lastFailure, isNull,
        reason: 'a cure for a fix that no longer exists must not outlive it');
  });

  test('a new attempt clears the previous failure before it runs', () async {
    var attempt = 0;
    final place = PlaceState(detect: () async {
      attempt++;
      if (attempt == 1) throw _environmentFailures.first.failure;
      return _algiers;
    });

    await place.askAndDetect();
    expect(place.lastFailure, isNotNull);

    await place.askAndDetect(force: true);
    expect(place.lastFailure, isNull,
        reason: 'the sentence must not survive the retry that answered it');
  });
}
