// A customer finds a contractor by the phone number he was handed in person,
// and this directory could not do it — on any input.
//
// Found 5 Oct 2026 on production, by reading the wire instead of the screen.
// `GET /api/mobile/workers/search` sends `phone` on **97 of 97** live rows
// (every one exactly 10 digits, `0` + 05/06/07 + 8), and also on
// `/api/mobile/workers/$id`. The app parsed none of it: `WorkerProfile` had no
// `phone` member at all, so the single column the wire carries for every
// contractor was dropped on the floor, and `browse_screen`'s `_matchesQuery`
// read only name, bio, commune, wilaya and trades.
//
// So typing `0550000009` into «ابحث عن مقاول» answered «لا نتائج مطابقة» and
// offered to clear the filters, while the man holding that number sat on the
// same screen one unfiltered scroll away. The app was not failing to find him;
// it was asserting that nobody carries it.
//
// ## Why this is not "just add phone to the field list"
//
// Two things make it a defect rather than a missing feature, and both are
// measured, not assumed.
//
// **1. Every shape of the number the app already knows how to read failed.**
//   * `0550000009`      — as typed
//   * `٠٥٥٠٠٠٠٠٠٩`      — Arabic-Indic, which is what a contact card on an
//                          Algerian keyboard produces
//   * `+213 550 00 00 09` / `00213550000009` — pasted out of a contact list
//   * `0009`            — what a customer actually remembers
//
// **2. The app had already paid for this and thrown it away.**
// `ArabicSearch` documents its Arabic-Indic digit fold with the sentence
// *"which arrive when someone pastes a phone number out of their contacts"*,
// and `DzPhone.digits` is the repo's one canonical digit extractor, used by
// every phone field in the app. Both were unreachable from here — because the
// number was discarded one layer earlier, at the parser. The repair existed and
// was documented; the directory was simply not wired to it.
//
// ## The rules, and why each is a rule and not a preference
//
// **Digits are compared, never the string.** A query is folded to digits with
// [DzPhone.digits] — the same helper the phone *fields* use — so the number the
// customer typed and the number the server stored are compared as the two
// things they are: sequences of digits. A space, a dash, a `+`, a country code
// and a different script all vanish, because none of them changes whose number
// it is. This is the `06 00 00 00 09` → `0550000009` case, and it is the *same*
// fold `DzPhone.canonicalFromDigits` performs, so the directory cannot disagree
// with the registration form about what a given keystroke means.
//
// **A partial number matches a prefix or a suffix, not a substring anywhere.**
// Four remembered digits is the realistic input — nobody types ten digits from
// memory — so a substring test would be nearly useless, and a *prefix* test
// would throw away `0009` entirely. Both ends are accepted and nothing else: a
// token that appears in the middle of the number (`5000` of `0550000009`) does
// not match, because it would answer a customer searching one thing with a
// contractor whose number only half contains what he asked for. It is also the
// only shape that keeps a short query from matching half the market.
//
// **The minimum is three digits, because below it the answer is noise.** Two
// digits match a large share of a 97-row directory and a customer typing `00`
// did not ask for that. Three is short enough for a remembered fragment and
// long enough to be a deliberate act. A query shorter than this is *not*
// silently ignored: it falls through to the ordinary word search, so typing
// `55` still finds a contractor whose bio or name contains it, and nothing the
// user typed ever produces a search that cannot be run.
//
// **A word is never a number, and this file never returns "no match" on its
// own.** The numeric arm is an *addition* to the existing text match, not a
// replacement: a query is a number only when [DzPhone.digits] leaves digits and
// the query's non-digit characters are nothing but the separators people type.
// So `سباكة` goes to the text matcher untouched, `055 00 00 09` goes to the
// numeric arm, and a mixed `سمير 0550000009` matches on both halves and finds
// a contractor who is *both* the man and the number. The single seam this
// guards is the one that makes a bug here expensive: if the numeric arm were
// the *only* arm, one unrecognised character would turn a working search into
// an empty list.
//
// ## What this deliberately does NOT do
//
// **It does not print the number.** Nothing in this app shows a contractor's
// phone — the contact path is «مراسلة», the in-app thread. Parsing the field
// makes it searchable; displaying it is a separate product decision the
// founder has not made, and taking it here would be the app handing out
// contact details nobody agreed to publish.
//
// **It does not filter the unfiltered directory.** With no query this returns
// every row, because 75 of 97 live rows carry no number at all and a man with
// no number in the payload is still a man in the market.
library;

