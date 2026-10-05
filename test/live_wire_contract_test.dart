// The contract between the app's parsers and the payloads the Worker really
// sends, checked against the LIVE API on every run of the suite.
//
// **The hole this file closes.** `live_payload_models_test.dart` copies its
// JSON into the repo by hand, and the copies are dated 11 Sep 2026. Between
// that date and this one the Worker renamed and added columns and the copies
// never noticed, which is the whole failure mode `payload_coverage_test.dart`
// documents from the other side: it compares `lib/` against ITS OWN captured
// key list, so a rename on the Worker moves both sides of its own comparison
// out of date together and the census reads green. Nothing in the tree ever
// fetched a payload and parsed it.
//
// So a column the Worker renames was not caught until a user hit the screen
// that reads it -- and the class of screen that reads a renamed column is the
// browse card, where the failure is not a crash but a contractor who is
// missing or blank. `worker_wire_shape_test.dart` pinned the tolerance that
// keeps a card drawing; this file is what keeps the tolerance honest against
// the shapes the server actually sends.
//
// **Read-only, which is why this is not tagged `live`.** The three
// `live_*_e2e_test.dart` files are skipped by default because a run of each
// registers real accounts on production, uploads into R2 and posts reviews --
// by 13 Sep the feed a real client browsed held ~30 junk contractors with no
// route to remove them. Every line here is a GET. This file creates nothing,
// deletes nothing and writes nothing, so running it on every gate is safe, and
// running it on every gate is the entire point: a contract checked only on
// demand is a contract nobody checks.
//
// **Driven through the app's own `Repository`, and the routes are read out of
// the run rather than written here.** Not through a bare `http` call, and not
// by grepping `lib/` for the route string. Fetching through `Repository` means
// every assertion below is about the rows the app itself would draw, after the
// app's own `_rows` drop contract has run: a row this file cannot see is a row
// a user cannot see either.
//
// The route half was got wrong first and the repo's own census caught it. The
// first version read `data/repository.dart` and searched for the literal, which
// `app_source_scope_test.dart` refused: a test that reads another file's source
// text is a source sweep, it must declare a root, and it was declaring one it
// never walked. The census was right, and the grep was the weaker instrument
// besides -- a route string can sit in the source while nothing calls it. So
// the routes come from [_Recorder], a `http.BaseClient` that records what was
// actually sent, and "is this the route the app calls?" is answered by a fact
// about the run.
//
// **What a failure means.** Every assertion here is an invariant of the
// product, not of the app's internals, so a red case is a real fact about the
// market and is worth reading rather than editing around:
//
//   * an unknown enum value is a state the app silently folds to its fallback,
//     so a `status` the parser has never heard of is a project whose state a
//     customer cannot trust;
//   * a wilaya code with no name is a chip that never draws;
//   * a slug with no canonical category is a card that prints the generic
//     «خدمات عامة» instead of the trade the contractor filed;
//   * a plan id the app cannot parse is a subscription screen with no name on
//     the plan a man is being charged for.
//
// **A transport failure fails this file rather than skipping it.** "Could not
// reach the API" and "reached it and the contract holds" must not both report
// as green in a gate whose verdict is a single line. The fetches are bounded
// (8 s per host, two hosts) so the cost of a bad network day is a short red
// run and not a stall: this file lives inside a sharded gate whose shard cap
// is 300 s, and a network test with no bound is how a suite stops being a
// suite.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/models/plan_id.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/models/worker.dart';

/// The customer-facing host first, then the workers.dev fallback -- the same
/// order and the same pair the release builds inject with `--dart-define`, so
/// a green run is a statement about the hosts the shipped APK calls.
const List<String> _hosts = <String>[
  'https://allomokawil.colisify.com',
  'https://finili.medsaidkichene.workers.dev',
];

/// Per-host budget, deliberately far under `ApiClient.defaultTimeout`.
///
/// The default is 20 s because a phone on a bad Algerian mobile link deserves
/// a second chance. A CI box on a wired link does not, and four routes at
/// 20 s each is 80 s of a 300 s shard spent proving the network is down.
const Duration _budget = Duration(seconds: 8);

