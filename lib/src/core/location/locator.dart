import 'dart:async';

import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

import '../../data/taxonomy.dart';
import '../../data/wilaya_centers.dart';

/// Where the phone is, said in the app's own terms: a wilaya id, the wilaya's
/// name as the picker writes it, and — when the phone's geocoder can name it —
/// the commune.
class DetectedPlace {
  final String wilayaId;
  final String wilayaName;
  final String? commune;
  final double lat;
  final double lng;
  final double seatKm;
  final bool communeFromDevice;

  const DetectedPlace({
    required this.wilayaId,
    required this.wilayaName,
    required this.lat,
    required this.lng,
    required this.seatKm,
    this.commune,
    this.communeFromDevice = false,
  });
}

/// Everything that can stop a fix, each carrying the Arabic sentence the user
/// should read — never a raw platform error.
class LocationFailure implements Exception {
  /// The line to show. Arabic: it is read by the person holding the phone.
  final String messageAr;

  /// True when the cure lives in the system settings, so the UI can offer a
  /// button that opens them.
  final bool opensSettings;

  /// True when the user was asked and said no — the only failure that ends the
  /// story.
  ///
  /// [Locator.detect] can fail four ways and exactly one of them is a decision
  /// the user made: a permission prompt they dismissed. The other three are the
  /// phone's state — the location toggle off, a permission blocked in Settings
  /// from an *earlier* prompt, or no fix indoors — and every one of those is
  /// cured by changing something and coming back. A caller that treats them as
  /// refusals burns its one-shot on a question the user never refused, so this
  /// flag is what separates "asked and declined" from "told us nothing".
  final bool userRefused;

  const LocationFailure(
    this.messageAr, {
    this.opensSettings = false,
    this.userRefused = false,
  });

  @override
  String toString() => 'LocationFailure($messageAr)';
}

/// Turns one GPS reading into a wilaya, and optionally a commune.
///
/// No network service and no API key: the fix is matched against the wilaya
/// seats in [wilayaSeats]. The device geocoder is used only for the commune
/// name, and its failure is never fatal — a wilaya is a complete answer.
class Locator {
  static const Duration _defaultTimeout = Duration(seconds: 15);

  static Future<DetectedPlace> detect({
    Duration timeout = _defaultTimeout,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        'خدمة الموقع مغلقة في الهاتف. شغّلها من الإعدادات ثم أعد المحاولة.',
        opensSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      // `deniedForever` is NOT a refusal of this launch's prompt: the phone
      // never shows one, so it was answered somewhere the user cannot see from
      // here — in the system Settings. Cured by unblocking and coming back.
      throw const LocationFailure(
        'الوصول إلى الموقع ممنوع لهذا التطبيق. اسمح به من الإعدادات ثم أعد المحاولة.',
        opensSettings: true,
      );
    }
    if (permission == LocationPermission.denied) {
      // The one genuine refusal: the prompt was shown and dismissed. This is
      // the only failure that spends the app's single question.
      throw const LocationFailure(
        'لم تسمح بالوصول إلى موقعك. يمكنك اختيار الولاية يدوياً.',
        userRefused: true,
      );
    }

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: timeout,
        ),
      ).timeout(timeout);
    } on TimeoutException {
      throw const LocationFailure(
        'تعذّر تحديد موقعك في الوقت المحدد. جرّب في مكان مفتوح، أو اختر الولاية يدوياً.',
      );
    } catch (_) {
      throw const LocationFailure(
        'تعذّر تحديد موقعك الآن. اختر الولاية يدوياً والمحاولة ممكنة لاحقاً.',
      );
    }

    final seat = nearestSeat(position.latitude, position.longitude);

    String? commune;
    var fromDevice = false;
    try {
      final marks = await geocoding.Geocoding()
          .placemarkFromCoordinates(position.latitude, position.longitude)
          .timeout(const Duration(seconds: 6));
      if (marks.isNotEmpty) {
        final place = marks.first;
        final local = place.locality ??
            place.subAdministrativeArea ??
            place.subLocality;
        final trimmed = local?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          commune = trimmed;
          fromDevice = true;
        }
      }
    } catch (_) {
      // The geocoder is a nicety: without it the wilaya alone still answers.
    }

    return DetectedPlace(
      wilayaId: seat.id,
      wilayaName: Taxonomy.wilayaName(seat.id),
      commune: commune,
      communeFromDevice: fromDevice,
      lat: position.latitude,
      lng: position.longitude,
      seatKm: seat.km,
    );
  }

  /// True when the app already holds permission, so a screen may fill the
  /// wilaya silently instead of asking out of nowhere.
  static Future<bool> canDetectQuietly() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() => Geolocator.openAppSettings();
}
