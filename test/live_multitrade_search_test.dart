import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/project_search.dart';
import 'package:allomokawil/src/models/project.dart';

/// The real bug, on a real row.
///
/// Copied verbatim from `GET /api/mobile/projects` on 26 Sep 2026
/// (https://finili.medsaidkichene.workers.dev), the same convention as
/// `live_payload_models_test.dart`. It matters that this row is real and not
/// invented, because the defect is about a shape the founder's own customers
/// produce: 4 of the 20 open projects on the market carried more than one
/// trade when this was found.
///
/// The job is a *finishing* job — that is the `category` the API records — and
/// it also covers painting, renovation, building, plumbing **and carpentry**. The
/// card the contractor scrolls shows him `+5`. He types «نجارة» and gets nothing.
const _finishingJob = '''
{"id": "8cee95af91ebda3846132f183fe6141ead3a89fdf79d9c9cb26b59a8096ce601", "customer_id": 336, "title": "test", "description": "test", "category": "general_finishing", "images": [], "wilaya": "04", "commune": "أولاد قاسم", "latitude": null, "longitude": null, "budget_min": 6000, "budget_max": 7000, "urgency": "within_week", "status": "open", "selected_worker_id": null, "created_at": "2026-09-19 20:39:41", "updated_at": "2026-09-19 20:39:41", "categories": ["general_finishing", "painting", "renovation", "construction", "plumbing", "carpentry_aluminum"], "wilaya_name": "أم البواقي"}
''';

void main() {
  group('a real multi-trade project, as the server sends it', () {
    late Project job;

    setUpAll(() {
      job = Project.fromJson(
          jsonDecode(_finishingJob) as Map<String, dynamic>);
    });

    test('the row really is multi-trade, or this file proves nothing', () {
      expect(job.allCategories.length, 6);
      expect(job.allCategories.last, 'carpentry_aluminum');
    });

    test('the title and description carry none of the trades', () {
      // If they did, a title match would make the tests below meaningless —
      // the whole point is that `categories` is the only place the trade is
      // written down.
      expect(job.title, 'test');
      expect(job.description, 'test');
    });

    test('the primary trade was always found, and still is', () {
      expect(projectMatchesQuery(job, 'تشطيب'), isTrue);
    });

    test('the five secondary trades are found too', () {
      expect(projectMatchesQuery(job, 'دهان'), isTrue);
      expect(projectMatchesQuery(job, 'ترميم'), isTrue);
      expect(projectMatchesQuery(job, 'بناء'), isTrue);
      expect(projectMatchesQuery(job, 'سباكة'), isTrue);
      // The one a carpenter would actually type.
      expect(projectMatchesQuery(job, 'نجارة'), isTrue);
    });

    test('a trade the job does not cover still finds nothing', () {
      expect(projectMatchesQuery(job, 'حدادة'), isFalse);
      expect(projectMatchesQuery(job, 'كهرباء'), isFalse);
    });

    test('the place still works, unchanged', () {
      expect(projectMatchesQuery(job, 'أم البواقي'), isTrue);
    });
  });
}
