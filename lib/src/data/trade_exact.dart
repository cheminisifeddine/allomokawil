// The rows a trade filter is allowed to show, and why the server's answer is a
// superset rather than the answer.
//
// Found on 4 Oct 2026 by reading the wire, not the screen — the audit rule the
// previous tick wrote down. This is the fifth member of the "the app trusts an
// answer it does not own" class (`review_order.dart` 29 Sep,
// `project_order.dart` 4 Oct, `worker_rank.dart` 4 Oct, and this one), and the
// first one where the server is not *ordering* rows wrongly but **matching**
// them wrongly.
//
// ## What the wire does
//
// `GET /api/mobile/workers/search?category=<slug>` does not answer with the
// contractors who do that trade. It answers with a **fuzzy** match. Measured
// on allomokawil.com, 4 Oct 2026, against every slug in `Taxonomy.categories`:
//
//   category=wallpaper          -> 9 rows, only 3 carry `wallpaper`
//   category=plaster_drywall    -> 3 rows, only 1 carries `plaster_drywall`
//   category=painting           -> 9 rows, all 9 carry it
//   … 41 rows served, 8 of them off-trade, across 2 of 16 trades.
//
// The mechanism is not a guess — it is the filter answering on a substring:
// `category=wall` returns 4 rows, `category=paper` 3, `category=paint` 9, and
// `category=a` returns **15**. A slug the app sends is a prefix of a longer
// slug, so `plaster_drywall` also drags in every `venetian_plaster` and
// `wallpaper` drags in every `painting`.
//
// ## Why that is a defect and not the server's business
//
// The founder pays for a *ranking* — the `search_boost` column that
// `worker_rank.dart` deliberately declines to re-derive. Nobody pays for
// membership, and membership is not a ranking claim that needs protecting: the
// card itself prints the man's trades, so a painter listed under «ورق جدران»
// is contradicted on the same card that carries him. The two taxonomy entries
// are adjacent on purpose —
//
//   plaster_drywall    جبس بورد وديكور
//   venetian_plaster   جبس فينيسي وستوكو
//
// — both are «جبس» to an Algerian customer, which is exactly why the fuzzy
// match fires and exactly why the two cannot be shown as the same result.
//
// Measured rows, verbatim from the wire on 4 Oct 2026:
//
//   category=wallpaper -> 9 rows; 6 do not carry it:
//     5  رشيد خليفي     ['painting']                          «الطلاء الخارجي والعام»
//     7  مراد حميدي     ['tiling_marble', 'painting']         «تأثير الرخام والترافرتان»
//     68 E2E اختبار…    ['painting']
//     71 E2E اختبار…    ['painting']
//     121 كريم بن سالم   ['painting', 'plumbing']              «دهان وسباكة»
//     124 حرفي 1200     ['painting']
//
// So a client who taps «ورق جدران» — a filter he chose to *narrow* the list —
// gets two thirds painters, and the only two men who actually do wallpaper
// (`2` خالد رحماني, `8` فريد زروالي) sit in the same nine rows, unmarked.
//
// ## What this file does, and what it deliberately does not
//
// It drops rows that do not carry the trade. It does **not** re-order: the
// server's order is preserved exactly, for the same reason
// `worker_rank.dart` preserves it — the boost is paid for and this app does
// not re-derive anybody's pricing model.
//
// Membership is read through [Taxonomy.canonical] on **both** sides, because a
// legacy row that writes `stucco` really does do `venetian_plaster`, and the
// alias table is the repo's own answer to that. Filtering on the raw string
// would re-introduce the same superset defect one layer down.
//
// Rows carrying **no** trade at all are dropped too, and that is the one arm
// worth arguing for: a row with `specialties: []` is not evidence of this
// trade, it is an absence of evidence, and the filter is a narrowing the user
// asked for. 74 of 91 live rows have no trades recorded — but **none of them
// are in any filtered answer**, so this arm is unreachable from today's wire
// and is here so that a future row cannot reintroduce it silently. It costs
// nothing to keep: with no category set this file returns the rows untouched,
// so a man with no trades is never hidden from the unfiltered directory.
//
// Empty is not a lie here: the screen already answers a filter that matches
// nobody with «لا نتائج مطابقة» and a «مسح البحث والفلاتر» button, which is
// the truth and an undo. Nothing needs to be invented to cover for this.
library;

import '../models/worker.dart';
import 'taxonomy.dart';

/// The rows of a filtered directory that really do the trade in [category].
///
/// Returns [rows] unchanged when [category] is null or blank — with no filter
/// set there is nothing to be exact about, and the unfiltered directory must
/// never lose a contractor (74 of 91 live rows carry no trades at all).
///
/// Server order is preserved; this is a filter and not a ranking. See the
/// header for the measurement and for why the alias table is read on both
/// sides.
List<WorkerProfile> exactTradeOnly(List<WorkerProfile> rows, String? category) {
  final wanted = category?.trim() ?? '';
  if (wanted.isEmpty) return rows;
  // Canonicalised once, not per row: the answer is the same question for the
  // whole list.
  final slug = Taxonomy.canonical(wanted);
  return rows
      .where((w) => w.specialties.any((s) => Taxonomy.canonical(s) == slug))
      .toList();
}
