// Which of a client's own jobs the app draws first, and why the app is allowed
// to decide.
//
// Found on 4 Oct 2026, the third member of a class this repo has now paid for
// twice. `review_order.dart` (29 Sep) is the precedent and states the defect
// in its own header: the wire sends `created_at` on every review, and
// `Review.fromJson` threw it away — so the reviews page drew all twelve of a
// contractor's reviews as identical undated cards, in server order, with the
// one thing a reader uses to judge a tradesman missing from the page whose
// entire job is that evidence.
//
// The same field, the same omission, one model over: `Project` had no
// `createdAt` at all, so **no project row in this app could be dated**. The
// home screen draws `shown.take(3)` under the heading «مشاريعي الأخيرة» — *my
// recent* projects — and nothing on the path from `Repository.myProjects` to
// `Project.fromJson` ordered anything. The three projects a client sees are
// whatever three rows the API answered first, and «الأخيرة» is a claim the code
// cannot honour. `projects_screen.dart` draws every row he owns in the same
// unsorted order.
//
// **What this file does NOT claim.** The public feed currently answers newest
// first (measured over 20 live rows on 4 Oct), so on today's server the rows
// happen to land correctly and the bug is *latent*, not visible. Latent is the
// worse kind: the app is correct only while someone else's `ORDER BY` stays
// correct, and nothing in this repo would notice the day it stopped. Owning
// the order is what turns that accident into a promise — which is precisely
// what `review_order.dart` argued when it took the same job.
//
// Two rules, both here rather than in a widget, because both are arithmetic and
// a rule testable only by pumping a screen is a rule that ships untested:
//
//   * **dated rows first, newest first**;
//   * **undated rows keep the order the server sent them, and go last** —
//     never dropped and never floated to the top pretending to be fresh.
//
// The tie-break is by id, and **it is a determinism rule, not a recency one**.
// `review_order.dart` breaks its ties on the higher id because a `Review.id` is
// a SQLite autoincrement, so "higher" really is "inserted later". A project id
// is a 64-character hash (`"961072acd6e7…"` on the wire), so that argument does
// not carry over: comparing two hashes lexically says nothing about which job
// was posted first. The tie-break is kept for the property it does give —
// Dart's `List.sort` is not stable, so two rows sharing a second could swap
// between two reads and the list would visibly shimmer as the client pulls.
library;

import '../models/project.dart';

/// A client's own jobs in the order he should read them.
List<Project> newestProjectFirst(List<Project> projects) {
  final dated = <Project>[];
  final undated = <Project>[];
  for (final p in projects) {
    (p.createdAt == null ? undated : dated).add(p);
  }
  dated.sort((a, b) {
    final byTime = b.createdAt!.compareTo(a.createdAt!);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  });
  return <Project>[...dated, ...undated];
}
