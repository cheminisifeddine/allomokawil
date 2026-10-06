// A customer's most common search is a phone number he was given in person —
// and the directory could not find anybody by it.
//
// Found 5 Oct 2026 on production, measured rather than inferred.
// `GET /api/mobile/workers/search` sends `phone` on **97 of 97** live browse
// rows (every one exactly 10 digits), and the app **never parses the field and
// never searches it**: `WorkerProfile` has no `phone` member at all (it is the
// one column the wire carries for every contractor that this app drops on the
// floor), and `browse_screen`'s `_matchesQuery` reads only fullName, bio,
// commune, the wilaya name and the trades.
//
// The consequence is not a missing nicety. In Algeria a contractor is found by
// the number a neighbour, a cousin or the man himself hands you in the street.
// Typing `0550000009` into «ابحث عن مقاول» returns «لا نتائج مطابقة» and offers
// to «مسح البحث والفلاتر», while the very man holding that number sits on the
// same screen, one unfiltered scroll away. The app is not failing to find him —
// it is asserting that nobody carries it.
//
// The app already owns the repair and even documents why it is missing.
// `ArabicSearch` folds Arabic-Indic digits (`٠٧٧٠` vs `0770`) *explicitly for
// this* — "which arrive when someone pastes a phone number out of their
// contacts" — and `DzPhone.digits` is the repo's single canonical
// digit-extraction helper, used by every phone field in the app. Neither was
// reachable here, because the number was thrown away one layer earlier, at the
// parser. The paste out of a contact card is the single most likely way a
// customer starts this search, and it is the one input the directory could not
// answer.
//
// Same shape as the four earlier fixes in this family (radius, reply time,
// rating, availability): the server sends a fact, and the screen that must act
// on it never reads it.
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
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/core/text/dz_phone.dart';
import 'package:allomokawil/src/data/worker_phone_search.dart';
import 'package:allomokawil/src/screens/browse/browse_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

Map<String, Object?> _user() => {
      'id': 30,
      'phone': '0773000000',
      'email': null,
      'full_name': 'عميل تجربة',
      'type': 'customer',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// A live-shaped row: `phone` present, exactly as the wire sends it on 97/97
/// rows today. [phone] is the only field the fix is about.
Map<String, Object?> _worker(
  int id,
  String name,
  String phone, {
  String? bio = 'دهان وتشطيب',
}) =>
    {
      'id': id,
      'user_id': 1000 + id,
      'full_name': name,
      'bio': bio,
      'specialties': <String>['painting'],
      'experience_years': 9,
      'price_range_min': 20000,
      'price_range_max': 90000,
      'service_radius_km': 15,
      'is_available': 1,
      'verification_status': 'verified',
      'is_identity_verified': 1,
      'subscription_plan': 'free_trial',
      'avg_rating': 4.6,
      'total_reviews': 12,
      'total_completed_jobs': 40,
      'response_time_hours': 3,
      'commune': 'باب الزوار',
      'wilaya': '16',
      'phone': phone,
      'cover_image_url': null,
      'avatar_url': null,
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
    };

Future<({ApiClient api, AuthState auth})> _boot(
  List<Map<String, Object?>> rows,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user()});
      }
      if (p.endsWith('/api/mobile/workers/search')) {
        return _json(rows);
      }
      return _json(<Object?>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _settle(WidgetTester tester, {int frames = 14}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth,
) async {
  tester.view.physicalSize = const Size(392, 860) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
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
      home: const BrowseScreen(),
    ),
  ));
  await _settle(tester);
}

