// «تحديث» on the contractor's gallery could install an **older** gallery over
// a photo he had just uploaded, and recompute his plan's photo allowance from
// rows that answer predates.
//
// Found on 4 Oct 2026 by the audit the 50th tick's "Next" pointed at: a census
// of `await` + `setState` methods with **no** generation token, of which
// `my_portfolio_screen._load` was named as one that writes state the rest of
// the same screen reads. It is the last member of the family the last four
// ticks closed — `projects_screen` lost rows to a late success, the
// notification centre lost rows *and* its pip, and `worker_home_screen`'s
// header read got the same guard in its sibling screen.
//
// Two races, one cause: a read that is no longer the current one still gets to
// write.
//
//   read 2  09:00  «تحديث» tapped, `/portfolio` answers **4 rows**, held on a
//                     slow uplink before the screen's `setState`
//   write   09:01  an upload lands: the server now holds 5, the app installs 5
//   read 2  09:02  lands LAST and installs its 4 → the photo he uploaded *and
//                     the server confirmed* is gone from his grid, and the
//                     allowance recomputes off 4/5 into «بقيت صورة» — the app
//                     offering a sixth slot to a contractor whose plan is
//                     already spent
//
// The add path is reachable while read 2 is in flight, and that is written
// down rather than assumed. The appBar's «تحديث» is `onPressed: _loading ?
// null : _load`, so it cannot fire a *second* read — but that is a gate on the
// button, not on the screen: the body renders on `_settled`
// (`_worker != null || !_loading`), which is deliberately true while a re-read
// is parked precisely so a refresh does not throw the contractor's own work
// away. So the add tile and `portfolio-add` stay live during the parked read,
// and `_addPhoto` is gated on `_busy`, never on `_loading`. A weak uplink with
// one photo going up and a «تحديث» going down is ordinary use, not a corner.
//
// The allowance half is the expensive one. `_loadAllowance` is not handed the
// rows it read — it is handed `images.length` from the `setState` above it, so
// the count the plan shows comes from whatever gallery was installed **last**.
// A gate computed from a guess is how a paid contractor gets locked out of a
// gallery that has room, and that rule is written on [_allowance] itself. The
// post-write `_settleUnconfirmed` path already got this right — it recomputes
// from `fresh.length` — so this screen holds two rules about the same number.
//
// The test parks read 2 on a `Completer` and releases it only after the upload
// has installed its photo, so the late read is genuinely late rather than a
// second call to the same mock.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';

/// The URL the upload returns. A retry would upload under a *new* key, which is
/// why this is one constant rather than a generated name.
const String uploaded = 'https://r2.test/portfolio/room-1.jpg';

/// The four rows the server held before the upload.
List<String> get beforeUpload => <String>[
      for (var i = 0; i < 4; i++) 'https://r2.test/p$i.jpg',
    ];

/// The five rows the server holds after it.
List<String> get afterUpload => <String>[...beforeUpload, uploaded];

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: <String, String>{'content-type': 'application/json'});

/// The platform, with the **gallery read** individually parkable so a test can
/// make a read land *after* a write rather than merely after another read.
///
/// Note the GET and the registration POST share one path
/// (`/api/mobile/workers/7/portfolio`), so the method is what separates them —
/// a path-only branch made the write "land" without a POST ever being attempted,
/// which is the same fixture-shape trap `worker_home_pull_to_refresh_test.dart`
/// records for its own mock.
class _Platform {
  /// When set, the **next** gallery GET parks until this completes.
  Completer<void>? gate;

  int galleryReads = 0;
  int registrations = 0;
  int uploads = 0;

  /// Whether the server already holds the uploaded row. False until the
  /// registration POST has answered, so a read issued before the write
  /// genuinely cannot know about it.
  bool hasUpload = false;

  ApiClient build() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (req.method == 'POST' && p.endsWith('/portfolio')) {
            registrations++;
            hasUpload = true;
            return _json(<String, Object?>{'ok': true});
          }
          if (p.endsWith('/portfolio')) {
            galleryReads++;
            // Parked **before** the answer is taken, so a read issued while the
            // server already holds five rows still reports the four it would
            // have had when it was asked. That is what makes the late answer
            // stale rather than merely late.
            final rows = hasUpload ? afterUpload : beforeUpload;
            final held = gate;
            if (held != null) await held.future;
            return _json(<Object>[
              for (final u in rows) <String, Object>{'image_url': u},
            ]);
          }
          if (p.endsWith('/api/login')) {
            return _json(<String, Object?>{
              'token': 'tok',
              'user': <String, Object?>{
                'id': 31,
                'phone': '0773000000',
                'email': null,
                'full_name': 'مقاول تجربة',
                'type': 'worker',
                'avatar_url': null,
                'wilaya': '16',
                'commune': null,
                'created_at': '2026-09-11 20:00:00',
              },
            });
          }
          if (p.endsWith('/api/unread')) return _json(0);
          if (p.contains('/my/profile')) {
            return _json(<String, Object?>{
              'id': 7,
              'user_id': 31,
              'full_name': 'مقاول تجربة',
              'specialties': <Object?>['دهان'],
              'experience_years': 5,
            });
          }
          if (p.contains('/subscription')) {
            return _json(<String, Object?>{
              'currency': 'DZD',
              'note_ar': '',
              'commission_percent': 0,
              'commission_per_order': 0,
              'plans': <Object?>[],
              'current': <String, Object?>{
                'plan': 'free_trial',
                'name_ar': 'الخطة المجانية',
                'status': 'active',
                'starts_at': '2026-09-01 00:00:00',
                'expires_at': null,
                'quote_limit': 3,
                'portfolio_limit': 5,
                'quotes_used_this_month': 0,
              },
            });
          }
          return _json(<Object>[]);
        }),
      );
}

