// Proving that an *edit* to a project reached the server — the one write on
// this screen that could not be told apart from a success no matter what it
// answered.
//
// Found 28 Sep 2026 while auditing the write-outcome contract. Seven write
// paths re-read the server after `errWriteUnconfirmed` and tell the user which
// of three things is true. The eighth — saving an edit to a project the client
// already owns — shared the *create* path's recheck, and that recheck cannot be
// true or false about an edit. It asks `myProjects().any((p) => p.title == t)`.
//
// For a create that question is real. For an edit it is **tautological**: the
// project is already in `myProjects()`, under its *old* title, and the answer
// is true before the PATCH is sent. So every ambiguous edit was reported
// «وجدناه في القائمة — الطلب وصل بنجاح» — a claim about a write that may never
// have left the phone.
//
// The cost is a silent revert. A client who removes a photo, corrects a wrong
// phone number in the description, or fixes a mistyped budget and gets a
// stalled PATCH is told the change saved. The screen then pops as it does on
// success, the list is re-read, and the project still carries the old values.
// Nothing in the app ever said otherwise, and a removed photo comes back on the
// next load. Nothing is *duplicated* — which is exactly why the `threadHolds`
// and `portfolioHolds` fixes do not cover it: the roles are reversed here. The
// false sentence is the *success* one, not a retry that would duplicate.
//
// What the edit path can honestly ask, and the create path cannot: **the row
// carries the values this form was about to send.** An edit sends the whole row,
// not one field, so the server's own copy of it is the write. If every field
// matches, the PATCH landed. If any one differs, it did not — and the mismatch
// list can name the field, which is the sentence a user editing a budget needs
// («الميزانية لم تتغيّر») rather than a yes/no that sends him back to the form
// to hunt for what did not save.
//
// Deliberately *not* asked: the status. A PATCH that landed and a PATCH that
// did not both leave `status` at `open` when the project was open, so status
// carries no evidence either way. Never the id either: the row existed before
// the write and existed before it too if the write was lost, so the id
// identifies the row and proves nothing about whether the row changed.
library;

import '../core/l10n/strings.dart';
import '../core/l10n/write_outcome.dart';
import 'photo_count_copy.dart';
import '../models/project.dart';

/// The values an edit sends, as the server stores them.
///
/// A named record rather than a bag of values, because the answer the screen
/// needs is *which field* disagreed. Every member is something the form can
/// show the user when it reports a mismatch, so no member is here that the form
/// could not put in front of him.
///
/// [images] compares as a multiset and not as a list, and that is the half of
/// this file that has no counterpart in the create path: the form keeps
/// already-uploaded photos in `_keptImages`, appends new uploads to it, and the
/// PATCH replaces the project's photos wholesale. The write is therefore *which
/// photos the project has*, and it landed when they agree. Order is
/// server-owned and the form never reorders them, so comparing order would
/// compare something the user never asked for.
class ProjectEditSnapshot {
  final String title;
  final String category;

  /// Every trade, not just the primary. The form sends both — `category` is the
  /// primary and `categories` is the whole set — so comparing only the primary
  /// would call a write that added or dropped a second trade a landing.
  final List<String> categories;
  final String wilaya;
  final String? commune;
  final int? budgetMin;
  final int? budgetMax;
  final UrgencyLevel urgency;
  final String? description;
  final List<String> images;

  /// How many photos the upload was still answering when the write stalled.
  ///
  /// Carried on the **sent** side and read only there. These are the pictures
  /// the form holds but the server may or may not have received, and they are
  /// the one part of an edit that cannot be answered by reading the row: the
  /// row is identical whether the blob landed in R2 or never left the phone.
  /// So they are named in their own sentence and deliberately excluded from
  /// [mismatches] — a predicate that asked about them would report every other
  /// field as saved and the photo as lost, and the reverse would report a
  /// landed upload as a failure.
  final int pendingPhotos;

  const ProjectEditSnapshot({
    required this.title,
    required this.category,
    this.categories = const [],
    required this.wilaya,
    this.commune,
    this.budgetMin,
    this.budgetMax,
    required this.urgency,
    this.description,
    this.images = const [],
    this.pendingPhotos = 0,
  });

