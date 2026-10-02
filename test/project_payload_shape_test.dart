// The project parser cast the server's JSON by hand, and this is the one file
// in the family where a cast could not fail quietly at all.
//
// `repository._rows` turns a model `TypeError` into an `ApiException` and drops
// the row. So the claim under test is the same one the other two files in this
// family make — **one row the server answered in an unexpected shape costs that
// row and nothing else** — and here the cost of the other half is the worst of
// the four outcomes the loop has found:
//
//   * a lost chat row is a message missing from a thread that still reads as a
//     thread;
//   * a lost notification is never drawn, and the badge under-counts;
//   * a lost **project** is a job the customer cannot open and the contractor
//     cannot quote, on the first screen either of them opens.
//
// Browsing is the first thing a customer does with this app. A feed that lost
// one row renders as «لا توجد مشاريع» over a market that has work in it, and
// to the founder it is an app with no projects rather than a bug he can report.
//
// Three of these casts were **not** nullable — `customer_id`, `title` and
// `category` were `as int` / `as String` — so there was no null to tolerate and
// any other shape threw. A SQLite string in `customer_id` was enough to empty
// the whole market page.
//
// So the tests are written from two ends, as in the two shipped files:
//   * the parser, against every shape the server is documented to answer with
//     (`_asInt`'s own doc comment: "a string from SQLite"); and
//   * the **real Repository against a fake HTTP client**, which is the only
//     place the "one row, not the list" promise can be proved at all — the drop
//     lives in `_rows`, not in the model, so a model-only test would pass while
//     the market page still emptied itself.
//
// **The rule that decides the fallbacks is the caller, not the field.** An
// unreadable *title* must stay empty rather than become «مشروع بدون عنوان»,
// because the same string seeds the edit form (`project_new_screen.dart:118`)
// and would be written back to the server as the customer's own words; an
// unreadable *category* must stay blank rather than throw, because every reader
// already routes an unknown slug to `Taxonomy`'s «خدمات عامة».
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/diagnostics/crash_reporter.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/models/project.dart';

/// A D1 project row in the shape `/api/mobile/projects` answers with.
/// Every field is `Object?` on purpose: the wrong-shape fixtures have to be
/// able to say `'30'` and `5`, which is the whole point of them.
Map<String, Object?> _row({
  Object? id = 'b0b5644a223e',
  Object? customerId = 30,
  Object? title = 'دهان شقة 3 غرف',
  Object? description = 'دهان كامل مع تحضير الجدران',
  Object? category = 'painting',
  Object? categories,
  Object? images = const <Object?>[],
  Object? wilaya = '16',
  Object? commune = 'حسين داي',
  Object? budgetMin = 60000,
  Object? budgetMax = 90000,
  Object? urgency = 'within_week',
  Object? status = 'open',
  Object? selectedWorkerId,
}) =>
    <String, Object?>{
      'id': id,
      'customer_id': customerId,
      'title': title,
      'description': description,
      'category': category,
      if (categories != null) 'categories': categories,
      'images': images,
      'wilaya': wilaya,
      'commune': commune,
      'budget_min': budgetMin,
      'budget_max': budgetMax,
      'urgency': urgency,
      'status': status,
      'selected_worker_id': selectedWorkerId,
    };

/// The real repository, against a backend that answers [rows] verbatim.
Repository _repoOver(List<Map<String, Object?>> rows) => Repository(
      ApiClient(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(rows),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        baseUrls: ['https://x.test'],
      ),
    );

