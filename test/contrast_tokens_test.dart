// The contrast contract: the palette in `app_theme.dart` is the answer to
// "how readable is this?", and this file fails the build when a token slips
// below the line WCAG draws for its job.
//
// Why a test and not a review: `AppTheme.star` sat at 1.91:1 (a "meaningful
// graphic" needs 3:1) and the rating input drew its unselected stars in
// `line` at 1.22:1, so the scale a user picks from was invisible — nobody
// noticed for months because nothing measured it. Two trade tiles in
// `taxonomy.dart` were in the same state (2.85 and 2.56 against their own
// wash). The numbers below are computed from the tokens themselves, so a
// "small tint tweak" can no longer quietly undo them.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';

const _themePath = 'lib/src/core/theme/app_theme.dart';
const _taxonomyPath = 'lib/src/data/taxonomy.dart';
const _reviewPath = 'lib/src/screens/review/review_screen.dart';

/// WCAG relative luminance of an sRGB colour.
double _luminance(Color c) {
  double chan(double v) {
    v /= 255.0;
    return v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * chan(c.r * 255) +
      0.7152 * chan(c.g * 255) +
      0.0722 * chan(c.b * 255);
}

double contrast(Color fg, Color bg) {
  final a = _luminance(fg);
  final b = _luminance(bg);
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

/// `tint:` / `wash:` pairs out of the trade taxonomy.
List<(Color, Color, String)> _tradeTints() {
  final src = File(_taxonomyPath).readAsStringSync();
  final re = RegExp(
      r"name: '([^']+)'[\s\S]*?tint: Color\(0xFF([0-9A-Fa-f]{6})\)[\s\S]*?wash: Color\(0xFF([0-9A-Fa-f]{6})\)");
  return [
    for (final m in re.allMatches(src))
      (
        Color(int.parse('FF${m.group(2)}', radix: 16)),
        Color(int.parse('FF${m.group(3)}', radix: 16)),
        m.group(1)!,
      )
  ];
}

void main() {
  group('text pairs clear 4.5:1', () {
    final pairs = <String, (Color, Color)>{
      'textPrimary on bg': (AppTheme.textPrimary, AppTheme.bg),
      'textPrimary on surfaceAlt': (AppTheme.textPrimary, AppTheme.surfaceAlt),
      'textSecondary on bg': (AppTheme.textSecondary, AppTheme.bg),
      'textSecondary on surfaceAlt':
          (AppTheme.textSecondary, AppTheme.surfaceAlt),
      'textMuted on bg': (AppTheme.textMuted, AppTheme.bg),
      'textMuted on surfaceAlt': (AppTheme.textMuted, AppTheme.surfaceAlt),
      'textMuted on accentWash': (AppTheme.textMuted, AppTheme.accentWash),
      'navy on accent': (AppTheme.navy, AppTheme.accent),
      'onNavy on navy': (AppTheme.onNavy, AppTheme.navy),
      'onNavyMuted on navy': (AppTheme.onNavyMuted, AppTheme.navy),
      'accentDeep on accentWash': (AppTheme.accentDeep, AppTheme.accentWash),
      'accentDeep on bg': (AppTheme.accentDeep, AppTheme.bg),
      'success on successWash': (AppTheme.success, AppTheme.successWash),
      'danger on dangerWash': (AppTheme.danger, AppTheme.dangerWash),
      'info on infoWash': (AppTheme.info, AppTheme.infoWash),
    };

    pairs.forEach((label, pair) {
      test(label, () {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5),
            reason: '$label is below the 4.5:1 body-text line');
      });
    });
  });

  group('meaningful graphics clear 3:1 (WCAG 1.4.11)', () {
    test('the rating star, on every surface it is drawn on', () {
      final surfaces = <String, Color>{
        'bg': AppTheme.bg,
        'surfaceAlt': AppTheme.surfaceAlt,
        'accentWash': AppTheme.accentWash,
        'navy': AppTheme.navy,
      };
      surfaces.forEach((name, bg) {
        final r = contrast(AppTheme.star, bg);
        expect(r, greaterThanOrEqualTo(3.0),
            reason: 'AppTheme.star on $name is ${r.toStringAsFixed(2)}:1');
      });
    });

    test('the unselected star of the rating input is not a hairline', () {
      for (final bg in [AppTheme.bg, AppTheme.surfaceAlt]) {
        expect(contrast(AppTheme.starEmpty, bg), greaterThanOrEqualTo(3.0));
      }
      // …and it is not the decorative divider, which is 1.22:1.
      expect(contrast(AppTheme.line, AppTheme.bg), lessThan(2.0));
      expect(AppTheme.starEmpty, isNot(AppTheme.line));
    });

    test('an outlined control is visible against the canvas', () {
      for (final bg in [AppTheme.bg, AppTheme.surfaceAlt]) {
        expect(contrast(AppTheme.controlLine, bg), greaterThanOrEqualTo(3.0));
      }
    });
  });

  group('the trade tiles', () {
    test('every tint clears 3:1 against its own wash', () {
      final tints = _tradeTints();
      expect(tints.length, greaterThanOrEqualTo(16),
          reason: 'taxonomy parse found ${tints.length} trades');
      for (final (tint, wash, name) in tints) {
        final r = contrast(tint, wash);
        expect(r, greaterThanOrEqualTo(3.0),
            reason: 'trade "$name" icon is ${r.toStringAsFixed(2)}:1 on its wash');
      }
    });
  });

  group('source guards', () {
    test('the unselected stars are never coloured with the hairline token', () {
      final code = File(_reviewPath)
          .readAsStringSync()
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'//.*'), ''))
          .join('\n');
      expect(code.contains('AppTheme.starEmpty'), isTrue,
          reason: 'review_screen.dart must colour unselected stars with '
              'AppTheme.starEmpty');
      expect(RegExp(r'\?\s*AppTheme\.star\s*:\s*AppTheme\.line').hasMatch(code),
          isFalse,
          reason: 'unselected stars fell back to AppTheme.line (1.22:1)');
    });

    test('no retired gold survives in the widget tree', () {
      // #F2B01E and #F2B23E are the pre-palette golds: the first was the star
      // at 1.91:1, the second a glow shadow in the tab bar. Gold lives in
      // `app_theme.dart` (accent / accentDeep / star) and nowhere else.
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        // Comments are stripped: the palette's doc comments *name* the retired
        // golds on purpose, so the history stays readable.
        final text = f
            .readAsStringSync()
            .split('\n')
            .map((l) => l.replaceAll(RegExp(r'//.*'), ''))
            .join('\n')
            .toUpperCase();
        if (text.contains('F2B01E') || text.contains('F2B23E')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'retired gold literal outside the palette: $offenders');
    });
  });

  test('the palette itself does not drift', () {
    final theme = File(_themePath).readAsStringSync();
    expect(theme.contains('static const Color star = Color(0xFFB5790B)'), isTrue);
    expect(theme.contains('static const Color starEmpty'), isTrue);
    expect(theme.contains('static const Color controlLine'), isTrue);
  });
}
