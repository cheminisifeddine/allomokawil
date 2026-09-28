// Answering «did my profile actually change» for a write that reported success.
//
// Found 29 Sep 2026 by auditing the write surface rather than the backlog, which
// is what the 28 Sep tick asked for. `ProfileEditScreen._save` is the one write
// in the app that can lose the user's data **on a 200**, with no error, no
// re-read and no way for the user to find out.
//
// The defect, in one line: the repository can only express «set this field».
// `updateMyProfile` builds its body with `if (priceRangeMin != null)`, and the
// form sends `DzNumber.tryParse(_minPrice.text)`, which is null for an empty
// box. So clearing a field produces a body with **no key at all** — the PATCH
// succeeds, the screen prints «تم حفظ ملفك بنجاح», and the server still holds
// the old value. Nothing is ever reported as failing, because nothing failed.
//
// The form invites the user to do exactly this. The hint above the two price
// boxes reads «اتركهما فارغين إذا كنت تفضل التسعير حسب المشروع» — leave them
// empty if you prefer per-project pricing — and live rows carry
// `price_range_min: 20000, price_range_max: 60000` (the app's own fixtures
// agree), so the ordinary contractor opening «تعديل ملفي» has a populated pair,
// decides to quote per project, clears two boxes and presses save. His public
// card keeps printing 20000-60000 دج to every customer browsing, and the app
// told him it was saved.
//
// So the rule here is the one `project_edit_outcome` already uses, for the same
// reason: **the request's own answer is not evidence.** A 200 carrying the row
// the server had *before* the PATCH is indistinguishable from a 200 carrying
// the row it has *after*, because both are `WorkerProfile.fromJson` of a
// well-formed profile. Only a fresh read, compared against what the form sent,
// can tell the two apart.
//
// This file is deliberately *not* the write-unconfirmed contract, and the reason
// is worth writing down because it is easy to assume otherwise: `ApiClient.patch`
// passes `idempotent: true`, and `_withFailover` raises `errWriteUnconfirmed`
// only for a request that is not idempotent. A PATCH therefore **never** throws
// it, so `isWriteUnconfirmed` is unreachable on this path and a re-read bolted
// onto its catch block would be code that can never run. The gap is not an error
// path. It is a successful one.
library;

import '../core/l10n/strings.dart';
import '../core/l10n/write_outcome.dart';
import '../models/worker.dart';
import 'taxonomy.dart';

/// The server's own copy of a contractor profile, as read back after a save.
class ProfileSnapshot {
  final String fullName;
  final String? bio;
  final List<String> specialties;
  final int experienceYears;
  final int? priceRangeMin;
  final int? priceRangeMax;
  final int? serviceRadiusKm;
  final bool isAvailable;

  const ProfileSnapshot({
    required this.fullName,
    this.bio,
    required this.specialties,
    required this.experienceYears,
    this.priceRangeMin,
    this.priceRangeMax,
    this.serviceRadiusKm,
    required this.isAvailable,
  });

  /// The server's row, read back.
  factory ProfileSnapshot.of(WorkerProfile p) => ProfileSnapshot(
        fullName: p.fullName,
        bio: p.bio,
        // Canonicalised on both sides: a legacy row may still hold a slug
        // dialect this form never writes, and comparing raw strings would call
        // an untouched profile "not saved".
        specialties: p.specialties.map(Taxonomy.canonical).toList(),
        experienceYears: p.experienceYears,
        priceRangeMin: p.priceRangeMin,
        priceRangeMax: p.priceRangeMax,
        // A stored 0 is the server's "never set" sentinel, not a value this
        // app can produce — the slider's floor is 1. The model's own
        // `serviceRadiusKm` note says the same, and this keeps the comparison
        // from reporting a 1 km radius as unsaved.
        serviceRadiusKm: (p.serviceRadiusKm != null && p.serviceRadiusKm! <= 0)
            ? null
            : p.serviceRadiusKm,
        isAvailable: p.isAvailable,
      );

  /// The values the form was about to send, built **before** the write.
  ///
  /// Before, for the same reason the project form builds its snapshot before
  /// posting: it is the only handle on a row whose answer is already in flight.
  factory ProfileSnapshot.form({
    required String fullName,
    required String bio,
    required Set<String> specialties,
    required int experienceYears,
    required int? priceRangeMin,
    required int? priceRangeMax,
    required int serviceRadiusKm,
    required bool isAvailable,
  }) =>
      ProfileSnapshot(
        fullName: fullName,
        bio: bio,
        specialties: specialties.map(Taxonomy.canonical).toList(),
        experienceYears: experienceYears,
        priceRangeMin: priceRangeMin,
        priceRangeMax: priceRangeMax,
        serviceRadiusKm: serviceRadiusKm,
        isAvailable: isAvailable,
      );

