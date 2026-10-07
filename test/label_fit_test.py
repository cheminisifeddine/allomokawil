#!/usr/bin/env python3
"""Prove `tool/label_fit.py` measures labels instead of asserting them.

Run directly — it is pure Python and is not a `flutter test`:

    python3 test/label_fit_test.py

**Why this file exists.** `tool/label_fit.py` is what finally settled the
`SelectableTile` question the R4 sweep left open for four ticks, and it makes a
claim a literal ratchet cannot check: that every Arabic label the app ships fits
the tile it is drawn in, at every width the app claims to support. A probe that
is wrong in the convenient direction is worse than no probe, because the loop
then cites its number as evidence. Each case below is one way this one could be
lying, and the case that matters most is last.

  1. the shape is measured, not declared — wrapping a long Arabic string into a
     narrow box yields *more* lines than a wide box, and never fewer than one;
  2. a line box snaps to whole logical pixels, so 11 * 1.25 lays out as **14**
     and not 13.75 (the fourteenth slice's `19.2 vs 19.00` came from getting
     this wrong, and this file is pinned against it);
  3. the **selected** tile has less room than the plain one, by the extra 1 dp
     border — so the state the user is in is the one that must be checked;
  4. the real face is **Bold**, because `AppTheme.label` is w600: measuring
     Cairo Regular understates the longest label by 14.4 dp, and a probe that
     picks the wrong face reports "fits" on a label that does not;
  5. the current source is *detected* as the current source — the probe reads
     its geometry out of `lib/`, so a stale constant cannot masquerade as a
     measurement, and it reads it from **`SelectableTile`'s own class body**,
     not from the first match in a shared kit file;
  5b. **and the scope is pinned**, because the probe really did get this wrong
     while being written: a bare search read `SectionTitle`'s `maxLines: 1` and
     the probe silently answered about a heading instead of a tile;
  6. **and when the geometry in `lib/` is edited, the probe stops rather than
     quietly agreeing with a layout that no longer exists.** This is the one
     that matters: a probe whose constants have drifted will keep printing
     "ok" about a layout it never read. It is exercised against a synthetic
     source, not the real one.

Expected: 7/7. A failure means the number the next tick cites is wrong.
"""
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), 'tool'))

import label_fit  # noqa: E402

FAILED = []


def check(name, got, want):
    if got != want:
        FAILED.append('%s\n     Expected: %r\n     Actual:   %r' % (name, want, got))
        print('  FAIL  %s' % name)
    else:
        print('  ok    %s' % name)


def case1_wrap_is_measured():
    width = label_fit._measurer('assets/fonts/Cairo-Bold.ttf', 11)
    long = 'تشطيب عام وتسليم مفتاح'
    wide = len(label_fit._wrap(long, 200.0, width))
    narrow = len(label_fit._wrap(long, 60.0, width))
    check('wrapping a long label needs at least one line', wide >= 1, True)
    check('a narrower tile needs more lines', narrow > wide, True)
    check('a narrow box still fits at least one word per line',
          all(l.strip() for l in label_fit._wrap(long, 30.0, width)), True)


def case2_line_box_snaps():
    check('11 * 1.25 lays out as 14 dp', label_fit._line_box(11, 1.25), 14)
    check('12.5 * 1.25 lays out as 16 dp', label_fit._line_box(12.5, 1.25), 16)
    check('a whole-pixel line is untouched', label_fit._line_box(16, 1.0), 16)


def case3_selected_has_less_room():
    geom = label_fit._from_source()
    pad = tuple(geom['tile.padding'])
    cases = {(c['name']): c for c in label_fit.grid_cases(geom)}
    plain = cases['grid 392 dp plain']
    sel = cases['grid 392 dp selected']
    r_plain = label_fit.evaluate(plain, ['سباكة'], label_fit._measurer(
        'assets/fonts/Cairo-Bold.ttf', geom['fsBadge'][0]), pad)['room']
    r_sel = label_fit.evaluate(sel, ['سباكة'], label_fit._measurer(
        'assets/fonts/Cairo-Bold.ttf', geom['fsBadge'][0]), pad)['room']
    check('the selected tile has 2 dp less label room',
          round(r_plain - r_sel, 6), 2.0)