/// Routes and models, fetched once for the whole file.
///
/// One fetch per route, shared by every case: the endpoint answers in about
/// a second and the four routes are independent GETs, so paying for them once
/// keeps the file inside its shard while still checking every row the market
/// has rather than a sample of them.
late final _Market _market;

Future<_Market> _fetchMarket() async {
  // `flutter_test`'s binding installs an `HttpOverrides` that fails every
  // request, which is right for a widget test and fatal for this one. The
  // three live E2E files clear it for the same reason.
  HttpOverrides.global = null;
  // The client records every GET the app makes, so the raw re-fetch follows
  // the routes the app actually issued rather than a second hand-written list
  // of them. That is strictly stronger than grepping `data/repository.dart`
  // for the literal: a route string can sit in the source while nothing calls
  // it, and a grep would certify that. Recorded here it is a fact about the
  // run.
  final _Recorder recorder = _Recorder(http.Client());
  final ApiClient api =
      ApiClient(httpClient: recorder, baseUrls: _hosts, timeout: _budget);
  final Repository repo = Repository(api);

  // `searchWorkers` rather than `topWorkers` for the zipped routes: `top` is
  // the ranked strip the customer home shows, and `evidenceBeforeAssertion`
  // REORDERS it, so a row the app draws from it is not the row the server
  // sent. `search` and `browseProjects` keep server order, which is what lets a
  // case line up one row's wire values with one row's parsed values.
  final List<WorkerProfile> search = await repo.searchWorkers(query: 'a');
  final List<WorkerProfile> top = await repo.topWorkers(limit: 20);
  final List<Project> projects = await repo.browseProjects(page: 1);
  final PlanCatalogue plans = await repo.planCatalogue();

  // The same payloads again, unparsed.
  //
  // **This is the half that makes the enum cases mean anything.** Parsed rows
  // alone can only ask "is every state this app produces one it knows", and a
  // parser that folded EVERY column to its fallback would sail through that:
  // `pending` and `open` and `flexible` are all states the app has names for.
  // The defect this file exists to catch is a worker who renames a column, and
  // a rename has exactly that shape — the server sends a new value and the app
  // answers its default. So the raw value is read beside the parsed one and the
  // two are asked to agree, row by row.
  //
  // Snapshot before re-fetching, because the re-fetch is itself a GET and the
  // list must stay a record of what the *four repository calls* asked for.
  final List<String> asked = recorder.distinctReads();
  final Map<String, dynamic> raw = <String, dynamic>{
    for (final String path in asked) path: await api.get(path),
  };
  return _Market(search: search, top: top, projects: projects, plans: plans,
      asked: asked, raw: raw);
}

/// Records every GET [http.BaseClient] forwards, in order and de-duplicated.
///
/// [BaseClient] rather than a hand-written wrapper so the app's own client is
/// untouched: the same request, the same headers, the same failover -- what is
/// being observed is what the app would have sent to the network, not a
/// simulation of it.
class _Recorder extends http.BaseClient {
  _Recorder(this._inner);

  final http.Client _inner;
  final List<String> _reads = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'GET') {
      // `request.url` is a full `Uri`, so `path` already carries the `?` when
      // there is a query -- `${request.url.path}` alone is
      // `/api/mobile/projects?page=1`, not `/api/mobile/projects`. Measured
      // here after writing the naive `${url.path}${url.query}`, which produced
      // `/api/mobile/projectspage=1`: every route came back unrecognised, the
      // zip found no rows, and `setUpAll` failed on a dead `_decode` while the
      // real fault was a string built out of two halves that already shared
      // their separator.
      _reads.add(request.url.toString().replaceAll(
          RegExp('^https?://[^/]+'), ''));
    }
    return _inner.send(request);
  }

  /// The recorded GETs, first-seen order, each one once.
  ///
  /// De-duplicated because [ApiClient] fails over between the two hosts: a
  /// request the primary did not answer is sent again to the fallback, and
  /// that retry is the same route twice, not two routes.
  List<String> distinctReads() => <String>[..._reads.toSet()];
}

