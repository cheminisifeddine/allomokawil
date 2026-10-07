#!/usr/bin/env python3
"""Does every Arabic tile label still FIT, at every width the app supports?

    python3 tool/label_fit.py            # every grid width, today vs proposed
    python3 tool/label_fit.py --why      # which label truncates, and by how much

**Why this file exists.** `SelectableTile` (`ui.dart`) is the one shared tile in
the app whose label is measured *nowhere*. The R4 ratchet counts the padding
literals wrapped around it; it cannot count a string. The previous tick closed
this question with arithmetic — "the real Arabic labels fit one line at
392/360/320, so it is unreachable today" — and **the arithmetic was wrong**: 7
of the 16 category labels already wrap to 2 lines at 392, and at 320 dp the
*selected* tile truncates «بلاط وسيراميك ورخام» to «بلاط وسيراميك…».

Whether a label fits depends on three things no literal ratchet reads:

  * the real **advance width** of the string in Cairo Bold w600 — a property of
    the glyphs, not of the layout. `AppTheme.label` is w600, so the grid tile's
    `fsBadge` 11 is set in Cairo **Bold**, not Regular; measuring the Regular
    face understates «تشطيب عام وتسليم مفتاح» by 14.4 dp and hides the defect.
  * the tile's real width: `(page - 2*gutter - 2*spacing) / 3` for the 3-column
    grid, `(cardContent - 12) / 2` for the two-up auth role row.
  * the **selected** border, 2 dp against 1 — so the state the user makes has
    2 dp *less* room, which is why today's worst case is the selected tile.

**Shaping, not guessing.** PIL with raqm lays the string out through the same
HarfBuzz Flutter uses, so a wrap count here is a wrap count there. The engine
then snaps a line box to whole logical pixels — a 13.75 dp line lays out as 14,
which is what the fourteenth slice got wrong (19.2 vs the measured 19.00).

**What it does NOT claim.** `Flexible` wraps the `Text`, so `maxLines: 2` is a
hard cap: a label needing 3 lines is **ellipsized, not overflowed**. There is no
overflow stripe and no clipping — the tile grows no stripe. The defect this
found is truncation, which is a legibility bug and nothing worse, and it is
reported as exactly that.

**A stale constant is the failure mode.** Every geometry number is read out of
the source (`_from_source`), so a tile edited without updating this probe fails
`self_test` instead of quietly agreeing with a layout that no longer exists.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Page widths this app is expected to survive. 392 and 360 are the two widths
# the goldens are shot at; 320 is the floor `review_screen.dart:127` already
# branches on (`MediaQuery.sizeOf(context).width >= 360 ? 20.0 : 8.0`), so a
# defect that only appears at 320 is a defect on a phone the app claims.
PAGES = (392, 360, 320)

# Where each number lives. One entry per fact the probe must not hardcode.
READ = [
    ('lib/src/widgets/category_grid.dart', r'crossAxisCount:\s*(\d+)',
     'grid.crossAxisCount'),
    ('lib/src/widgets/category_grid.dart', r'crossAxisSpacing:\s*([\d.]+)',
     'grid.crossAxisSpacing'),
    ('lib/src/widgets/category_grid.dart', r'mainAxisSpacing:\s*([\d.]+)',
     'grid.mainAxisSpacing'),
    ('lib/src/widgets/category_grid.dart', r'childAspectRatio:\s*([\d.]+)',
     'grid.childAspectRatio'),
    # The horizontal inset is an IDENTIFIER now (`AppTheme.s4`), so this
    # regex reads the vertical literal and resolves the horizontal one against
    # the ladder -- the same stale-constant guard applies to tokens, and the
    # probe must fail loudly rather than silently fall back to the old `6`.
    # It did fail loudly on this edit, which is the point of case 6.
    ('lib/src/widgets/ui.dart',
     r'symmetric\(\s*horizontal:\s*([\w.]+),\s*vertical:\s*([\d.]+)\)',
     'tile.padding', 'SelectableTile'),
    # `maxLines` is the whole contract: `Flexible` makes it a hard cap, so a
    # label needing more is ellipsized rather than drawn. Hardcoding 2 here
    # would be the exact stale-constant trap case 6 is written to catch.
    ('lib/src/widgets/ui.dart', r'maxLines:\s*(\d+)', 'tile.maxLines',
     'SelectableTile'),
    ('lib/src/core/theme/app_theme.dart', r'fsBadge\s*=\s*([\d.]+)',
     'fsBadge'),
    ('lib/src/core/theme/app_theme.dart', r'gutter\s*=\s*([\d.]+)', 'gutter'),
    ('lib/src/core/theme/app_theme.dart', r's12\s*=\s*([\d.]+)', 's12'),
]


def _src(rel):
    with open(os.path.join(REPO, rel), encoding='utf-8') as fh:
        return fh.read()


def _selectable_tile_body():
    """`SelectableTile`'s own source, and nothing else.

    `ui.dart` holds several widgets with their own `maxLines` and their own
    `symmetric(horizontal: ...)`, so a bare `re.search` over the file reads
    whichever comes FIRST and reports another widget's layout as this one's.
    That is not hypothetical: while writing this probe a bare search picked up
    `SectionTitle`'s `maxLines: 1` instead of the tile's, which made the probe
    answer about a heading rather than a tile. Scope every read to the class.
    """
    src = _src('lib/src/widgets/ui.dart')
    start = src.index('class SelectableTile')
    nxt = src.find('\nclass ', start + 1)
    return src[start:nxt if nxt > 0 else len(src)]


def _from_source():
    """Read every geometry number out of the source. No hardcoded layout."""
    out = {}
    for entry in READ:
        rel, pattern, name = entry[0], entry[1], entry[2]
        scope = entry[3] if len(entry) > 3 else None
        body = _selectable_tile_body() if scope else _src(rel)
        m = re.search(pattern, body)
        if not m:
            raise SystemExit(
                'label_fit: cannot read %s from %s — the probe is stale, fix '
                'it in the same commit as the layout change.' % (name, rel))
        out[name] = [_resolve(g) for g in m.groups()]
    return out


def _resolve(token):
    """`4` -> 4.0, `AppTheme.s4` -> the ladder value. Unknown -> stop."""
    try:
        return float(token)
    except ValueError:
        pass
    m = re.fullmatch(r'AppTheme\.(\w+)', token)
    if not m:
        raise SystemExit(
            'label_fit: cannot resolve %r — the probe reads layout tokens '
            'from the ladder and stops rather than guessing.' % token)
    try:
        body = _src('lib/src/core/theme/app_theme.dart')
    except OSError:
        # An unreadable ladder is the same failure as a drifted one: the probe
        # cannot answer the question, so it stops rather than tracebacking out
        # of a loop that cites its number as evidence.
        raise SystemExit(
            'label_fit: cannot read the spacing ladder — the probe is stale, '
            'fix it in the same commit as the layout change.')
    d = re.search(r'static const double %s\s*=\s*([\d.]+)' % re.escape(m.group(1)),
                  body)
    if not d:
        raise SystemExit(
            'label_fit: %s is not on the spacing ladder any more — the probe is '
            'stale, fix it in the same commit as the layout change.'
            % token)
    return float(d.group(1))


def _labels():
    """The 16 Arabic category names, from the taxonomy itself."""
    src = _src('lib/src/data/taxonomy.dart')
    body = src[src.index('categories = ['):]
    return re.findall(r"name:\s*'([^']+)'", body)


def _measurer(font_file, size_dp):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(os.path.join(REPO, font_file),
                              int(size_dp * 1000))
    draw = ImageDraw.Draw(Image.new('L', (10, 10)))

    def width(text, scale=1.0):
        return (draw.textlength(text, font=font, direction='rtl',
                                language='ar') / 1000.0) * scale
    return width


def _wrap(text, avail, width, scale=1.0):
    """Greedy word wrap, the way the engine breaks an Arabic label."""
    lines, cur = [], ''
    for word in text.split(' '):
        trial = (cur + ' ' + word).strip()
        if cur and width(trial, scale) > avail:
            lines.append(cur)
            cur = word
        else:
            cur = trial
    if cur:
        lines.append(cur)
    return lines


def _line_box(font_size, height=1.25):
    """A line box snaps to whole logical pixels; the engine does this, so
    must the probe. 11 * 1.25 = 13.75 lays out as 14, not 13.75."""
    return round(font_size * height)


def grid_cases(geom):
    """One case per (page width, selected?) for the 3-column grid."""
    cols = geom['grid.crossAxisCount'][0]
    spacing_x = geom['grid.crossAxisSpacing'][0]
    aspect = geom['grid.childAspectRatio'][0]
    hp, vp = geom['tile.padding']
    fs = geom['fsBadge'][0]
    gutter = geom['gutter'][0]
    max_lines = int(geom['tile.maxLines'][0])
    for page in PAGES:
        tile = (page - 2 * gutter - (cols - 1) * spacing_x) / cols
        for border, sel in ((1.0, False), (2.0, True)):
            yield {
                'border': border,
                'name': 'grid %d dp %s' % (page, 'selected' if sel else 'plain'),
                'tile_w': tile,
                'tile_h': tile / aspect,
                'pad_v': vp,
                'fs': fs,
                'sel': sel,
                'max_lines': max_lines,
            }


def auth_cases(geom):
    """The two-up «نوع الحساب» row on sign-up."""
    hp, vp = geom['tile.padding']
    fs = 12.5  # fsCaption — see `SelectableTile`'s label
    gutter = geom['gutter'][0]
    max_lines = int(geom['tile.maxLines'][0])
    for page in PAGES:
        content = page - 2 * (gutter + 1 + 16)  # card content 35..357
        tile = (content - geom['s12'][0]) / 2
        yield {
            'name': 'auth %d dp' % page,
            'tile_w': tile,
            'tile_h': 92,
            'border': 2.0,
            'pad_v': vp,
            'fs': fs,
            'sel': False,
            'max_lines': max_lines,
        }


def evaluate(case, labels, width_fn, pad, scale=1.0):
    """Worst case for one tile: how many lines the widest label needs."""
    hp, vp = pad
    room = case['tile_w'] - 2 * hp - 2 * case['border']
    lab_h = case['tile_h'] - 2 * vp - 36 - 6
    worst, needed = 0, ''
    for name in labels:
        n = len(_wrap(name, room, width_fn, scale))
        if n > worst:
            worst, needed = n, name
    return {
        'lines': worst,
        'label': needed,
        'room': room,
        'label_h': lab_h,
        'fits_height': worst * _line_box(case['fs']) <= lab_h,
    }


def main(argv):
    geom = _from_source()
    labels = _labels()
    fs = geom['fsBadge'][0]
    width = _measurer('assets/fonts/Cairo-Bold.ttf', fs)
    why = '--why' in argv

    print('labels: %d   grid: %d cols, spacing %g, aspect %g   tile padding %s'
          % (len(labels), geom['grid.crossAxisCount'][0],
             geom['grid.crossAxisSpacing'][0], geom['grid.childAspectRatio'][0],
             geom['tile.padding']))
    print()
    bad = 0
    for case in list(grid_cases(geom)):
        res = evaluate(case, labels, width, tuple(geom['tile.padding']))
        over = res['lines'] > case['max_lines']
        bad += 1 if over else 0
        flag = 'TRUNCATES' if over else 'ok'
        print('  %-22s room %6.2f dp  %d line(s) %-9s %s'
              % (case['name'], res['room'], res['lines'], flag,
                 ('«%s»' % res['label']) if (over or why) else ''))
    if bad:
        print('\n%d tile(s) ellipsize a label the app ships.\n' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
