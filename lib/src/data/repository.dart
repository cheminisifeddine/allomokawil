import 'dart:io';

import '../core/diagnostics/crash_reporter.dart';
import '../core/l10n/strings.dart';
import '../core/network/api_client.dart';
import '../models/chat.dart';
import '../models/notification.dart';
import '../models/plan.dart';
import '../models/project.dart';
import '../models/quote_review.dart';
import '../models/worker.dart';
import 'partial_market_copy.dart';
import 'project_trade_exact.dart';
import '../models/row_identity.dart';
import 'trade_exact.dart';
import 'worker_rank.dart';

/// Screen-facing data layer. Mirrors the web app's loaders/actions and talks
/// to the same Cloudflare Workers API. Endpoint paths here define the mobile
/// API contract the backend must expose (parallel to the web routes).
class Repository {
  Repository(this._api);

  final ApiClient _api;

  // ---- Workers / contractors -------------------------------------------
  /// The best-rated contractors, with the ones in the visitor's own wilaya
  /// first when the app knows where he is.
  ///
  /// **"Best-rated" is the app's own claim and this method now enforces it.**
  /// The server sorts a mean over one review as if it were a mean over
  /// twenty-four, so measured over 50 live rows on 4 Oct the unfiltered strip
  /// opened with five accounts of one review, one job and no verified papers
  /// above a 45-job pro. [evidenceBeforeAssertion] moves those behind the rows
  /// a customer can compare, and preserves the server's order inside each
  /// group — the app decides which group a contractor is in, not how a man with
  /// thirty reviews ranks against a man with fifteen.
  ///
  /// The ordering is client-side on purpose: asking the server to filter would
  /// empty the strip in a wilaya where no contractor has signed up yet, and a
  /// client's home must never lose its contractors because of the visitor's
  /// phone. «Near you first» keeps everyone on the screen and still answers the
  /// founder's «show related offers» brief. The wider fetch exists so a
  /// same-wilaya contractor can reach the front even when he is not in the
  /// default top ten.
  Future<List<WorkerProfile>> topWorkers(
      {int limit = 10, String? preferWilaya}) async {
    final prefer = preferWilaya != null && preferWilaya.isNotEmpty;
    final rows = _rows(
        await _api.get(
            '/api/mobile/workers/top?limit=${prefer ? limit * 4 : limit}'),
        WorkerProfile.fromJson);
    if (!prefer) return evidenceBeforeAssertion(rows).take(limit).toList();
    final near = <WorkerProfile>[];
    final rest = <WorkerProfile>[];
    for (final w in rows) {
      (w.wilaya == preferWilaya ? near : rest).add(w);
    }
    // **Partition each group, then take.** The order matters and it is the
    // whole fix: `take` before the partition would let the first twelve rows
    // the server sent fill the strip and leave nothing to reorder, which is
    // precisely how the five single-review accounts got there in the first
    // place. Same order [customer_home_screen] applies to its project strip.
    return <WorkerProfile>[
      ...evidenceBeforeAssertion(near),
      ...evidenceBeforeAssertion(rest),
    ].take(limit).toList();
  }

  Future<List<WorkerProfile>> searchWorkers({
    String? category,
    String? wilaya,
    String? query,
  }) async {
    final q = <String>[
      if (category != null) 'category=$category',
      if (wilaya != null) 'wilaya=$wilaya',
      if (query != null && query.trim().isNotEmpty)
        'q=${Uri.encodeQueryComponent(query.trim())}',
    ].join('&');
    final rows = _rows(
        await _api.get('/api/mobile/workers/search${q.isEmpty ? '' : '?$q'}'),
        WorkerProfile.fromJson);
    // The server matches `category` on a substring, so its answer is a
    // superset: `category=wallpaper` came back with six painters in it on
    // 4 Oct. See `data/trade_exact.dart` for the measurement. Server order is
    // kept exactly — this narrows membership, it does not re-rank.
    return exactTradeOnly(rows, category);
  }

  Future<WorkerProfile> getWorker(int id) async {
    return _row(
        await _api.get('/api/mobile/workers/$id'), WorkerProfile.fromJson);
  }

  /// Portfolio gallery image URLs for a contractor's profile.
  Future<List<String>> portfolioImages(int workerId) async {
    final data =
        _asList(await _api.get('/api/mobile/workers/$workerId/portfolio'));
    return data.map((e) {
      // The endpoint answers either a row per photo or a bare URL per photo
      // depending on the deploy; anything else is dropped instead of raising.
      final url = e is Map ? e['image_url'] : e;
      return url is String ? url : '';
    }).where((s) => s.isNotEmpty).toList();
  }

