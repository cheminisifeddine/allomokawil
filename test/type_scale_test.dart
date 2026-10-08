// The typography contract: one ladder, and nobody types their own size.
//
// Why this is a test and not a convention: 121 call sites were each typing a
// number next to a scale entry — `AppTheme.caption.copyWith(fontSize: 12)`,
// `AppTheme.h1.copyWith(fontSize: 18)`, `AppTheme.h2.copyWith(fontSize: 16)` —
// so the same caption was 12 dp on one screen and 12.5 on the next, the four
// app-bar titles disagreed with each other, and "how big is a caption?" had no
// answer anywhere in the codebase. The ladder in `app_theme.dart` is the
// answer; this file fails the build when a screen starts inventing sizes again.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';

const _themePath = 'lib/src/core/theme/app_theme.dart';

// Two probe styles built from the ladder — the raster test below proves the
// steps reach the engine, not just the source text.
const _badgeStyle =
    TextStyle(fontFamily: 'Cairo', fontSize: AppTheme.fsBadge);
const _heroStyle =
    TextStyle(fontFamily: 'Cairo', fontSize: AppTheme.fsHero);

List<File> _sources() {
  final dir = Directory('lib');
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// The source with `//` comments removed, so a doc comment that *mentions*
/// fontSize is not read as code.
String _code(String text) => text
    .split('\n')
    .map((l) => l.replaceAll(RegExp(r'//.*'), ''))
    .join('\n');

/// `fontSize:` followed by whatever comes after it, per line.
///
/// The capture runs to the next `,` `;` `)` or newline and **not** to the next
/// space. That distinction is the whole reason this guard can be trusted: with
/// `[^\s,);]+` a line reading `fontSize: AppTheme.pipNumeral * 2` yields the
/// bare token `AppTheme.pipNumeral`, which is on the ladder, so a hand-picked
/// 22 dp passed the ladder test while never once being a ladder step. Capturing
/// the full expression hands the guard something it can actually judge.
Iterable<String> _sizes(String text) sync* {
  final re = RegExp(r'fontSize:\s*([^,;)\n]+)');
  for (final m in re.allMatches(text)) {
    final line =
        text.substring(0, m.start).split('\n').length; // 1-based, for messages
    yield 'line $line: ${m.group(1)}';
  }
}

/// Every `static const double` in the theme, name -> right-hand side text.
///
/// A size token is allowed to be spelled as a *derived* name rather than a bare
/// `fsX`, and the ladder guard below has to know about those too — see
/// [ladderSizeNames] for why the answer is read from the theme instead of
/// hardcoded here.
final RegExp _tokenDecl =
    RegExp(r'static\s+const\s+double\s+(\w+)\s*=\s*([^;]+);');

/// The names in [app_theme.dart] whose value **is** a step of [AppTheme.scale].
///
/// This is the guard's real question. The old rule asked a different one —
/// "does the name start with `fs`?" — and that is a *spelling* test wearing the
/// costume of a design rule: it rejected [AppTheme.pipNumeral], which is a real
/// token defined as `static const double pipNumeral = fsBadge`, on no grounds
/// except that its name is spelled differently from the ladder step it aliases.
///
/// Deriving the set from the theme means a token qualifies **because it lands on
/// a ladder step**, and a non-type token (`AppTheme.gutter`, `AppTheme.ring`,
/// `AppTheme.s16`) stays rejected because 18.0 and 3.0 are not type sizes.
/// Those two are the whole point: a rule that accepted every theme token would
/// pass a border width straight into a `fontSize`, which is the defect this file
/// exists to catch.
Set<String> ladderSizeNames() {
  final source = _code(File(_themePath).readAsStringSync());
  final raw = <String, String>{
    for (final m in _tokenDecl.allMatches(source))
      m.group(1)!: m.group(2)!.trim(),
  };

  // Resolve `= fsBadge`, `= 11`, and `= stripH - 34` to a number, iterating
  // until nothing new resolves (declarations are not in dependency order).
  final values = <String, double>{};
  var progressed = true;
  while (progressed) {
    progressed = false;
    for (final entry in raw.entries) {
      if (values.containsKey(entry.key)) continue;
      final double? resolved = _resolveSizeExpr(entry.value, values);
      if (resolved != null) {
        values[entry.key] = resolved;
        progressed = true;
      }
    }
  }

  final missing = raw.keys.toSet().difference(values.keys.toSet());
  expect(missing, isEmpty,
      reason: 'could not read the value of these theme tokens, so the ladder '
          'guard would be judging on a partial theme:\n${missing.join('\n')}');

  final ladder = AppTheme.scale.toSet();
  return <String>{
    for (final e in values.entries)
      if (ladder.contains(e.value)) e.key,
  };
}

/// One right-hand side of a size declaration, resolved against [known].
double? _resolveSizeExpr(String expr, Map<String, double> known) {
  final asNumber = double.tryParse(expr);
  if (asNumber != null) return asNumber;
  final bare = RegExp(r'^(\w+)$').firstMatch(expr);
  if (bare != null) return known[bare.group(1)];
  final derived = RegExp(r'^(\w+)\s*([+-])\s*([\d.]+)$').firstMatch(expr);
  if (derived != null) {
    final base = known[derived.group(1)];
    if (base == null) return null;
    final delta = double.tryParse(derived.group(3)!);
    if (delta == null) return null;
    return derived.group(2) == '+' ? base + delta : base - delta;
  }
  return null;
}

/// `AppTheme.x`, returning the bare member name — or null if it is not that.
String? _memberName(String value) {
  // Anchored at the end on purpose. Without it `AppTheme.pipNumeral * 2` reads
  // as `pipNumeral`, and a hand-picked 22 dp "badge" sails through the guard on
  // the strength of a name that is merely spelled right. A token is a token
  // only when it is the whole expression.
  final m = RegExp(r'^AppTheme\.(\w+)$').firstMatch(value);
  return m?.group(1);
}

/// The size *functions*, which compute a ladder step from an argument and so
/// cannot be checked by value at read time.
bool _isSizeFunction(String value) =>
    RegExp(r'^AppTheme\.(monogram\(|nearest\(|rating\w+\()').hasMatch(value);

void main() {
  group('the size ladder', () {
    test('is ordered, distinct and spaced at least 1 dp', () {
      const steps = AppTheme.scale;
      expect(steps.length, greaterThanOrEqualTo(8),
          reason: 'a ladder with fewer steps than roles is not a ladder');
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i] - steps[i - 1], greaterThanOrEqualTo(1.0),
            reason: 'steps ${steps[i - 1]} and ${steps[i]} are closer than '
                '1 dp apart, which is a rounding error pretending to be a '
                'design decision');
      }
      expect(steps.toSet().length, steps.length, reason: 'duplicate step');
    });

    test('stays in the readable band for Arabic', () {
      expect(AppTheme.scale.first, greaterThanOrEqualTo(11.0),
          reason: 'below 11 dp Arabic loses its dots');
      expect(AppTheme.scale.last, greaterThanOrEqualTo(27.0),
          reason: 'the landing promise needs a display step');
    });

    test('every role style is a ladder step', () {
      const roles = <String, TextStyle>{
        'display': AppTheme.display,
        'h1': AppTheme.h1,
        'h2': AppTheme.h2,
        'body': AppTheme.body,
        'bodySoft': AppTheme.bodySoft,
        'label': AppTheme.label,
        'caption': AppTheme.caption,
        'button': AppTheme.button,
        'bar': AppTheme.bar,
      };
      roles.forEach((name, style) {
        expect(AppTheme.scale, contains(style.fontSize),
            reason: 'role "$name" is set at ${style.fontSize}, which is not a '
                'step on the ladder');
        expect(style.fontFamily, 'Cairo', reason: 'role "$name" lost its face');
      });
    });

    test('the app bar uses the bar role, not a shrunk h1', () {
      final theme = AppTheme.light;
      expect(theme.appBarTheme.titleTextStyle?.fontSize, AppTheme.fsBar);
      expect(theme.appBarTheme.titleTextStyle?.fontWeight, FontWeight.w700);
    });

    test('derived sizes land on the ladder', () {
      expect(AppTheme.nearest(12.4), AppTheme.fsCaption);
      expect(AppTheme.nearest(100), AppTheme.fsHero);
      expect(AppTheme.nearest(-5), AppTheme.fsBadge);
      // The three star sizes the app actually renders (13/14/15 dp).
      for (final star in <double>[13, 14, 15]) {
        expect(AppTheme.scale, contains(AppTheme.ratingValue(star).fontSize),
            reason: 'rating value beside a $star dp star is off-ladder');
        expect(AppTheme.scale, contains(AppTheme.ratingCount(star).fontSize),
            reason: 'review count beside a $star dp star is off-ladder');
      }
      expect(AppTheme.monogram(48), closeTo(20.16, 0.001));
      expect(AppTheme.monogram(48, ratio: 0.4), closeTo(19.2, 0.001));
    });
  });

  test('no file outside the theme types a font size', () {
    final allowed = ladderSizeNames();
    final offenders = <String>[];
    for (final f in _sources()) {
      if (f.path.endsWith('core/theme/app_theme.dart')) continue;
      for (final s in _sizes(_code(f.readAsStringSync()))) {
        final value = s.split(': ').last;
        final member = _memberName(value);
        if (_isSizeFunction(value)) continue;
        if (member != null && allowed.contains(member)) continue;
        offenders.add('${f.path} $s');
      }
    }
    expect(offenders, isEmpty,
        reason: 'a screen is choosing its own type size again. Pick a step '
            'from AppTheme.scale (or an AppTheme token that lands on one) '
            'instead:\n'
            '${offenders.join('\n')}');
  });

  test('the theme itself only ever uses ladder tokens', () {
    final offenders = <String>[];
    for (final s in _sizes(_code(File(_themePath).readAsStringSync()))) {
      final value = s.split(': ').last;
      if (!RegExp(r'^(fs\w+|nearest\()').hasMatch(value)) {
        offenders.add(s);
      }
    }
    expect(offenders, isEmpty,
        reason: 'app_theme.dart is the single source of sizes — a number '
            'there defeats the ladder:\n${offenders.join('\n')}');
  });

  testWidgets('the ladder really drives the engine, not just the source',
      (tester) async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    expect(reg.lengthInBytes, greaterThan(10000),
        reason: 'Cairo-Regular.ttf is missing from the asset bundle');
    await (FontLoader('Cairo')..addFont(Future.value(reg))).load();

    const text = 'مقاول الو مقاول';
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, key: Key('badge'), style: _badgeStyle),
          Text(text, key: Key('hero'), style: _heroStyle),
        ]),
      ),
    ));

    final small = tester.getSize(find.byKey(const Key('badge'))).width;
    final large = tester.getSize(find.byKey(const Key('hero'))).width;
    const expected = AppTheme.fsHero / AppTheme.fsBadge;
    expect(large / small, closeTo(expected, expected * 0.15),
        reason: 'the painted widths should scale with the ladder steps '
            '($small → $large for a $expected x size step); if they do not, '
            'the tokens are decorative');
  });
}
