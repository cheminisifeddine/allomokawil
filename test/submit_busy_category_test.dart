// The publish form let a customer empty the required trade list *while the
// photo upload was in flight*, and the send line then crashed the submit.
//
// `_submit` checks `_categories.isEmpty` **once**, at the top — and that check
// is correct. It is not, however, the value that is sent. Three steps later,
// after `await _repo.uploadDocument(...)` has run for however long the phone's
// upload takes, the form sends `category: _categories.first`.
//
// `_categories` is a plain `Set<String>` that the trade grid mutates in
// `onToggle`, and that grid is **not** disabled while `_busy` — only the
// publish button is (`loading: _busy` → `onPressed: null`). So a customer who
// taps a trade, taps «نشر المشروع», and then tidies up their selection by
// tapping that same trade again has deselected the last one, and the send line
// runs `Set.first` on an empty set.
//
// That raises `Bad state: No element`, an `Error` — and `errorCopy` has no arm
// for it either way, so the customer is told «حدث خطأ غير متوقع. أعد المحاولة،
// وإن تكرّر الأمر أغلق التطبيق وافتحه من جديد» — "close the app" — about a form
// that was valid, whose text and numbers are all still on screen. On the
// **edit** path the same throw happens after the PATCH is built, so a project
// the customer edited silently does not update while the app blames their
// phone.
//
// The rule pinned here: **the values that are sent are captured before the
// first `await`.** The form stays editable for the whole write on purpose —
// an upload can take ten seconds, and a user who cannot touch a form for ten
// seconds assumes it has frozen — so the write has to be built from the values
// the form held when it was submitted, which is the set the user approved.
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
import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _pickerChannel = MethodChannel('plugins.flutter.io/image_picker');

/// The URL a successful upload hands back.
const uploaded = 'https://r2.test/projects/bathroom-1.jpg';

String _onePixelPng(String name) {
  final dir = Directory.systemTemp.createTempSync('am_busy');
  final f = File('${dir.path}/$name.png');
  f.writeAsBytesSync(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x0A,
    0x49, 0x44, 0x41, 0x54, 0x78, 0x63, 0x60, 0x00, 0x00, 0x00, 0x02, 0x00,
    0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00,
  ]);
  return f.path;
}

/// Every request the app makes, in order — the body is the evidence.
final sent = <({String method, String path, Map<String, dynamic> body})>[];

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );

/// The app's own [Repository] with **one** method replaced.
///
/// `Repository.uploadDocument` is a `MultipartRequest`, and that request builds
/// its own `HttpClient` instead of the one handed to [ApiClient], so a
/// `MockClient` can never see an upload however the test is wired. The upload
/// is stubbed and nothing else: the login and the project POST go through the
/// real transport, which is what makes the POST body the evidence.
class _SlowUploadRepo extends Repository {
  _SlowUploadRepo(super.api);

  /// Completed when the upload is *entered* — the form is provably mid-write.
  final entered = Completer<void>();
  /// Held open by the test to keep the write parked inside the upload.
  final release = Completer<void>();
  int uploads = 0;

  @override
  Future<String> uploadDocument(File file) async {
    uploads++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return uploaded;
  }
}

Future<({ApiClient api, AuthState auth, _SlowUploadRepo repo})> _boot() async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (req.body.isNotEmpty) {
        try {
          sent.add((
            method: req.method,
            path: p,
            body: jsonDecode(req.body) as Map<String, dynamic>,
          ));
        } catch (_) {
          // Not JSON — not a body this test cares about.
        }
      }
      if (p.endsWith('/api/login')) {
        return _json({
          'token': 'tok',
          'user': {
            'id': 30,
            'phone': '0773000000',
            'email': null,
            'full_name': 'زبون تجربة',
            'type': 'customer',
            'avatar_url': null,
            'wilaya': '16',
            'commune': null,
            'created_at': '2026-09-13 08:00:00',
          },
        });
      }
      if (p.endsWith('/unread')) return _json({'unread': 0});
      if (p.contains('/projects')) {
        return _json({
          'id': 'p-1',
          'customer_id': 30,
          'title': 'ترميم فيلا',
          'description': null,
          'category': 'painting',
          'images': <String>[],
          'wilaya': '16',
          'commune': null,
          'budget_min': null,
          'budget_max': null,
          'urgency': 'flexible',
          'status': 'open',
          'selected_worker_id': null,
          'created_at': '2026-09-13 08:00:00',
          'updated_at': '2026-09-13 08:00:00',
        });
      }
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth, repo: _SlowUploadRepo(api));
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 260,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Mounts the real publish screen with the three required fields filled, and
/// one photo attached so the submit has an `await` to park in.
Future<void> _mount(WidgetTester tester,
    ({ApiClient api, AuthState auth, _SlowUploadRepo repo}) boot,
    {Project? initial}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pickerChannel, (call) async {
    if (call.method == 'pickMultiImage') return <String>[_onePixelPng('p0')];
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pickerChannel, null));

  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(AppScope(
    api: boot.api,
    auth: boot.auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: ProjectNewScreen(repo: boot.repo, initial: initial),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  if (initial == null) {
    await tester.enterText(find.byType(TextField).first, 'ترميم فيلا');
    await tester.tap(find.byType(SelectableTile).first);
    await tester.pump();
  }

  final wilayaField = find.text('اختر الولاية');
  if (wilayaField.evaluate().isNotEmpty) {
    await _reveal(tester, wilayaField);
    await tester.tap(wilayaField);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(TextField)),
      '16',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('الجزائر').first);
    await tester.pump(const Duration(milliseconds: 300));
  }

  // The photo, so `_submit` must upload before it can send.
  await _reveal(tester, find.text('أضف صورة'));
  final addTile = find
      .ancestor(of: find.text('أضف صورة'), matching: find.byType(InkWell))
      .first;
  await tester.tap(addTile);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Finder _publish() => find.text('نشر المشروع');