  /// Adds one picture to the signed-in contractor's own gallery.
  ///
  /// The file goes to R2 first (`uploadPhoto`) and only the resulting URL is
  /// posted, so a full-resolution phone photo never travels as JSON — which is
  /// also why the upload has to succeed before this returns: the URL is what the
  /// public profile will show.
  Future<void> addPortfolioImage(
    int workerId, {
    required String imageUrl,
    String? category,
    String? caption,
  }) async {
    await _api.post('/api/mobile/workers/$workerId/portfolio', body: {
      'image_url': imageUrl,
      if (category != null && category.isNotEmpty) 'category': category,
      if (caption != null && caption.trim().isNotEmpty)
        'caption': caption.trim(),
    });
  }

  // ---- Projects ---------------------------------------------------------
  /// The signed-in contractor's own profile (for verification & portfolio).
  Future<WorkerProfile> myProfile() async {
    return _row(
        await _api.get('/api/mobile/my/profile'), WorkerProfile.fromJson);
  }

  /// Save the contractor's own profile.
  ///
  /// Every field the profile form owns is sent **unconditionally**, which is the
  /// whole point of this method and was quietly its opposite. It used to add a
  /// key only when the value was non-null, so an emptied field produced a body
  /// with no key in it — the PATCH returned 200, the screen said «تم حفظ ملفك
  /// بنجاح», and the server kept the old value. A contractor who cleared the
  /// price range to quote per project kept printing 20000-60000 دج to every
  /// customer, and nothing anywhere reported a failure, because nothing had
  /// failed. See `profile_write_outcome.dart`.
  ///
  /// The nullable parameters stay nullable because *these* fields are genuinely
  /// partial — `wilaya` and `commune` are only ever sent by callers that
  /// actually have a place to put them, and a caller with nothing to say about
  /// the wilaya must not blank the one the server holds.
  Future<WorkerProfile> updateMyProfile({
    required String fullName,
    required String bio,
    required List<String> specialties,
    required int experienceYears,
    required int? priceRangeMin,
    required int? priceRangeMax,
    required int serviceRadiusKm,
    required bool isAvailable,
    String? wilaya,
    String? commune,
  }) async {
    final body = <String, dynamic>{
      // The five form fields are sent whatever they hold, null included, because
      // an empty box is a *decision* by the user and not an absent answer. The
      // server's own clear-the-column rule is the one thing this cannot verify
      // from the phone, so the screen re-reads and compares rather than
      // asserting; see `ProfileSnapshot`.
      'full_name': fullName,
      'bio': bio,
      'specialties': specialties,
      'experience_years': experienceYears,
      'price_range_min': priceRangeMin,
      'price_range_max': priceRangeMax,
      'service_radius_km': serviceRadiusKm,
      'is_available': isAvailable,
    };
    if (wilaya != null) body['wilaya'] = wilaya;
    if (commune != null) body['commune'] = commune;
    return _row(await _api.patch('/api/mobile/my/profile', body: body),
        WorkerProfile.fromJson);
  }

  /// Open projects for the contractor feed.
  ///
  /// The endpoint pages in hard-coded chunks of 20 rows and has no text query
  /// (SQLite on D1 cannot fold Arabic orthography), so [pages] lets the feed
  /// pull several pages at once and filter the union — otherwise a search would
  /// only ever see the newest twenty projects on the whole platform.
  ///
  /// Pages are fetched concurrently and de-duplicated by id. One failing page
  /// does not sink the batch; if *every* page fails the first page is re-issued
  /// so the caller still gets the real error instead of a silently empty market.
  ///
  /// **That doc was half true, and the half that was false is the half that
  /// happens in the field.** The batch was judged on `every (b) => b == null`:
  /// only pages that *threw* counted as lost. But a search widens to
  /// [pages] rows precisely because the market is bigger than one page — and
  /// on a marketplace that is still growing, the tail pages legitimately answer
  /// `[]` because there is no page 6. An empty page is a *successful* answer,
  /// so a batch where four of five pages were lost still passed the check and
  /// the search quietly narrowed to the pages that happened to be alive.
  ///
  /// The contractor's screen cannot see the difference. He types «دهان», gets
  /// «لا توجد نتائج», and reads *nothing on the market matches* — while a
  /// third of the postings he never saw are sitting on the server. «No
  /// results» and «I could not read a third of the market» are identical on
  /// screen and mean opposite things.
  ///
  /// So the batch is now judged on pages **lost**, not on pages that threw:
  ///
  ///   * **A lost page is recorded**, with the page number, so a short result
  ///     set is never a silent under-search.
  ///   * **The head page is re-issued whenever it was one of the lost ones.**
  ///     Page 1 is every newest posting — the ones a contractor opening the
  ///     app most wants to quote on. Losing it is the case that turns a live
  ///     market into an empty one, because a marketplace with fewer than 20
  ///     open projects answers pages 2-5 with `[]` truthfully: so every
  ///     *other* page looks healthy while the one that carries the market is
  ///     gone, and «every page failed» is false when the batch is in exactly
  ///     the state that matters. Re-issuing it turns that one-sided truth back
  ///     into a real answer.
  ///   * **A page that answered empty is still an answer.** A wilaya with no
  ///     open projects is an empty market, not an error, and must keep
  ///     rendering the empty state.
  Future<List<Project>> browseProjects({
    String? category,
    String? wilaya,
    ProjectStatus? status,
    int page = 1,
    int pages = 1,
  }) async {
    final result = await browseProjectsPaged(
      category: category,
      wilaya: wilaya,
      status: status,
      page: page,
      pages: pages,
    );
    return result.rows;
  }

