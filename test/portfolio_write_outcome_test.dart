// Proves the seventh write got the contract the other six already had.
//
// `S.errWriteUnconfirmed` is «...تحقّق من القائمة قبل إعادة المحاولة» and six
// write screens answer it by re-reading the server. The portfolio add did
// not: one `catch` served the whole send, so an unconfirmed write was reported
// as «تعذّر رفع الملف» — a claim about the *upload* when the upload had
// returned a URL and it was the registration that never answered.
//
// The cost is not the sentence, it is the instruction inside it. «أعد المحاولة»
// re-uploads the same room under a new R2 key and registers a second row, and
// each row spends one of the plan's `portfolio_limit` slots, so a contractor
// who retries a photo he already has discovers his gallery «full» with half
// the work missing.
//
// Two halves, because a rule nothing is wired to passes clean:
//  * the predicate and the probe, pure and therefore testable without a
//    widget — including the decoy the chat audit taught us to look for;
//  * the screen, driven over a real `image_picker` channel and a real stalled
//    POST, because "the screen asks the question at all" is not a property of
//    the helper.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/l10n/write_outcome.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/portfolio_write_outcome.dart';
import 'package:allomokawil/src/data/photo_count_copy.dart';
import 'package:allomokawil/src/data/stale_gallery_copy.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';

/// The key the upload returned. Every test names a different one, so a
/// comparison that always answers true cannot pass by reusing a fixture.
const String uploaded = 'https://r2.test/portfolio/room-1.jpg';


/// The two taps a contractor makes to add a photo from his phone: the add tile,
/// then the sheet's gallery option.
///
/// Shared so a case that drives the add itself drives the **same** taps this
/// helper does — a second copy of these two lines is a third thing that can
/// drift from the button key the screen actually draws.
Future<void> _tapAddFromGallery(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('portfolio-add')));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.tap(find.text('من معرض الصور'));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: <String, String>{'content-type': 'application/json'});

/// The band's own sentence, read off the keyed `Text` so the claim is about the
/// tree and not about a `find.text` guess.
///
/// The key is the one `_StaleGalleryBanner` draws its line with, so this reads
/// the same widget the contractor reads.
String? _bandLine(WidgetTester tester) {
  final found = find.byKey(const Key('stale-gallery-line'));
  if (found.evaluate().isEmpty) return null;
  return tester.widget<Text>(found).data;
}

/// The app's own [Repository], with **one** method replaced.
///
/// `Repository.uploadDocument` is a `MultipartRequest`, and that request builds
/// its own `HttpClient` instead of the one handed to [ApiClient] — so a
/// `MockClient` cannot see the upload no matter how the test is wired. This
/// was established the hard way: three runs failed with the registration never
/// attempted and a mock log that showed the login and the profile reads and
/// nothing else, and the loopback-server alternative deadlocks inside
/// `TestWidgetsFlutterBinding`'s fake-async zone.
///
/// So the upload is stubbed and **nothing else is**. The registration POST
/// and the gallery re-read go through the real transport, which is what
/// produces the `errWriteUnconfirmed` under test — a hand-thrown exception
/// would have proved the screen handles an object, not that the failure
/// reaches it.
///
/// [uploadFails] selects the other half of the defect: the *upload* is what
/// never answers, so no URL ever exists.
class _RepoWithFakeUpload extends Repository {
  _RepoWithFakeUpload(super.api, {this.uploadFails = false});

  final bool uploadFails;

  @override
  Future<String> uploadDocument(File file) async {
    if (uploadFails) {
      // What the transport layer actually throws for a POST whose answer
      // never arrived: `ApiException` carrying `S.errWriteUnconfirmed`, which
      // is the exact shape `isWriteUnconfirmed` matches on.
      throw ApiException(S.errWriteUnconfirmed);
    }
    return uploaded;
  }
}

