// The jobs a trade filter is allowed to show, and why the market's answer is a
// family union rather than the answer.
//
// Found on 4 Oct 2026 by reading the wire, not the screen — the audit rule the
// 43rd tick wrote down. This is the sixth member of the "the app trusts an
// answer it does not own" class (`review_order.dart` 29 Sep, `project_order.dart`
// 4 Oct, `worker_rank.dart` 4 Oct, `trade_exact.dart` 4 Oct), and the **projects
// half** of the one the last tick shipped for the directory.
//
// ## What the wire does
//
// `GET /api/mobile/projects?category=<slug>` does not answer with the jobs
// filed under that trade. It answers with a **family union**. Measured on
// finili.medsaidkichene.workers.dev, 4 Oct 2026, against every slug the app
// actually sends (`Taxonomy.categories` — 16 that carry projects):
//
//   category=wallpaper        -> 17 rows, 1 carries `wallpaper`
//   category=painting         -> 17 rows, 16 carry `painting`
//   category=plaster_drywall  ->  5 rows, 3 carry `plaster_drywall`
//   category=venetian_plaster ->  5 rows, 2 carry `venetian_plaster`
//   … 82 rows served across 16 trades, **22 of them off-trade, in 4 trades**.
//
// ## The mechanism is a family union, NOT a substring — and saying so matters
//
// The last tick measured `workers/search` answering on a **substring**
// (`category=wall` -> 4 rows, `category=a` -> 15). It is tempting to copy that
// conclusion here. It is **wrong**, and a rule written on it would be built on a
// measurement that does not hold on this endpoint:
//
//   category=wall   -> 0 rows      category=paint  -> 0 rows
//   category=paper  -> 0 rows      category=plaster -> 0 rows
//   category=w      -> 0 rows      category=ain    -> 0 rows
//   category=ter    -> 0 rows      category=a      -> 0 rows
//
// Every fragment returns **nothing**. What the endpoint actually does is group
// the taxonomy into *finish families* and answer with the union of the family —
// so two slugs that are not substrings of one another still answer with the
// **identical row set**: `wallpaper` and `painting` are byte-identical 17-row
// lists, and `plaster_drywall`, `drywall` and `venetian_plaster` are the same 5
// rows. `wallpaper_` and `painting_` (trailing underscore, matches no slug)
// also answer 17. `epoxy` == `epoxy_flooring` == 3, `aluminum` ==
// `carpentry_aluminum` == 1, `welding` == `ironwork_welding` == 1.
//
// So this file is **not** a copy of `trade_exact.dart` with a different
// argument: the workers rule and the project rule have the same *duty* (a filter
// must answer with the rows that carry the trade) but different *reasons* the
// server widens, and the header of each says which. That distinction is the
// reason both files exist rather than one shared helper.
//
// ## Why that is a defect and not the server's business
//
// The founder pays for a *ranking* — the `search_boost` the other order files
// deliberately decline to re-derive. Nobody pays for **membership**, and the
// project card prints the man's trades back to him, so a «ورق جدران» filter
// answering with sixteen painters is contradicted on the card that carries the
// job. The taxonomy entries are adjacent on purpose:
//
//   plaster_drywall    جبس بورد وديكور
//   venetian_plaster   جبس فينيسي وستوكو
//
// — both «جبس» to an Algerian customer, which is exactly why the server groups
// them and exactly why they cannot be one answer. A contractor who opens the
// market, picks «جبس فينيسي» to find decorative-finish work, and is handed a
// drywall job he did not bid on has been lied to by a filter he chose to
// *narrow* with.
//
// ## What this file does, and what it deliberately does not
//
// It drops jobs that do not carry the trade. It does **not** re-order: server
// order is preserved exactly, for the reason `worker_rank.dart` gives.
//
// Membership is read through [Taxonomy.canonical] on **both** sides, because a
// legacy row writing `gypsum` really does do `plaster_drywall`, and the alias
// table is this repo's own answer to that. Filtering on the raw string would
// re-introduce the same superset defect one layer down — which is precisely how
// the `plaster_drywall` answer already pulls in `25ef91d0`, a `construction`
// job that merely *lists* drywall among six trades.
//
// `allCategories` is read, not `categories`: a job posted before multi-trade
// existed has only `category`, and dropping those rows would hide the oldest
// jobs in the market — the opposite of the fix.
library;

import '../models/project.dart';
import 'taxonomy.dart';

/// The rows of a filtered market that really do the trade in [category].
///
/// Returns [rows] unchanged when [category] is null or blank — with no filter
/// set there is nothing to be exact about, and the unfiltered market must never
/// lose a job.
///
/// Server order is preserved; this is a filter and not a ranking.
List<Project> exactProjectTrades(List<Project> rows, String? category) {
  final wanted = category?.trim() ?? '';
  if (wanted.isEmpty) return rows;
  // Canonicalised once, not per row: the answer is the same question for the
  // whole list.
  final slug = Taxonomy.canonical(wanted);
  return rows
      .where((p) => p.allCategories.any((c) => Taxonomy.canonical(c) == slug))
      .toList();
}