  /// [browseProjects], plus the pages of the widen that never answered.
  ///
  /// **A second entry point, and the reason for it is the loss.** A row list
  /// answers «what did you find»; it cannot also answer «what did you not look
  /// at», so a caller that renders a verdict about the market — «لا نتائج
  /// مطابقة» — cannot tell a complete search from a partial one. Threading the
  /// count through the existing method's return type would have made every
  /// ordinary caller read `.rows` to get at rows it already had, and this is a
  /// repository used by six screens that do not widen at all. So the loss is an
  /// opt-in: the plain method keeps its contract, and the caller that prints a
  /// verdict asks for the one that can refuse to print it.
  Future<MarketPageResult> browseProjectsPaged({
    String? category,
    String? wilaya,
    ProjectStatus? status,
    int page = 1,
    int pages = 1,
  }) async {
    if (pages <= 1) {
      return MarketPageResult(await _browseProjectsPage(
          category: category, wilaya: wilaya, status: status, page: page));
    }
    final batches = await Future.wait<_PageBatch>([
      for (var i = 0; i < pages; i++)
        _safeBrowsePage(
          category: category,
          wilaya: wilaya,
          status: status,
          page: page + i,
        ),
    ]);
    final lost = <int>[
      for (var i = 0; i < batches.length; i++)
        if (batches[i].failure != null) page + i,
    ];
    for (var i = 0; i < batches.length; i++) {
      final failure = batches[i].failure;
      if (failure == null) continue;
      CrashReporter.active?.capture(
        'صفحة ${page + i} من بحث السوق لم تصل',
        null,
        kind: 'page',
        context: '${lost.length} of $pages pages could not be read'
            ' · ${_whyItFailed(failure)}',
      );
    }
    // The head page carries the newest postings, so losing it is the case that
    // turns a live market into an empty one: on a marketplace with fewer open
    // projects than one page holds, every other page answers `[]` truthfully
    // and looks healthy. Re-issue it — and if it is still dead the caller gets
    // the real error, never an empty list that reads as «لا توجد نتائج».
    //
    // **The re-issue heals the head, it does not replace the batch.** It used
    // to `return` the re-issued page straight to the caller, which threw away
    // every page that had answered in the same batch: on a full market the
    // search came back holding *one* page instead of five, so the widen that
    // exists to reach a project on page 3 was making page 3 unreachable. The
    // retry is a repair, and a repair merges.
    if (lost.isNotEmpty && lost.first == page) {
      batches[0] = _PageBatch(await _browseProjectsPage(
          category: category, wilaya: wilaya, status: status, page: page));
    }
    final seen = <String>{};
    final merged = <Project>[];
    for (final batch in batches) {
      for (final p in batch.rows ?? const <Project>[]) {
        if (seen.add(p.id)) merged.add(p);
      }
    }
    // **The loss travels with the rows, not only to the log.** This count used
    // to stop at `CrashReporter`, which support reads the morning after and
    // the contractor never sees: the screen merged the union, set
    // `_widened = true`, and let the in-memory filter declare «لا نتائج
    // مطابقة» over a market it had read three pages of five. The row list is
    // an answer to «what did you find»; it cannot also carry «what did you not
    // look at», so the second has to be a separate value or it is lost.
    return MarketPageResult(merged,
        lostPages: lost.length, requestedPages: pages);
  }

  /// One page, or a record holding the error that stopped it answering.
  ///
  /// The error used to be dropped here and the page reduced to `null`, so the
  /// `ApiException` — with the status code and the cause, the only two
  /// things that say *which* failure this was — never reached the record.
  /// Carrying it costs one nullable field and is the difference between a
  /// support log that can answer the question and one that only timestamps it.
  Future<_PageBatch> _safeBrowsePage({
    String? category,
    String? wilaya,
    ProjectStatus? status,
    required int page,
  }) async {
    try {
      return _PageBatch(await _browseProjectsPage(
          category: category, wilaya: wilaya, status: status, page: page));
    } catch (error) {
      return _PageBatch(null, error);
    }
  }

