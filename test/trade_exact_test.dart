// A trade filter must answer with the tradesman who does that trade.
//
// Found on 4 Oct 2026 by reading the wire. `GET /api/mobile/workers/search`
// matches `category` on a **substring**: `category=wallpaper` answers with 9
// rows and only 3 of them carry `wallpaper`; `category=plaster_drywall`
// answers with 3 and only 1 carries it. The directory drew all 9.
//
// The rows below are transcribed verbatim from that live answer, so the tests
// fail on the order and the membership the server actually sent — not on a
// hand-picked arrangement that would have passed either way.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/trade_exact.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/worker.dart';

WorkerProfile _w(int id, List<String> trades) => WorkerProfile(
      id: id,
      userId: id * 10,
      fullName: 'مقاول $id',
      specialties: trades,
      experienceYears: 3,
      isAvailable: true,
      verificationStatus: VerificationStatus.pending,
      avgRating: 0,
      totalReviews: 0,
      totalCompletedJobs: 0,
    );

void main() {
  group('exactTradeOnly', () {
    // Exactly the nine rows `category=wallpaper` answered with on 4 Oct 2026.
    final wallpaperLive = <WorkerProfile>[
      _w(5, ['painting']),
      _w(2, ['painting', 'wallpaper', 'tiling_marble']),
      _w(7, ['tiling_marble', 'painting']),
      _w(8, ['wallpaper', 'painting']),
      _w(68, ['painting']),
      _w(71, ['painting']),
      _w(25, ['painting', 'carpentry_aluminum', 'wallpaper']),
      _w(121, ['painting', 'plumbing']),
      _w(124, ['painting']),
    ];

    test('the live wallpaper answer: the six painters are not wallpaperers', () {
      final kept = exactTradeOnly(wallpaperLive, 'wallpaper');
      expect(kept.map((w) => w.id).toList(), [2, 8, 25]);
      // The pre-fix behaviour, written down so the count is a measurement.
      expect(wallpaperLive.length - kept.length, 6);
    });

    test('the two men who actually do wallpaper are the ones who survive', () {
      // «خالد رحماني» (2) and «فريد زروالي» (8) — the only two rows whose own
      // trade list carries the trade the client tapped.
      final kept = exactTradeOnly(wallpaperLive, 'wallpaper');
      expect(kept.every((w) => w.specialties.contains('wallpaper')), isTrue);
    });

    // The other half of the live measurement: `plaster_drywall` dragged in
    // every `venetian_plaster`, because the app's two gypsum trades —
    // «جبس بورد وديكور» and «جبس فينيسي وستوكو» — are one word to a customer.
    test('the live gypsum answer: one board man, not three plasterers', () {
      final plasterLive = <WorkerProfile>[
        _w(1, ['venetian_plaster']),
        _w(4, ['plaster_drywall', 'tiling_marble', 'venetian_plaster']),
        _w(6, ['venetian_plaster', 'tiling_marble']),
      ];
      expect(exactTradeOnly(plasterLive, 'plaster_drywall').map((w) => w.id),
          [4]);
    });

    test('a slug the filter has no answer for empties the list, not the app', () {
      // 6 of the 16 trades in `Taxonomy.categories` have no live professional.
      // Dropping every row is the truth, and the screen already answers it
      // with «لا نتائج مطابقة» plus a button that clears the filter.
      expect(exactTradeOnly(wallpaperLive, 'hvac_heating'), isEmpty);
    });

    test('server order is preserved exactly — this narrows, it never re-ranks',
        () {
      // The founder pays for `search_boost`; `worker_rank.dart` declines to
      // re-derive it and so does this. Every survivor keeps its input index.
      final kept = exactTradeOnly(wallpaperLive, 'wallpaper');
      final inputOrder = <int>[
        for (var i = 0; i < wallpaperLive.length; i++)
          if (wallpaperLive[i].specialties.contains('wallpaper')) i,
      ];
      final keptOrder = [
        for (final w in kept) wallpaperLive.indexOf(w),
      ];
      expect(keptOrder, inputOrder);
    });

    test('no filter means no filtering — the directory must not lose anyone',
        () {
      // 74 of 91 live rows carry no trades at all. With nothing tapped they
      // still have to be drawable, or the unfiltered directory hides most of
      // the marketplace.
      final untyped = <WorkerProfile>[_w(14, []), _w(15, []), _w(73, [])];
      expect(exactTradeOnly(untyped, null), untyped);
      expect(exactTradeOnly(untyped, ''), untyped);
      expect(exactTradeOnly(untyped, '   '), untyped);
    });

    test('a row with no trades is not evidence of the trade that was tapped', () {
      // Currently unreachable from the wire — none of the 41 filtered rows is
      // one of these — and kept so a future row cannot reintroduce it. The
      // header says why this is a narrowing the user asked for.
      expect(exactTradeOnly([_w(14, [])], 'painting'), isEmpty);
    });

    test('membership is read through the alias table on both sides', () {
      // A legacy row that writes `stucco` really does do `venetian_plaster`;
      // `Taxonomy._aliases` is the repo's own answer to that. Filtering on the
      // raw string would re-introduce the same superset defect one layer down.
      expect(exactTradeOnly([_w(9, ['stucco'])], 'venetian_plaster'),
          hasLength(1));
      expect(exactTradeOnly([_w(9, ['venetian_plaster'])], 'stucco'),
          hasLength(1));
    });

    test('a hyphenated dialect of a real slug still matches', () {
      // `Taxonomy.canonical` folds 'venetian-plaster'; the server does not, so
      // the app is the only place that dialect can be answered.
      expect(exactTradeOnly([_w(1, ['venetian-plaster'])], 'venetian_plaster'),
          hasLength(1));
    });

    test('a slug nobody wrote matches nothing rather than everything', () {
      // The server answers `category=wall` with 4 rows and `category=a` with
      // 15. The app is the last place that can refuse to show them.
      expect(exactTradeOnly(wallpaperLive, 'wall'), isEmpty);
      expect(exactTradeOnly(wallpaperLive, 'a'), isEmpty);
    });
  });
}
