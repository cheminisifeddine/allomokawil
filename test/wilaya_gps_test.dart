import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/data/wilaya_centers.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fix is turned into a wilaya by comparing it with the wilaya seats. The
/// test pins the property that matters: a reading taken in a known Algerian
/// city resolves to that city's wilaya, from the table alone, with no network.
void main() {
  group('wilaya seats', () {
    test('every wilaya in the taxonomy has a seat', () {
      for (final wilaya in Taxonomy.wilayas) {
        expect(wilayaSeats.containsKey(wilaya.id), isTrue,
            reason: 'no seat for ${wilaya.id} ${wilaya.name}');
      }
    });

    test('no seat is a placeholder at sea', () {
      for (final entry in wilayaSeats.entries) {
        expect(entry.value.lat, inInclusiveRange(18.0, 38.0),
            reason: 'latitude out of Algeria for ${entry.key}');
        expect(entry.value.lng, inInclusiveRange(-9.0, 12.0),
            reason: 'longitude out of Algeria for ${entry.key}');
      }
    });

    test('a fix in Algiers resolves to Algiers', () {
      final seat = nearestSeat(36.7538, 3.0588);
      expect(seat.id, '16');
      expect(seat.km, lessThan(1));
    });

    test('a fix in Oran resolves to Oran', () {
      final seat = nearestSeat(35.6971, -0.6308);
      expect(seat.id, '31');
    });

    test('a fix in Constantine resolves to Constantine', () {
      expect(nearestSeat(36.3650, 6.6147).id, '25');
    });

    test('a fix in Bou Saada resolves to Msila, not to a neighbour', () {
      // 35.2122, 4.1737 is Bou Saâda itself, well inside M'Sila.
      expect(nearestSeat(35.2122, 4.1737).id, '28');
    });

    test('the deep south resolves to the southern wilayas', () {
      expect(nearestSeat(22.7850, 5.5228).id, '11'); // تمنراست
      expect(nearestSeat(27.1953, 2.4814).id, '57'); // عين صالح
      expect(nearestSeat(19.5686, 5.7722).id, '58'); // عين قزام
    });

    test('the distance term is real kilometres', () {
      // Algiers to Oran is a little over 350 km as the crow flies.
      final km = distanceKm(36.7538, 3.0588, 35.6969, -0.6331);
      expect(km, inInclusiveRange(330, 400));
    });

    test('a point one kilometre from a seat is about one kilometre away', () {
      // One minute of latitude is 1.852 km by definition.
      expect(distanceKm(36.7538, 3.0588, 36.7538 + 1 / 60, 3.0588),
          inInclusiveRange(1.7, 2.0));
    });

    test('every seat is the nearest one to itself', () {
      for (final entry in wilayaSeats.entries) {
        final seat = nearestSeat(entry.value.lat, entry.value.lng);
        expect(seat.id, entry.key,
            reason: '${entry.key} does not win its own seat');
      }
    });
  });
}