  Future<List<Project>> _browseProjectsPage({
    String? category,
    String? wilaya,
    ProjectStatus? status,
    required int page,
  }) async {
    final q = <String>[
      if (category != null) 'category=$category',
      if (wilaya != null) 'wilaya=$wilaya',
      // `.wire`, not `.name` — see [ProjectStatus.wire]. The market's own
      // in-progress filter asked for `inProgress` and matched nothing.
      if (status != null) 'status=${status.wire}',
      'page=$page',
    ].join('&');
    final rows = _rows(
        await _api.get('/api/mobile/projects?$q'), Project.fromJson);
    // The server answers `category` with a *family union*, so its answer is a
    // superset: `category=wallpaper` came back with 17 rows and 1 of them was
    // wallpaper on 4 Oct, while `category=painting` came back with the same 17.
    // See `data/project_trade_exact.dart` for the measurement — and for why
    // this endpoint widens by family and not by substring, which is *not* what
    // the directory's own filter does. Server order is kept exactly: this
    // narrows membership, it does not re-rank.
    return exactProjectTrades(rows, category);
  }

  Future<Project> getProject(String id) async {
    return _row(
        await _api.get('/api/mobile/projects/$id'), Project.fromJson);
  }

  Future<List<Project>> myProjects({ProjectStatus? status}) async {
    // `.wire`, not `.name`, for the reason in [ProjectStatus.wire]: the
    // «قيد التنفيذ» tab on «مشاريعي» answered with zero rows for a project
    // that was in progress.
    final q = status != null ? '?status=${status.wire}' : '';
    return _rows(
        await _api.get('/api/mobile/my/projects$q'), Project.fromJson);
  }

  Future<Project> createProject({
    required String title,
    String? description,
    required String category,
    List<String>? categories,
    String? wilaya,
    String? commune,
    int? budgetMin,
    int? budgetMax,
    required UrgencyLevel urgency,
    List<String> images = const [],
  }) async {
    return _row(await _api.post('/api/mobile/projects', body: {
      'title': title,
      'description': description,
      'category': category,
      // The full list of trades. `category` stays for older servers; the API
      // takes the first entry as the primary either way.
      'categories': (categories == null || categories.isEmpty)
          ? [category]
          : categories,
      'wilaya': wilaya,
      'commune': commune,
      'budget_min': budgetMin,
      'budget_max': budgetMax,
      // `.wire`, not `.name`: the API writes this straight into a column
      // whose CHECK only accepts the snake_case values.
      'urgency': urgency.wire,
      'images': images,
    }), Project.fromJson);
  }

  /// Edits a posted project. Same fields and same validation as
  /// [createProject] because it is the same form — the API refuses the edit
  /// once a contractor has been chosen, so this is only sent while `open`.
  ///
  /// `images` is always sent: the screen holds the pictures the project
  /// already has plus anything just attached, so an edit can drop a photo as
  /// well as add one.
  Future<Project> updateProject(
    String projectId, {
    required String title,
    String? description,
    required String category,
    List<String>? categories,
    String? wilaya,
    String? commune,
    int? budgetMin,
    int? budgetMax,
    required UrgencyLevel urgency,
    List<String> images = const [],
  }) async {
    return _row(await _api.patch('/api/mobile/projects/$projectId', body: {
      'title': title,
      'description': description,
      'category': category,
      'categories': (categories == null || categories.isEmpty)
          ? [category]
          : categories,
      'wilaya': wilaya,
      'commune': commune,
      'budget_min': budgetMin,
      'budget_max': budgetMax,
      'urgency': urgency.wire,
      'images': images,
    }), Project.fromJson);
  }

  /// Cancels a posted project — the owner's own project only.
  ///
  /// Server-side this also withdraws every pending quote and notifies the
  /// chosen contractor, so the app does not have to unpick the offers itself.
  Future<void> cancelProject(String projectId) async {
    await _api.post('/api/mobile/projects/$projectId/cancel');
  }

  // ---- Quotes -----------------------------------------------------------
  Future<List<Quote>> projectQuotes(String projectId) async {
    return _rows(
        await _api.get('/api/mobile/projects/$projectId/quotes'), Quote.fromJson);
  }

  Future<Quote> submitQuote({
    required String projectId,
    required int amount,
    String? message,
    int? estimatedDays,
  }) async {
    return _row(
        await _api.post('/api/mobile/projects/$projectId/quotes', body: {
      'amount': amount,
      'message': message,
      'estimated_days': estimatedDays,
    }),
        Quote.fromJson);
  }