/// How many trade tiles the grid currently shows as selected.
///
/// Read off the widget tree rather than assumed from the tap: a tap that
/// misses an off-screen tile is a warning, not a failure, and a test built on
/// one would go green without ever reaching the defect it names.
int _selectedCount(WidgetTester tester) => tester
    .widgetList<SelectableTile>(find.byType(SelectableTile))
    .where((t) => t.selected)
    .length;

void main() {
  setUp(sent.clear);

  testWidgets('sanity: the form reaches the send line fully filled',
      (tester) async {
    final boot = await _boot();
    await _mount(tester, boot);
    expect(_publish(), findsOneWidget);
    expect(find.text('صور المشروع'), findsOneWidget);
  });

  testWidgets('a trade deselected during the upload does not break the send',
      (tester) async {
    final boot = await _boot();
    await _mount(tester, boot);

    // Tap publish. The write parks inside the upload.
    await tester.tap(_publish());
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(boot.repo.uploads, 1, reason: 'the submit reached the upload');

    // The form is live for the whole write — only the button is disabled. The
    // customer scrolls back up and tidies up their selection: the same trade,
    // tapped again. `ensureVisible` first, because a tap that misses the tile
    // would leave the set populated and this test would pass without ever
    // reaching the defect.
    await _reveal(tester, find.byType(SelectableTile).first);
    await tester.tap(find.byType(SelectableTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // The tile really was hit: `warnIfMissed` would have fired above otherwise,
    // and the tile now reads as unselected.
    expect(_selectedCount(tester), 0,
        reason: 'the last trade was deselected during the upload');

    // Let the upload finish so the send line runs.
    boot.repo.release.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The bug being fixed: `_categories` is empty and the send line read
    // `_categories.first`, so nothing was posted and the user was told to close
    // the app.
    final post = sent.where((r) => r.path.endsWith('/api/mobile/projects'));
    expect(post, hasLength(1),
        reason: 'the project must be posted exactly once');
    expect(post.first.body['category'], isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the edit path sends the values the form held when save was '
      'pressed, not the ones on screen when the PATCH left', (tester) async {
    final boot = await _boot();
    final project = Project(
      id: 'p-1',
      customerId: 30,
      title: 'ترميم فيلا',
      category: 'painting',
      wilaya: '16',
      status: ProjectStatus.open,
      urgency: UrgencyLevel.flexible,
      images: <String>[],
    );
    await _mount(tester, boot, initial: project);

    // The save button reads «احفظ التعديل» on this path.
    final save = find.text('احفظ التعديل');
    expect(save, findsOneWidget, reason: 'sanity: the edit CTA is on screen');

    // Scroll back to the title and type a new one, then save and immediately
    // retype — the PATCH must carry what was on screen at the press.
    await _reveal(tester, find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'ترميم فيلا بالورق');
    await tester.pump();

    await tester.tap(save);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(boot.repo.uploads, 1, reason: 'the save reached the upload');

    // The user keeps typing while the photo is still going up.
    await _reveal(tester, find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'عنوان لم يُضغط بعد');
    await tester.pump();

    boot.repo.release.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final patch = sent.where(
        (r) => r.method == 'PATCH' && r.path.contains('/projects/p-1'));
    expect(patch, hasLength(1), reason: 'the project must be patched once');
    expect(patch.first.body['title'], 'ترميم فيلا بالورق',
        reason: 'the PATCH must carry the title the user pressed save for, '
            'not the one they typed into a form that had already left');
  });

  testWidgets('a trade added during the upload is not silently sent',
      (tester) async {
    final boot = await _boot();
    await _mount(tester, boot);

    final first = Taxonomy.categories[0].slug;

    await tester.tap(_publish());
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(boot.repo.uploads, 1);

    // Add a second trade *while* the write is in flight.
    await _reveal(tester, find.byType(SelectableTile).at(1));
    await tester.tap(find.byType(SelectableTile).at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_selectedCount(tester), 2,
        reason: 'a second trade was really added during the upload');

    boot.repo.release.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final post = sent.where((r) => r.path.endsWith('/api/mobile/projects'));
    expect(post, hasLength(1));
    // What the user saw when they pressed publish is what is sent. Adding a
    // trade mid-write must not silently change the project being written.
    expect(post.first.body['category'], first);
    expect(post.first.body['categories'], [first]);
  });
}
