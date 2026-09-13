// Publishing a project must send the only urgency value the database accepts.
//
// `projects.urgency` in D1 is
//   CHECK(urgency IN ('flexible','within_week','within_month','urgent'))
// and the Dart enum is camelCase. The publish path sent `urgency.name`, so
// «خلال أسبوع» and «خلال شهر» — two of the four options on the publish screen,
// and the two a client with a deadline actually picks — came back from the live
// API as a 500:
//   {"error":"حدث خطأ غير متوقع، الرجاء المحاولة مرة أخرى","code":"internal"}
// which the app can only render as a server fault. Reproduced with curl on
// 13 Sep (withinWeek/withinMonth -> 500, the four snake values -> 201). The
// fix is one getter, `UrgencyLevel.wire`, but the value is the whole point, so
// it is pinned here three ways: the table, the round-trip, and the wire body.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/project.dart';

/// Copied from `migrations/0001_schema.sql`, the CHECK on `projects.urgency`.
const _accepted = <String>{
  'flexible',
  'within_week',
  'within_month',
  'urgent',
};

void main() {
  test('every urgency level serialises to a value the column accepts', () {
    for (final level in UrgencyLevel.values) {
      expect(_accepted, contains(level.wire),
          reason: '${level.name} would be rejected by the CHECK constraint');
    }
    expect(
        UrgencyLevel.values.map((l) => l.wire).toSet(), _accepted,
        reason: 'the four levels must cover the four stored values');
  });

  test('the wire value is the same one the feed parses back', () {
    for (final level in UrgencyLevel.values) {
      expect(UrgencyLevel.fromWire(level.wire), level,
          reason: 'write and read must not disagree about ${level.name}');
    }
    // An unknown or missing value reads as the column's own default rather
    // than crashing a feed.
    expect(UrgencyLevel.fromWire(null), UrgencyLevel.flexible);
    expect(UrgencyLevel.fromWire('whenever'), UrgencyLevel.flexible);
    // The camelCase Dart name is NOT a wire value — the old bug, stated.
    expect(UrgencyLevel.fromWire('withinWeek'), UrgencyLevel.flexible);
  });

  test('the publish request carries snake_case urgency', () async {
    Map<String, dynamic>? body;
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
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
              'urgency': 'within_week',
              'status': 'open',
              'selected_worker_id': null,
              'created_at': '2026-09-13 09:00:00',
              'updated_at': '2026-09-13 09:00:00',
            }),
            201,
            headers: {'content-type': 'application/json'});
      }),
    );

    final project = await Repository(api).createProject(
      title: 'دهان',
      category: 'painting',
      wilaya: '16',
      urgency: UrgencyLevel.withinWeek,
    );

    expect(body?['urgency'], 'within_week',
        reason: 'withinWeek is what the live API answered with a 500');
    expect(project.urgency, UrgencyLevel.withinWeek);
  });
}
