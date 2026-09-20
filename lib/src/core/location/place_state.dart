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
  PlaceState() : _detached = false;

  /// A store with no storage behind it.
  ///
  /// Widget tests and any tree pumped without an [AppScope] get the same API
  /// without touching a platform channel, which is also why every method here
  /// tolerates a failure instead of throwing.
  PlaceState.detached() : _detached = true;

  static const _key = 'place.v1';
  static const _askedKey = 'place.asked.v1';

  /// True for [PlaceState.detached]: no prefs, no platform channels.
  final bool _detached;

  DetectedPlace? _place;
  bool _asked = false;
  bool _busy = false;

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
    notifyListeners();
    try {
      _place = await Locator.detect();
      await _save();
      await _markAsked();
      return true;
    } catch (_) {
      // The refusal is the user's; it is not an error to report. Only the
      // attempt is recorded, so the dialog never comes back unprompted.
      await _markAsked();
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
    if (_place == null) return;
    _place = null;
    notifyListeners();
    if (_detached) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
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
    } catch (_) {}
  }

  Future<void> _markAsked() async {
    _asked = true;
    if (_detached) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_askedKey, true);
    } catch (_) {}
  }
}