/// `uploadDocument` is a `MultipartRequest` and constructs its own `HttpClient`,
/// so a `MockClient` never sees it — the seam every write-path case in this
/// repo uses, established in `portfolio_write_outcome_test.dart`. Only the
/// upload is stubbed; the registration POST and the re-read go through the real
/// transport, because "the screen handles an object" is not the claim.
class _RepoWithFakeUpload extends Repository {
  _RepoWithFakeUpload(super.api, this._platform);

  final _Platform _platform;

  @override
  Future<String> uploadDocument(File file) async {
    _platform.uploads++;
    return uploaded;
  }
}

void main() {
  testWidgets(
      'a late re-read does not delete a photo a landed upload just installed',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final platform = _Platform();
    final api = platform.build();
    final auth = AuthState(api);
    await auth.login(phone: '0773000000', password: 'secret123');

    const picker = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, (call) async {
      if (call.method == 'pickImage') return '/tmp/does-not-matter.png';
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null));

    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: MyPortfolioScreen(
          repo: _RepoWithFakeUpload(api, platform),
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Guard the guard: the first load must actually have rendered, or every
    // assertion below is vacuously true.
    expect(find.text('4 صور في معرض أعمالك'), findsOneWidget,
        reason: 'the fixture must render the four rows it returned');

    // Park the gallery read the refresh is about to issue. The rows are
    // captured at *issue*, while the server still holds four.
    final parked = Completer<void>();
    platform.gate = parked;
    await tester.tap(find.byTooltip('تحديث'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.galleryReads, 2,
        reason: 'the refresh must have issued its read before the upload');
    expect(find.text('4 صور في معرض أعمالك'), findsOneWidget,
        reason: 'a parked re-read must not blank a gallery that was working');

    // While that read is in flight, the contractor adds a photo. The add tile is
    // live during a re-read by design — see [_settled].
    await tester.tap(find.byKey(const Key('portfolio-add')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.text('من معرض الصور'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(platform.uploads, 1, reason: 'the upload never happened');
    expect(platform.registrations, 1,
        reason: 'the registration was never attempted');
    expect(find.text('5 صور في معرض أعمالك'), findsOneWidget,
        reason: 'a landed upload must be on screen before the race resolves');

    // The write is done and the server holds five. Now the parked read answers —
    // with the four rows it captured when it was issued.
    parked.complete();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('5 صور في معرض أعمالك'), findsOneWidget,
        reason: 'the late read installed 4 rows over a gallery of 5, deleting '
            'the photo that just landed and the server confirmed');
    // **The allowance, which is the expensive half.** It is not handed the rows
    // it read — it is handed `images.length` from the `setState` above it — so
    // the count the plan shows comes from whatever gallery was installed last.
    //
    // The server holds five photos against a five-photo plan, so the honest
    // answer is that the gallery is **full**: the add tile goes and the limit is
    // named. The stale gallery was four, which computes as «بقيت صورة» — the
    // app offering a fifth slot to a contractor who has already spent it. That
    // is the money claim, and it is what the red run printed over a grid the
    // contractor could see was full.
    expect(find.text('بلغت حد صور خطتك: 5 صور'), findsWidgets,
        reason: 'five photos on a five-photo plan is a full gallery, whatever '
            'the stale read said');
    expect(find.text('بقيت صورة من 5 صور في خطتك'), findsNothing,
        reason: 'the allowance was recomputed from the superseded gallery, so '
            'the app offered a slot the plan had already spent');
    expect(find.byKey(const Key('portfolio-add')), findsNothing,
        reason: 'a full plan must stop offering the upload');
    expect(find.byKey(const Key('portfolio-full')), findsOneWidget,
        reason: 'a missing add control with no explanation is a broken screen');
    expect(find.byKey(const Key('stale-gallery')), findsNothing,
        reason: 'a read that landed is not a failed read');
    expect(tester.takeException(), isNull);
  });
}
