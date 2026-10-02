// The bid card cast the server's JSON by hand, and this file holds the two
// models that draw the two screens a customer decides who to hire from.
//
// `repository._rows` turns a model `TypeError` into an `ApiException` and drops
// the row, so the claim is the same one the other three files in this family
// make — **one row the server answered in an unexpected shape costs that row
// and nothing else** — and here the cost is the worst of the five outcomes the
// loop has found. A lost chat row is a message missing from a thread. A lost
// notification is never drawn. A lost project is a job nobody can open. And a
// lost **bid** is the other half of a decision: the customer comparing three
// contractors sees two, and the one that vanished is the one the backend then
// accepts on their behalf.
//
// Both models here are non-nullable on their identifiers — `id` and `worker_id`
// were hard `as int` — so there was no null to tolerate and any other shape
// threw on the whole list.
//
// So the tests are written from two ends, as in the three shipped files:
//   * the parser, against every shape the server is documented to answer with
//     (`_asInt`'s own doc: "a string from SQLite"); and
//   * the **real Repository against a fake HTTP client**, which is the only
//     place the "one row, not the list" promise can be proved at all — the drop
//     lives in `_rows`, not in the model.
//
// **The rule that decides the fallbacks is the caller, not the field.** Two of
// the columns on this row are printed to the customer as facts — the price and
// the star row — and for those a reader's 0 is not an absence but a *lie*:
// «المبلغ: 0 دج» is a price no contractor typed, and five empty stars say a
// man did bad work. Those two draw sites now ask the model whether the value is
// real, so an unreadable column costs the line rather than the truth.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/text/monogram.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/quote_review.dart';

/// A D1 quote row in the shape `/api/mobile/projects/{id}/quotes` answers
/// with. Every field is `Object?` on purpose: the wrong-shape fixtures have to
/// be able to say `'30'` and `5`, which is the whole point of them.
Map<String, Object?> _quote({
  Object? id = 88,
  Object? projectId = 'b0b5644a223e',
  Object? workerId = 12,
  Object? amount = 45000,
  Object? message = 'أقدر نتكفل بها في أسبوع',
  Object? estimatedDays = 7,
  Object? workerFullName = 'كريم بلقاسم',
  Object? workerAvatarUrl,
  Object? workerAvgRating = 4.5,
  Object? workerTotalReviews = 3,
  Object? workerVerificationStatus = 'verified',
  Object? status = 'pending',
  Object? createdAt = '2026-09-20 10:00:00',
}) =>
    {
      'id': id,
      'project_id': projectId,
      'worker_id': workerId,
      'amount': amount,
      'message': message,
      'estimated_days': estimatedDays,
      'worker_full_name': workerFullName,
      'worker_avatar_url': workerAvatarUrl,
      'worker_avg_rating': workerAvgRating,
      'worker_total_reviews': workerTotalReviews,
      'worker_verification_status': workerVerificationStatus,
      'status': status,
      'created_at': createdAt,
    };

/// A D1 review row in the shape `/api/mobile/workers/{id}/reviews` answers
/// with.
/// **No sentinel, and that is the point.** A default in the *signature* already
/// separates the two cases: omitted -> the good list, explicit `null` -> absent.
/// The earlier `images ?? [...]` in the body collapsed them, so the test that
/// exists to prove an absent column is survived was quietly asserting against a
/// full list and passing for the wrong reason.

Map<String, Object?> _review({
  Object? id = 5,
  Object? projectId = 'b0b5644a223e',
  Object? workerId = 12,
  Object? rating = 4,
  Object? comment = 'عمل نظيف واحترافي',
  Object? images = const <String>['https://cdn.x.test/1.jpg'],
  Object? customerFullName = 'ياسين عماري',
  Object? createdAt = '2026-09-18 08:30:00',
}) =>
    {
      'id': id,
      'project_id': projectId,
      'worker_id': workerId,
      'rating': rating,
      'comment': comment,
      'images': images,
      'customer_full_name': customerFullName,
      'created_at': createdAt,
    };

Repository _repoOver(List<Map<String, Object?>> rows) => Repository(
      ApiClient(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(rows),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        baseUrls: ['https://x.test'],
      ),
    );

