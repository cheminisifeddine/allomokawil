// One card recipe, one shape, and a guard that fails the build when a screen
// drifts back to "radius 14 here, 13 dp of inset there".
//
// Why this is a test and not a taste call: the same card was being drawn by
// hand in 20 files — three radii, six insets, four of them with a border that
// was the theme's but typed out again. Nobody reading a screen file could tell
// which numbers were the design and which were an accident. So the recipe is
// asserted twice: once as values (the tokens), once as pixels (a raster of a
// real AppCard), and once as source text (no screen may hand-roll the recipe).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const int _offGridBudget = 197;

List<File> _sources() {
  final dir = Directory('lib');
  if (!dir.existsSync()) return const <File>[];
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// The text of the balanced `(...)` starting at [open] (the index of `(`).
String _balanced(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') {
      depth--;
      if (depth == 0) return s.substring(open, i + 1);
    }
  }
  return s.substring(open);
}

/// A call's own arguments — nested children's arguments are not the call's.
List<String> _topLevelArgs(String s, int open) {
  final body = _balanced(s, open);
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  for (var i = 1; i < body.length - 1; i++) {
    final c = body[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ',' && depth == 0) {
      parts.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  if (buf.toString().trim().isNotEmpty) parts.add(buf.toString().trim());
  return parts;
}

/// Numeric literals in [body]. `AppTheme.s16` is an identifier, not a 16.
Iterable<double> _literals(String body) sync* {
  for (final m in RegExp(r'[A-Za-z_][A-Za-z0-9_]*|\d+(?:\.\d+)?')
      .allMatches(body)) {
    final t = m.group(0)!;
    if (RegExp(r'^[A-Za-z_]').hasMatch(t)) continue;
    yield double.parse(t);
  }
}

int _lineOf(String s, int index) => s.substring(0, index).split('\n').length;

void main() {
  group('the recipe is one set of values', () {
    test('one radius: 20, named once', () {
      expect(AppTheme.cardRadius, AppTheme.rLg);
      expect(AppTheme.cardRadius, 20);
      expect(AppTheme.rXs, 6);
      expect(AppTheme.rSm, 12);
      expect(AppTheme.rMd, 16);
      expect(AppTheme.rLg, 20);
      expect(AppTheme.rXl, 28);
      expect(AppTheme.rPill, 999);
    });

    test('one fill, one hairline, no shadow', () {
      expect(AppTheme.cardFill, AppTheme.surface);
      expect(AppTheme.cardLine, AppTheme.line);
      expect(AppTheme.cardLineWidth, 1);
      expect(AppTheme.cardShadow, isEmpty,
          reason: 'a drop shadow on this canvas is a grey smear; the hairline '
              'border does the separating');
    });

    test('three insets, all off the same 4 dp ladder', () {
      expect(AppTheme.cardPad, const EdgeInsets.all(16));
      expect(AppTheme.cardPadRail, const EdgeInsets.all(12));
      expect(AppTheme.cardPadRows,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8));
      for (final v in <double>[
        AppTheme.s4, AppTheme.s8, AppTheme.s12, AppTheme.s16,
        AppTheme.s20, AppTheme.s24, AppTheme.s28, AppTheme.s32,
      ]) {
        expect(v % 4, 0, reason: '$v is off the grid');
      }
      expect(AppTheme.cardPad, const EdgeInsets.all(AppTheme.s16));
      expect(AppTheme.cardPadRail, const EdgeInsets.all(AppTheme.s12));
      expect(AppTheme.cardPadRows.left, AppTheme.s16);
      expect(AppTheme.cardPadRows.right, AppTheme.s16);
      expect(AppTheme.cardPadRows.top, AppTheme.s8);
      expect(AppTheme.cardPadRows.bottom, AppTheme.s8);
    });

    test('the decoration getter is the recipe', () {
      final d = AppTheme.cardDecoration;
      expect(d.color, AppTheme.cardFill);
      expect(d.borderRadius, BorderRadius.circular(AppTheme.cardRadius));
      expect(d.boxShadow, isEmpty);
      final b = d.border! as Border;
      expect(b.top.color, AppTheme.cardLine);
      expect(b.top.width, AppTheme.cardLineWidth);
    });

    test('a tinted card keeps the shape and only moves the colour', () {
      final d = AppTheme.cardDecorationOf(
          fill: AppTheme.dangerWash, border: AppTheme.danger);
      expect(d.color, AppTheme.dangerWash);
      expect((d.border! as Border).top.color, AppTheme.danger);
      expect(d.borderRadius, BorderRadius.circular(AppTheme.cardRadius),
          reason: 'the danger banner is still a card, not a new shape');
      expect(d.boxShadow, isEmpty);
    });
  });

  group('AppCard builds the recipe', () {
    testWidgets('default card: recipe fill, hairline, radius, cardPad',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          backgroundColor: AppTheme.bg,
          body: Center(child: AppCard(child: Text('مرحبا'))),
        ),
      ));

      final container = tester.widget<Container>(find
          .descendant(of: find.byType(AppCard), matching: find.byType(Container))
          .first);
      expect(container.padding, AppTheme.cardPad);
      final d = container.decoration! as BoxDecoration;
      expect(d.color, AppTheme.cardFill);
      expect(d.borderRadius, BorderRadius.circular(AppTheme.cardRadius));
      expect((d.border! as Border).top.color, AppTheme.cardLine);
      expect((d.border! as Border).top.width, AppTheme.cardLineWidth);
      expect(d.boxShadow, isEmpty);
    });

    testWidgets('a tappable card is the same shape', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppTheme.bg,
          body: Center(
            child: AppCard(onTap: () => taps++, child: const Text('افتح')),
          ),
        ),
      ));
      final container = tester.widget<Container>(find
          .descendant(of: find.byType(AppCard), matching: find.byType(Container))
          .first);
      final d = container.decoration! as BoxDecoration;
      expect(d.color, AppTheme.cardFill,
          reason: 'the tap target must not change the paint');
      expect(d.borderRadius, BorderRadius.circular(AppTheme.cardRadius));
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('rasterises as one surface with one hairline', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: key,
          child: const ColoredBox(
            color: AppTheme.bg,
            child: Center(
              child: SizedBox(
                width: 320,
                height: 180,
                child: AppCard(child: Text('بطاقة')),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      late final int fillPx, linePx, bgPx;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final px = data!.buffer.asUint8List();
        var fill = 0, line = 0, bg = 0;
        // The modern accessors are 0..1 doubles; the raster is 0..255 bytes.
        bool near(int i, Color c) {
          final r = (c.r * 255).round();
          final g = (c.g * 255).round();
          final b = (c.b * 255).round();
          return (px[i] - r).abs() <= 4 &&
              (px[i + 1] - g).abs() <= 4 &&
              (px[i + 2] - b).abs() <= 4;
        }

        for (var i = 0; i < px.length; i += 4) {
          if (near(i, AppTheme.cardFill)) fill++;
          if (near(i, AppTheme.cardLine)) line++;
          if (near(i, AppTheme.bg)) bg++;
        }
        fillPx = fill;
        linePx = line;
        bgPx = bg;
        image.dispose();
      });

      expect(bgPx, greaterThan(1000), reason: 'the canvas is behind the card');
      expect(fillPx, greaterThan(30000),
          reason: 'the card body really paints the recipe fill');
      expect(linePx, greaterThan(0),
          reason: 'the hairline really paints — a borderless card would read '
              'as a hole in the page');
      expect(linePx * 20, lessThan(fillPx),
          reason: 'the border is a hairline, not a frame');
    });
  });

  group('no screen hand-rolls the recipe', () {
    final sources = _sources();

    test('the guard can see the app', () {
      expect(sources, isNotEmpty,
          reason: 'run from the package root — test/card_recipe_test.dart reads '
              'lib/ as text');
      expect(
          sources.any((f) => f.path.endsWith('app_theme.dart')), isTrue);
    });

    test('R1 — a radius is named, never typed', () {
      final offenders = <String>[];
      for (final f in sources) {
        final s = f.readAsStringSync();
        for (final m
            in RegExp(r'BorderRadius\.circular\(\s*\d+\s*\)').allMatches(s)) {
          offenders.add('${f.path}:${_lineOf(s, m.start)} ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'use AppTheme.rSm / rMd / rLg / rXl / rPill:\n'
              '${offenders.join('\n')}');
    });

    test('R2 — a surface card has one definition', () {
      final offenders = <String>[];
      final lookup = RegExp(r'BoxDecoration\(');
      for (final f in sources) {
        if (f.path.endsWith('app_theme.dart') || f.path.endsWith('ui.dart')) {
          continue;
        }
        final s = f.readAsStringSync();
        for (final m in lookup.allMatches(s)) {
          final block = _balanced(s, m.end - 1);
          if (RegExp(r'color:\s*AppTheme\.(surface|cardFill)\s*,')
                  .hasMatch(block) &&
              RegExp(r'borderRadius:\s*BorderRadius\.circular\(')
                  .hasMatch(block) &&
              RegExp(r'Border\.all\(\s*color:\s*AppTheme\.(line|cardLine)\b')
                  .hasMatch(block)) {
            offenders.add('${f.path}:${_lineOf(s, m.start)}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'this is AppTheme.cardDecoration (or cardDecorationOf with '
              'named overrides) — a screen that rebuilds it drifts:\n'
              '${offenders.join('\n')}');
    });

    test('R3 — every AppCard inset comes from the recipe', () {
      const allowed = <String>[
        'padding:AppTheme.cardPad',
        'padding:AppTheme.cardPadRail',
        'padding:AppTheme.cardPadRows',
        'padding:AppTheme.fieldPad',
        'padding:EdgeInsets.zero',
      ];
      final offenders = <String>[];
      for (final f in sources) {
        if (f.path.endsWith('ui.dart')) continue;
        final s = f.readAsStringSync();
        for (final m in RegExp(r'AppCard\(').allMatches(s)) {
          for (final arg in _topLevelArgs(s, m.end - 1)) {
            if (!arg.startsWith('padding:')) continue;
            final flat = arg.replaceAll(RegExp(r'\s+'), '');
            if (!allowed.any(flat.startsWith)) {
              offenders.add('${f.path}:${_lineOf(s, m.start)} $flat');
            }
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'cardPad / cardPadRail / cardPadRows, nothing else:\n'
              '${offenders.join('\n')}');
    });

    test('R4 — off-grid literal spacing has not gone up', () {
      var offGrid = 0;
      final sites = <String>[];
      final lookup =
          RegExp(r'EdgeInsets\.(all|symmetric|only|fromLTRB|fromSTEB)\(');
      for (final f in sources) {
        if (f.path.endsWith('app_theme.dart')) continue;
        final s = f.readAsStringSync();
        for (final m in lookup.allMatches(s)) {
          final body = _balanced(s, m.end - 1);
          for (final v in _literals(body)) {
            if (v != 0 && v % 4 != 0) {
              offGrid++;
              sites.add('${f.path}:${_lineOf(s, m.start)} $v');
            }
          }
        }
      }
      expect(offGrid, lessThanOrEqualTo(_offGridBudget),
          reason: 'this number may only go down — it is the ratchet for the '
              'rest of the 8pt sweep (now $offGrid):\n'
              '${sites.take(12).join('\n')}');
    });
  });
}
