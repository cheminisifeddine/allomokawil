// Two pills, one scroll view, 1 dp apart — and neither counter could see it.
//
// The dossier card on the verification screen (`_PartsStatusCard._part`) drew
// its verdict by hand: `symmetric(horizontal: 10, vertical: 5)`, a 13 dp icon
// and a 5 dp gap. Four lines below it, inside the **same `ListView`**, the
// document cards drew a real `StatusPill` at `AppTheme.pillPad`
// (`symmetric(10, 6)`), a 14 dp icon and `AppTheme.pillGap` (6) — and at
// `fsCaption`, where the hand-rolled one used `fsBadge`. Same radius, same
// wash, same caption weight. A contractor scrolling the screen watches the
// pill change shape, which reads as *unfinished* rather than as a defect.
//
// Why both instruments missed it:
//   * `card_recipe_test.dart`'s **R4** counts off-grid literals per file. The
//     copy was `10, 5` — `5` is off-grid, so it *did* have a row — but the
//     ratchet is a **budget** (`<= 40` across the whole app), so a single row
//     among 40 is invisible to it, and "make the count go down" is the only
//     thing it can ask. Fixing it as a ratchet would have been a rename.
//   * `pill_inset_test.dart` compares `CategoryBadge` / `StatusPill` /
//     `MetaChip` — three pills that already *were* one component. Comparing a
//     component against itself cannot see a component that was spelled out
//     instead of reused.
//
// So the assertion here is deliberately **screen-level**: it boots the real
// `VerificationScreen` against a fake API, scrolls until both pills are on
// screen, and measures the two containers' padding off real layout. That is
// the only framing in which the defect exists — "these two draw beside each
// other" is the bug, and a per-widget or per-file assertion cannot express it.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/verify/verification_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart' show AppCard, StatusPill;