void main() {
  group('the columns D1 answers as strings are still read as columns', () {
    test('a row of strings parses exactly as the numbers it stands for', () {
      // `_asInt` in data/repository.dart documents this answer in its own
      // words — "a null from a LEFT JOIN, a string from SQLite".
      final q = Quote.fromJson(_quote(
        id: '88',
        workerId: '12',
        amount: '45000',
        estimatedDays: '7',
        workerTotalReviews: '3',
      ));
      expect(q.id, 88);
      expect(q.workerId, 12);
      expect(q.amount, 45000);
      expect(q.estimatedDays, 7);
      expect(q.workerTotalReviews, 3);
    });

    test('a stringified status still reaches its table', () {
      // The value arrives as an int here — the shape a `JSON_EXTRACT` column
      // takes when the worker wrote a number into a name — and must still
      // land on the enum rather than throwing on the way in.
      final q = Quote.fromJson(_quote(status: 'accepted'));
      expect(q.status, QuoteStatus.accepted);
      expect(q.isDecided, isTrue);
    });

    test('an unreadable status is pending, and the card stays drawable', () {
      // Same promise [QuoteStatus.from] already makes for null, now for the
      // shapes that used to throw: a bid is decided only when the server says
      // it is, so nothing the app cannot read counts as a decision.
      for (final raw in <Object?>[7, true, <String>[], const {}]) {
        final q = Quote.fromJson(_quote(status: raw));
        expect(q.status, QuoteStatus.pending, reason: 'raw: $raw');
        expect(q.isDecided, isFalse, reason: 'raw: $raw');
      }
    });

    test('an unreadable verification state is pending, never verified', () {
      // The green tick is the field this whole row is trusted on, so the
      // fallback that matters is that an unreadable value can never produce
      // it. `pending` is «asked, not answered», which is the truth here.
      for (final raw in <Object?>[1, true, <String>[]]) {
        final q = Quote.fromJson(_quote(workerVerificationStatus: raw));
        expect(q.workerVerificationStatus, VerificationStatus.pending,
            reason: 'raw: $raw');
        expect(q.workerVerificationStatus,
            isNot(VerificationStatus.verified),
            reason: 'raw: $raw');
      }
    });

    test('the statuses the server does send are untouched', () {
      expect(Quote.fromJson(_quote(status: 'rejected')).status,
          QuoteStatus.rejected);
      expect(Quote.fromJson(_quote(workerVerificationStatus: 'rejected'))
          .workerVerificationStatus, VerificationStatus.rejected);
      expect(Quote.fromJson(_quote(workerVerificationStatus: 'pending'))
          .workerVerificationStatus, VerificationStatus.pending);
    });
  });

  group('no field prints a number where a sentence belongs', () {
    test('a numeric message is absent, not «5»', () {
      // A real shape: a count or a score in a text column. Flattening it would
      // print a number in the contractor's own words box as though he had
      // typed it.
      final q = Quote.fromJson(_quote(message: 5));
      expect(q.message, isNull);
    });

    test('a numeric comment is absent rather than «4»', () {
      final r = Review.fromJson(_review(comment: 4));
      expect(r.comment, isNull);
    });

    test('a numeric avatar url is absent, not a request to host "5"', () {
      // The trust widget feeds this straight to `NetImage`. Flattening it
      // would open a request to a host that does not exist; null falls back to
      // the monogram the widget already draws.
      final q = Quote.fromJson(_quote(workerAvatarUrl: 5));
      expect(q.workerAvatarUrl, isNull);
    });

    test('a numeric name is empty, and never the word «null»', () {
      final q = Quote.fromJson(_quote(workerFullName: 42));
      expect(q.workerFullName, isEmpty);
      expect(q.workerFullName, isNot(contains('null')));
    });

    test('an absent name is empty, and the monogram still draws', () {
      // The exception that proves the rule on the other side: the *name* IS
      // flattened to nothing rather than throwing, because `Monogram.of` answers
      // an empty string with «؟» and the card already has a fallback for a
      // customer with no name («زبون»).
      final q = Quote.fromJson(_quote()..remove('worker_full_name'));
      expect(q.workerFullName, isEmpty);
      expect(Monogram.of(q.workerFullName), Monogram.fallback);
    });

    test('an absent project id is empty, never «null»', () {
      // `'/api/mobile/projects/null/quotes'` is a dead link. '' is also a dead
      // link, but one nobody can mistake for a row id.
      final q = Quote.fromJson(_quote()..remove('project_id'));
      expect(q.projectId, isEmpty);
      expect(q.projectId, isNot(contains('null')));
    });

    test('a number sent as the project id is flattened, as a key', () {
      // Identifiers are the exception to "no flattening" and `.toString()`
      // already did this. What changed is that `null` no longer reaches it as
      // the literal «null».
      final q = Quote.fromJson(_quote(projectId: 55));
      expect(q.projectId, '55');
    });

    test('a blank message is absent, not an empty gap', () {
      // Padding is how this column actually arrives from a D1 row, and an
      // empty string drawn as a message block is a paragraph of nothing.
      final q = Quote.fromJson(_quote(message: '   '));
      expect(q.message, isNull);
    });

    test('a padded message is trimmed copy', () {
      final q = Quote.fromJson(_quote(message: '  جاهز للبدء  '));
      expect(q.message, 'جاهز للبدء');
    });
  });

  group('the price is never invented', () {
    test('an unreadable amount is not a real price', () {
      // `amount` is non-nullable, so the reader answers 0 — and 0 is the one
      // number on this card that would be an outright lie rather than a
      // missing fact. The bid's own floor is 1000 DZD, so on this row a 0 can
      // only ever mean "the app read nothing".
      for (final raw in <Object?>[null, 'قليلا', true, <int>[]]) {
        final q = Quote.fromJson(_quote(amount: raw));
        expect(q.amountIsReal, isFalse, reason: 'raw: $raw');
      }
    });

    test('a real price still reports itself real', () {
      expect(Quote.fromJson(_quote(amount: 45000)).amountIsReal, isTrue);
      expect(Quote.fromJson(_quote(amount: '45000')).amountIsReal, isTrue);
      expect(Quote.fromJson(_quote(amount: 1000)).amountIsReal, isTrue,
          reason: 'the floor itself is a price a contractor can quote');
    });

    test('a price below the write-path floor is not a real price', () {
      // `submitQuote` refuses less than 1000, so a 500 on the way back is not
      // a cheap bid either — it is a row the two sides of this app disagree
      // about, and the card must not print it as one.
      final q = Quote.fromJson(_quote(amount: 500));
      expect(q.amountIsReal, isFalse);
      expect(q.amount, 500, reason: 'the value is kept; only the claim is');
    });
  });

  group('a score of zero is not a bad review', () {
    test('an unreadable rating is not a real score', () {
      // The review form is 1-5, so no set of real reviews can average to zero
      // and a 0 is the reader saying it read nothing. `RatingStars` clamps
      // whatever it is handed, so without the guard this drew five empty stars
      // beside a customer's name: a review saying the man did bad work.
      for (final raw in <Object?>[null, 'خمس', true, <int>[]]) {
        final r = Review.fromJson(_review(rating: raw));
        expect(r.ratingIsReal, isFalse, reason: 'raw: $raw');
      }
    });

    test('the scores the server does send are all real', () {
      for (var n = 1; n <= 5; n++) {
        expect(Review.fromJson(_review(rating: n)).ratingIsReal, isTrue,
            reason: 'rating: $n');
      }
      expect(Review.fromJson(_review(rating: '4')).ratingIsReal, isTrue);
    });

    test('a score outside the form is not drawn as stars', () {
      // 9 is not a rating this app collects, whatever the server sent.
      final r = Review.fromJson(_review(rating: 9));
      expect(r.ratingIsReal, isFalse);
      expect(r.rating, 9, reason: 'the value is kept; only the claim is');
    });
  });

  group('the bid list loses one row, not the list — real Repository', () {
    test('one unreadable row does not empty the quotes list', () async {
      // The production failure, driven through `_rows` rather than asserted:
      // before this parser, `worker_id` arriving as a string threw and took the
      // whole list with it, so the project page showed no contractors at all
      // over a project that had three bids on it.
      final repo = _repoOver([
        _quote(id: 1),
        _quote(id: 2, workerId: 'twelve'), // not a number, not a null
        _quote(id: 3),
      ]);

      final rows = await repo.projectQuotes('b0b5644a223e');

      // Stronger than "the good rows survive": **nothing is lost at all.** A
      // bid row that parses with the columns it could read is a card the
      // customer can still compare, and `_rows`'s drop path is for a model
      // that cannot answer at all — which this one no longer does.
      expect(rows.length, 3);
      expect(rows.map((q) => q.id), [1, 2, 3]);
      expect(rows[1].workerId, 0, reason: 'the one row that could not be read');
    });

    test('a review list loses one row, not the list', () async {
      final repo = _repoOver([
        _review(id: 1),
        _review(id: 2, rating: 'النجمة'), // not a number
        _review(id: 3),
      ]);

      final rows = await repo.workerReviews(12);

      expect(rows.length, 3);
      expect(rows.map((r) => r.id), [1, 2, 3]);
    });

    test('an unreadable row leaves the other rows fully usable', () async {
      // The promise is not only "no row is lost" — it is that the surviving
      // rows are the *whole* row, not a stub with the bad column blanked.
      final repo = _repoOver([
        _quote(id: 1, status: 12, workerVerificationStatus: 9, amount: 'x'),
      ]);

      final rows = await repo.projectQuotes('b0b5644a223e');

      expect(rows.single.workerFullName, 'كريم بلقاسم');
      expect(rows.single.message, 'أقدر نتكفل بها في أسبوع');
      expect(rows.single.status, QuoteStatus.pending);
      expect(rows.single.workerVerificationStatus, VerificationStatus.pending);
      expect(rows.single.amountIsReal, isFalse);
    });
  });

  group('the fields that were already right are still right', () {
    test('a clean row is read exactly as the server sent it', () {
      final q = Quote.fromJson(_quote());
      expect(q.id, 88);
      expect(q.projectId, 'b0b5644a223e');
      expect(q.workerId, 12);
      expect(q.amount, 45000);
      expect(q.message, 'أقدر نتكفل بها في أسبوع');
      expect(q.estimatedDays, 7);
      expect(q.workerFullName, 'كريم بلقاسم');
      expect(q.workerAvgRating, 4.5);
      expect(q.workerTotalReviews, 3);
      expect(q.workerVerificationStatus, VerificationStatus.verified);
      expect(q.status, QuoteStatus.pending);
      expect(q.isDecided, isFalse);
      expect(q.hasRating, isTrue);
      expect(q.amountIsReal, isTrue);
    });

    test("a 0 the server sent as «not rated yet» is still not a score", () {
      // The sentinel the model already folds to null, untouched by this change.
      final q = Quote.fromJson(_quote(workerAvgRating: 0));
      expect(q.hasRating, isFalse);
      expect(q.workerAvgRating, isNull);
    });

    test('a review row is read exactly as the server sent it', () {
      final r = Review.fromJson(_review());
      expect(r.id, 5);
      expect(r.projectId, 'b0b5644a223e');
      expect(r.workerId, 12);
      expect(r.rating, 4);
      expect(r.comment, 'عمل نظيف واحترافي');
      expect(r.images, ['https://cdn.x.test/1.jpg']);
      expect(r.customerFullName, 'ياسين عماري');
      expect(r.ratingIsReal, isTrue);
    });

    test('images that are not a list are an empty list, not a throw', () {
      for (final raw in <Object?>[null, 'x', 3]) {
        final r = Review.fromJson(_review(images: raw));
        expect(r.images, isEmpty, reason: 'raw: $raw');
      }
    });

    test('a numeric image url is kept as text, because a URL is a key', () {
      // The one place in this file a number is flattened into a sentence, and
      // it is right: these are URLs drawn as links, and the pre-existing
      // `toString()` is the correct reader for them.
      final r = Review.fromJson(_review(images: <Object>[123]));
      expect(r.images, ['123']);
    });
  });
}