  Future<void> acceptQuote(String projectId, int quoteId) async {
    await _api.post('/api/mobile/projects/$projectId/quotes/$quoteId/accept');
  }

  Future<void> completeProject(String projectId, {int? workerId}) async {
    await _api.post('/api/mobile/projects/$projectId/complete',
        body: {'worker_id': workerId});
  }

  // ---- Reviews ----------------------------------------------------------
  /// Publishes the customer's rating for a finished job.
  ///
  /// The endpoint answers `{ok: true}` and nothing else — it does not echo the
  /// review row back. This used to hand that ack to `Review.fromJson`, which
  /// reads `id` with a hard cast, so the real response threw a `_TypeError`
  /// ("type 'Null' is not a subtype of type 'int'"). A `TypeError` is an
  /// `Error`, not an `Exception`, so the screen's `on Exception` catch never
  /// saw it either: the server stored the rating while the app showed no
  /// confirmation and stayed on the form. Nothing here parses an ack; the
  /// caller reads the result the way every other viewer does, through
  /// [workerReviews] and [getWorker].
  Future<void> createReview({
    required String projectId,
    required int workerId,
    required int rating,
    String? comment,
  }) async {
    await _api.post('/api/mobile/projects/$projectId/review', body: {
      'worker_id': workerId,
      'rating': rating,
      'comment': comment,
    });
  }

  Future<List<Review>> workerReviews(int workerId) async {
    return _rows(
        await _api.get('/api/mobile/workers/$workerId/reviews'), Review.fromJson);
  }

  // ---- Chat -------------------------------------------------------------
  /// Get or create the conversation thread for (customer, worker, project).
  Future<int> openConversation({
    String? projectId,
    int otherUserId = 0,
  }) async {
    final data = _asMap(await _api.post('/api/mobile/conversations', body: {
      'project_id': projectId,
      'other_user_id': otherUserId,
    }));
    return _asInt(data['id']);
  }

  Future<List<Conversation>> conversations() async {
    return _rows(
        await _api.get('/api/mobile/conversations'), Conversation.fromJson);
  }

  Future<List<Message>> messages(int conversationId, {int after = 0}) async {
    return _rows(
        await _api.get(
            '/api/messages/$conversationId${after > 0 ? '?after=$after' : ''}'),
        Message.fromJson);
  }

  Future<Message> sendText(int conversationId, String text) async {
    return _row(await _api.post('/api/messages/$conversationId', body: {
      'content': text,
      'message_type': 'text',
    }), Message.fromJson);
  }

  /// Uploads a picture and posts it into [conversationId].
  ///
  /// [onUploaded] is called with the R2 URL the upload returned, **before** the
  /// message row is posted, and it exists because a picture cannot be identified
  /// in a later re-read without it. The row the server holds carries
  /// `image_url`; the phone holds a local path. Those are different namespaces
  /// and were never equal, so the phone asked the re-read «did my message
  /// arrive?» with a comparison that could not possibly match a photo — and
  /// `null == null` matched one anyway. See `data/thread_match.dart`.
  ///
  /// The callback is awaited, so a caller that has somewhere to put the URL has
  /// put it there by the time this returns, and an upload whose answer arrived
  /// but whose message row did not can still be recognised as delivered.
  Future<Message> sendImage(int conversationId, File image,
      {Future<void> Function(String url)? onUploaded}) async {
    final url = await _api.uploadPhoto(image);
    if (onUploaded != null) await onUploaded(url);
    return _row(await _api.post('/api/messages/$conversationId', body: {
      'image_url': url,
      'message_type': 'image',
    }), Message.fromJson);
  }

  // ---- Notifications ----------------------------------------------------
  Future<List<AppNotification>> notifications() async {
    return _rows(
        await _api.get('/api/notifications'), AppNotification.fromJson);
  }

  /// Marks notifications read and returns the server's new unread count.
  ///
  /// With no [ids] every notification is cleared — that is the
  /// «تعليم الكل كمقروء» action. The count comes back so the caller never has
  /// to guess what the database now holds.
  Future<int> markNotificationsRead({List<int>? ids}) async {
    final data = await _api.post(
      '/api/notifications/read',
      body: ids == null
          ? const <String, Object?>{}
          : <String, Object?>{'ids': ids},
    );
    if (data is num) {
      return data.toInt();
    }
    if (data is Map && data['unread'] is num) {
      return (data['unread'] as num).toInt();
    }
    return 0;
  }

