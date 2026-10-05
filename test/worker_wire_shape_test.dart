// The last model that casts instead of reading, and what that costs a
// contractor who is on the page.
//
// `chat.dart`, `notification.dart` and `project.dart` were each taken off
// `json['x'] as String?` — the cast that succeeds on a `String` and on `null`
// and **throws on everything else**. `worker.dart` was left behind with seven
// of them (`id`, `user_id`, `full_name`, `bio`, `verification_status`, the two
// image URLs, `wilaya`, `commune`) and eleven `as num?`.
//
// **Why the throw is not survivable here.** `repository._rows` turns a model
// `TypeError` into an `ApiException` and **drops the row**. A dropped worker row
// is a contractor who does not exist on the browse screen — no card, no name,
// no error, no empty slot. The customer sees a shorter directory and has no
// way to know the man he was scrolling towards is missing. `chat.dart` says
// this exact thing about its own drop ("a hole in the conversation"), and the
// notification centre says it is "worse, because nothing on the screen is
// broken-looking; the screen simply lies". A contractor directory is the same
// class of screen with the same property, and it is the one the founder's own
// marketplace brief is about.
//
// **The shapes are real, not invented.** Two are D1's, and both are named in
// this repo already:
//   * `_asInt` in `data/repository.dart` — "a null from a LEFT JOIN, a string
//     from SQLite". Every id on a joined query arrives as `'16'`.
//   * a JSON **boolean** where a 0/1 flag is expected. `is_available`,
//     `is_identity_verified`, `is_certificate_verified` are all `(x as num?)`
//     with a `== 1` test, so a server that answers `true` — and the app's own
//     writer sends `is_available` as a **JSON bool**, `repository.dart:173` —
//     throws on a field that is in the same request the app just made.
//
// **And the bug that survives the cast.** `id: json['id'] as int` is not the
// only reading here that lies. `(json['user_wilaya'] ?? json['wilaya']) as
// String?` answers `null` for a wilaya the server sent as the **number** 16 —
// and `wilayaNameOrNull` then draws no chip, which is correct. But `commune` is
// used the same way and a `wilaya` sent as a number is a real shape in this
// API's own payloads. What matters is that both are *codes*, and a code must be
// text: `project.dart` reached the same conclusion for its own `wilaya` and
// says why — "flattening a number here would name a wilaya nobody stated".
//
// This file is the model-level regression. The read must (a) never throw, and
// (b) land on the same answer every other field of the same row already has.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/models/worker.dart';

/// A row copied from the live API on 5 Oct 2026 (`/api/mobile/workers/top`,
/// 96 rows read), with the shape left exactly as it arrived.
Map<String, dynamic> _live(Map<String, Object?> overrides) => {
      'id': 14,
      'user_id': 23,
      'bio': null,
      'specialties': ['painting'],
      'experience_years': 0,
      'price_range_min': null,
      'price_range_max': null,
      'service_radius_km': 30,
      'is_available': 1,
      'is_identity_verified': 0,
      'is_certificate_verified': 0,
      'verification_status': 'pending',
      'subscription_plan': 'free_trial',
      'avg_rating': 5,
      'total_reviews': 1,
      'total_completed_jobs': 1,
      'response_time_hours': null,
      'cover_image_url': null,
      'created_at': '2026-09-07 02:50:39',
      'updated_at': '2026-09-07 02:52:19',
      'full_name': 'مقاول أحمد',
      'phone': '0699555444',
      'user_wilaya': null,
      'commune': null,
      'avatar_url': null,
      'search_boost': 0,
      'wilaya_name': null,
    }..addAll(overrides);

