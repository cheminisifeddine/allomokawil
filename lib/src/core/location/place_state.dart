import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'locator.dart';

/// Where the visitor is — one answer for the whole app.
///
/// The founder's brief, verbatim:
///   «add gps to identify the user city and wilaya automaticaly to the app»
///   «ask for gps fird thing when the user open the app so you show related
///    offers to him. And get accurate offers too»
///
/// So the app asks once, at the top of the launch, and keeps the answer: the
/// worker's market opens filtered on his wilaya and the client's explore strip
/// leads with the pros who work in it. It is a *hint*, never a cage — every
/// screen that uses it also offers «كل الولايات», and a refusal costs nothing
/// because the manual pickers are all still there.
///
/// The value lives here rather than in each screen because two tabs asking for
/// the same fix would be two permission dialogs and two GPS reads.
class PlaceState extends ChangeNotifier {
  /// The detector, injectable for tests — the same convention as the screens'
  /// `clock` and [AuthState]'s outbox.
  ///
  /// Defaults to the real [Locator.detect], which is a GPS fix plus a platform
  /// permission prompt: neither exists in a widget test, and the branch this
  /// class exists to get right is the failure arm, so a test has to be able to
  /// hand it each of the four failures on purpose.
  final Future<DetectedPlace> Function() detect;

  PlaceState({Future<DetectedPlace> Function()? detect})
      : _detached = false,
        detect = detect ?? Locator.detect;

  /// A store with no storage behind it.
  ///
  /// Widget tests and any tree pumped without an [AppScope] get the same API
  /// without touching a platform channel, which is also why every method here
  /// tolerates a failure instead of throwing.
  PlaceState.detached() : _detached = true, detect = _neverDetect;

  static Future<DetectedPlace> _neverDetect() async =>
      throw StateError('a detached PlaceState has no detector');

  static const _key = 'place.v1';
  static const _askedKey = 'place.asked.v1';

  /// True for [PlaceState.detached]: no prefs, no platform channels.
  final bool _detached;

  DetectedPlace? _place;
  bool _asked = false;
  bool _busy = false;

  /// The last failure the app can name a cure for, if the last attempt failed
  /// for a reason the user can act on.
  ///
  /// Null after a success and null after a refusal, because neither of those has
  /// anything to report — a refusal is an answer. A [LocationFailure] with
  /// `opensSettings` set lands here, so a screen that wants to offer the system
  /// Settings can, and one that only wants to know "did it work" is not obliged
  /// to read a sentence.
  LocationFailure? lastFailure;

  /// The last fix, or null while nothing is known.
  DetectedPlace? get place => _place;

  bool get hasPlace => _place != null;

  /// True once the phone has been asked — including when the answer was no.
  /// The question is asked once per install, not once per launch.
  bool get asked => _asked;

  /// True while a fix is being negotiated, so the UI can show a quiet state
  /// instead of a second dialog.
  bool get busy => _busy;

  /// The detected wilaya, in the id the app and the API both use (`'16'`).
  String? get wilayaId => _place?.wilayaId;

  /// The wilaya as the pickers write it («الجزائر»), for headers and chips.
  String? get wilayaName => _place?.wilayaName;

  String? get commune => _place?.commune;

  /// Test-only: pretends the phone already answered.
  ///
  /// The real path needs a permission dialog and a GPS chip, neither of which a
  /// widget test has; every screen reads the answer through the getters above,
  /// so seeding here is the whole of what they need.
  @visibleForTesting
  void seed(DetectedPlace place) {
    _place = place;
    _asked = true;
    notifyListeners();
  }