void main() {
  group('portfolioHolds', () {
    test('a gallery holding the exact URL is my photo', () {
      expect(portfolioHolds(<String>['https://r2.test/a.jpg', uploaded], uploaded),
          isTrue);
    });

    test('a gallery without it is not', () {
      expect(portfolioHolds(<String>['https://r2.test/a.jpg'], uploaded), isFalse);
      expect(portfolioHolds(const <String>[], uploaded), isFalse);
    });

    // The decoy: a retry of one picture uploads it again under a NEW key, so
    // the gallery legitimately holds a *different* URL for the same room. A
    // predicate that matched loosely — a tail, a prefix, a path without the
    // bucket — would call the retry a landing and leave the contractor with two
    // rows and two plan slots spent on one photo. This is the same trap the
    // chat outbox fell into, one layer up.
    test('another copy of the same picture is not this one', () {
      // Every suffix and every substring of a real R2 key, in the shapes a
      // loose comparison would accept. The earlier version of this decoy only
      // shared a *prefix* with the real key, and a predicate mutated to match
      // on a substring passed all thirteen tests — a green test that proved
      // nothing. A decoy has to be indistinguishable from the real thing to
      // everything except the rule.
      for (final decoy in const <String>[
        'https://r2.test/portfolio/room-1-copy.jpg', // a retry's new key
        'https://r2.test/portfolio/room-1.jpg.bak', // this key, suffixed
        'https://cdn.test/portfolio/room-1.jpg', // another host, same key
        'room-1.jpg', // the bare key
        '1.jpg', // a tail match on a shorter, unrelated key
        'room-',
        '.jpg',
      ]) {
        expect(portfolioHolds(<String>[decoy], uploaded), isFalse,
            reason: 'a loose match let the decoy through: $decoy');
      }
      // And the reverse direction: my photo being a *prefix* of a stranger's
      // is equally not mine.
      expect(
        portfolioHolds(<String>['https://r2.test/portfolio/room-1.jpg.extra'],
            uploaded),
        isFalse,
      );
    });

    // No URL means no name. A photo whose upload never answered has, by
    // construction, no row on the server: the row is written carrying the URL
    // the upload produced. Answering true here would draw a tile for a photo
    // nobody can see, which disappears on the next refresh.
    test('a photo with no URL is never in the gallery', () {
      expect(portfolioHolds(<String>[uploaded], null), isFalse);
      expect(portfolioHolds(<String>[uploaded], ''), isFalse);
    });

    test('an empty or null gallery holds nothing', () {
      expect(portfolioHolds(const <String>[], uploaded), isFalse);
    });
  });

  group('resolvePortfolioWriteOutcome', () {
    test('the URL is in the fresh gallery: the write landed', () async {
      final r = await resolvePortfolioWriteOutcome(
        uploadedUrl: uploaded,
        fetch: () async => <String>['https://r2.test/old.jpg', uploaded],
      );
      expect(r.outcome, WriteOutcome.landed);
      // The list comes back with the verdict, so the screen can put the
      // server's own gallery on screen rather than a local guess.
      expect(r.gallery, isNotNull);
      expect(r.gallery, contains(uploaded));
    });

    test('the fresh gallery has no such URL: the write is missing', () async {
      final r = await resolvePortfolioWriteOutcome(
        uploadedUrl: uploaded,
        fetch: () async => <String>['https://r2.test/old.jpg'],
      );
      expect(r.outcome, WriteOutcome.missing);
      expect(r.gallery, isNotEmpty);
    });

    // The phone is still offline. This is NOT proof the write failed, and the
    // gallery must be null so the screen cannot draw a list it invented.
    test('a re-read that fails is unknown, never missing', () async {
      final r = await resolvePortfolioWriteOutcome(
        uploadedUrl: uploaded,
        fetch: () async => throw StateError('offline'),
      );
      expect(r.outcome, WriteOutcome.unknown);
      expect(r.gallery, isNull);
    });

    test('a re-read with no URL on either side is missing, not landed', () async {
      final r = await resolvePortfolioWriteOutcome(
        uploadedUrl: null,
        fetch: () async => <String>['https://r2.test/old.jpg'],
      );
      expect(r.outcome, WriteOutcome.missing);
    });
  });

  group('on the real screen', () {
    /// Renders [MyPortfolioScreen] against a server where the **registration
    /// POST** times out while the **upload** succeeds, and [after] decides what
    /// the gallery read answers.
    ///
    /// The stall is on the POST *after* the upload, not a fake 500: a 5xx
    /// decodes to `errServer` and correctly skips the re-read, and an upload
    /// that fails for real is the other half of the defect. Only the ambiguous
    /// middle — file in R2, row not answered — reaches this screen's new code.
    /// Renders [MyPortfolioScreen] against a server where the **registration
    /// POST** times out while the **upload** succeeds, and [after] decides what
    /// the gallery read answers.
    ///
    /// The stall is on the POST *after* the upload, not a fake 500: a 5xx
    /// decodes to `errServer` and correctly skips the re-read, and an upload
    /// that fails for real is the other half of the defect. Only the ambiguous
    /// middle — file in R2, row not answered — reaches this screen's new code.
    ///
    /// The repository is injected rather than built from `AppScope` because
    /// `uploadPhoto` is a `MultipartRequest`, which constructs its own
    /// `HttpClient` and never touches the `httpClient` given to [ApiClient].
    /// That cost this file three false failures — `uploads == 0` and
    /// `posts == 0` with a perfectly healthy mock log — before it was
    /// established: the multipart bypasses `MockClient` outright, and a real
    /// loopback socket instead deadlocks inside `TestWidgetsFlutterBinding`'s
    /// fake-async zone. `MyPortfolioScreen.repo` is the seam, and it is the
    /// same one `ReviewScreen` already had.
    Future<({List<String> said, int posts, int reads})> stalledRegistration(
      WidgetTester tester, {
      required List<String> Function(int read) after,
      bool stallUpload = false,
      DateTime Function()? clock,
      Set<int> failingReads = const <int>{},
      bool addFlow = true,
    }) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      var reads = 0;
      var posts = 0;
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (req.method == 'POST' && p.endsWith('/portfolio')) {
            posts++;
            // The POST must outlast the client's own patience, so the failure
            // is ambiguous rather than a refusal.
            await Future<void>.delayed(const Duration(milliseconds: 120));
            return _json(<String, Object?>{'ok': true});
          }
          if (p.endsWith('/portfolio')) {
            reads++;
            // A **5xx**, not a stall: this is the «تحديث» that fails on hotel
            // wifi, which is a refusal the app can name, so it takes the
            // `_load()` catch and raises the band. Distinct from the stalled
            // POST below, which is the ambiguous write that reaches the
            // recheck.
            if (failingReads.contains(reads)) {
              return http.Response('boom', 500,
                  headers: <String, String>{'content-type': 'text/plain'});
            }
            return _json(<Object>[
              for (final u in after(reads)) <String, Object>{'image_url': u},
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
        timeout: const Duration(milliseconds: 25),
      );

      final auth = AuthState(api);
      await auth.login(phone: '0773000000', password: 'secret123');

      // The real picker channel, so `_pickAndUpload` is driven as a user drives
      // it rather than by calling a private method. Returns a path that does
      // not exist: the upload never opens a file through this client, and a
      // real fixture would only make the test look more real than it is.
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
            repo: _RepoWithFakeUpload(api, uploadFails: stallUpload),
            clock: clock,
          ),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The add button, then the sheet's gallery option — the two taps a
      // contractor makes. Skippable because a case that needs a read to land
      // *between* the load and the add (a failing «تحديث») has to spend those
      // reads itself, in that order, and this helper issues the add on the way
      // out.
      if (addFlow) await _tapAddFromGallery(tester);

      return (
        said: <String>[
          ...tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? ''),
          ...tester
              .widgetList<SnackBar>(find.byType(SnackBar))
              .map((s) => (s.content as Text).data ?? ''),
        ],
        posts: posts,
        reads: reads,
      );
    }

    testWidgets('a photo that landed is reported landed, not lost',
        (tester) async {
      // First read: empty (the screen's own load). The re-read after the
      // stalled POST finds the photo — the server did register it.
      final r = await stalledRegistration(
        tester,
        after: (read) => read <= 1 ? const <String>[] : <String>[uploaded],
      );
      final said = r.said;

      // The screen must have asked. Both halves of that are asserted: a
      // verdict rendered from a screen that never re-read would be a
      // coincidence, and this harness is the only thing that can tell.
      expect(r.posts, 1, reason: 'the registration was never attempted');
      expect(r.reads, greaterThanOrEqualTo(2),
          reason: 'the gallery was never re-read after the stalled write');
      expect(said, contains(S.writeUnconfirmedLanded),
          reason: 'the photo was on the server and the app called it a loss: $said');
      // The old sentence claimed the file never uploaded. It did.
      expect(said, isNot(contains(S.errUpload)));
    });

    testWidgets('a photo that is genuinely missing says so', (tester) async {
      final r = await stalledRegistration(
        tester,
        after: (_) => const <String>[],
      );
      final said = r.said;

      expect(r.reads, greaterThanOrEqualTo(2),
          reason: 'the gallery was never re-read after the stalled write');
      expect(said, contains(S.writeUnconfirmedMissing),
          reason: 'the re-read found nothing and the app did not say so: $said');
    });

    // The half the fix exists for. Re-uploading the same room produces a new
    // URL; if the predicate matched loosely the re-read would call that copy
    // this one, the screen would say «arrived», and the gallery would hold a
    // row for a picture that is not on it.
    testWidgets('a second copy of the same picture is not called landed',
        (tester) async {
      final r = await stalledRegistration(
        tester,
        after: (read) => read <= 1
            ? const <String>[]
            : <String>['https://r2.test/portfolio/room-1-copy.jpg'],
      );
      final said = r.said;

      expect(r.reads, greaterThanOrEqualTo(2),
          reason: 'the gallery was never re-read after the stalled write');
      expect(said, contains(S.writeUnconfirmedMissing),
          reason: 'a different URL was accepted as this photo: $said');
      expect(said, isNot(contains(S.writeUnconfirmedLanded)));
    });

    // The upload itself is what never answered. There is no URL to ask about,
    // so «تحقّق من القائمة» is unfollowable and a landed verdict is impossible.
    // What must NOT happen is the old claim that the file did not upload while
    // the transport layer is the one saying it might have.
    // ---- the stamp outlives the rows it dates, and then lies about them ----
    //
    // The predicate this pins is not in this file's helper and not in the
    // verdict — both of those are correct, and both are covered above. It is in
    // the **state a re-read leaves behind when it lands.**
    //
    // `_settleUnconfirmed` exists to answer «did that photo reach my profile?».
    // To answer it honestly it puts **the server's own rows** on screen — the
    // whole point of a re-read is that the grid it already had cannot prove
    // anything. And that is where the stamp is lost: `_readAt` is written in
    // exactly one place in this screen, the success path of `_load()`, and
    // `_settleUnconfirmed` is not that path. It writes `_images`, the run
    // counter and the plan's count, and it leaves `_readAt` describing a
    // gallery that is no longer on the screen.
    //
    // The band itself is fine in the middle of this — `_addPhoto` clears
    // `_error` when the write starts, so the band is withdrawn and the fresh
    // grid is drawn clean. Nothing is false at that moment; the band is simply
    // not there. The false claim arrives on the **next** failure, which is the
    // ordinary one:
    //
    //   1. the gallery loads at 09:48 — `_readAt` = 09:48, three photos;
    //   2. a «تحديث» fails — the band appears, correctly dating those photos;
    //   3. the contractor adds a photo, the registration stalls, and the
    //      re-read **lands** — `_settleUnconfirmed` installs the server's four
    //      rows. The band is withdrawn. `_readAt` is still 09:48;
    //   4. another «تحديث» fails at 12:30 — the band comes back, and now it is
    //      drawn over a grid that was read at 11:55 while the band says 09:48.
    //
    // Step 4 is the defect, and it is worse than printing no age at all, because
    // «these photos are from 09:48» is a **specific** claim about **these**
    // rows and it is false: the grid under it is the 11:55 re-read. On this
    // screen an age is a *commercial* claim, not a convenience — the whole
    // reason the band exists is that a contractor deciding whether to spend his
    // evening re-uploading everything is reading it as evidence about the
    // pictures in front of him. Here it is evidence about a set of pictures
    // that has been gone for two hours.
    //
    // So the rule is the one this screen's own comment already states, and the
    // one `projects_screen.dart` puts in one sentence: **rows, and the stamp
    // that dates them, are one fact.** Every write that installs fresh rows
    // writes the stamp in the same `setState` that installs them, because a
    // stamp older than the rows it dates is a stamp about a gallery that is
    // gone.
    testWidgets('a re-read that lands re-stamps the rows it installs',
        (tester) async {
      // Three reads, in the order the screen issues them, and the two ages they
      // imply are deliberately far apart («2 ساعتين» against «35 دقيقة») so a
      // predicate that took the wrong one cannot be mistaken for the right one.
      //
      // Read 1 is the screen's own load and stamps `_readAt`. Read 2 is the
      // re-read after the stalled write, and it answers with the four rows the
      // server holds. Read 3 is the «تحديث» that fails and raises the band.
      final readAt = DateTime(2026, 10, 4, 9, 48);
      final recheckAt = DateTime(2026, 10, 4, 11, 55);
      final refreshAt = DateTime(2026, 10, 4, 12, 30);
      var now = readAt;
      final three = <String>[
        'https://r2.test/portfolio/a.jpg',
        'https://r2.test/portfolio/b.jpg',
        'https://r2.test/portfolio/c.jpg',
      ];

      await stalledRegistration(
        tester,
        clock: () => now,
        addFlow: false,
        failingReads: const <int>{3},
        after: (read) => read == 1 ? three : <String>[...three, uploaded],
      );

      // --- step 2 and 3: the write stalls, and the re-read lands ---
      //
      // The clock moves **before** the add, because the re-read settles when
      // the POST's answer is chased — 11:55 is what «when the server's rows
      // arrived» means. Stamping afterwards would date a read already composed.
      now = recheckAt;
      await _tapAddFromGallery(tester);

      expect(
        find.textContaining(portfolioCountLineAr(4)),
        findsOneWidget,
        reason: 'the re-read did not install the server\'s own rows, so the '
            'case is not reaching the state it claims',
      );

      // --- step 4: the refresh that raises the band again ---
      now = refreshAt;
      await tester.tap(find.byTooltip('تحديث'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(
        find.byKey(const Key('stale-gallery')),
        findsOneWidget,
        reason: 'the failed refresh did not raise the band, so the case under '
            'test is not the state it claims',
      );

      // The band must date the re-read — 11:55 — and not the load that preceded
      // it. Both ages are asserted so a band that printed *neither* cannot pass.
      final ageOfRecheck = staleGalleryAgeAr(recheckAt, now: refreshAt);
      final ageOfLoad = staleGalleryAgeAr(readAt, now: refreshAt);
      expect(ageOfRecheck, isNotEmpty,
          reason: 'the fixture is wrong, not the app: a clock 35 minutes past '
              'the stamp must produce an age to assert');
      expect(ageOfLoad, isNot(ageOfRecheck),
          reason: 'the fixture is wrong, not the app: both stamps produce the '
              'same sentence, so this case cannot tell them apart');
      expect(
        _bandLine(tester),
        contains(ageOfRecheck),
        reason: 'the band is dating the load\'s rows over a grid the re-read '
            'replaced. Every read here answered HTTP 200 except the last, so '
            'nothing in the band can notice the rows moved — which is exactly '
            'why the stamp has to travel with them. Band was: '
            '${_bandLine(tester)}',
      );
      expect(
        _bandLine(tester),
        isNot(contains(ageOfLoad)),
        reason: 'the band is reporting the age of a gallery that is no longer '
            'on the screen',
      );
    });

    testWidgets('an unconfirmed upload says the upload, not a re-read',
        (tester) async {
      final r = await stalledRegistration(
        tester,
        after: (_) => const <String>[],
        stallUpload: true,
      );
      final said = r.said;

      // The upload never answered, so nothing was registered: no photo name
      // ever existed, so posting a registration for it would be filing a row
      // that points at nothing.
      expect(r.posts, 0,
          reason: 'a registration was posted for an upload that never answered');
      expect(said, contains(S.errUpload),
          reason: 'the upload never answered and the app did not say so: $said');
      // A landed verdict here would be a claim about a photo with no name.
      expect(said, isNot(contains(S.writeUnconfirmedLanded)));
    });
  });
}