  Future<int> unreadCount() async {
    final data = await _api.get('/api/unread');
    // The backend answers {"unread": n}; accept a bare number too.
    if (data is num) return data.toInt();
    if (data is Map && data['unread'] is num) {
      return (data['unread'] as num).toInt();
    }
    return 0;
  }

  // ---- Verification -----------------------------------------------------
  Future<void> submitVerification(
    int workerId,
    List<Map<String, dynamic>> documents,
  ) async {
    await _api.post('/api/mobile/workers/$workerId/verification', body: {
      'documents': documents,
    });
  }

  Future<String> uploadDocument(File file) => _api.uploadPhoto(file);

  // ---- Subscription (contractor billing) ---------------------------------
  //
  // The founder's model is subscription-only: the مقاول pays for a plan,
  // and nobody takes a commission on an order or a percentage of a project.
  // These four calls are the whole surface the app needs for that.

  /// The public price list. Works before sign-in, so a contractor can see what
  /// he would pay before he creates an account.
  Future<PlanCatalogue> planCatalogue() async {
    return _row(
        await _api.get('/api/mobile/plans'), PlanCatalogue.fromJson);
  }

  /// The live plan, this month's usage, and how to pay.
  Future<BillingCatalogue> subscription() async {
    return _row(
        await _api.get('/api/mobile/subscription'), BillingCatalogue.fromJson);
  }

  /// Declares a payment. Deliberately does NOT change the plan — only confirmed
  /// money flips a plan, so a contractor cannot talk his way into a paid tier
  /// by posting to this endpoint.
  Future<Map<String, dynamic>> requestSubscription({
    required String plan,
    required BillingPeriod period,
    required String method,
    String? reference,
  }) async {
    final data = await _api.post('/api/mobile/subscription', body: {
      'plan': plan,
      'period': period.wire,
      'method': method,
      if (reference != null && reference.trim().isNotEmpty)
        'reference': reference.trim(),
    });
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry('$k', v));
    return const {};
  }

  /// Redeems a prepaid activation code — the path a contractor who paid cash
  /// or by BaridiMob actually uses. Answers the plan id that is now live.
  Future<String?> redeemActivationCode(String code) async {
    final data = await _api.post('/api/mobile/subscription/redeem',
        body: {'code': code.trim().toUpperCase()});
    if (data is Map && data['plan'] is Map) {
      return '${(data['plan'] as Map)['id']}';
    }
    return null;
  }
}

// ---- Response shape guards ----------------------------------------------
//
// One bad row used to be a silent failure. `jsonDecode` hands back whatever
// the API sent, the repository cast it with `as List` / `as Map<String,
// dynamic>`, and a drifted column — a null `id`, a string where a number
// belongs — raised a `TypeError`. A `TypeError` is an `Error`, not an
// `Exception`, so the screens' catch clauses never saw it and the user got a
// dead button with no sentence on screen. These four helpers convert every
// one of those shapes into the same Arabic, retryable [ApiException] the rest
// of the app already renders through `errorCopy`.

/// The response body as a JSON array, or Arabic copy when it is not one.
List<dynamic> _asList(Object? value) {
  if (value is List) return value;
  throw ApiException(S.errUnexpected, cause: value);
}

/// The response body as a JSON object, or Arabic copy when it is not one.
Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw ApiException(S.errUnexpected, cause: value);
}

/// An integer field, or Arabic copy when the column came back as something
/// else (a null from a LEFT JOIN, a string from SQLite).
int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw ApiException(S.errUnexpected, cause: value);
}

/// One row, parsed by [fromJson]. A model cast that fails on a malformed row
/// becomes the same sentence instead of a `TypeError` escaping to the screen.
T _row<T>(Object? value, T Function(Map<String, dynamic>) fromJson) {
  try {
    return fromJson(_asMap(value));
  } on ApiException {
    rethrow;
  } catch (e) {
    throw ApiException(S.errUnexpected, cause: e);
  }
}

/// One page of a widened search: the rows it answered with, or the error that
/// stopped it answering. Exactly one of the two is set.
class _PageBatch {
  const _PageBatch(this.rows, [this.failure]);

  /// The rows, or `null` when the page never answered.
  final List<Project>? rows;

  /// What the page threw, kept so the record can say *why* it is missing.
  final Object? failure;
}

/// What a widened market read returned: the rows it reached, and the pages it
/// did not.
///
/// **This type exists because the loss was being told to the wrong reader.**
/// `browseProjects` records every page it could not read on the diagnostics
/// channel, which is a place only support can look, and returns a bare
/// `List<Project>` — so the count had no path to the widget that prints the
/// answer. A contractor searching «دهان» while three of five pages were down
/// was told «لا نتائج مطابقة» — *nothing matches* — and that sentence is a
/// verdict about a market he had not been allowed to read. See
/// `data/partial_market_copy.dart`.
///
/// The count is carried rather than logged because the two are not the same
/// audience: the log is read after a support message arrives, and the line on
/// screen is read by the man who is about to decide whether to bid.
class MarketPageResult {
  const MarketPageResult(this.rows, {this.lostPages = 0, this.requestedPages = 1});