Map<String, dynamic> _user() => <String, dynamic>{
      'id': 31,
      'phone': '0773000000',
      'email': null,
      'full_name': 'مقاول تجربة',
      'type': 'worker',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// The half-accepted dossier: identity approved, contractor card refused.
///
/// **`verification_pending_docs` is 0 on purpose, and getting that wrong cost
/// this file a 6½-minute hang.** The screen branches three ways
/// (`verification_screen.dart`): verified -> a banner; *documents queued* ->
/// the parts card and nothing else; otherwise -> the parts card **and** the
/// document cards. A queue of 2 therefore hides the doc pills this file
/// measures, and the under-review panel animates, so `pumpAndSettle` never
/// settles and the case is killed at the deadline with a SIGTERM rather than
/// an assertion. A timeout that reports as `did not complete` is a **fixture**
/// talking, and it looks nothing like a red guard.
Map<String, Object?> _profile() => <String, Object?>{
      'id': 5,
      'user_id': 9,
      'full_name': 'أحمد بن علي',
      'bio': 'دهان وترميم',
      'specialties': '["painting"]',
      'experience_years': 6,
      'is_available': 1,
      'verification_status': 'pending',
      'verification_pending_docs': 0,
      'is_identity_verified': 1,
      'is_certificate_verified': 0,
      'total_reviews': 3,
      'total_completed_jobs': 4,
      'user_wilaya': '16',
      'commune': 'حسين داي',
    };

ApiClient _api() => ApiClient(
      baseUrls: const ['https://api.test'],
      httpClient: MockClient((req) async {
        if (req.url.path.contains('/my/profile')) {
          return http.Response(jsonEncode(_profile()), 200,
              headers: const {'content-type': 'application/json'});
        }
        if (req.url.path.endsWith('/api/login')) {
          return http.Response(
              jsonEncode(<String, Object?>{'token': 'tok', 'user': _user()}),
              200,
              headers: const {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode(<Object>[]), 200,
            headers: const {'content-type': 'application/json'});
      }),
    );

Future<void> _boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // **Required, and its absence is a 5-minute hang that reports no
  // assertion at all.** `AuthState.login` persists the session, and
  // `SharedPreferences` without this mock reaches for the real platform
  // channel — which never answers inside `testWidgets`' fake-async zone. The
  // case then dies as `did not complete` with a SIGTERM on the `flutter_tester`
  // subprocess, which reads like an OOM and is neither. The sibling
  // `verification_silent_success_test.dart` sets it; this file's first draft
  // did not, and cost two ticks to diagnose.
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = _api();
  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');

  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const VerificationScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The inset of the pill [text] sits in, read off the real tree.
///
/// Written to work on **both** sides of this change, which is the whole point:
/// a guard that can only find a pill through `StatusPill` reports
/// `Bad state: No element` when the hand-rolled copy is back, and that is a
/// red with no number in it — you cannot tell a 5 dp defect from a broken
/// finder. So this walks the padded `Container`s above the text and takes the
/// **innermost** one, which is the pill either way.
///
/// `find.ancestor` on this screen returns the card's own `Container`
/// (`cardPad`, `all(16)`) as well, so picking by hand without knowing the order
/// gets the card. `ancestor` yields **nearest-first** here, measured — the
/// first draft used `.reversed` and read `all(16.0)`, which is a real number
/// and the wrong one.
EdgeInsets _padOf(WidgetTester tester, String text) {
  final ancestors = find
      .ancestor(of: find.text(text), matching: find.byType(Container))
      .evaluate()
      .toList();
  for (final e in ancestors) {
    final pad = (e.widget as Container).padding;
    if (pad != null) return pad.resolve(TextDirection.rtl);
  }
  fail('no padded Container above «$text» — the pill is not what is being found');
}

/// The [StatusPill]s inside the dossier card — anchored on the **card**, not on
/// its title `Text`.
///
/// A pill in a row is a *sibling* of the row's heading, so
/// `descendant(of: find.text('حالة ملفك'), ...)` returns nothing and the first
/// draft of this file passed a vacuous assertion for exactly that reason.
Finder _partPills(WidgetTester tester) => find
    .descendant(
      of: find
          .ancestor(of: find.text('حالة ملفك'), matching: find.byType(AppCard))
          .first,
      matching: find.byType(StatusPill),
    );

void main() {
  group('the dossier verdict pill is the pill beside it', () {
    testWidgets('both pills on the verification screen sit on the same inset',
        (tester) async {
      await _boot(tester);

      // The parts row's verdict and the document row's pill, which share a
      // `ListView` on the real screen.
      final partsPad = _padOf(tester, 'موثّقة');
      final docPad = _padOf(tester, 'اضغط للإضافة');

      expect(partsPad, AppTheme.pillPad,
          reason: 'the dossier verdict is a StatusPill, so it takes the '
              'shared inset and not its own');
      expect(docPad, partsPad,
          reason: 'these two draw one scroll view apart on the screen a '
              'contractor uploads his papers on; a 1 dp disagreement between '
              'neighbours reads as unfinished, not as a defect');
    });

    testWidgets('the parts verdict is a StatusPill, not a copy of one',
        (tester) async {
      await _boot(tester);

      // Type-level, so it fails on the widget rather than on a number that can
      // silently drift back: a pill built from a raw Container inside the parts
      // card is what this guards against.
      expect(_partPills(tester).evaluate().length, greaterThanOrEqualTo(1),
          reason: 'the parts card must draw its verdict with the shared pill');

      final verdict = tester.widget<StatusPill>(_partPills(tester).first);
      expect(verdict.icon, isNotNull,
          reason: 'every state on this row names itself with a mark');
      expect(verdict.border, isNotNull,
          reason: 'the parts row keeps the outline the hand-rolled copy had — '
              'without it «لم تُرسل» is a grey ghost on a white card, because '
              'surfaceAlt on surface is 1.06:1');
    });

    testWidgets('the parts verdict is at the shared caption size, not a badge',
        (tester) async {
      await _boot(tester);
      final verdict = tester.widget<StatusPill>(_partPills(tester).first);
      final text = find
          .descendant(
            of: find.byWidget(verdict),
            matching: find.byType(Text),
          )
          .first;
      final style = tester.widget<Text>(text).style!;
      expect(style.fontSize, AppTheme.fsCaption,
          reason: 'the copy used fsBadge (11) while every pill it sits beside '
              'reads at fsCaption (12.5); two verdicts at two sizes in one '
              'scroll view is the same "unfinished" signal as the 1 dp');
    });
  });
}