void main() {
  group('a worker row that does not cast is still a worker', () {
    test('a SQLite string id is the number the app needs', () {
      // `_asInt`'s own words: a string from SQLite. `/api/mobile/workers/$id`
      // is built from this id, so a throw here loses the profile link too.
      final w = WorkerProfile.fromJson(
          _live({'id': '14', 'user_id': '23'}));
      expect(w.id, 14);
      expect(w.userId, 23);
    });

    test('an id sent as a string that is not a number does not throw', () {
      // Not a shape the server sends today. It is the shape the *next*
      // deploy sends, and the contract this file pins is that an unreadable
      // id is a visible wrong one, never an exception that takes the row.
      expect(() => WorkerProfile.fromJson(_live({'id': 'abc'})), returnsNormally);
    });

    test('a JSON bool where a 0/1 flag is expected is true, not a throw', () {
      // The app's **own** writer sends these three as JSON bools
      // (`repository.updateMyProfile` -> `'is_available': isAvailable`). A
      // read that only understands numbers cannot read the app's own writes.
      for (final key in const [
        'is_available',
        'is_identity_verified',
        'is_certificate_verified'
      ]) {
        final on = WorkerProfile.fromJson(_live({key: true}));
        final off = WorkerProfile.fromJson(_live({key: false}));
        expect(on.isAvailable || on.identityVerified || on.certificateVerified,
            isTrue,
            reason: '$key=true read as false');
        expect(off.isAvailable && off.identityVerified && off.certificateVerified,
            isFalse,
            reason: '$key=false read as true');
      }
    });

    test('the flag that matters is the one it claims to be', () {
      final w = WorkerProfile.fromJson(
          _live({'is_available': true, 'is_identity_verified': false,
            'is_certificate_verified': true}));
      expect(w.isAvailable, isTrue);
      expect(w.identityVerified, isFalse);
      expect(w.certificateVerified, isTrue);
    });

    test('a 1/0 flag kept answering as 1/0, so nothing moved', () {
      final w = WorkerProfile.fromJson(_live({
        'is_available': 1,
        'is_identity_verified': 0,
        'is_certificate_verified': 1,
      }));
      expect(w.isAvailable, isTrue);
      expect(w.identityVerified, isFalse);
      expect(w.certificateVerified, isTrue);
    });

    test('copy that is not copy is never flattened into digits', () {
      // `bio` is a person's own words. A number there is not a sentence, and
      // `worker_profile_screen` draws it as one.
      final w = WorkerProfile.fromJson(_live({'bio': 5, 'full_name': 42}));
      expect(w.bio, isNull);
      expect(w.fullName, isNot('42'));
    });

    test('a name that is only spaces is not a name', () {
      // `profile_edit_screen` seeds `_name.text = p.fullName`, so a name of
      // spaces comes back as a name of spaces and the save round-trips it.
      final w = WorkerProfile.fromJson(_live({'full_name': '   '}));
      expect(w.fullName.trim(), isEmpty);
    });

    test('an image URL that is not a string is no image', () {
      // `worker_card._Avatar` only checks null and empty, so a non-empty
      // non-URL string reaches `NetImage` and a number would reach it as one.
      final w = WorkerProfile.fromJson(
          _live({'avatar_url': 7, 'cover_image_url': 9}));
      expect(w.avatarUrl, isNull);
      expect(w.coverImageUrl, isNull);
    });

    test('an unreadable verification status is pending, never rejected', () {
      // `fromWire` maps anything it does not know to pending. That is the safe
      // half of the verdict: it cannot be `as String?` throwing here, and it
      // cannot become «مستنداتك مرفوضة» on a shape nobody read.
      final w = WorkerProfile.fromJson(_live({'verification_status': 3}));
      expect(w.verificationStatus.name, 'pending');
    });

    test('a wilaya code sent as a JSON number is the same code', () {
      // **Correction to what this file asserted first.** It was written to
      // demand that a numeric wilaya draw no chip at all, on the strength of
      // `project.dart`'s note that "an unreadable code must be blank and stay
      // blank". That note is about a code the app *cannot read*, and it is
      // also contradicted by the line two lines below it: `project.dart` reads
      // its own `wilaya` with `_wireText`, which flattens a number to its own
      // text. So which of the two is right?
      //
      // A wilaya code is an **identifier**, and JSON has no reason to quote
      // one: `16` and `"16"` are the same claim about the same wilaya. D1
      // returns the quoted form because SQLite stores every column as text, and
      // that is the only reason the string has to be tolerated. Flattening here
      // therefore names the wilaya the row **did** state.
      //
      // The lie the note guards against is flattening something that is not a
      // code — a name, a sentence, a column that drifted. Those are refused by
      // `_text` below, and a number in *those* fields is null, not digits.
      final w = WorkerProfile.fromJson(_live({'user_wilaya': 16}));
      expect(w.wilaya, '16');
      expect(Taxonomy.wilayaNameOrNull(w.wilaya), 'الجزائر');
      // And it must agree with the quoted form on the same row, because the
      // two arrive from the same column in two different deploys.
      final quoted = WorkerProfile.fromJson(_live({'user_wilaya': '16'}));
      expect(w.wilaya, quoted.wilaya);
    });

    test('a code nobody stated is still no chip', () {
      // The real drift case: a column that became something else. `''` and an
      // unreadable shape both draw nothing, so the card never names a place
      // the row did not say.
      for (final drifted in ['', '   ', 'zz', <int>[]]) {
        final w = WorkerProfile.fromJson(_live({'user_wilaya': drifted}));
        expect(Taxonomy.wilayaNameOrNull(w.wilaya), isNull,
            reason: 'user_wilaya=$drifted named a wilaya');
      }
    });

    test('a wilaya sent as a string is the chip it always was', () {
      final w = WorkerProfile.fromJson(_live({'user_wilaya': '16'}));
      expect(Taxonomy.wilayaNameOrNull(w.wilaya), 'الجزائر');
    });

    test('the legacy `wilaya` key is still read', () {
      final w = WorkerProfile.fromJson(_live({'user_wilaya': null, 'wilaya': '31'}));
      expect(Taxonomy.wilayaNameOrNull(w.wilaya), 'وهران');
    });

    test('a numeric count sent as a string is a count', () {
      final w = WorkerProfile.fromJson(_live({
        'experience_years': '12',
        'total_reviews': '24',
        'total_completed_jobs': '45',
        'service_radius_km': '50',
      }));
      expect(w.experienceYears, 12);
      expect(w.totalReviews, 24);
      expect(w.totalCompletedJobs, 45);
      expect(w.serviceRadiusKm, 50);
    });

    test('an absent count stays absent rather than becoming zero', () {
      // `serviceRadiusKm`'s own note: null means never set, and a 0 radius
      // would print «نصف قطر الخدمة: 0 كم» about a man who never answered.
      final w = WorkerProfile.fromJson(_live({'service_radius_km': null}));
      expect(w.serviceRadiusKm, isNull);
    });

    test('every readable row parses to the same profile as before', () {
      final w = WorkerProfile.fromJson(_live(const {}));
      expect(w.id, 14);
      expect(w.fullName, 'مقاول أحمد');
      expect(w.specialties, ['painting']);
      expect(w.verificationStatus.name, 'pending');
      expect(w.avgRating, 5.0);
      expect(w.totalReviews, 1);
      expect(w.hasRating, isTrue);
    });
  });
}