  /// The union of every page that answered, de-duplicated by id.
  final List<Project> rows;

  /// How many of the pages asked for never answered.
  ///
  /// A page that answered **empty** is not counted: an empty market is an
  /// answer, and a wilaya with no open projects must keep rendering «لا مشاريع
  /// مفتوحة» rather than a band about a network.
  final int lostPages;

  /// How many pages the caller asked for, so the sentence can name the gap
  /// («3 من 5») instead of an absolute the reader cannot judge.
  final int requestedPages;

  /// True when the search may print «لا نتائج مطابقة».
  ///
  /// Delegated to the copy layer so the rule has one owner: a verdict about
  /// the market may only be printed by a read that covered the market.
  bool get mayClaimNoResults => partialMarketMayClaimNoResults(
      lost: lostPages, total: requestedPages);
}

/// Why a page could not be read, in the terms a support reply can act on.
///
/// The four failures that actually happen in the field are indistinguishable
/// from the page number alone: a 500 from the Worker, a 401 that means the
/// session died mid-search, a dead socket or a timeout, and a row shape the
/// parser has never seen. The first two are the API's problem, the third is
/// the phone's network, the fourth is a bug in the app — and the fix for
/// each is different, so a record that cannot separate them can only be
/// answered with a guess shipped to a user.
///
/// Logging only: this never reaches a screen. [ApiException.cause] is already
/// documented as never shown to the user, and a type name is not copy.
String _whyItFailed(Object error) {
  if (error is ApiException) {
    final status = error.statusCode;
    final cause = error.cause;
    return <String>[
      if (status != null) 'HTTP $status',
      if (cause != null) cause.runtimeType.toString(),
      if (status == null && cause == null) error.message,
    ].join(' · ');
  }
  return error.runtimeType.toString();
}

/// Why a **row** could not be read, by the shape that broke rather than by the
/// value that broke it.
///
/// The sibling of [_whyItFailed], and the other half of the same defect. A
/// dropped row is a different failure from a lost page — it is never the
/// network, it is the shape of what the Worker sent — and it arrives as the
/// same Arabic sentence, because the parser refuses a column and keeps only
/// what it refused.
///
/// **The refused thing is the value, and the value is not the finding.** A
/// drifted `wilaya` made the record read `null`, a `user_id` that came back as
/// a string made it read `abc`: a log line that is literally the server's
/// payload, carrying no type, no column and no way to tell a null from a
/// missing key. What a support reply can act on is *which shape arrived where
/// an int was expected* — that names the line in the model to go and read, and
/// the same value can be perfectly valid somewhere else.
///
/// [Type] as a support log should read it: `TypeError`, not `_TypeError`.
String _whyRowFailed(ApiException error) {
  final cause = error.cause;
  if (cause == null) return error.message;
  // `_asMap`/`_asInt` keep the value they refused, and a failed cast keeps the
  // `TypeError`. `runtimeType` is the part of either that survives being a user
  // datum — and it is the part that points at a line of a model to go and read.
  return _publicName(cause.runtimeType);
}

/// The cause recorded for a row that parsed and is still not drawable.
///
/// A word and not a type, because nothing failed: the row answered, it just
/// could not be drawn. It is what makes this line tell a support reader that
/// the fix is in the model's identity rule rather than in a column on the
/// Worker.
const _undrawable = 'unreadable row identity';

/// The cause for a feed whose rows all read and none of them can be drawn.
///
/// A private type so a support log names a *shape* («UndrawableRow»), which is
/// what `_whyRowFailed` was written to print, and never a server value.
class _UndrawableRow {
  const _UndrawableRow();
}

/// [Type] as a support log should read it: `TypeError`, not `_TypeError`.
///
/// Dart's own error types are private, so their `runtimeType` prints with a
/// leading underscore — a name that does not exist in any source file and would
/// send a support reply looking for a class the project has never heard of.
/// Everything else is already the name a developer would type.
String _publicName(Type type) {
  final name = type.toString();
  return name.startsWith('_') ? name.substring(1) : name;
}