  /// The fields the server's copy disagrees with, in a fixed order.
  ///
  /// Fixed so the sentence never reshuffles between two runs of the same save,
  /// and public so the screen can name a field instead of reporting only that
  /// something did not take.
  List<String> mismatches(ProfileSnapshot sent) {
    final out = <String>[];
    if (fullName != sent.fullName) out.add('name');
    if (!_sameList(specialties, sent.specialties)) out.add('specialties');
    if (!_sameText(bio, sent.bio)) out.add('bio');
    if (experienceYears != sent.experienceYears) out.add('experience');
    // The price range is **one** name for the pair, the same reason the project
    // form's budget is one: a user reads min and max as a single figure, and two
    // names would send him to a box instead of the thing he changed.
    if (priceRangeMin != sent.priceRangeMin ||
        priceRangeMax != sent.priceRangeMax) {
      out.add('price_range');
    }
    if (serviceRadiusKm != sent.serviceRadiusKm) out.add('radius');
    if (isAvailable != sent.isAvailable) out.add('availability');
    return out;
  }

  bool matches(ProfileSnapshot sent) => mismatches(sent).isEmpty;

  /// A blank bio and an absent one are the same row: the form sends `''` and the
  /// API answers with a column that may be `null` or `''`. Comparing with `==`
  /// would call every *cleared* bio a mismatch.
  static bool _sameText(String? a, String? b) =>
      (a ?? '').trim() == (b ?? '').trim();

  /// Multiset, like the project form's trades and photos: sorted equality plus
  /// length, so a duplicate is not silently folded into "the same".
  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final x = [...a]..sort();
    final y = [...b]..sort();
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}

/// How a save that reported success turned out.
///
/// [fresh] is the server's own copy when there was one, so the screen can pop
/// with the profile the server really holds rather than the one the PATCH
/// echoed back. It is null only when the verification read failed, which is
/// **not** proof the save failed.
typedef ProfileWriteResult = ({
  WriteOutcome outcome,
  WorkerProfile? fresh,
  List<String> mismatched,
});

/// Re-reads the saved profile and classifies what the server actually kept.
///
/// [fetch] is a bare read. It must never throw: a second network failure while
/// one is already being reported would replace an honest answer with a stack
/// trace, and a throw is read as [WriteOutcome.unknown] — never
/// [WriteOutcome.missing], because the PATCH *did* answer 200 and telling the
/// user it did not save would be a lie about a request that succeeded.
Future<ProfileWriteResult> resolveProfileWriteOutcome({
  required ProfileSnapshot sent,
  required Future<WorkerProfile> Function() fetch,
}) async {
  WorkerProfile fresh;
  try {
    fresh = await fetch();
  } catch (_) {
    return (
      outcome: WriteOutcome.unknown,
      fresh: null,
      mismatched: const <String>[],
    );
  }
  final mismatched = ProfileSnapshot.of(fresh).mismatches(sent);
  return (
    outcome: mismatched.isEmpty ? WriteOutcome.landed : WriteOutcome.missing,
    fresh: fresh,
    mismatched: mismatched,
  );
}

/// The sentence for a save whose answer disagreed with the server's row.
///
/// Deliberately not [writeOutcomeCopy]: those three sentences answer a write
/// whose outcome was **unknown**, and this one answers a write that was
/// **confirmed and incomplete**. «وجدناه في القائمة» would be absurd — the
/// profile is on screen and was there before — and «لم يصل» would be a lie,
/// because the PATCH returned 200.
String profileWriteOutcomeCopy(ProfileWriteResult r) {
  if (r.outcome == WriteOutcome.landed) return S.profileSavedOk;
  if (r.outcome == WriteOutcome.unknown) return S.profileSavedUnverified;
  return S.profileSavedFieldHeld.replaceFirst(
      '%s', profileFieldCopy(r.mismatched.first));
}

/// The Arabic name of a field [ProfileSnapshot.mismatches] spells in English.
///
/// The keys stay English because they are what selects the comparison; turning
/// a key into a sentence at the point of comparison would make the contract
/// depend on the localisation layer. Every key is covered, and an unknown one
/// throws rather than rendering a name the user has never seen.
String profileFieldCopy(String key) => switch (key) {
      'name' => S.fieldName,
      'specialties' => S.fieldSpecialties,
      'bio' => S.fieldBio,
      'experience' => S.fieldExperience,
      'price_range' => S.fieldPriceRange,
      'radius' => S.fieldRadius,
      'availability' => S.fieldAvailability,
      _ => throw ArgumentError.value(key, 'key', 'no Arabic name for this field'),
    };
