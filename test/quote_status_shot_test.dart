// The owner\'s quote list, before and after he commits — photographed.
//
// The widget assertions in `quote_status_test.dart` prove the behaviour. This
// file proves the *pixels*, because the claim that matters is visual: a
// customer who lost the bid must be able to see, on the card itself, that he
// lost it. `findsNothing` on a button is a fact about the tree; it says nothing
// about whether the two cards still look identical to a reader — and
// "identical" is precisely the defect.
//
// Two captures of the same screen:
//
//   * `quote_cards_live.png`    two live bids, both carrying «قبول العرض»;
//   * `quote_cards_decided.png` the state the Worker sends after a commit:
//                               48 `accepted`, 49 `rejected`, zero buttons.
//
// They must differ, and the difference must be where the verdict is, not
// anywhere else in the frame. Both are written to /tmp/shots/ and are NOT
// goldens: a golden here would freeze «الآن» into a baseline and fail on every
// other day of the week, which is exactly the trap the `clock` seam exists to
// avoid.
//
// Run with:  flutter test test/quote_status_shot_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/quote_status_copy.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

const _out = '/tmp/shots/quote';

/// Fixed, so the date line is a constant word in both captures and the only
/// thing that differs between them is the verdict.
final _now = DateTime.utc(2026, 9, 29, 17, 0, 53);

Map<String, dynamic> _row(int id, {String status = 'pending'}) => <String, dynamic>{
      'id': id,
      'project_id': 'p1',
      'worker_id': 100 + id,
      'amount': 5000 + id * 400,
      'message': 'يمكنني البدء غداً',
      'estimated_days': 5,
      'status': status,
      'created_at': '2026-09-29 17:00:53',
      'worker_full_name': id == 48 ? 'خالد رحماني' : 'يوسف بن عمر',
      'worker_avatar_url': null,
      'worker_avg_rating': 4.6,
      'worker_total_reviews': 18,
      'worker_verification_status': 'verified',
    };

Map<String, dynamic> _user() => <String, dynamic>{
      'id': 30,
      'phone': '0773000000',
      'email': null,
      'full_name': 'زبون تجربة',
      'type': 'customer',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

Map<String, dynamic> _project({String status = 'open'}) => <String, dynamic>{
      'id': 'p1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': 'دهان كامل مع تصليح',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'latitude': null,
      'longitude': null,
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': status,
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

http.Response _json(Object b) => http.Response(jsonEncode(b), 200,
    headers: {'content-type': 'application/json'});

/// A signed-in owner plus the API client the screen is driven against — the
/// **same** client, because `AuthState` owns its own and a screen wired to a
/// second one would be reading a different server than the assertions claim.
Future<({ApiClient api, AuthState auth})> _boot(
    List<Map<String, dynamic>> rows) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object>{'token': 'tok', 'user': _user()});
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.startsWith('/api/mobile/projects/p1/quotes')) return _json(rows);
      if (p == '/api/mobile/projects/p1') return _json(_project());
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

/// Where a shot went, and which bands of it are the *verdict*.
///
/// [verdictBands] is measured from the widget tree — the rect of the widget
/// carrying the verdict line — and converted into the pixel rows the PNG will
/// hold. It is captured *before* the bytes, so a band can never be derived
/// from the diff it is supposed to police.
class _Shot {
  final String path;

  /// The same capture as **uncompressed RGBA**, because a PNG is deflated and
  /// `a[i] != b[i]` over its bytes answers "does the compressor emit a
  /// different stream", not "is this pixel different". Comparing compressed
  /// bytes cannot localise a difference to a row, which is the entire question
  /// here — the first version of this check did exactly that and reported 0.0%
  /// for a band it had itself just proven to be the verdict.
  final Uint8List rgba;
  final int width;
  final int height;
  final List<(int, int)> verdictBands;
  final List<(int, int)> acceptButtonBands;
  const _Shot(this.path, this.rgba, this.width, this.height,
      this.verdictBands, this.acceptButtonBands);
}

Rect _px(Rect r, double dpr) =>
    Rect.fromLTRB(r.left * dpr, r.top * dpr, r.right * dpr, r.bottom * dpr);