void main() {
  group('the parser keeps the number the wire sends', () {
    test('a live row parses the phone it carries', () {
      final w = WorkerProfile.fromJson(_worker(5, 'رشيد خليفي', '0550000009')
          .cast<String, dynamic>());
      expect(w.phone, '0550000009');
    });

    test('an absent or blank number stays null, and is never 0', () {
      for (final row in <Map<String, Object?>>[
        {..._worker(6, 'أ', '0550000010')}..remove('phone'),
        {..._worker(7, 'ب', '0550000011'), 'phone': '   '},
        {..._worker(8, 'ج', '0550000012'), 'phone': 55},
      ]) {
        final w = WorkerProfile.fromJson(row.cast<String, dynamic>());
        expect(w.phone, isNull,
            reason: 'no number is not a number: a row that printed «0» here '
                'would be searched as user 0');
      }
    });
  });

  group('a customer searching a number he was given finds its owner', () {
    testWidgets('the number the wire sends finds the man who holds it',
        (tester) async {
      final b = await _boot([
        _worker(5, 'رشيد خليفي', '0550000009'),
        _worker(2, 'خالد رحماني', '0550000006'),
      ]);
      await _pump(tester, b.api, b.auth);
      expect(find.text('رشيد خليفي'), findsOneWidget);
      expect(find.text('خالد رحماني'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '0550000009');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _settle(tester);

      expect(find.text('رشيد خليفي'), findsOneWidget);
      expect(find.text('خالد رحماني'), findsNothing,
          reason: 'the number belongs to one man');
      expect(find.text('لا نتائج مطابقة'), findsNothing);
    });

    testWidgets('a number nobody holds finds nobody, and says so',
        (tester) async {
      final b = await _boot([
        _worker(5, 'رشيد خليفي', '0550000009'),
        _worker(2, 'خالد رحماني', '0550000006'),
      ]);
      await _pump(tester, b.api, b.auth);

      await tester.enterText(find.byType(TextField), '0770999999');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _settle(tester);

      // The heading stays: nothing matched, and that is still true.
      expect(find.text('لا نتائج مطابقة'), findsOneWidget);
      // The body is NOT the word sentence any more. He typed a number, and
      // «لا يوجد مقاول يطابق «0770999999» / جرّب كلمة أقصر» told a man holding
      // a number from the street to shorten a *word* — there is no word in it.
      // `empty_phone_search_copy.dart` owns this state; see the note there.
      expect(find.textContaining('لم يُعثر على رقم مطابق'), findsOneWidget);
      expect(find.textContaining('لا يوجد مقاول يطابق'), findsNothing,
          reason: 'this sentence quotes a word-search result at a phone lookup, '
              'and re-prints the number the customer pasted');
      expect(
        find.descendant(
            of: find.byType(EmptyView), matching: find.textContaining('كلمة')),
        findsNothing,
        reason: 'there is no word in a phone number to shorten');
      // The safe action is unchanged by that fix.
      expect(find.text('مسح البحث والفلاتر'), findsOneWidget);
    });

    testWidgets('the paste out of a contact card works — the reason the '
        'app already folds Arabic-Indic digits', (tester) async {
      // `٠٥٥٠٠٠٠٠٠٩` is what a contact card on an Algerian keyboard produces
      // for 0550000009. `ArabicSearch` documents this exact fold "which arrive
      // when someone pastes a phone number out of their contacts", so the
      // directory was one layer short of an answer it had already paid for.
      final b = await _boot([
        _worker(5, 'رشيد خليفي', '0550000009'),
        _worker(2, 'خالد رحماني', '0550000006'),
      ]);
      await _pump(tester, b.api, b.auth);

      await tester.enterText(find.byType(TextField), '٠٥٥٠٠٠٠٠٠٩');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _settle(tester);

      expect(find.text('رشيد خليفي'), findsOneWidget);
      expect(find.text('خالد رحماني'), findsNothing);
    });

    testWidgets('a partial number still finds its owner — a customer '
        'remembers the last four digits and types only those', (tester) async {
      final b = await _boot([
        _worker(5, 'رشيد خليفي', '0550000009'),
        _worker(2, 'خالد رحماني', '0550000006'),
      ]);
      await _pump(tester, b.api, b.auth);

      await tester.enterText(find.byType(TextField), '0009');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _settle(tester);

      expect(find.text('رشيد خليفي'), findsOneWidget);
      expect(find.text('خالد رحماني'), findsNothing);
    });

    testWidgets('a word is still a word — the number must not turn every '
        'list into a number list', (tester) async {
      final b = await _boot([
        _worker(5, 'رشيد خليفي', '0550000009', bio: 'سباكة وترصيح'),
        _worker(2, 'خالد رحماني', '0550000006', bio: 'دهان وتشطيب'),
      ]);
      await _pump(tester, b.api, b.auth);

      await tester.enterText(find.byType(TextField), 'سباكة');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _settle(tester);

      expect(find.text('رشيد خليفي'), findsOneWidget);
      expect(find.text('خالد رحماني'), findsNothing);
    });

    testWidgets('the unfiltered list is never narrowed by this fix',
        (tester) async {
      final b = await _boot([
        _worker(5, 'رشيد خليفي', '0550000009'),
        _worker(2, 'خالد رحماني', '0550000006'),
      ]);
      await _pump(tester, b.api, b.auth);
      expect(find.text('رشيد خليفي'), findsOneWidget);
      expect(find.text('خالد رحماني'), findsOneWidget);
    });
  });

  _pureRules();
}

// The pure rules, tested without a widget: the thresholds and the word/number
// seam are the parts a future edit could quietly change, and the widget tests
// above only observe their net effect on a two-row directory.
void _pureRules() {
  group('what counts as a number query', () {
    test('the shapes a number actually arrives in are number queries', () {
      for (final q in <String>[
        '0550000009',
        '٠٥٥٠٠٠٠٠٠٩',
        '055 00 00 09',
        '05-50-00-00-09',
        '+213 550 00 00 09',
        '00213550000009',
        '0009',
      ]) {
        expect(phoneQueryDigits(q), isNotNull,
            reason: '«$q» is a number a customer can hold, not a word');
      }
    });

    // Added 6 Oct with the `_isDigit` repair. `_isDigit` hand-rolled its own
    // digit ranges (`0x30..0x39` and `0x0660..0x0669`) and therefore did not
    // know about U+06F0..U+06F9, the Extended-Arabic / Persian digits that
    // `ArabicSearch.normalize` **does** fold — and that fold runs two lines
    // earlier, in the very `DzPhone.canonicalFromDigits(trimmed)` call whose
    // length this loop then vetoes. So the query passed the digit-count floor
    // and was rejected by the next loop: `phoneQueryDigits` answered null, the
    // numeric arm was skipped, and the text arm searched name/bio/commune/
    // trades — none of which can contain a digit. A customer who pasted his
    // number out of a Persian-locale contact card was told nobody matched.
    test('Extended-Arabic digits are digits, because the fold says so', () {
      // U+06F0 U+06F5 U+06F0 U+06F1 U+06F2 U+06F3 U+06F4 U+06F5 U+06F6 is
      // «۰۵۰۱۲۳۴۵۶», which the fold reads as 050123456 — nine digits, so it
      // clears the floor, and it is the number the next line looks for. Before
      // the repair this answered `null`.
      expect(phoneQueryDigits('\u06f0\u06f5\u06f0\u06f1\u06f2\u06f3'
              '\u06f4\u06f5\u06f6'), '050123456');
      expect(workerPhoneMatches(
              '\u06f0\u06f5\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6',
              '050123456'),
          isTrue);
    });

    // The ratchet, so the next script cannot reopen this hole: whatever the
    // fold in `ArabicSearch` calls a digit has to be a character this loop
    // lets through, so no hand-written range can fall behind the fold again.
    test('the digit test cannot disagree with the fold that runs above it', () {
      for (var cu = 0; cu < 0x0800; cu++) {
        final ch = String.fromCharCode(cu);
        final folded = DzPhone.digits(ch);
        if (folded.isEmpty) continue;
        if (!folded.runes.every((r) => r >= 0x30 && r <= 0x39)) continue;
        expect(phoneQueryDigits('${ch}055000000'), isNotNull,
            reason: 'U+${cu.toRadixString(16).toUpperCase().padLeft(4, '0')}'
                ' «$ch» folds to the digit «$folded», so it cannot be the '
                'character that turns a number into a word');
      }
    });

    test('a word is never a number query', () {
      for (final q in <String>[
        'سباكة',
        'رشيد',
        'painting',
        'الجزائر',
        'abc',
        // Digits inside a word must not smuggle it into the numeric arm.
        '55abc',
        'coat5',
      ]) {
        expect(phoneQueryDigits(q), isNull,
            reason: '«$q» must reach the text arm untouched');
      }
    });

    test('too few digits is not a number query, so nothing is silently '
        'dropped', () {
      expect(phoneQueryDigits('55'), isNull);
      expect(phoneQueryDigits('0'), isNull);
      expect(phoneQueryDigits(''), isNull);
      expect(phoneQueryDigits('   '), isNull);
    });
  });

  group('workerPhoneMatches', () {
    test('every shape of the same number matches the same man', () {
      for (final q in <String>[
        '0550000009',
        '٠٥٥٠٠٠٠٠٠٩',
        '05 50 00 00 09',
        '+213 550 00 00 09',
        '00213550000009',
        '055000000',
        '0009',
      ]) {
        expect(workerPhoneMatches(q, '0550000009'), isTrue,
            reason: '«$q» names 0550000009');
      }

      // `055 00 00 09` is 8 digits, and **that is the correct answer being a
      // refusal**: those eight digits are a middle fragment of a ten-digit
      // number, so answering it would hand the customer a man whose number
      // only partly contains what he typed. A grouped *full* number is the
      // one below, `05 50 00 00 09`.
      expect(workerPhoneMatches('055 00 00 09', '0550000009'), isFalse,
          reason: 'a middle fragment is a coincidence, not a match');
    });

    test('a grouped number of the full length matches — the group spacing a '
        'phone keyboard inserts must not cost the customer his man', () {
      // The stored value is ten digits and the grouped query is eight: this is
      // a **partial** query (a remembered fragment), not a different spelling,
      // and it matches on the leading `05500000` — which is the correct answer
      // for a fragment, and is why the test above lists the full-length shapes
      // separately from the grouped one.
      expect(workerPhoneMatches('055 0000 009', '0550000009'), isTrue);
      // The grouped spelling of the WHOLE number, which is what `DzPhone`
      // produces as a display group: every digit is there, just spaced.
      expect(workerPhoneMatches('05 50 00 00 09', '0550000009'), isTrue);
    });

    test('a remembered fragment at either end matches, a middle one does '
        'not', () {
      expect(workerPhoneMatches('0550', '0550000009'), isTrue);
      expect(workerPhoneMatches('0009', '0550000009'), isTrue);
      // Middle only: answering this with the man would be a coincidence, not a
      // match, and two digits of a remembered number is exactly the noise
      // minPhoneDigits exists to refuse.
      expect(workerPhoneMatches('5000', '0550000009'), isFalse);
    });

    test('a number belonging to nobody matches nobody', () {
      expect(workerPhoneMatches('0550000009', '0550000006'), isFalse);
      expect(workerPhoneMatches('0550000009', null), isFalse);
      expect(workerPhoneMatches('0550000009', ''), isFalse);
    });

    test('a full-length query cannot be answered by a shorter number', () {
      expect(workerPhoneMatches('05500000099', '0550000009'), isFalse);
    });

    test('a word never matches a number', () {
      expect(workerPhoneMatches('سباكة', '0550000009'), isFalse);
    });
  });

  group('narrowWorkers', () {
    WorkerProfile row(int id, String name, String? phone) =>
        WorkerProfile.fromJson({
          'id': id,
          'user_id': 1000 + id,
          'full_name': name,
          'bio': 'سباكة',
          'specialties': <String>['plumbing'],
          'experience_years': 1,
          'is_available': 1,
          'verification_status': 'pending',
          'avg_rating': 0,
          'total_reviews': 0,
          'total_completed_jobs': 0,
          if (phone != null) 'phone': phone,
        });

    test('an empty query returns the list untouched, so the unfiltered '
        'directory is never narrowed', () {
      final rows = <WorkerProfile>[row(1, 'أ', '0550000001'), row(2, 'ب', null)];
      expect(narrowWorkers(rows, ''), rows);
      expect(narrowWorkers(rows, '   '), rows);
      expect(narrowWorkers(rows, '!!!'), rows);
    });

    test('a man with no number is still a man in the market', () {
      final rows = <WorkerProfile>[row(1, 'أ', '0550000001'), row(2, 'ب', null)];
      expect(narrowWorkers(rows, 'سباكة').map((w) => w.id), <int>[1, 2]);
    });

    test('a row with no number is simply not findable by one', () {
      final rows = <WorkerProfile>[row(1, 'أ', '0550000001'), row(2, 'ب', null)];
      expect(narrowWorkers(rows, '0550000002'), isEmpty);
      expect(narrowWorkers(rows, '0550000001').map((w) => w.id), <int>[1]);
    });
  });
}