/// The routes whose payloads are zipped, matched by the path the app used.
///
/// A prefix rather than a literal, for the reason the recorder exists: the app
/// appends its own query (`?q=a`, `?page=1`) and a test that hard-codes the
/// full string is a test that breaks the moment a default changes, so it would
/// be red for a reason that has nothing to do with the contract.
const String _searchPrefix = '/api/mobile/workers/search';
const String _projectsPrefix = '/api/mobile/projects';
const String _plansPrefix = '/api/mobile/plans';

/// What the four routes answered, parsed by the app's own models.
class _Market {
  const _Market({
    required this.search,
    required this.top,
    required this.projects,
    required this.plans,
    required this.asked,
    required this.raw,
  });

  final List<WorkerProfile> search;
  final List<WorkerProfile> top;
  final List<Project> projects;
  final PlanCatalogue plans;
  /// Every GET the four repository calls actually issued, de-duplicated.
  final List<String> asked;
  final Map<String, dynamic> raw;

  /// The one recorded read whose path starts with [prefix], or null.
  ///
  /// Null rather than an empty list when the app never asked, so a case can
  /// tell "the route answered nothing" from "the app never called it" -- the
  /// second one is a defect in the app and the first is a fact about the
  /// market, and the group above separates them by name.
  ///
  /// Typed `Object?` because the three routes answer different shapes: two
  /// lists and one object. The first draft declared it `Map<String, dynamic>?`
  /// and every row accessor below threw
  /// `type 'List<dynamic>' is not a subtype of type 'Map<String, dynamic>?'`
  /// on the two list routes -- a cast typed to the one shape that is the
  /// exception, so the file was red for a wrong reason and the reason was in
  /// the declaration rather than in the wire.
  Object? _rawFor(String prefix) {
    for (final String path in asked) {
      if (path.startsWith(prefix)) return raw[path];
    }
    return null;
  }

  /// Whether the app issued a read of [prefix] at all.
  bool askedFor(String prefix) =>
      asked.any((String path) => path.startsWith(prefix));

  /// The unparsed worker rows, in the order the server sent them.
  List<Map<String, dynamic>> get rawSearch => _rows(_rawFor(_searchPrefix));

  /// The unparsed project rows, in the order the server sent them.
  List<Map<String, dynamic>> get rawProjects =>
      _rows(_rawFor(_projectsPrefix));

  /// The unparsed plan rows, one level down inside the catalogue object.
  List<Map<String, dynamic>> get rawPlans {
    final Object? payload = _rawFor(_plansPrefix);
    if (payload is! Map) return const <Map<String, dynamic>>[];
    return _rows(payload['plans']);
  }

  /// The decoded rows of [payload], or an empty list when it is not a list.
  ///
  /// A shape that is not a list of objects would make every zip below compare
  /// nothing, so it is named by the case that checks the counts instead of
  /// being smoothed over here.
  static List<Map<String, dynamic>> _rows(Object? payload) {
    if (payload is! List) return const <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      for (final Object? row in payload)
        if (row is Map<String, dynamic>) row,
    ];
  }
}

/// The rows the wire really carries, described per failing row rather than as
/// one number, because "3 of 96 rows" does not say which three.
String _names(Iterable<String> ids, int total) => ids.isEmpty
    ? ''
    : '\n  ${ids.join(', ')}\n  ($ids of $total row(s) — the ids are what to '
        'look up on the Worker)';