/// The pixel rows [r] occupies in a capture taken at [pixelRatio].
///
/// The capture is `boundary.toImage(pixelRatio: 2.0)` of a repaint boundary
/// whose own logical top is not the frame's — the boundary is inset by
/// [MediaQuery.padding] in a test harness — so the offset is not guessed. It
/// is read off the boundary's own rect, which is the same object `toImage`
/// rasterises.
(int, int) _rowsFor(Rect r, Rect boundaryLogical, double pixelRatio) {
  final b = _px(boundaryLogical, pixelRatio);
  final y0 = (_px(r, pixelRatio).top - b.top).round().clamp(0, 1 << 30);
  final y1 = (y0 + (r.height * pixelRatio).round()).clamp(0, 1 << 30);
  return (y0, y1);
}

Future<_Shot> _capture(
    WidgetTester tester, String name, List<String> verdictTexts) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  const pixelRatio = 2.0;
  final m = boundary.getTransformTo(null);
  final boundaryLogical = MatrixUtils.transformRect(m, Offset.zero & boundary.size);

  final verdictBands = <(int, int)>[];
  for (final t in verdictTexts) {
    final f = find.text(t);
    if (f.evaluate().isEmpty) continue;
    verdictBands.add(_rowsFor(
        tester.getRect(f.first), boundaryLogical, pixelRatio));
  }
  final acceptBands = <(int, int)>[];
  final accept = find.text('قبول العرض');
  for (final e in accept.evaluate()) {
    acceptBands.add(_rowsFor(
        tester.getRect(find.byWidget(e.widget).first), boundaryLogical, pixelRatio));
  }

  late String path;
  late Uint8List raw;
  late int w;
  late int h;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    path = '$_out/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    w = image.width;
    h = image.height;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    raw = rgba!.buffer.asUint8List();
  });
  return _Shot(path, raw, w, h, verdictBands, acceptBands);
}