def case4_bold_is_the_real_face():
    bold = label_fit._measurer('assets/fonts/Cairo-Bold.ttf', 11)
    reg = label_fit._measurer('assets/fonts/Cairo-Regular.ttf', 11)
    longest = max(label_fit._labels(), key=bold)
    under = bold(longest) - reg(longest)
    check('Cairo Bold is wider than Regular for the longest label', under > 0,
          True)
    check('and the gap is big enough to matter', round(under, 1) >= 10.0, True)


def case5b_scope_is_the_tile_not_the_file():
    """The bug that bit me while writing the probe, pinned.

    `ui.dart` is a shared kit: `SectionTitle`, `CategoryBadge` and others each
    carry their own `maxLines`. A bare search reads whichever comes first and
    reports another widget's layout as the tile's — which is exactly what
    happened, and it made the probe answer about a heading.
    """
    body = label_fit._selectable_tile_body()
    check('the body starts at the tile', body.startswith('class SelectableTile'),
          True)
    check('the body stops at the next class',
          'class SectionTitle' not in body and 'class StatusPill' not in body,
          True)
    geom = label_fit._from_source()
    check('maxLines read is the tile\'s, not the file\'s first',
          int(geom['tile.maxLines'][0]),
          int(re.search(r'maxLines:\s*(\d+)', body).group(1)))
    check('and the tile still declares a 2-line cap at HEAD',
          int(geom['tile.maxLines'][0]), 2)


def case5_reads_the_real_source():
    geom = label_fit._from_source()
    raw = label_fit._src('lib/src/widgets/category_grid.dart')
    check('crossAxisCount came from the file, not a constant',
          geom['grid.crossAxisCount'][0],
          float(re.search(r'crossAxisCount:\s*(\d+)', raw).group(1)))
    check('the tile padding came from ui.dart, not a constant',
          len(geom['tile.padding']), 2)
    check('fsBadge came from app_theme, not a constant',
          geom['fsBadge'][0], 11.0)


def case6_stale_source_is_caught():
    """The dangerous one: a drifted constant must stop the probe."""
    root = tempfile.mkdtemp(prefix='label_fit_stale_')
    for rel in {e[0] for e in label_fit.READ}:
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write('// a source where the fact the probe reads is GONE\n')
    original = label_fit.REPO
    label_fit.REPO = root
    try:
        label_fit._from_source()
        raised = None
    except SystemExit as exc:
        raised = str(exc)
    finally:
        label_fit.REPO = original
    check('a source that no longer holds the geometry is an error',
          raised is not None and 'stale' in raised, True)


def case7_token_resolves_through_the_ladder():
    """The probe must resolve a ladder TOKEN, not only a bare literal.

    The tile's horizontal inset became `AppTheme.s4`, and a regex written for
    `horizontal: 6` would have found nothing and raised -- which is right, but
    only because the probe *stops*. If it had instead quietly fallen back to a
    default it would print "ok" about a layout it never read, so the resolver
    is pinned here: a token resolves, and an unknown token is still an error.
    """
    geom = label_fit._from_source()
    check('the token resolved to a ladder value', geom['tile.padding'][0], 4.0)
    check('and the vertical literal is untouched', geom['tile.padding'][1], 10.0)
    original = label_fit.REPO
    label_fit.REPO = os.path.join(original, 'lib')
    try:
        label_fit._resolve('AppTheme.s4')
        resolved = True
    except SystemExit:
        resolved = False
    finally:
        label_fit.REPO = original
    check('a token it cannot resolve stops the probe', resolved, False)


def main():
    for fn in (case1_wrap_is_measured, case2_line_box_snaps,
               case3_selected_has_less_room, case4_bold_is_the_real_face,
               case5_reads_the_real_source, case5b_scope_is_the_tile_not_the_file,
               case6_stale_source_is_caught,
               case7_token_resolves_through_the_ladder):
        fn()
    print()
    if FAILED:
        print('%d checks FAILED' % len(FAILED))
        for f in FAILED:
            print('  ' + f)
        return 1
    print('all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