  /// The server's own copy, as read back after an unconfirmed write.
  factory ProjectEditSnapshot.of(Project p) => ProjectEditSnapshot(
        title: p.title,
        category: p.category,
        categories: p.allCategories,
        wilaya: p.wilaya,
        commune: p.commune,
        budgetMin: p.budgetMin,
        budgetMax: p.budgetMax,
        urgency: p.urgency,
        description: p.description,
        images: p.images,
      );

  /// The values this form is about to send, built from live form state.
  ///
  /// Built **before** the write, for the same reason the create path captures
  /// `publishedTitle` before posting: it is the one handle on a row whose
  /// answer is in flight. A form the user can still edit after the PATCH has
  /// left would otherwise describe a state that never existed.
  factory ProjectEditSnapshot.form({
    required String title,
    required Set<String> categories,
    required String? wilaya,
    String? commune,
    int? budgetMin,
    int? budgetMax,
    required UrgencyLevel urgency,
    String? description,
    required List<String> images,
    int pendingPhotos = 0,
  }) =>
      ProjectEditSnapshot(
        pendingPhotos: pendingPhotos,
        title: title,
        // The form holds a *set* of trades and sends `_categories.first` as the
        // primary. A snapshot carrying the set would compare a list against the
        // server's single `category` field, and could never match.
        category: categories.isEmpty ? '' : categories.first,
        categories: categories.toList(),
        wilaya: wilaya ?? '',
        commune: commune,
        budgetMin: budgetMin,
        budgetMax: budgetMax,
        urgency: urgency,
        description: description,
        images: images,
      );

  /// True when this snapshot (the server's copy) agrees with what the form sent.
  bool matches(ProjectEditSnapshot sent) => mismatches(sent).isEmpty;

  /// The fields the server's copy disagrees with, in a fixed order.
  ///
  /// Public so the screen can name the field instead of reporting only that
  /// something did not save. A fixed order so the sentence never reshuffles
  /// itself between two runs of the same write.
  ///
  /// The **photos already on the project** are in here, and [pendingPhotos] is
  /// what is deliberately not. They answer different questions and both are
  /// honest:
  ///
  ///  * A photo the user *removed* is a real mismatch. The only unconfirmed
  ///    write here is the upload, which runs before the PATCH is built, so a
  ///    re-read proves the PATCH never went — and the server therefore still
  ///    holds the picture the user believes he deleted. Nothing is unknowable
  ///    here; it is knowable and worth saying.
  ///  * A photo the user *added* is not in the snapshot at all, because it
  ///    never got a URL. The row cannot answer for it either way, which is
  ///    what [pendingPhotos] counts.
  ///
  /// The budget is **one** name, not two: a user edits min and max in one pair
  /// of boxes and reads them as one number, and «الميزانية» is the word that
  /// sends him back to the right place.
  List<String> mismatches(ProjectEditSnapshot sent) {
    final out = <String>[];
    if (title != sent.title) out.add('title');
    if (category != sent.category ||
        !_sameList(categories, sent.categories)) {
      out.add('category');
    }
    if (wilaya != sent.wilaya) out.add('wilaya');
    if (!_sameText(commune, sent.commune)) out.add('commune');
    if (budgetMin != sent.budgetMin || budgetMax != sent.budgetMax) {
      out.add('budget');
    }
    if (urgency != sent.urgency) out.add('urgency');
    if (!_sameText(description, sent.description)) out.add('description');
    if (!_sameList(images, sent.images)) out.add('images');
    return out;
  }

  /// Text compares as the server stores it, never as the user typed it.
  ///
  /// A blank description and an absent one are the same row: the form sends
  /// `null` for an empty box and the API answers with a column that may be
  /// `null` or `''`. Comparing with `==` would call every *cleared* description
  /// a mismatch, so a client who empties a box to remove text would be told the
  /// removal did not save. The same reason `threadHolds` never compares free
  /// text the user typed.
  static bool _sameText(String? a, String? b) => (a ?? '').trim() == (b ?? '').trim();