void main() {
  testWidgets('the owner\'s quote list, live and after he commits', (tester) async {
    // 2400, not 1150. The bid cards sit well below the fold on a project with
    // this much chrome above them, and a capture that stops short of them
    // photographs the same header in both states — which is how the first
    // version of this file reported two byte-identical PNGs as a *product*
    // defect instead of a harness that never looked at the cards. Same size the
    // widget tests use for the same screen.
    tester.view.physicalSize = const Size(392, 2400) * 2.75;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final live = <Map<String, dynamic>>[_row(48), _row(49)];
    final decided = <Map<String, dynamic>>[
      _row(48, status: 'accepted'),
      _row(49, status: 'rejected'),
    ];

    _Shot? liveShot;
    _Shot? decidedShot;

    final verdicts = <String>[
      quoteStatusNoteAr(QuoteStatus.accepted),
      quoteStatusNoteAr(QuoteStatus.rejected),
    ];

    for (final shot in <(String, List<Map<String, dynamic>>)>[
      ('live', live),
      ('decided', decided),
    ]) {
      final boot = await _boot(shot.$2);
      final api = boot.api;
      final repo = Repository(api);
      await tester.pumpWidget(AppScope(
        api: api,
        auth: boot.auth,
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
          // Keyed by the capture. The second `pumpWidget` in this test builds
          // the *same* widget types, so Flutter keeps the existing State and
          // `ProjectDetailScreen.initState` never runs a second time — the
          // quotes future created for the live capture is still mounted, and
          // the decided state is never fetched. The two PNGs were then
          // byte-identical for a reason that had nothing to do with the
          // product. A distinct key forces a real rebuild.
          home: RepaintBoundary(
            key: const ValueKey('shot'),
            child: ProjectDetailScreen(
                key: ValueKey('capture-${shot.$1}'),
                projectId: 'p1',
                repo: repo,
                clock: () => _now),
          ),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      final shotOut =
          await _capture(tester, 'quote_cards_${shot.$1}', verdicts);
      if (shot.$1 == 'live') {
        liveShot = shotOut;
      } else {
        decidedShot = shotOut;
      }
    }
    final l = liveShot!;
    final d = decidedShot!;

    // ---- The two captures must differ *in the verdict*, not merely differ.
    //
    // The original check here was global: "the two files are not byte-equal".
    // That is a much weaker claim than the sentence above it, and it was
    // vacuous. Measured on this tree before the fix: flattening the verdict
    // line to a constant one-character `Text` — deleting the sentence that
    // tells a losing bidder he lost — changed the live/decided difference by
    // 75,746 pixels and the test stayed green, because the vanishing
    // «قبول العرض» button alone was enough to make the two files differ. A
    // global inequality cannot tell "the verdict reached the pixels" from
    // "something, somewhere, changed", and this file's whole purpose is the
    // first.
    //
    // So the check is localised, and the band is measured from the widget tree
    // rather than derived from the diff it polices (deriving it from the diff
    // would make the assertion true by construction).
    final a = File(l.path).readAsBytesSync();
    final b = File(d.path).readAsBytesSync();
    expect(a.length, greaterThan(1000));
    expect(b.length, greaterThan(1000));
    // Kept: identical files are still a failure, and this is the cheap check.
    expect(a.length == b.length && _sameBytes(a, b), isFalse,
        reason: 'the live and decided lists rendered identically — the verdict '
            'is not reaching the pixels');

    /// Fraction of pixel rows in [y0]..[y1] whose pixels differ between the
    /// two captures. Read from raw RGBA, so it is a fact about pixels.
    double rowDiffIn(int y0, int y1) {
      if (d.width != l.width || d.height != l.height) {
        fail('the two captures are different sizes (${l.width}x${l.height} vs '
            '${d.width}x${d.height}) — a row band means nothing');
      }
      var rows = 0, differing = 0;
      final stride = d.width * 4;
      for (var y = y0; y < y1; y++) {
        if (y < 0 || y >= d.height) continue;
        rows++;
        final row = y * stride;
        var different = false;
        for (var x = 0; x < d.width; x++) {
          final o = row + x * 4;
          if (l.rgba[o] != d.rgba[o] ||
              l.rgba[o + 1] != d.rgba[o + 1] ||
              l.rgba[o + 2] != d.rgba[o + 2]) {
            different = true;
            break;
          }
        }
        if (different) differing++;
      }
      return rows == 0 ? 0 : differing / rows;
    }

    // 1. Every verdict string must be *painted* in the decided capture, at the
    //    band its widget occupies. Two of them, one per card.
    expect(d.verdictBands.length, verdicts.length,
        reason: 'the decided capture is not showing a verdict line per card — '
            'the losing bidder is told nothing. Widgets found: '
            '${d.verdictBands.length}, verdict strings: ${verdicts.length}');

    for (final band in d.verdictBands) {
      final f = rowDiffIn(band.$1, band.$2);
      expect(f, greaterThan(0.5),
          reason: 'rows ${band.$1}..${band.$2} are the verdict line in the '
              'decided capture and only ${(f * 100).toStringAsFixed(1)}% of '
              'them differ from the live capture — the card changed around the '
              'verdict, not in it');
    }

    // 2. The live capture must carry NO verdict band at all. `pending` returns
    //    '' from `quoteStatusNoteAr`, so a live card that grew a verdict line
    //    would be showing the empty string, i.e. a row drawn for nothing.
    expect(l.verdictBands, isEmpty,
        reason: 'a live bid is painting a verdict line at rows '
            '${l.verdictBands} — `quoteStatusNoteAr` returns '' for pending, '
            'so this is a placeholder row, not a message');

    // 3. And the buttons themselves must move, which is the other half of the
    //    defect: a decided card with no button and a live card with two.
    expect(l.acceptButtonBands.length, 2,
        reason: 'the live capture should carry two «قبول العرض» buttons, found '
            '${l.acceptButtonBands.length}');
    expect(d.acceptButtonBands, isEmpty,
        reason: 'a decided card still carries «قبول العرض» at rows '
            '${d.acceptButtonBands} — the offer can still be taken after the '
            'owner committed to somebody else');

    // ignore: avoid_print
    print('SHOT live=${l.path} decided=${d.path} '
        'liveBytes=${a.length} decidedBytes=${b.length} '
        'verdictBands=${d.verdictBands} acceptButtons=${l.acceptButtonBands}');
  });
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
