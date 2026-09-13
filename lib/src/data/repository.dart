import 'dart:io';

import '../core/l10n/strings.dart';
import '../core/network/api_client.dart';
import '../models/chat.dart';
import '../models/notification.dart';
import '../models/plan.dart';
import '../models/project.dart';
import '../models/quote_review.dart';
import '../models/worker.dart';

/// Screen-facing data layer. Mirrors the web app's loaders/actions and talks
/// to the same Cloudflare Workers API. Endpoint paths here define the mobile
/// API contract the backend must expose (parallel to the web routes).
class Repository {
  Repository(this._api);

  final ApiClient _api;

  // ---- Workers / contractors -------------------------------------------
  Future<List<WorkerProfile>> topWorkers({int limit = 10}) async {
    return _rows(
        await _api.get('/api/mobile/workers/top?limit=$limit'),
        WorkerProfile.fromJson);
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
    return _rows(
        await _api.get('/api/mobile/workers/search${q.isEmpty ? '' : '?$q'}'),
        WorkerProfile.fromJson);
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

  /// Save the contractor's own profile. Only the fields that are supplied are
  /// sent, so a partially filled form can never blank out the rest.
  Future<WorkerProfile> updateMyProfile({
    String? fullName,
    String? bio,
    List<String>? specialties,
    int? experienceYears,
    int? priceRangeMin,
    int? priceRangeMax,
    int? serviceRadiusKm,
    bool? isAvailable,
    String? wilaya,
    String? commune,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (bio != null) body['bio'] = bio;
    if (specialties != null) body['specialties'] = specialties;
    if (experienceYears != null) body['experience_years'] = experienceYears;
    if (priceRangeMin != null) body['price_range_min'] = priceRangeMin;
    if (priceRangeMax != null) body['price_range_max'] = priceRangeMax;
    if (serviceRadiusKm != null) body['service_radius_km'] = serviceRadiusKm;
    if (isAvailable != null) body['is_available'] = isAvailable;
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
  Future<List<Project>> browseProjects({
    String? category,
    String? wilaya,
    ProjectStatus? status,
    int page = 1,
    int pages = 1,
  }) async {
    if (pages <= 1) {
      return _browseProjectsPage(
          category: category, wilaya: wilaya, status: status, page: page);
    }
    final batches = await Future.wait<List<Project>?>([
      for (var i = 0; i < pages; i++)
        _safeBrowsePage(
          category: category,
          wilaya: wilaya,
          status: status,
          page: page + i,
        ),
    ]);
    if (batches.every((b) => b == null)) {
      return _browseProjectsPage(
          category: category, wilaya: wilaya, status: status, page: page);
    }
    final seen = <String>{};
    final merged = <Project>[];
    for (final batch in batches) {
      for (final p in batch ?? const <Project>[]) {
        if (seen.add(p.id)) merged.add(p);
      }
    }
    return merged;
  }

  /// One page, or `null` when that page failed.
  Future<List<Project>?> _safeBrowsePage({
    String? category,
    String? wilaya,
    ProjectStatus? status,
    required int page,
  }) async {
    try {
      return await _browseProjectsPage(
          category: category, wilaya: wilaya, status: status, page: page);
    } catch (_) {
      return null;
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
      if (status != null) 'status=${status.name}',
      'page=$page',
    ].join('&');
    return _rows(
        await _api.get('/api/mobile/projects?$q'), Project.fromJson);
  }

  Future<Project> getProject(String id) async {
    return _row(
        await _api.get('/api/mobile/projects/$id'), Project.fromJson);
  }

  Future<List<Project>> myProjects({ProjectStatus? status}) async {
    final q = status != null ? '?status=${status.name}' : '';
    return _rows(
        await _api.get('/api/mobile/my/projects$q'), Project.fromJson);
  }

  Future<Project> createProject({
    required String title,
    String? description,
    required String category,
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

  Future<Message> sendImage(int conversationId, File image) async {
    final url = await _api.uploadPhoto(image);
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

/// A list of rows, parsed row by row so one malformed row cannot take the
/// whole screen down with an `Error`.
List<T> _rows<T>(Object? value, T Function(Map<String, dynamic>) fromJson) =>
    [for (final row in _asList(value)) _row(row, fromJson)];
