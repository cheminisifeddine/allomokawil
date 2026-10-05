// What the directory says when a customer filtered to a wilaya that has nobody
// in it — and why that sentence is not the one the screen already draws.
//
// Found 5 Oct 2026 by asking the live API the same question 58 times, which is
// the only way to see this defect: the filter sheet and the directory are two
// surfaces, and nothing in the app ever compared them.
//
//   for every id in Taxonomy.wilayas (58):
//       GET /api/mobile/workers/search?wilaya=<id>   -> row count
//
// Measured on production on 5 Oct 2026:
//
//   51 of 58 wilayas answer with **0 rows**
//   7 answer:  16 الجزائر 3 · 09 البليدة 1 · 15 تيزي وزو 1
//              19 سطيف 1 · 25 قسنطينة 1 · 31 وهران 1 · 35 بومرداس 1
//
// The cause is visible in the same payload and is not a server bug at all:
// **88 of the 97 rows in `/workers/search` carry no wilaya whatsoever** —
// `user_wilaya` null, `wilaya_name` null, `commune` null. Every contractor the
// app can show except nine has no place on the map, so filtering by place can
// only ever return the nine. The seven non-empty wilayas above are exactly
// those nine rows, minus two.
//
// So the sheet asks the customer a question the platform cannot answer. He
// taps «تيزي وزو» — a real wilaya, spelled correctly, in the right place in
// the list — and the directory answers:
//
//   لا نتائج مطابقة
//   جرّب تغيير التخصص أو الولاية
//   [ مسح البحث والفلاتر ]
//
// Every word of that is true and together they are worse than useless. They
// do not say **this wilaya is empty**, they say *your search matched nothing* —
// which puts the fault on the customer and on the trade he may also have set,
// and offers him a button that undoes the filter he did not know was the
// problem. The one thing that would actually help — that nobody is registered
// in Tizi Ouzou yet, and the way to find someone is to widen — is stated
// nowhere. Worse, «جرّب تغيير التخصص» is advice to change a chip he may not
// have touched, sent to 51 of 58 taps.
//
// This is the same defect class [browse_empty_action_test.dart] fixed on
// 29 Sep and the reason it needed fixing again: that item separated *filtered*
// from *unfiltered* so the unfiltered state could stop blaming a filter. This
// file finishes the separation — it tells apart the case where **a filter is
// on and the wilaya itself is what is empty** from the case where a category or
// a word is what is empty. Those are three different messages about three
// different situations, and one of them was answering the other two.
//
// ## The rule
//
// When the only filter set is a wilaya, and the server returned nothing, the
// sentence names the wilaya and says it is empty. Null otherwise: a category, a
// search word, or both are the ordinary «لا نتائج مطابقة» case, which the
// screen already draws correctly and this file does not claim.
//
// It deliberately does **not** claim the wilaya is permanently empty — it was
// empty when the question was asked, and contractors register. «ليس هناك مقاول
// مسجّل في <wilaya>» is a statement about this read, which is what the customer
// is entitled to, and the button underneath still says «مسح البحث والفلاتر» so
// the one action that helps is the one he is offered.
library;

/// The message for a directory filtered to one wilaya that has no contractor
/// in it, or null when the wilaya is not the only thing filtering the list.
///
/// [wilayaName] must be the name the sheet itself showed — the same string the
/// filter pill is drawn from — so the message names the place the customer
/// picked rather than a second, possibly different spelling of it.
String? emptyWilayaAr({
  required String? wilayaName,
  required bool categorySet,
  required bool querySet,
}) {
  if (wilayaName == null || wilayaName.isEmpty) return null;
  if (categorySet || querySet) return null;
  return 'ليس هناك مقاول مسجّل في $wilayaName بعد.\n'
      'وسّع البحث لعرض المقاولين في ولايات أخرى.';
}

/// The heading for that state.
///
/// Separate from the body because the body is the only sentence in this state
/// that names the place: the heading stays short enough to fit the 392 dp
/// canvas the app ships on, and the name goes in the line where there is room
/// for it.
const String emptyWilayaTitle = 'لا يوجد مقاول في هذه الولاية';
