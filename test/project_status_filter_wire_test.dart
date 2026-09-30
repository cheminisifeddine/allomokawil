// The status filter tabs must send the only status values the server matches on.
//
// Found on production 30 Sep 2026 by registering a customer (405), posting a
// project, and driving a real bid + accept so the project reached `in_progress`
// — then asking the two endpoints the app itself calls, with the two spellings:
//
//   GET /api/mobile/my/projects?status=inProgress   -> 200, 0 rows
//   GET /api/mobile/my/projects?status=in_progress  -> 200, 1 row  (the project)
//   GET /api/mobile/projects?status=inProgress      -> 200, 0 rows
//   GET /api/mobile/projects?status=in_progress     -> 200, 4 rows
//
// `Repository.myProjects` and `_browseProjectsPage` both sent `status.name`,
// so the app sent the Dart camelCase `inProgress` and the server's comparison
// found nothing to match. The «قيد التنفيذ» tab — one of five on «مشاريعي»,
// and the one a client opens to see the job he is actually paying for —
// answered with a successful read of **zero rows** while the job was running,
// and the empty state then said «لا مشاريع في هذه الحالة» ("no projects in this
// state") about a project in that state. A 200, so nothing anywhere reported an
// error; the customer is told his renovation is not here.
//
// This is the same bug as `UrgencyLevel.name` → 500 on publish, already fixed
// by the `wire` getter in `project.dart`. It was fixed for `urgency` and left
// for `status` in the same file, on two call sites, and the `StatusPill`
// display helper was widened to accept **both** spellings to paper over it
// downstream — so the mismatch was visible in the app and harmless in exactly
// the one place it mattered. Note the one value the Dart names agree on:
// `open` and `completed` are single words, which is why only the one tab broke.
//
// Pinned three ways, the same three as the urgency sibling: the table, the
// round-trip, and the request each endpoint actually receives.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/project.dart';

/// The four values the Worker stores, observed on production and matching the
/// `projects.status` column: 'open' | 'in_progress' | 'completed' | 'cancelled'.
const _stored = <String>{
  'open',
  'in_progress',
  'completed',
  'cancelled',
};

/// One project row, minimal but parseable.
Map<String, dynamic> _row({String status = 'open'}) => {
      'id': 'p-1',
      'customer_id': 1,
      'title': 'دهان',
      'description': null,
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': null,
      'budget_min': null,
      'budget_max': null,
      'urgency': 'flexible',
      'status': status,
      'selected_worker_id': null,
      'created_at': '2026-09-30 11:00:00',
      'updated_at': '2026-09-30 11:00:00',
    };

void main() {
  test('every project status serialises to a value the column stores', () {
    for (final s in ProjectStatus.values) {
      expect(_stored, contains(s.wire),
          reason: '${s.name} is not a value the server matches on');
    }
    expect(ProjectStatus.values.map((s) => s.wire).toSet(), _stored,
        reason: 'the four statuses must cover the four stored values');
  });

  test('the wire value is the same one the feed parses back', () {
    for (final s in ProjectStatus.values) {
      expect(ProjectStatus.fromWire(s.wire), s,
          reason: 'write and read must not disagree about ${s.name}');
    }
    // The camelCase Dart name is NOT a wire value — the old bug, stated, and
    // pinned in the direction the fix chose: the parser **refuses** it, so a
    // row still carrying the Dart name reads as `open` rather than being
    // quietly honoured. Tolerating it on the way in is what let the mismatched
    // write look correct everywhere it was displayed.
    expect(ProjectStatus.fromWire('in_progress'), ProjectStatus.inProgress);
    expect(ProjectStatus.fromWire('inProgress'), ProjectStatus.open,
        reason: 'the Dart name must not survive as a readable status');
    // A value nobody recognises is an open project, the column's own default.
    expect(ProjectStatus.fromWire(null), ProjectStatus.open);
    expect(ProjectStatus.fromWire('whenever'), ProjectStatus.open);
  });

  test('the in-progress tab asks for in_progress, not inProgress', () async {
    final requested = <String>[];
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        requested.add(req.url.queryParameters['status'] ?? '');
        return http.Response(jsonEncode([_row(status: 'in_progress')]), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    final repo = Repository(api);

    final rows = await repo.myProjects(status: ProjectStatus.inProgress);

    expect(requested, ['in_progress'],
        reason: 'the live API answered 0 rows for inProgress on a real '
            'in_progress project');
    expect(rows.single.status, ProjectStatus.inProgress);
  });

  test('the market filter asks for the same value as «مشاريعي»', () async {
    final requested = <String>[];
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        requested.add(req.url.queryParameters['status'] ?? '');
        return http.Response(jsonEncode([_row(status: 'in_progress')]), 200,
            headers: {'content-type': 'application/json'});
      }),
    );

    await Repository(api).browseProjects(
      status: ProjectStatus.inProgress,
      page: 1,
    );

    expect(requested, ['in_progress'],
        reason: 'the two call sites were both wrong in the same way');
  });

  test('a null filter sends no status at all - the All tab', () async {
    final requested = <String?>{};
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        requested.add(req.url.queryParameters['status']);
        return http.Response(jsonEncode([_row()]), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    final repo = Repository(api);

    await repo.myProjects();
    await repo.browseProjects(page: 1);

    expect(requested, {null},
        reason: 'no filter means every status, and it must be absent, not empty');
  });
}
