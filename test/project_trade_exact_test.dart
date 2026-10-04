// A trade filter on the market must answer with the jobs filed under it.
//
// Found on 4 Oct 2026 by reading the wire. `GET /api/mobile/projects`
// answers `category` with a **family union**, not the trade:
// `category=wallpaper` returned 17 rows and only `proj_006` is wallpaper, while
// `category=painting` returned the *identical* 17 rows. The market drew all of
// them, so «ورق جدران» showed sixteen painters.
//
// This is the projects half of the defect `trade_exact.dart` shipped for the
// directory on the same day, on an endpoint that file never touched — and the
// mechanism is **not** the substring one measured there. See
// `data/project_trade_exact.dart`; the short version is that every *fragment*
// (`wall`, `paper`, `paint`, `plaster`, `a`) answers 0 rows here, so a rule
// copied on the substring story would be right by luck.
//
// The rows are transcribed verbatim from the live answers, so the tests fail
// on the membership and the order the server actually sent.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/project_trade_exact.dart';
import 'package:allomokawil/src/models/project.dart';

Project _p(String id, String primary, List<String> more) => Project(
      id: id,
      customerId: 1,
      title: 'مشروع $id',
      category: primary,
      categories: more.isEmpty ? <String>[] : <String>[primary, ...more],
      images: const [],
      wilaya: '16',
      urgency: UrgencyLevel.withinWeek,
      status: ProjectStatus.open,
    );

void main() {
  group('exactProjectTrades', () {
    // Exactly the 17 rows `category=wallpaper` answered with on 4 Oct 2026.
    final wallpaperLive = <Project>[
      _p('961072ac', 'painting', const []),
      _p('3d918ee7', 'painting', const []),
      _p('3a915d88', 'plumbing', const ['electrical', 'painting']),
      _p('32fa3e1f', 'painting', const ['plumbing']),
      _p('bf2a66f3', 'painting', const []),
      _p('2d94081c', 'painting', const []),
      _p('21fb59cf', 'painting', const []),
      _p('2a929f52', 'painting', const []),
      _p('25ef91d0', 'construction',
          const ['renovation', 'plaster_drywall', 'painting']),
      _p('90dc9045', 'painting', const ['electrical']),
      _p('8cee95af', 'general_finishing', const [
        'painting',
        'renovation',
        'construction',
        'plumbing',
        'carpentry_aluminum',
      ]),
      _p('5700e663', 'painting', const []),
      _p('b5e739eb', 'painting', const []),
      _p('b37a6feb', 'painting', const []),
      _p('70a8c03b', 'painting', const []),
      _p('proj_006', 'wallpaper', const []),
      _p('proj_005', 'painting', const []),
    ];

    // Exactly the 5 rows `category=plaster_drywall` answered with. `drywall`
    // and `venetian_plaster` answer with the identical five.
    final plasterLive = <Project>[
      _p('25ef91d0', 'construction',
          const ['renovation', 'plaster_drywall', 'painting']),
      _p('d1a7dd46', 'plaster_drywall', const []),
      _p('proj_002', 'venetian_plaster', const []),
      _p('proj_001', 'venetian_plaster', const []),
      _p('proj_004', 'plaster_drywall', const []),
    ];

    test('«ورق جدران» keeps the one wallpaper job and drops sixteen painters',
        () {
      final kept = exactProjectTrades(wallpaperLive, 'wallpaper');
      expect(kept.map((p) => p.id), ['proj_006']);
    });

    test('the same 17 rows answer «دهان» with the sixteen that carry it', () {
      final kept = exactProjectTrades(wallpaperLive, 'painting');
      // Server order preserved exactly, painters first, wallpaper left out.
      expect(
        kept.map((p) => p.id),
        <String>[
          '961072ac', '3d918ee7', '3a915d88', '32fa3e1f', 'bf2a66f3',
          '2d94081c', '21fb59cf', '2a929f52', '25ef91d0', '90dc9045',
          '8cee95af', '5700e663', 'b5e739eb', 'b37a6feb', '70a8c03b',
          'proj_005',
        ],
      );
    });

    test('«جبس فينيسي» does not answer with drywall jobs', () {
      // The two are both «جبس» to the customer, which is why the server groups
      // them — and why they cannot be one answer. `proj_002`/`proj_001` are
      // decorative; `d1a7dd46`/`proj_004` are drywall boards.
      final kept = exactProjectTrades(plasterLive, 'venetian_plaster');
      expect(kept.map((p) => p.id), ['proj_002', 'proj_001']);
    });

    test('«جبس بورد» keeps drywall and drops the decorative rows', () {
      final kept = exactProjectTrades(plasterLive, 'plaster_drywall');
      expect(kept.map((p) => p.id),
          ['25ef91d0', 'd1a7dd46', 'proj_004']);
    });

    test('a multi-trade job answers under every trade it lists', () {
      // `25ef91d0` is a `construction` job that lists four more trades; it is
      // evidence for each of them and must not be dropped from their filters.
      for (final slug in const ['construction', 'renovation', 'painting']) {
        expect(exactProjectTrades(plasterLive, slug).map((p) => p.id),
            contains('25ef91d0'), reason: 'multi-trade job lost from $slug');
      }
    });

    test('a legacy alias row answers for its canonical trade', () {
      // `gypsum` -> `plaster_drywall`, `stucco` -> `venetian_plaster`. A filter
      // on the raw string would drop these; the alias table is this repo's own
      // answer to that dialect.
      final legacy = <Project>[
        _p('proj_leg', 'gypsum', const []),
        _p('proj_stu', 'stucco', const []),
      ];
      expect(exactProjectTrades(legacy, 'plaster_drywall').map((p) => p.id),
          ['proj_leg']);
      expect(exactProjectTrades(legacy, 'venetian_plaster').map((p) => p.id),
          ['proj_stu']);
    });

    test('a pre-multi-trade job is kept, not dropped for an empty list', () {
      // `categories` empty: `allCategories` falls back to [category]. Reading
      // `categories` instead would hide the oldest jobs in the market.
      final legacy = <Project>[_p('proj_old', 'painting', const [])];
      expect(exactProjectTrades(legacy, 'painting').map((p) => p.id),
          ['proj_old']);
    });

    test('a filter that matches nobody answers empty, never everything', () {
      expect(exactProjectTrades(wallpaperLive, 'hvac_heating'), isEmpty);
    });

    test('no filter means no filtering — the market never loses a job', () {
      // 41 of 41 live jobs carry trades today, but an unfiltered read must
      // return the rows object itself, not a copy: this is the arm that keeps
      // the marketplace whole.
      expect(exactProjectTrades(wallpaperLive, null), same(wallpaperLive));
      expect(exactProjectTrades(wallpaperLive, ''), same(wallpaperLive));
      expect(exactProjectTrades(wallpaperLive, '   '), same(wallpaperLive));
    });
  });
}
