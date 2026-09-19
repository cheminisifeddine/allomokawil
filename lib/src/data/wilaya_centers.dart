/// Where each wilaya's seat sits, so a GPS fix can be answered with a wilaya id
/// without a network call and without a geocoding key.
///
/// The values are the coordinates of the wilaya capital (the seat), the same
/// points used by the official administrative tables. A fix is matched to the
/// nearest seat by great-circle distance, which is the right answer for the
/// overwhelming majority of the country: the seats are spread out enough that
/// the nearest one is the wilaya the user is actually standing in, and the
/// result is always shown to the user for confirmation rather than assumed.
///
/// Keys are the ids used by [Taxonomy.wilayas] — zero padded, two digits.
library;

import 'dart:math' as math;

class WilayaSeat {
  final double lat;
  final double lng;

  const WilayaSeat(this.lat, this.lng);
}

const Map<String, WilayaSeat> wilayaSeats = {
  '01': WilayaSeat(27.8743, -0.2939), // أدرار
  '02': WilayaSeat(36.1647, 1.3317), // الشلف
  '03': WilayaSeat(33.8000, 2.8650), // الأغواط
  '04': WilayaSeat(35.8754, 7.1135), // أم البواقي
  '05': WilayaSeat(35.5560, 6.1741), // باتنة
  '06': WilayaSeat(36.7515, 5.0567), // بجاية
  '07': WilayaSeat(34.8504, 5.7281), // بسكرة
  '08': WilayaSeat(31.6167, -2.2167), // بشار
  '09': WilayaSeat(36.4703, 2.8277), // البليدة
  '10': WilayaSeat(36.3742, 3.9020), // البويرة
  '11': WilayaSeat(22.7850, 5.5228), // تمنراست
  '12': WilayaSeat(35.4042, 8.1244), // تبسة
  '13': WilayaSeat(34.8828, -1.3150), // تلمسان
  '14': WilayaSeat(35.3711, 1.3170), // تيارت
  '15': WilayaSeat(36.7169, 4.0497), // تيزي وزو
  '16': WilayaSeat(36.7538, 3.0588), // الجزائر
  '17': WilayaSeat(34.6703, 3.2630), // الجلفة
  '18': WilayaSeat(36.8210, 5.7667), // جيجل
  '19': WilayaSeat(36.1898, 5.4108), // سطيف
  '20': WilayaSeat(34.8303, 0.1517), // سعيدة
  '21': WilayaSeat(36.8761, 6.9094), // سكيكدة
  '22': WilayaSeat(35.1878, -0.6308), // سيدي بلعباس
  '23': WilayaSeat(36.9000, 7.7667), // عنابة
  '24': WilayaSeat(36.4625, 7.4262), // قالمة
  '25': WilayaSeat(36.3650, 6.6147), // قسنطينة
  '26': WilayaSeat(36.2639, 2.7539), // المدية
  '27': WilayaSeat(35.9315, 0.0892), // مستغانم
  '28': WilayaSeat(35.7050, 4.5419), // المسيلة
  '29': WilayaSeat(35.3975, 0.1400), // معسكر
  '30': WilayaSeat(31.9494, 5.3255), // ورقلة
  '31': WilayaSeat(35.6969, -0.6331), // وهران
  '32': WilayaSeat(33.6803, 1.0192), // البيض
  '33': WilayaSeat(26.4833, 8.4667), // إليزي
  '34': WilayaSeat(36.0731, 4.7608), // برج بوعريريج
  '35': WilayaSeat(36.7663, 3.4772), // بومرداس
  '36': WilayaSeat(36.7672, 8.3138), // الطارف
  '37': WilayaSeat(27.6711, -8.1474), // تندوف
  '38': WilayaSeat(35.6072, 1.8111), // تيسمسيلت
  '39': WilayaSeat(33.3683, 6.8674), // الوادي
  '40': WilayaSeat(35.4361, 7.1439), // خنشلة
  '41': WilayaSeat(36.2864, 7.9511), // سوق أهراس
  '42': WilayaSeat(36.5892, 2.4478), // تيبازة
  '43': WilayaSeat(36.4504, 6.2644), // ميلة
  '44': WilayaSeat(36.2647, 1.9672), // عين الدفلى
  '45': WilayaSeat(33.2667, -0.3167), // النعامة
  '46': WilayaSeat(35.2986, -1.1400), // عين تموشنت
  '47': WilayaSeat(32.4900, 3.6700), // غرداية
  '48': WilayaSeat(35.7372, 0.5556), // غليزان
  '49': WilayaSeat(33.9506, 5.9242), // المغير
  '50': WilayaSeat(30.5789, 2.8788), // المنيعة
  '51': WilayaSeat(34.4167, 5.0667), // أولاد جلال
  '52': WilayaSeat(21.3286, 0.9542), // برج باجي مختار
  '53': WilayaSeat(30.1300, -2.1700), // بني عباس
  '54': WilayaSeat(29.2639, 0.2392), // تيميمون
  '55': WilayaSeat(33.1000, 6.0667), // تقرت
  '56': WilayaSeat(24.5542, 9.4842), // جانت
  '57': WilayaSeat(27.1953, 2.4814), // عين صالح
  '58': WilayaSeat(19.5686, 5.7722), // عين قزام
};

/// Mean Earth radius in kilometres, the constant the great-circle term uses.
const double _earthRadiusKm = 6371.0088;

double _toRadians(double degrees) => degrees * 3.1415926535897932 / 180.0;

/// Great-circle distance between two points, in kilometres.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusKm * math.asin(math.sqrt(a));
}

/// The seat nearest to a fix, with the distance to it in kilometres.
({String id, double km}) nearestSeat(double lat, double lng) {
  String best = '16';
  double bestKm = double.infinity;
  for (final entry in wilayaSeats.entries) {
    final km = distanceKm(lat, lng, entry.value.lat, entry.value.lng);
    if (km < bestKm) {
      bestKm = km;
      best = entry.key;
    }
  }
  return (id: best, km: bestKm);
}