/// A list of rows, parsed row by row so one malformed row cannot take the
/// whole screen down with an `Error`.
///
/// **The doc was a promise the code did not keep.** This was a list
/// comprehension, which builds every element eagerly, so the first drifted
/// column — one `id` that came back null, one `wilaya` SQLite handed over as
/// an integer — raised out of the whole expression. The caller got the Arabic
/// «حدث خطأ غير متوقع» sentence with an **empty screen behind it**, and the
/// workers that came back in the very same 200, perfectly readable, were thrown
/// away with the broken one.
///
/// That is the worst possible reading of a 200. A feed is not one row: a
/// contractor whose profile drifted cannot be the reason a visitor opening the
/// app sees an empty market, or a man waiting on a quote sees an empty list,
/// because a *different* profile has a bad column. The blast radius was the
/// whole page instead of one card.
///
/// So a row that will not parse is **dropped** and the readable ones are
/// returned. Two boundaries hold that line, and both are load-bearing:
///
///   * **An empty answer is not a failure.** `[]` is what the Worker sends
///     when a contractor has no projects, a wilaya has no workers or the bell
///     has nothing. Throwing there would turn every genuinely empty screen in
///     the app into an error card — so the count that decides is the number of
///     rows **arrived**, not the number that parsed.
///   * **Nothing readable is still a failure.** When rows arrived and every
///     one of them failed, the screen must not render «لا توجد إشعارات بعد» —
///     copy that says *there is nothing here*, where the truth is *we could not
///     read what is here*. Those two look identical to a user and mean opposite
///     things, so this case keeps raising, with the **first row's own**
///     exception re-thrown, so its status code and cause survive unchanged.
///
/// A dropped row is **not silent**: it is captured on the diagnostics channel
/// with `kind: 'row'`, so it lands in the log the next support message reads.
/// That is the whole reason a partial feed is safe to render — the contractor
/// the user came for can be the one that was dropped, and without a record of
/// it the app has no way to say so. [CrashReporter.active] is null before boot
/// installs the reporter, which is correct: there is nowhere to write to yet,
/// and the screen still renders everything it could read.
List<T> _rows<T>(
  Object? value,
  T Function(Map<String, dynamic>) fromJson,
) {
  final arrived = _asList(value);
  final out = <T>[];
  Object? firstFailure;
  // The distinct causes, in first-seen order, so the record can name the
  // shapes it could not read without repeating one of them per row.
  final causes = <String>[];
  var lost = 0;
  for (var i = 0; i < arrived.length; i++) {
    try {
      final row = _row(arrived[i], fromJson);
      // **Readable, or drawable.** A tolerant parser no longer throws on a
      // shape it did not expect, which left this loop with no way to notice a
      // row that parsed and is still undrawable — the models made tolerant
      // carry `RenderableRow` for exactly this, and the check is what keeps
      // «a card whose profile link can only 404» out of the market.
      //
      // A model that does not declare it is renderable, so the opt-in costs a
      // row nothing: it can only ever drop a row that says it cannot be drawn.
      if (row is RenderableRow && !row.isRenderable) {
        lost++;
        if (!causes.contains(_undrawable)) causes.add(_undrawable);
        continue;
      }
      out.add(row);
    } on ApiException catch (e) {
      firstFailure ??= e;
      lost++;
      final why = _whyRowFailed(e);
      if (!causes.contains(why)) causes.add(why);
    }
  }
  // **One record per parse, not one per dropped row.** The capture used to sit
  // inside the loop, so a feed that lost three rows wrote three lines, and each
  // of them read «1 of 5 rows could not be read» — the log said 1, 1 and 1 for a
  // feed that was missing a third of the market. It is a report about the
  // response, not about a row, so it is written once the response is read.
  if (lost > 0) {
    CrashReporter.active?.capture(
      'سطر غير قابل للقراءة ($T)',
      null,
      kind: 'row',
      context: '$lost of ${arrived.length} rows could not be read'
          '${causes.isEmpty ? '' : ' · ${causes.join(', ')}'}',
    );
  }
  // **Nothing drawable is still a failure**, and after this change that case can
  // arrive without any exception to re-throw: a tolerant model reads a row the
  // app cannot draw and says so, so `firstFailure` is null while `lost` is not.
  // The boundary is the same one the doc states — rows arrived, and none of them
  // can be drawn, so «there is nothing here» would be a lie — and the sentence
  // is the same one, built from the same Arabic string every other unexpected
  // read uses.
  //
  // The cause is a private sentinel, not a row: a record must never print the
  // server's value (`rows_partial_test` pins that), and there is no value here
  // anyway — nothing failed, the rows simply could not be drawn.
  final failure = firstFailure;
  if (out.isEmpty && failure != null) {
    throw failure;
  }
  if (out.isEmpty && lost > 0) {
    throw ApiException(S.errUnexpected, cause: const _UndrawableRow());
  }
  return out;
}
