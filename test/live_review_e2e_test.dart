// LIVE end-to-end proof for the backlog item "Reviews flow after completion".
//
// The item asks for the rating to reach the API *and* to be reflected in the
// contractor's average, "with a test that the average updates". Nothing short of
// the real thing counts here: a screen can show a thank-you for a review the
// server never stored, and an average can be read off a value the client
// invented. So this file drives the app's own code path end to end against the
// live API —
//
//   `Repository.createProject` -> `submitQuote` -> `acceptQuote` ->
//   `completeProject` -> `createReview`
//
// — and then asks the API, not the app, what the review did to the contractor:
//
//   1. a brand-new contractor reads 0 reviews / no rating before the job;
//   2. after one 4-star review the contractor reads exactly **4.0 / 1**;
//   3. the review the profile lists carries the rating and the Arabic comment
//      that were typed, from this customer;
//   4. rating the same job again is an **edit, not a second review** — 2 stars
//      moves the average to 2.0 and leaves the count at 1, which is what the
//      endpoint's upsert on (project, customer) promises;
//   5. no review is ever seeded: the contractor's numbers are zero until this
//      test writes one.
//
// Run with:  flutter test test/live_review_e2e_test.dart
//
// It needs the network. A network-level failure here is not a code regression —
// the file names the call that failed and the loop reports it as such. Each run
// creates two real accounts, one project, one quote and one review, the same way
// `live_chat_image_e2e_test.dart` and `live_register_e2e_test.dart` already do.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/project.dart';

/// The customer-facing API host (not the workers.dev fallback), so the calls
/// below are the ones a real install makes.
const _live = 'https://allomokawil.colisify.com';

/// `% 100000000` keeps the padding honest — a shorter number would be correctly
/// rejected by `isValidDzPhone`.
String _freshPhone(String prefix) =>
    '$prefix${(DateTime.now().microsecondsSinceEpoch % 100000000).toString().padLeft(8, '0')}';

void main() {
  // `TestWidgetsFlutterBinding` installs an HttpOverrides that answers every
  // request with a failure — the app's own client must reach the real API here.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
      'LIVE: a review written through the app moves the contractor average, and '
      'a second rating edits it instead of doubling it', () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // ---- the customer, through the app's own sign-up -----------------------
    final ownerApi = ApiClient(baseUrls: const <String>[_live]);
    final ownerAuth = AuthState(ownerApi);
    final ownerPhone = _freshPhone('06');
    await ownerAuth.register(
      phone: ownerPhone,
      email: '',
      fullName: 'صاحب مشروع (اختبار التقييم)',
      password: 'secret123',
      role: UserRole.customer,
    );
    expect(ownerAuth.isAuthenticated, isTrue,
        reason: 'sign-up must store a session');
    final repo = Repository(ownerApi);
    debugPrint('LIVE review: owner phone=$ownerPhone id=${ownerAuth.user?.id}');

    // ---- the contractor, registered as a worker ----------------------------
    final workerApi = ApiClient(baseUrls: const <String>[_live]);
    final workerPhone = _freshPhone('07');
    final reg = await workerApi.post('/api/register', body: <String, Object?>{
      'phone': workerPhone,
      'email': '',
      'full_name': 'مقاول (اختبار التقييم)',
      'password': 'secret123',
      'type': 'worker',
    }) as Map<String, dynamic>;
    workerApi.token = reg['token'] as String;
    final workerRepo = Repository(workerApi);
    debugPrint('LIVE review: worker phone=$workerPhone '
        'user=${(reg['user'] as Map<String, dynamic>)['id']}');

    // ---- a real job, closed for real ---------------------------------------
    final project = await repo.createProject(
      title: 'دهان شقة (اختبار التقييم)',
      description: 'مشروع اختبار حقيقي لقياس أثر التقييم',
      category: 'painting',
      wilaya: '16',
      commune: 'حسين داي',
      budgetMin: 60000,
      budgetMax: 90000,
      urgency: UrgencyLevel.withinWeek,
    );
    debugPrint('LIVE review: project=${project.id} status=${project.status.name}');

    final quote = await workerRepo.submitQuote(
      projectId: project.id,
      amount: 75000,
      message: 'جاهز للبدء فوراً',
      estimatedDays: 5,
    );
    final workerId = quote.workerId;
    debugPrint('LIVE review: quote=${quote.id} worker_profile=$workerId');

    // 1. Nothing is seeded: a contractor nobody has rated reads zero.
    final before = await repo.getWorker(workerId);
    expect(before.totalReviews, 0,
        reason: 'a fresh contractor must start with no reviews at all');
    expect(before.avgRating, 0);

    await repo.acceptQuote(project.id, quote.id);
    await repo.completeProject(project.id, workerId: workerId);

    // 2. The app's own submit path, with the ack the live Worker returns.
    await repo.createReview(
      projectId: project.id,
      workerId: workerId,
      rating: 4,
      comment: 'عمل جيد، سلّم في الموعد',
    );

    final after = await repo.getWorker(workerId);
    debugPrint('LIVE review: after first rating avg=${after.avgRating} '
        'count=${after.totalReviews} jobs=${after.totalCompletedJobs}');
    expect(after.totalReviews, 1,
        reason: 'one review must move the count from 0 to exactly 1');
    expect(after.avgRating, 4.0,
        reason: 'a single 4-star review is an average of exactly 4.0');

    // 3. What the profile lists is the review that was written.
    final listed = await repo.workerReviews(workerId);
    expect(listed, hasLength(1));
    expect(listed.single.rating, 4);
    expect(listed.single.comment, 'عمل جيد، سلّم في الموعد');
    expect(listed.single.workerId, workerId);
    expect(listed.single.projectId, project.id);

    // 4. Rating the same job again is an edit of that one review.
    await repo.createReview(
      projectId: project.id,
      workerId: workerId,
      rating: 2,
      comment: 'تأخر في التسليم',
    );

    final edited = await repo.getWorker(workerId);
    debugPrint('LIVE review: after re-rating avg=${edited.avgRating} '
        'count=${edited.totalReviews}');
    expect(edited.totalReviews, 1,
        reason: 'a second rating of the same job is an edit, not a second '
            'review — otherwise one customer could inflate a count');
    expect(edited.avgRating, 2.0);

    final relisted = await repo.workerReviews(workerId);
    expect(relisted, hasLength(1));
    expect(relisted.single.rating, 2);
    expect(relisted.single.comment, 'تأخر في التسليم');

    // 5. And the app's model reads that average back unchanged, which is what
    // every screen between here and the customer actually renders.
    expect(edited.avgRating, relisted.fold<double>(0, (a, r) => a + r.rating) /
        relisted.length);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
