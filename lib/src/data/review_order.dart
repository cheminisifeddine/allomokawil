// Which review a customer reads first, and why the app is allowed to decide.
//
// Found on 29 Sep 2026. The wire sends `created_at` on every review — it is in
// `live_payload_models_test.dart`'s captured payload
// (`"created_at":"2026-09-11 20:23:50"`) and in every fixture the app has ever
// been driven with — and `Review.fromJson` **threw it away**. The model kept
// `rating`, `comment`, `images`, `customerFullName` and dropped the one field
// that says when.
//
// The consequence is on the page a customer picks his tradesman from. A
// contractor with twelve reviews — three this week, nine from last March —
// drew all twelve as identical cards: same stars, same comment, same avatar,
// **no time at all**. Every other dated list in this app says how old its rows
// are: the chat list, the notification centre, the projects list, the inbox,
// the browse strip. This one, on the one page whose whole job is evidence, was
// the only surface where a reader could not tell a review left last week from
// one left eight months ago — which is the difference between a man whose work
// kept being good and a man who was good once.
//
// So the field is parsed (through `parseServerTime`, the app's single
// server-clock reader, because D1 writes UTC without a zone) and the row prints
// it through `relativeTimeAr` — the same function, not a fifth copy of the
// grammar. This file owns the second half, which is the half that is easy to
// get wrong: **the order the list is drawn in.**
//
// An undated sort is a different defect, not a missing feature. `snap.data` is
// drawn in whatever order the Worker sent, so the moment the rows carry dates
// the list can read «قبل 3 أشهر» above «الآن» — the page would be dating its
// own evidence inconsistently, which is the one thing the rest of this app's
// copy layer exists to prevent. The customer arrives at a list he is about to
// make a decision from; the newest answer to "is he still good?" is the one
// that answers it.
//
// Two rules, both here rather than in the widget, because both are arithmetic
// and a rule that can only be tested by pumping a screen is a rule that ships
// untested:
//
//   * **dated rows first, newest first**;
//   * **undated rows keep the order the server sent them, and go last** —
//     never dropped and never floated to the top pretending to be fresh. A row
//     the server could not date is an absence, and this file has never deleted
//     anything, including on the surfaces where deleting was tempting.
library;

import '../models/quote_review.dart';

/// The reviews in the order a customer should read them.
///
/// A stable ordering: rows sharing a timestamp fall back to the higher id,
/// which is the row the server inserted last. Dart's `List.sort` is not stable,
/// so leaving the tie to it would let two reviews written in the same second
/// swap places between two reads of the same page.
List<Review> newestReviewFirst(List<Review> reviews) {
  final dated = <Review>[];
  final undated = <Review>[];
  for (final r in reviews) {
    (r.createdAt == null ? undated : dated).add(r);
  }
  dated.sort((a, b) {
    final byTime = b.createdAt!.compareTo(a.createdAt!);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  });
  return <Review>[...dated, ...undated];
}