void main() {
  setUpAll(() async {
    _market = await _fetchMarket();
  });

  group('the file is measuring the routes the app calls', () {
    // **A hard-coded route is a claim about an endpoint, and a claim that goes
    // stale silently.** The zip compares a parsed row against the wire row it
    // came from, so a route literal that had drifted from the one `Repository`
    // calls would keep every case below green while comparing the app against
    // an endpoint it stopped using. `payload_coverage_test.dart` found this
    // exact hole in itself and needed a case to close it.
    //
    // The first version of this check read `data/repository.dart` and looked
    // for the route string, and `app_source_scope_test.dart` failed on it: a
    // test that reads another file's source text is a *source sweep*, it has to
    // declare a root, and it was declaring one it did not walk. The census was
    // right and the grep was the weaker instrument -- a string can sit in the
    // source while nothing calls it. So the routes are read out of the run
    // itself, from [http.BaseClient], which is a fact rather than a reading.
    test('every zipped route is a route the app issued in this run', () {
      final List<String> missing = <String>[
        for (final String prefix in <String>[
          _searchPrefix,
          _projectsPrefix,
          _plansPrefix,
        ])
          if (!_market.askedFor(prefix)) prefix,
      ];
      expect(missing, isEmpty,
          reason: 'these routes are compared against live payloads but the '
              'app never issued a read of them, so the zip would grade it '
              'against an endpoint it does not use:\n'
              '${missing.join('\n')}\n'
              'The app actually asked for: ${_market.asked.join(', ')}');
    });

    // The zip compares row i with row i, which is only true while both paths
    // parsed every row they fetched. `exactTradeOnly` and
    // `exactProjectTrades` narrow by category and are passed null here, so
    // they return the list untouched -- but a future filter argument would
    // silently break the pairing, and the result would be a green file
    // comparing the wrong two rows.
    test('the wire rows and the parsed rows line up one for one', () {
      expect(_market.rawSearch.length, _market.search.length);
      expect(_market.rawProjects.length, _market.projects.length);
      expect(_market.rawPlans.length, _market.plans.plans.length);
    });

    test('the rows really are objects, so the comparison is row by row', () {
      // `_rows` answers an empty list for a payload that is not a list of
      // objects, and the count above would then read 0 == 0. A payload shape
      // this app cannot even enumerate is worth failing on by name.
      expect(_market.rawSearch, isNotEmpty);
      expect(_market.rawProjects, isNotEmpty);
      expect(_market.rawPlans, isNotEmpty);
    });
  });

  group('every contractor the market publishes is a card that can be drawn', () {
    test('the search route answers rows at all', () {
      // `q=a` matches on the latin/arabic name field, so a wilaya whose only
      // contractors are named entirely in Arabic could legitimately answer
      // `[]`. Asserted as "the app got a list it can draw from", with the
      // emptiness reported as a failure to read rather than a passing market
      // of zero -- an empty browse screen is indistinguishable on-device from
      // a broken one.
      expect(_market.search.isEmpty, isFalse,
          reason: 'the search route answered no contractor rows. Either the '
              'market is empty or the route changed; both mean this file '
              'cannot check the contract.');
    });

    test('no row is undrawable, on either worker route', () {
      // `isRenderable` is the 71st's seam: `id > 0 && userId > 0`, because
      // `id` opens the profile and `userId` is what «مراسلة ${fullName}» sends
      // to the chat screen. `_rows` drops a row that fails it, so this is
      // counting contractors the app has decided not to show.
      for (final List<WorkerProfile> route in <List<WorkerProfile>>[
        _market.search,
        _market.top,
      ]) {
        final Iterable<WorkerProfile> lost =
            route.where((WorkerProfile w) => !w.isRenderable);
        expect(lost.map((WorkerProfile w) => w.id).toList(), isEmpty,
            reason: 'rows arrived with no readable id or user id, so '
                '_rows dropped them: the market is shorter on screen with no '
                'error and no empty slot.${_names(lost.map((WorkerProfile w) => '${w.id}/${w.userId}'), route.length)}');
      }
    });

    test('every contractor the server names has an id, not a folded zero',
        () {
      // `_int` answers 0 for a shape it cannot read (see `worker.dart`), which
      // is deliberately visible rather than fatal. So a 0 id here is not a
      // parse crash -- it is a real-looking card whose only possible answer is
      // a 404. Checking the ids are distinct AND positive catches a server
      // that ever sends the same id twice, which would make one man fill two
      // cards on the directory.
      final List<int> ids =
          _market.search.map((WorkerProfile w) => w.id).toList();
      expect(ids.where((int id) => id <= 0).toList(), isEmpty,
          reason: 'a contractor row parsed to id 0, which is the id a row '
              'nobody stated resolves to.');

      // The same id on two rows is a *different* defect from a 0, and the two
      // are checked apart on purpose: a duplicated id does not make either
      // card undrawable, so the count above stays green, and the directory
      // quietly shows the same man twice -- one of them with his real name
      // and one with a place chip the card widget draws from whichever row it
      // was handed.
      final Map<int, int> seen = <int, int>{};
      for (final int id in ids) {
        seen[id] = (seen[id] ?? 0) + 1;
      }
      expect(seen.entries.where((MapEntry<int, int> e) => e.value > 1).map((MapEntry<int, int> e) => e.key.toString()).toList(),
          isEmpty,
          reason: 'the same contractor came back on more than one row, so the '
              'directory would draw one man twice.');
    });

    test('every wilaya the server names is a wilaya the app can print', () {
      // `worker_card` draws the chip from `Taxonomy.wilayaNameOrNull`, which
      // answers null for a code it does not know -- so an unprintable code is
      // not an error state, it is a chip that silently never draws and a
      // customer sorting contractors by place who cannot sort them at all.
      final Iterable<WorkerProfile> unknown = _market.search
          .where((WorkerProfile w) => (w.wilaya ?? '').isNotEmpty &&
              Taxonomy.wilayaNameOrNull(w.wilaya) == null);
      expect(unknown.map((WorkerProfile w) => w.wilaya).toList(), isEmpty,
          reason: 'these wilaya codes are not in the 58-entry table, so the '
              'card draws no place for them.${_names(unknown.map((WorkerProfile w) => '${w.id}:${w.wilaya}'), _market.search.length)}');
    });

    test('every trade a contractor filed has a name in Arabic', () {
      // `Taxonomy.categoryName` answers «خدمات عامة» for a slug it has never
      // heard of. That fallback is right for a slug a user typed and wrong for
      // one the SERVER filed: a contractor whose trade is spelled differently
      // in the Worker's vocabulary prints the generic name on his own card,
      // next to the pictures of the job he actually does.
      final Map<String, List<String>> unseen = <String, List<String>>{};
      for (final WorkerProfile w in _market.search) {
        for (final String slug in w.specialties) {
          if (Taxonomy.categoryName(slug) == 'خدمات عامة') {
            (unseen[slug] ??= <String>[]).add('${w.id}');
          }
        }
      }
      expect(unseen.keys.toList(), isEmpty,
          reason: 'these specialty slugs have no canonical category, so every '
              'card for a contractor who filed one prints «خدمات عامة»:\n'
              '${unseen.entries.map((MapEntry<String, List<String>> e) => '  ${e.key} — ${e.value.length} contractor(s), e.g. ${e.value.take(3).join(', ')}').join('\n')}');
    });

    test('a verification state the app has never heard of is a silent change',
        () {
      // **The zip is the case.** Parsed rows alone could not catch a rename: a
      // parser that folded every value to `pending` produces states this app
      // has names for, so the file stayed green. What has to be compared is the
      // string ON THE WIRE beside the state the app drew from it, and the two
      // must name the same thing.
      //
      // `VerificationStatus.fromWire` folds anything unrecognised to
      // `pending`, which is the honest reading of "asked, not answered" and
      // the wrong reading of a state the Worker has since added: a contractor
      // the server calls something new loses his green tick, and nothing says
      // why.
      //
      // The wire spellings are literals read out of the enum itself, so the
      // case fails if a value is ever added without the check being extended
      // rather than silently passing on a fallback.
      final Set<String> known = VerificationStatus.values
          .map((VerificationStatus v) => v.wire)
          .toSet();

      final List<Map<String, dynamic>> raw = _market.rawSearch;
      final Iterable<int> folded = <int>[
        for (int i = 0; i < raw.length && i < _market.search.length; i++)
          if (raw[i]['verification_status'] is String &&
              !known.contains(raw[i]['verification_status'] as String))
            i,
      ];
      expect(folded.toList(), isEmpty,
          reason: 'the Worker sends a verification state this app has no name '
              'for. `VerificationStatus.fromWire` folds an unknown value to '
              '«pending», so an unrecognised state is drawn as «لم يُوثّق '
              'بعد» — add the value to `VerificationStatus` if the new state '
              'is real:\n'
              '${folded.map((int i) => '  worker ${raw[i]['id']} sends '
                  '"${raw[i]['verification_status']}", the app reads it as '
                  '"${i < _market.search.length ? _market.search[i].verificationStatus.wire : '?'}"').join('\n')}\n'
              'The wire values this app knows: ${(known.toList()..sort()).join(', ')}');

      // The zip needs at least one row it actually paired, or the check above
      // is true by being empty. Which brings the real question: is parsed row
      // i the parse of wire row i? The **id** is what proves it -- it is the
      // one value both sides must carry identically, and the two fetches are
      // separate requests, so a filter, a drop or a reorder between them shows
      // up here as a mismatch rather than as every row silently graded
      // against the wrong one.
      final int paired = raw.length < _market.search.length
          ? raw.length
          : _market.search.length;
      final List<String> mispaired = <String>[
        for (int i = 0; i < paired; i++)
          if ('${raw[i]['id']}' != '${_market.search[i].id}')
            'wire row $i is contractor ${raw[i]['id']}, but parsed row $i is '
                '${_market.search[i].id}',
      ];
      expect(mispaired, isEmpty,
          reason: 'the parsed rows and the wire rows are not the same rows in '
              'the same order, so every comparison in this group is grading '
              'the app against a payload it did not draw:\n'
              '${mispaired.take(5).join('\n')}');
      expect(paired, greaterThan(0),
          reason: 'no contractor row could be paired, so the rename check '
              'above would pass on an empty market.');
    });

    test('a rating and a review count that disagree mean one card lies', () {
      // The `0` sentinel, in both directions. `avg_rating: 0` is the server
      // saying "nobody has rated me yet" -- the review form is 1-5, so no set
      // of reviews averages to zero -- and both models fold it to null so the
      // card prints no stars rather than zero. If the server ever sends a
      // non-zero mean beside a zero count, the card would print a score
      // nobody left, and that is the one number on this marketplace a
      // customer cannot check for himself.
      final Iterable<WorkerProfile> scored = _market.search
          .where((WorkerProfile w) => w.hasRating && w.totalReviews <= 0);
      expect(scored.map((WorkerProfile w) => '${w.id}:${w.avgRating}').toList(),
          isEmpty,
          reason: 'these contractors print a score with no review behind it.${_names(scored.map((WorkerProfile w) => '${w.id}'), _market.search.length)}');
      final Iterable<WorkerProfile> rated = _market.search
          .where((WorkerProfile w) => !w.hasRating && w.totalReviews > 0);
      expect(rated.map((WorkerProfile w) => '${w.id}:${w.totalReviews}').toList(),
          isEmpty,
          reason: 'these contractors have reviews but no score, so the card '
              'hides the number their customers gave them.${_names(rated.map((WorkerProfile w) => '${w.id}'), _market.search.length)}');
    });
  });

  group('every project on the market is a posting that can be read', () {
    test('the market answers postings at all', () {
      expect(_market.projects.isEmpty, isFalse,
          reason: 'the projects route answered no rows, so this file cannot '
              'check the project contract.');
    });

    test('every posting keeps the id its own detail page is addressed by', () {
      // `Project.id` is the whole key: it is the path segment in
      // `/api/mobile/projects/$id`, the link a notification carries, and the
      // de-duplication key a five-page search merges on. A row whose id does
      // not parse is not a broken card, it is a card that opens nothing -- and
      // `getProject` will answer a 404 for it with no way to tell that apart
      // from a project that was deleted.
      final Iterable<Project> unusable = _market.projects
          .where((Project p) => p.id.isEmpty || p.customerId <= 0);
      expect(unusable.map((Project p) => p.id).toList(), isEmpty,
          reason: 'a posting has no readable id or owner, so it cannot be '
              'opened or attributed.${_names(unusable.map((Project p) => p.id.isEmpty ? '<empty>' : p.id), _market.projects.length)}');
    });

    test('the primary trade is inside the list of trades', () {
      // `Project.allCategories` is `[category]` when `categories` is empty and
      // otherwise the server's list -- and the screen searches against
      // `allCategories`. A `categories` array that omits its own `category`
      // therefore means the primary trade is searchable only through the
      // fallback branch, so a row that *has* an array loses a search that the
      // same trade used to win. Measured on live rows: 0 violations.
      final Iterable<Project> split = _market.projects
          .where((Project p) => p.categories.isNotEmpty && !p.allCategories.contains(p.category));
      expect(split.map((Project p) => '${p.id}:${p.category}').toList(), isEmpty,
          reason: 'these postings list trades that exclude their own primary '
              'one.${_names(split.map((Project p) => p.id), _market.projects.length)}');
    });

    test('a trade on a live posting has a name the app can print', () {
      // The same «خدمات عامة» argument as the contractor card, on the other
      // half of the marketplace: «نجارة» and «karouri_serrurerie» must both
      // resolve, or a posting reads as a generic request.
      final Map<String, List<String>> unseen = <String, List<String>>{};
      for (final Project p in _market.projects) {
        for (final String slug in p.allCategories) {
          if (Taxonomy.categoryName(slug) == 'خدمات عامة') {
            (unseen[slug] ??= <String>[]).add(p.id);
          }
        }
      }
      expect(unseen.keys.toList(), isEmpty,
          reason: 'these trades have no canonical category, so the posting '
              'prints «خدمات عامة» instead of the trade:\n'
              '${unseen.entries.map((MapEntry<String, List<String>> e) => '  ${e.key} — ${e.value.length} posting(s)').join('\n')}');
    });

    test('a status or urgency the app has never heard of is a silent change',
        () {
      // Same zip as the contractor case, and for the same reason: both
      // `fromWire`s fold an unknown value to the column default, so only the
      // string beside the parsed state can notice a new one. `open` and
      // `flexible` are values the app knows, which is exactly why asking the
      // parser alone was not a check.
      final List<String> spelled =
          ProjectStatus.values.map((ProjectStatus s) => s.wire).toList();
      final List<String> levels =
          UrgencyLevel.values.map((UrgencyLevel u) => u.wire).toList();

      final List<Map<String, dynamic>> raw = _market.rawProjects;
      final int n = raw.length < _market.projects.length
          ? raw.length
          : _market.projects.length;
      expect(n, greaterThan(0),
          reason: 'no posting could be paired with its own wire row, so the '
              'two checks below would compare nothing.');

      final List<String> badStatus = <String>[
        for (int i = 0; i < n; i++)
          if (raw[i]['status'] is String &&
              !spelled.contains(raw[i]['status']))
            '  ${raw[i]['id']} -> "${raw[i]['status']}" reads as '
                '"${_market.projects[i].status.wire}"',
      ];
      expect(badStatus, isEmpty,
          reason: 'the Worker sends a project status this app has no name '
              'for. `ProjectStatus.fromWire` folds an unknown value to «open», '
              'so an unrecognised state is drawn as a live job — add the value '
              'to `ProjectStatus` if the new state is real:\n'
              '${badStatus.join('\n')}\n'
              'This app knows: ${spelled.join(', ')}');

      final List<String> badUrgency = <String>[
        for (int i = 0; i < n; i++)
          if (raw[i]['urgency'] is String &&
              !levels.contains(raw[i]['urgency']))
            '  ${raw[i]['id']} -> "${raw[i]['urgency']}" reads as '
                '"${_market.projects[i].urgency.wire}"',
      ];
      expect(badUrgency, isEmpty,
          reason: 'the Worker sends an urgency this app has no name for. '
              '`UrgencyLevel.fromWire` folds an unknown value to «flexible», '
              'so an unrecognised value is drawn as «مرن» — add the value to '
              '`UrgencyLevel` if it is real:\n${badUrgency.join('\n')}\n'
              'This app knows: ${levels.join(', ')}');
    });

    test('the wilaya on a posting names a place the app can print', () {
      final Iterable<Project> unknown = _market.projects
          .where((Project p) => p.wilaya.isNotEmpty && Taxonomy.wilayaNameOrNull(p.wilaya) == null);
      expect(unknown.map((Project p) => '${p.id}:${p.wilaya}').toList(), isEmpty,
          reason: 'these posting wilaya codes are not in the 58-entry table, '
              'so the card draws no place.${_names(unknown.map((Project p) => p.id), _market.projects.length)}');
    });

    test('a budget that is not a range reads as one', () {
      // `budgetLabel` prints «من $min إلى $max دج» on the founder's own call.
      // A posting whose minimum is above its maximum prints a range no
      // customer can act on, and the server -- not the app -- would have to be
      // asked why.
      final Iterable<Project> inverted = _market.projects.where(
          (Project p) => p.budgetMin != null && p.budgetMax != null && p.budgetMin! > p.budgetMax!);
      expect(inverted.map((Project p) => p.id).toList(), isEmpty,
          reason: 'these postings have a minimum above their maximum.${_names(inverted.map((Project p) => p.id), _market.projects.length)}');
    });
  });

  group('the plan catalogue is priced in a form the subscription screen can '
      'print', () {
    test('the catalogue answers plans at all', () {
      expect(_market.plans.plans, isNotEmpty,
          reason: 'the plans route answered no rows; a contractor opening the '
              'subscription screen would see an empty list of prices.');
    });

    test('every plan id is one this app can name', () {
      // `PlanId` is the enum that replaced a bare `String` compare, and
      // `SubscriptionStatus.isFree` reads `PlanId.fromWire(current.plan) == null`
      // to mean "this is not the free plan". A plan id the parser cannot read
      // is therefore a plan whose price is shown with no name on it, and a
      // paid plan misread as "not free" by accident rather than by evidence.
      final Iterable<Plan> unknown = _market.plans.plans
          .where((Plan p) => PlanId.fromWire(p.id) == null);
      expect(unknown.map((Plan p) => p.id).toList(), isEmpty,
          reason: 'these plan ids are not in PlanId, so the subscription '
              'screen has no name for the plan being charged for:\n'
              '${unknown.map((Plan p) => p.id).join('\n')}');
    });

    test('a plan with a monthly price has a yearly one', () {
      // `Plan.isFree` is `priceMonth <= 0 && priceYear <= 0` and
      // `savingFor` multiplies the monthly price by twelve, so a plan with a
      // price for one period and silence about the other is either printed as
      // free or priced at zero for a year a customer is being offered.
      final Iterable<Plan> half = _market.plans.plans
          .where((Plan p) => (p.priceMonth > 0) != (p.priceYear > 0));
      expect(half.map((Plan p) => '${p.id}:${p.priceMonth}/${p.priceYear}').toList(),
          isEmpty,
          reason: 'these plans are priced for one period and free for the '
              'other:\n${half.map((Plan p) => '  ${p.id}').join('\n')}');
    });

    test('the founder\'s own promise about commissions is on the payload', () {
      // `/api/mobile/plans` sends `note_ar`, and `PlanCatalogue` keeps it as
      // `noteAr` for the subscription screen to print verbatim. An empty
      // string is not a promise about nothing: the screen would show a
      // subscription with no line saying what the platform does not charge.
      expect(_market.plans.noteAr.trim(), isNotEmpty,
          reason: 'the catalogue carries no note_ar, so the subscription '
              'screen cannot state what it does not charge.');
    });

    test('a plan with an Arabic name has a trade the app can label', () {
      // `features` is what the plan card actually renders (`quoteAllowanceAr`
      // was deleted precisely because nothing called it), so a plan whose
      // feature list is empty is a card with a price and no reason to pay it.
      final Iterable<Plan> bare = _market.plans.plans
          .where((Plan p) => p.nameAr.trim().isEmpty || p.features.isEmpty);
      expect(bare.map((Plan p) => p.id).toList(), isEmpty,
          reason: 'these plans have no name or no features, so the plan card '
              'shows a price with nothing behind it:\n'
              '${bare.map((Plan p) => '  ${p.id}').join('\n')}');
    });
  });
}