  /// Lists compare as a multiset — sorted element equality plus length.
  ///
  /// Used for the photos, the trades and nothing else. Sorted rather than
  /// deduplicated, so a duplicate is not silently folded away: two copies of
  /// one photo means the PATCH would store two rows, and the server's own copy
  /// would then hold two of them, and a set would have called that "the same".
  /// Length plus sorted equality catches it, and it is the one case where
  /// "the set is the same" is the wrong question.
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

/// How an unconfirmed edit turned out.
///
/// [fresh] is the server's own copy when there was one, so the screen can put
/// the real values on screen rather than a guess. It is null exactly when
/// [ProjectEditResult.outcome] is [WriteOutcome.unknown] — the phone could not
/// read the project, which is not proof the write failed.
typedef ProjectEditResult = ({
  WriteOutcome outcome,
  ProjectEditSnapshot? fresh,
  List<String> mismatched,
  int pendingPhotos,
});

/// Re-reads the edited project and classifies an unconfirmed PATCH.
///
/// [fetch] is a bare read of one project by id. It must never throw: a second
/// network failure while we are already reporting one would replace an honest
/// «outcome unknown» with a stack trace, and a throw is read as
/// [WriteOutcome.unknown] — never as [WriteOutcome.missing], because «the change
/// did not save, try again» is the one answer that would send a client editing
/// a budget into saving twice.
Future<ProjectEditResult> resolveProjectEditOutcome({
  required ProjectEditSnapshot sent,
  required Future<Project> Function() fetch,
}) async {
  Project fresh;
  try {
    fresh = await fetch();
  } catch (_) {
    return (
    outcome: WriteOutcome.unknown,
    fresh: null,
    mismatched: const <String>[],
    pendingPhotos: sent.pendingPhotos,
  );
  }
  final server = ProjectEditSnapshot.of(fresh);
  final mismatched = server.mismatches(sent);
  return (
    outcome: mismatched.isEmpty ? WriteOutcome.landed : WriteOutcome.missing,
    fresh: server,
    mismatched: mismatched,
    pendingPhotos: sent.pendingPhotos,
  );
}

/// The Arabic name of a mismatched field, as [ProjectEditSnapshot.mismatches]
/// spells it internally.
///
/// The field names travel in English because they are *keys* that select the
/// comparison, and turning a key into a sentence at the point of comparison
/// would make the contract depend on the localisation layer. Every key here is
/// covered, and a key with no name throws in debug rather than rendering
/// `unknown` to a user — a new field added to [ProjectEditSnapshot] without a
/// name is a bug in the app, not something to paper over at runtime.
String fieldCopy(String key) => switch (key) {
      'title' => S.fieldTitle,
      'category' => S.fieldCategory,
      'wilaya' => S.fieldWilaya,
      'commune' => S.fieldCommune,
      'budget' => S.fieldBudget,
      'urgency' => S.fieldUrgency,
      'description' => S.fieldDescription,
      'images' => S.fieldImages,
      _ => throw ArgumentError.value(key, 'key', 'no Arabic name for this field'),
    };

/// The sentence for an unconfirmed edit.
///
/// [mismatched] names the fields the server's copy disagrees with, and only
/// the first is spoken when several disagree: a client who changed the budget
/// and the description and got «العنوان، الميزانية، الوصف، الصور» learns less
/// than he did, and the sentence grows with every field the form gains. The
/// first one is enough to send him to the right part of the form, and the whole
/// form is one screen behind him.
String editOutcomeCopy(ProjectEditResult r) => switch (r.outcome) {
      // The photo is the one thing the re-read cannot vouch for, so «وصل» is
      // only said when there was no photo in question. Otherwise the sentence
      // names the fields that DID land and the picture that is unaccounted for,
      // which is the true shape of the answer: a budget that saved and a photo
      // that may or may not exist is neither "saved" nor "not saved".
      WriteOutcome.landed => r.pendingPhotos == 0
          ? S.editUnconfirmedLanded
          : S.editUnconfirmedPhotoUnchecked.replaceFirst(
              '%s', _photoCount(r.pendingPhotos)),
      WriteOutcome.missing => r.mismatched.isEmpty
          ? S.editUnconfirmedMissing.replaceFirst('%s', S.fieldTitle)
          : S.editUnconfirmedMissing
              .replaceFirst('%s', fieldCopy(r.mismatched.first)),
      WriteOutcome.unknown => S.editUnconfirmedUnknown,
    };

/// «صورة» / «صورتان» / «3 صور», the app's one photo count.
///
/// Borrowed from [photosAr] rather than spelled out again, and that is the
/// whole point of importing it: the portfolio limit, the attach strip and this
/// sentence must never disagree about what two photos are called, and a fourth
/// hand-written count in this app is how the first three came to disagree. A
/// count the helper has no form for is zero, which is the one value that can
/// never reach here — [pendingPhotos] is a length.
String _photoCount(int n) {
  final photos = photosAr(n);
  return photos.isEmpty ? '' : photos;
}