  /// Reads what the last launch stored. Called once at boot; a miss is silent.
  Future<void> restore() async {
    if (_detached) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _asked = prefs.getBool(_askedKey) ?? false;
      final raw = prefs.getString(_key);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final id = m['wilaya_id']?.toString();
        if (id != null && id.isNotEmpty) {
          _place = DetectedPlace(
            wilayaId: id,
            wilayaName: m['wilaya_name']?.toString() ?? id,
            commune: m['commune']?.toString(),
            lat: (m['lat'] as num?)?.toDouble() ?? 0,
            lng: (m['lng'] as num?)?.toDouble() ?? 0,
            seatKm: (m['seat_km'] as num?)?.toDouble() ?? 0,
            communeFromDevice: m['from_device'] == true,
          );
        }
      }
      if (_place != null || _asked) notifyListeners();
    } catch (_) {
      // No storage (a locked profile, a test host): the app runs on its manual
      // pickers, which is the same app, one tap slower.
    }
  }

  /// Asks the phone where it is. The first thing a fresh install does.
  ///
  /// Returns true when a place is known afterwards. Never throws: a refusal, a
  /// closed location service or no fix leaves the manual pickers intact.
  Future<bool> askAndDetect({bool force = false}) async {
    if (_detached || _busy) return hasPlace;
    if (!force && _place != null) {
      await _markAsked();
      return true;
    }
    _busy = true;
    lastFailure = null;
    notifyListeners();
    try {
      _place = await detect();
      await _save();
      await _markAsked();
      return true;
    } on LocationFailure catch (failure) {
      // Only a real refusal spends the one-shot.
      //
      // This arm used to be `catch (_)` and to mark the question asked for every
      // failure alike, which quietly contradicted `Locator.detect`'s own doc: it
      // throws four ways and only one of them is a decision the user made. A
      // phone with the location toggle off, or one whose permission was blocked
      // in Settings, or one indoors with no fix — none of those is a refusal,
      // and none of them is answerable by never asking again. Marking them asked
      // made `PlaceWarmup`'s `if (!place.asked)` false for the rest of the
      // install (the flag is persisted), so the founder's brief — «ask for gps
      // fird thing when the user open the app» — could never run again even after
      // the user fixed the setting that blocked it. The three now keep the
      // question, and say what to do about it.
      if (!failure.userRefused) {
        lastFailure = failure;
      }
      // A refusal is recorded so the dialog never comes back unprompted. So is
      // a successful detection (the branch above). Nothing else is recorded,
      // because "not asked" is exactly what lets the next launch try again.
      if (failure.userRefused) await _markAsked();
      return false;
    } catch (_) {
      // Anything outside [Locator.detect]'s own vocabulary — a platform channel
      // throwing something it was never asked for. Also not a refusal, and also
      // not worth spending the question on.
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Fills the place without a dialog, for a launch that already has the
  /// permission from an earlier one.
  Future<bool> detectQuietly() async {
    if (_detached || _place != null || _busy) return hasPlace;
    try {
      if (!await Locator.canDetectQuietly()) return false;
      return await askAndDetect();
    } catch (_) {
      return false;
    }
  }

  /// Forgets the fix — used when a user says the detected wilaya is wrong.
  Future<void> clear() async {
    lastFailure = null;
    if (_place == null) return;
    _place = null;
    notifyListeners();
    if (_detached) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (error) {
      // The in-memory fix is already gone and the manual pickers still work, so
      // this must not throw — but a store that will not forget means the wilaya
      // the user just rejected is restored on the next launch. Named, because
      // "the app remembered a wilaya the user cancelled" is not a report anyone
      // can file from the outside.
      _reportStoreFailure('could not forget the detected wilaya', error);
    }
  }

  Future<void> _save() async {
    final p = _place;
    if (_detached || p == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'wilaya_id': p.wilayaId,
          'wilaya_name': p.wilayaName,
          'commune': p.commune,
          'lat': p.lat,
          'lng': p.lng,
          'seat_km': p.seatKm,
          'from_device': p.communeFromDevice,
        }),
      );
    } catch (error) {
      // **The one that mattered.** A refusal here is invisible until the next
      // launch, when the market opens unfiltered: the worker's own wilaya is
      // gone with nothing on screen to say so, and no way to tell a support
      // message "I set my city" apart from "I never did".
      _reportStoreFailure('could not store the detected wilaya', error);
    }
  }

  /// Says a preferences write that this class deliberately tolerated.
  ///
  /// Every caller here has a reason to swallow — the manual pickers still
  /// answer, so throwing would be worse — but "tolerated" is not "invisible":
  /// three writes below were the only failures in `lib/` with **no** record of
  /// any kind, while eight sibling refusals in `auth_state.dart` all print. The
  /// device writes the detected wilaya and nothing in the app can rebuild it,
  /// so a refusal has to be findable in a log line rather than in a user's
  /// description of a market that opened on the wrong wilaya.
  ///
  /// A [debugPrint] rather than `CrashReporter.capture`, matching the prefs
  /// refusals in `auth_state.dart`: this store is the same store, and a report
  /// written *through* prefs must not recurse when prefs is what failed.
  static void _reportStoreFailure(String what, Object error) {
    debugPrint('place: $what ($error)');
  }

  Future<void> _markAsked() async {
    _asked = true;
    if (_detached) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_askedKey, true);
    } catch (error) {
      // Costs one extra permission prompt on the next launch and nothing else,
      // which is why this stays a record rather than an error state.
      _reportStoreFailure('could not record the "asked" flag', error);
    }
  }
}