/// The real repository against a body that is **not** a list of maps — the one
/// shape `_rows` still cannot read, and the boundary its "nothing readable is
/// still a failure" rule exists for.
Repository _repoOverRaw(String body) => Repository(
      ApiClient(
        httpClient: MockClient(
          (_) async => http.Response(
            body,
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        baseUrls: ['https://x.test'],
      ),
    );

void main() {
  group('the columns D1 answers as strings are still read as columns', () {
    test('a row of strings parses exactly as the numbers it stands for', () {
      // `_asInt` in data/repository.dart documents this answer in its own
      // words — "a null from a LEFT JOIN, a string from SQLite".
      final p = Project.fromJson(_row(
        id: 'abc123',
        customerId: '30',
        budgetMin: '60000',
        budgetMax: '90000',
        selectedWorkerId: '7',
      ));
      expect(p.id, 'abc123');
      expect(p.customerId, 30);
      expect(p.budgetMin, 60000);
      expect(p.budgetMax, 90000);
      expect(p.selectedWorkerId, 7);
    });

    test('a stringified status and urgency still reach their tables', () {
      // `fromWire` is the only translator on purpose; the point is that the
      // value arrives as a String and is not cast on the way in.
      final p = Project.fromJson(_row(status: 'in_progress'));
      expect(p.status, ProjectStatus.inProgress);
      expect(p.urgency, UrgencyLevel.withinWeek);
    });
  });

  group('no field prints a number where a sentence belongs', () {
    test('a numeric description is absent, not «5»', () {
      // A real shape: a score or a count in a text column. Flattening it would
      // print a number in the description section as though the customer had
      // written it.
      final p = Project.fromJson(_row(description: 5));
      expect(p.description, isNull);
    });

    test('a numeric title is empty, and never the word «null»', () {
      final p = Project.fromJson(_row(title: 42));
      expect(p.title, isEmpty);
    });

    test('a numeric commune is absent rather than «16»', () {
      final p = Project.fromJson(_row(commune: 16));
      expect(p.commune, isNull);
    });

    test('the id of a row that sent a number is the number, as a key', () {
      // The exception that proves the rule: an id IS an identifier, so it is
      // flattened by its own text. `.toString()` already did this, and it must
      // keep doing it — what changed is that `null` no longer reaches it as
      // the literal «null».
      final p = Project.fromJson(_row(id: 55));
      expect(p.id, '55');
    });

    test('an absent id is empty, never «null»', () {
      // `push('/api/mobile/projects/null')` is a dead link. '' is also a dead
      // link, but it is one nobody can mistake for a row id 0.
      final p = Project.fromJson(_row()..remove('id'));
      expect(p.id, isEmpty);
    });
  });

  group('the title is never invented', () {
    test('an unreadable title does not become a placeholder sentence', () {
      // The rule that separates this file from the other two: a placeholder is
      // right for a *category* (every reader has a fallback) and wrong for a
      // title, because `project_new_screen.dart:118` seeds the edit form with
      // this exact string and the next save writes it back to the server as the
      // customer's own words.
      final p = Project.fromJson(_row(title: 42));
      expect(p.title, isEmpty);
      expect(p.title, isNot(contains('null')));
    });

    test('a whitespace-only title is empty, which the form can still see', () {
      // The edit form guards on `_title.text.trim().isEmpty`
      // (`project_new_screen.dart:249`), so an empty title stops the publish
      // and tells the user to complete it. A placeholder would sail past that
      // guard and overwrite the real title.
      final p = Project.fromJson(_row(title: '   '));
      expect(p.title, isEmpty);
    });
  });

  group('the category falls on the fallback that already exists', () {
    test('an unreadable category draws «خدمات عامة» and no English', () {
      // `Taxonomy.categoryName` answers an unknown slug with «خدمات عامة» and
      // never leaks a raw slug. A category is a **key**, so it is flattened by
      // its own text — '7' is a slug this build has never heard of, which is
      // exactly where an absent category already lands.
      final p = Project.fromJson(_row(category: 7));
      expect(p.category, '7');
      expect(Taxonomy.categoryName(p.category), 'خدمات عامة');
    });

    test('an absent category reaches the same fallback as an unknown one', () {
      final p = Project.fromJson(_row()..['category'] = null);
      expect(Taxonomy.categoryName(p.category), 'خدمات عامة');
    });

    test('an unknown slug is still the fallback, exactly as before', () {
      final p = Project.fromJson(_row(category: 'unheard_of_trade'));
      expect(p.category, 'unheard_of_trade');
      expect(Taxonomy.categoryName(p.category), 'خدمات عامة');
    });

    test('allCategories is never empty, so the card never draws "+-1"', () {
      // `project_card.dart:43` prints `+${allCategories.length - 1}` when the
      // list is longer than one. An empty list that reached that line would
      // print «+-1».
      final p = Project.fromJson(_row(category: 7));
      expect(p.allCategories, isNotEmpty);
      expect(p.allCategories.length - 1, 0);
    });
  });

  group('a wilaya code is a code', () {
    test('an absent wilaya drops the location row instead of naming one', () {
      // `Taxonomy.wilayaNameOrNull` returns null for a blank or unknown code
      // and `project_card.dart:59` then draws no location row at all — the fix
      // the 26 Sep «a project without a wilaya is published in الجزائر» bug
      // produced. An unreadable wilaya must reach that null, not the capital's
      // name by way of a fallback.
      expect(Taxonomy.wilayaNameOrNull(Project.fromJson(_row()..['wilaya'] = null).wilaya),
          isNull);
    });

    test('a code sent as a number still names the wilaya it is', () {
      // The opposite case, and it must not be broken by being defensive: 16 is
      // **Algiers**, so flattening it to '16' is the correct answer, not a
      // fabrication. The rule is "a code is a code", not "a number is never a
      // code" — and `Wilaya.toString` on a real row is what made this one
      // reachable in the first place.
      final p = Project.fromJson(_row(wilaya: 16));
      expect(Taxonomy.wilayaNameOrNull(p.wilaya),
          Taxonomy.wilayaNameOrNull('16'));
    });

    test('a number that is not a wilaya code names nothing at all', () {
      // Where flattening could invent a location, it still cannot: '9999' is
      // not in the 58-wilaya table, so the row draws no location rather than
      // a wrong one.
      final p = Project.fromJson(_row(wilaya: 9999));
      expect(Taxonomy.wilayaNameOrNull(p.wilaya), isNull);
    });

    test('a known code still names its wilaya', () {
      expect(Taxonomy.wilayaNameOrNull(Project.fromJson(_row()).wilaya),
          isNotNull);
    });
  });

  group('a budget is absent, never a zero the customer never typed', () {
    test('an unreadable budget is null, so the form shows an empty box', () {
      // `project_new_screen.dart:120` writes
      // `existing.budgetMin?.toString() ?? ''`. A 0 here would render «0» in
      // the box and save it back as a zero floor.
      final p = Project.fromJson(_row(budgetMin: 'abc', budgetMax: null));
      expect(p.budgetMin, isNull);
      expect(p.budgetMax, isNull);
      expect(p.budgetMin?.toString() ?? '', isEmpty);
    });

    test('an empty string is not a budget of zero either', () {
      final p = Project.fromJson(_row(budgetMin: '', budgetMax: ''));
      expect(p.budgetMin, isNull);
      expect(p.budgetMax, isNull);
    });

    test('an unreadable budget band reads as «no budget given»', () {
      // The honest rendering, which `budgetLabel` already owns.
      final p = Project.fromJson(_row(budgetMin: null, budgetMax: 'oops'));
      expect(p.budgetLabel, 'بدون ميزانية محددة');
    });
  });

  group('the selected worker is only claimed when the server sent one', () {
    test('an unreadable selected_worker_id does not invent a worker', () {
      // `project_commit_outcome.dart:152` decides a contractor's pick is
      // confirmed on `fresh.selectedWorkerId != null`. A fabricated 0 would
      // make every project claim a worker nobody chose.
      final p = Project.fromJson(_row(selectedWorkerId: 'nope'));
      expect(p.selectedWorkerId, isNull);
    });

    test('a stringified worker id is the number the comparison needs', () {
      final p = Project.fromJson(_row(selectedWorkerId: '7'));
      expect(p.selectedWorkerId, 7);
    });
  });

  group('the market page loses one row, not the page — real Repository', () {
    test('one unreadable row does not empty the browse feed', () async {
      // The production failure, driven through `_rows` rather than asserted:
      // before this parser, the `customer_id` string threw and took the whole
      // list with it, so the screen showed «لا توجد مشاريع» over a market that
      // had work in it.
      final repo = _repoOver([
        _row(id: 'good-1'),
        _row(id: 'drifted', customerId: 'thirty'), // not a number, not a null
        _row(id: 'good-2'),
      ]);

      final rows = await repo.browseProjects();

      // Stronger than "the good rows survive": **nothing is lost at all.** A
      // project row that parses with the columns it could read is a card the
      // customer can open, and `_rows`'s drop path is for a model that cannot
      // answer at all — which this one no longer does for any shape.
      expect(rows.map((p) => p.id), ['good-1', 'drifted', 'good-2']);
      expect(rows[1].customerId, 0,
          reason: 'an id the phone cannot read is 0, and the card still opens');
    });

    test('a feed of stringified columns is still a market, not an error', () async {
      // **This is the production failure**, and the reason a partial-feed test
      // is not enough on its own. The cast that throws sat on *every* row,
      // because the shape that breaks it is a property of the column rather
      // than of one row: a Worker build whose SELECT hands `customer_id` back
      // as text took every project down, `_rows` found nothing readable, and
      // re-threw — so the screen answered «حدث خطأ غير متوقع» over a market
      // full of work, with no log line naming a row because no single row was
      // at fault. Both halves have to be asserted: one bad row among good ones
      // (above) and a whole feed of them (here).
      final repo = _repoOver([
        _row(id: 'p1', customerId: '30'),
        _row(id: 'p2', customerId: '31'),
        _row(id: 'p3', customerId: '32', budgetMin: '60000'),
      ]);

      final rows = await repo.browseProjects();

      expect(rows.map((p) => p.id), ['p1', 'p2', 'p3']);
      expect(rows.map((p) => p.customerId), [30, 31, 32]);
      expect(rows.first.budgetMin, 60000);
    });

    test('a row that is not a map at all still raises when nothing is read', () async {
      // The boundary that must not move, and the only shape this parser still
      // refuses: `_asMap` throws, so a list of strings is dropped like any
      // unreadable row — and when *every* row is one, `_rows` re-throws rather
      // than rendering «لا توجد مشاريع» (there are none) where the truth is
      // «we could not read them». Those look identical and mean opposite
      // things.
      final repo = _repoOverRaw(jsonEncode(['not-a-map', 42]));

      await expectLater(repo.browseProjects(), throwsA(isA<ApiException>()));
    });

    test('a genuinely empty market is still empty, not an error', () async {
      // `[]` is what the Worker sends for a wilaya with no open projects, and
      // turning that into an error card would be its own defect.
      expect(await _repoOver([]).browseProjects(), isEmpty);
    });

    test('the customer\'s own list keeps the same promise', () async {
      // `myProjects` is the «مشاريعي» tab — the tab a client opens to see the
      // renovation he is currently paying for.
      final repo = _repoOver([
        _row(id: 'mine-1'),
        _row(id: 'mine-2', status: {'nested': 'map'}),
      ]);

      final rows = await repo.myProjects();

      expect(rows.map((p) => p.id), ['mine-1', 'mine-2']);
      expect(rows[1].status, ProjectStatus.open,
          reason: 'an unreadable status is the column default, not a throw');
    });

    test('a lost row is recorded, not silent', () async {
      // Without this, the contractor the user came for can be the one that was
      // dropped and the app has no way to say so.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

      await _repoOverRaw(jsonEncode([_row(), 'not-a-map'])).browseProjects();

      final rowRecords =
          reporter.log.records.where((r) => r.kind == 'row').toList();
      expect(rowRecords, hasLength(1),
          reason: 'one record per response, not one per dropped row');
      expect(rowRecords.single.detail, contains('1 of 2'));
      expect(rowRecords.single.message, contains('Project'),
          reason: 'the record names the model whose row could not be read');
    });
  });
}

/// The store every diagnostics test in this repo uses: a crash log that starts
/// empty and swallows what it is told, so the assertion is about the record in
/// memory and never about shared preferences.
class _MemoryStore implements CrashStore {
  @override
  Future<List<String>> read() async => const <String>[];

  @override
  Future<void> write(List<String> lines) async {}
}