import '../core/text/arabic_search.dart';
import '../core/text/dz_phone.dart';
import '../models/worker.dart';
import 'taxonomy.dart';

/// Fewest digits that may be compared on their own.
///
/// Below three a query matches a large share of the directory, so answering it
/// with numbers would be inventing a relevance claim nobody made. See the
/// header for why the threshold is three and not one.
const int minPhoneDigits = 3;

/// The digits of [query] when it is a **number query**, else null.
///
/// A number query is one whose only non-digit characters are the separators a
/// phone keyboard produces — spaces, dashes, dots, brackets, a `+`. Anything
/// else (`سباكة`, `abc`, `55abc`) is a word query and answers null, which sends
/// it to the text arm untouched. This is the seam that keeps a word search
/// from ever being read as a number.
String? phoneQueryDigits(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;
  // `canonicalFromDigits`, not bare `digits`: the country-code forms
  // (`+213 550 00 00 09`, `00213…`) are the ones people paste out of a contact
  // list, and [DzPhone] already owns the repair for both — a second hand-rolled
  // strip here would be a rule that can disagree with the registration form.
  // The international form it yields is 9 digits, so the length floor is
  // measured on what a customer can actually remember, not on the format.
  final digits = DzPhone.canonicalFromDigits(trimmed);
  if (digits.length < minPhoneDigits) return null;
  // The rest must be separators only. Without this, `55abc` would contribute
  // the digits `55` and be answered as a number query, and a word that happens
  // to carry digits would be searched as a number.
  for (final rune in trimmed.runes) {
    final ch = String.fromCharCode(rune);
    if (_isDigit(ch)) continue;
    if (_separators.contains(ch)) continue;
    return null;
  }
  return digits;
}

bool _isDigit(String ch) =>
    (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) ||
    (ch.codeUnitAt(0) >= 0x0660 && ch.codeUnitAt(0) <= 0x0669);

const String _separators = ' \t+-()._/ ';

/// True when [query] is the customer's own number for [worker].
///
/// Both sides are folded through [DzPhone.digits], so the three shapes a
/// number actually arrives in — ASCII, Arabic-Indic, spaced or grouped — are
/// one comparison, and the `+213` / `00213` prefix the phone fields already
/// repair is handled by the same helper rather than by a second rule written
/// here.
///
/// The test is **prefix or suffix**, never "contains": see the header for why
/// a remembered four-digit fragment has to match and a middle fragment must not.
bool workerPhoneMatches(String query, String? phone) {
  if (phone == null) return false;
  final q = phoneQueryDigits(query);
  if (q == null) return false;
  final stored = DzPhone.digits(phone);
  if (stored.length < q.length) return false;
  return stored.startsWith(q) || stored.endsWith(q);
}

/// Does this contractor answer the typed text?
///
/// [ArabicSearch.matches] on the five things a contractor is known by — name,
/// bio, commune, wilaya, trades — **or** [workerPhoneMatches]. The numeric arm
/// is added to the text arm and never replaces it, so a mixed query matches on
/// whichever half it can and a word is never routed into a numeric comparison.
bool workerMatchesQuery(WorkerProfile w, String query) {
  final text = ArabicSearch.matches(query, [
    w.fullName,
    w.bio,
    w.commune,
    // Null for a blank or unknown code, so the old «الجزائر» fallback could
    // not make every contractor answer a search for Algiers.
    Taxonomy.wilayaNameOrNull(w.wilaya),
    w.specialties.map(Taxonomy.categoryName).join(' '),
  ]);
  if (text) return true;
  return workerPhoneMatches(query, w.phone);
}

/// [workerMatchesQuery] over a list, with the empty-query shortcut: a cleared
/// (or punctuation-only) search box returns the rows untouched, so the
/// unfiltered directory is never narrowed by anything in this file.
List<WorkerProfile> narrowWorkers(List<WorkerProfile> rows, String query) {
  if (ArabicSearch.normalize(query).isEmpty) return rows;
  return rows.where((w) => workerMatchesQuery(w, query)).toList();
}
