// The review screen re-read the picker's **live** value when the recheck ran.
//
// `_submit` sends `rating: _rating` and the value it posts is correct, so the
// defect is invisible on a healthy connection. It appears only on the one path
// the screen exists to handle: the POST *reaches* the Worker, the row is
// stored, and no answer comes back inside the timeout — so `ApiClient` refuses
// to guess and throws `errWriteUnconfirmed`. The screen then re-reads the
// worker's review list to find out whether the rating landed.
//
// That recheck is a closure, and it reads `_rating` from the state object **at
// the moment it runs** — after two awaits, several seconds after the customer
// pressed send. The star picker is not disabled while `_busy` (only the button
// is: `loading: _busy` → `onPressed: null`), so those seconds are exactly when a
// customer fiddles with the stars.
//
// The predicate is `r.rating == _rating`, so it compares the server's row
// against whatever the picker happens to hold. Re-pick 4 stars as 1 star while
// the recheck is in flight and the predicate asks «is there a 1-star review on
// this project?» — the list comes back holding the real, stored, 4-star row,
// `rows.any(...)` is false, and the app announces, in Arabic, that the review
// did **not** arrive and invites the customer to type it again. The rating is
// on the server the whole time. Retrying creates a second one: a customer who
// rates a man 4 and is then told "it didn't arrive" is being taught to rate him
// twice, and the profile the marketplace sells trust on ends up with two rows
// for one job.
//
// This is the same class the publish form had (fixed in `da876a3`): a write
// whose *answer* is built from state read after the first `await`. The POST was
// always right; only the recheck was live.
//
// The rule pinned here: **the values that are sent are captured before the
// first `await`, and the recheck is judged against that capture** — not against
// the picker's later, possibly-tampered state.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/review/review_screen.dart';

Finder _stars(IconData icon) => find
    .descendant(of: find.byType(InkWell), matching: find.byIcon(icon))
    .hitTestable();

/// The review the Worker actually stored, as `GET /workers/:id/reviews` returns
/// it. Fields match `Review.fromJson` exactly, so nothing here is a shape the
/// real API would refuse.
Map<String, dynamic> _row(String projectId, int rating) => {
      'id': 901,
      'project_id': projectId,
      'worker_id': 16,
      'rating': rating,
      'comment': null,
      'images': <String>[],
      'customer_full_name': 'زبون تجربة',
      'created_at': '2026-09-29 10:00:00',
    };

/// A host that stores the write and loses the answer — the Algerian dead-zone
/// case — and then answers the recheck from what it really holds.
///
/// [gate] lets the test hold the recheck open for as long as it likes, which is
/// the window in which the picker is still live.
({ApiClient api, List<Map<String, dynamic>> stored}) _stalledApi({
  required Completer<void> gate,
}) {
  final stored = <Map<String, dynamic>>[];
  return (
    api: ApiClient(
      baseUrls: const ['https://x.test'],
      timeout: const Duration(milliseconds: 100),
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/review') && req.method == 'POST') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          // The write lands…
          stored.add(_row('p-1', (body['rating'] as num).toInt()));
          // …and the answer never comes back. `ClientException` is ambiguous
          // on purpose: the row is stored, so `_neverReached` must be false and
          // the layer must raise the unconfirmed verdict rather than retry.
          await gate.future;
          throw http.ClientException(
              'Connection closed before full header', req.url);
        }
        if (p.endsWith('/workers/16/reviews')) {
          return http.Response(
            jsonEncode(stored),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }),
    ),
    stored: stored,
  );
}

Future<void> _pumpReview(
  WidgetTester tester, Repository repo, String projectId) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ar'),
    home: ReviewScreen(
      projectId: projectId,
      workerId: 16,
      repo: repo,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

/// The number of stars the **picker** is currently showing as chosen.
///
/// Scoped to the picker's own `InkWell`s on purpose: the trust line under the
/// button also draws one `star_rounded` as decoration, and a plain
/// `find.byIcon` counts that one too — which is how a counter silently reports
/// a rating the user never picked.
int _liveRating(WidgetTester tester) => tester
    .widgetList<Icon>(_stars(Icons.star_rounded))
    .length;

void main() {
  testWidgets(
      'a rating the server stored is found even when the user re-picks mid-recheck',
      (tester) async {
    // Held open: the recheck GET cannot start until this completes, and the
    // timeout below fires while the test holds it.
    final gate = Completer<void>();
    final env = _stalledApi(gate: gate);
    final repo = Repository(env.api);
    await _pumpReview(tester, repo, 'p-1');

    await tester.tap(_stars(Icons.star_outline_rounded).at(3)); // 4 stars
    await tester.pump(const Duration(milliseconds: 100));
    expect(_liveRating(tester), 4,
        reason: 'the tap must have landed before the send is pressed');

    await tester.tap(find.text('إرسال التقييم'));
    await tester.pump(const Duration(milliseconds: 20));

    // The customer changes his mind while the POST is in flight. The picker is
    // live — the button is the only thing disabled — so this is a real tap on
    // a real control, not a poked state object.
    await tester.tap(_stars(Icons.star_rounded).at(0)); // now 1 star
    await tester.pump(const Duration(milliseconds: 20));
    expect(_liveRating(tester), 1,
        reason: 'the defect needs the picker to really have moved');

    // Let the stored write fail, then let the recheck run to completion.
    gate.complete();
    // Bounded, never `pumpAndSettle`: the busy button spins until the write
    // resolves, so the tree never settles and a settling pump would time out
    // rather than fail on the assertion this test is about.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(env.stored, hasLength(1));
    expect(env.stored.single['rating'], 4,
        reason: 'the POST carried the value the form held when it was pressed');

    // The recheck must judge the row against the rating that was **sent**.
    expect(find.text(S.writeUnconfirmedLanded), findsOneWidget,
        reason: 'the 4-star row is on the server; the recheck said it was not '
            'there because it compared it against a live _rating of 1');
    expect(find.text(S.writeUnconfirmedMissing), findsNothing,
        reason: 'telling a customer his rating was not sent, when it is stored, '
            'is the worst answer this screen can give');
    expect(tester.takeException(), isNull);
  });
}
