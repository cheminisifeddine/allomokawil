import 'dart:io';

import '../core/network/api_client.dart';
import '../models/chat.dart';
import '../models/notification.dart';
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
    final data = await _api.get('/api/mobile/workers/top?limit=$limit') as List;
    return data
        .map((e) => WorkerProfile.fromJson(e as Map<String, dynamic>))
        .toList();
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
    final data =
        await _api.get('/api/mobile/workers/search${q.isEmpty ? '' : '?$q'}')
            as List;
    return data
        .map((e) => WorkerProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WorkerProfile> getWorker(int id) async {
    final data = await _api.get('/api/mobile/workers/$id')
        as Map<String, dynamic>;
    return WorkerProfile.fromJson(data);
  }

  /// Portfolio gallery image URLs for a contractor's profile.
  Future<List<String>> portfolioImages(int workerId) async {
    final data = await _api.get('/api/mobile/workers/$workerId/portfolio')
        as List;
    return data
        .map((e) => (e is Map) ? (e['image_url'] as String?) ?? '' : e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
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
    final data = await _api.get('/api/mobile/my/profile')
        as Map<String, dynamic>;
    return WorkerProfile.fromJson(data);
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
    final data = await _api.patch('/api/mobile/my/profile', body: body)
        as Map<String, dynamic>;
    return WorkerProfile.fromJson(data);
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
    final data = await _api.get('/api/mobile/projects?$q') as List;
    return data
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Project> getProject(String id) async {
    final data = await _api.get('/api/mobile/projects/$id')
        as Map<String, dynamic>;
    return Project.fromJson(data);
  }

  Future<List<Project>> myProjects({ProjectStatus? status}) async {
    final q = status != null ? '?status=${status.name}' : '';
    final data = await _api.get('/api/mobile/my/projects$q') as List;
    return data
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList();
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
    final data = await _api.post('/api/mobile/projects', body: {
      'title': title,
      'description': description,
      'category': category,
      'wilaya': wilaya,
      'commune': commune,
      'budget_min': budgetMin,
      'budget_max': budgetMax,
      'urgency': urgency.name,
      'images': images,
    }) as Map<String, dynamic>;
    return Project.fromJson(data);
  }

  // ---- Quotes -----------------------------------------------------------
  Future<List<Quote>> projectQuotes(String projectId) async {
    final data = await _api.get('/api/mobile/projects/$projectId/quotes')
        as List;
    return data
        .map((e) => Quote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Quote> submitQuote({
    required String projectId,
    required int amount,
    String? message,
    int? estimatedDays,
  }) async {
    final data = await _api.post('/api/mobile/projects/$projectId/quotes',
        body: {
      'amount': amount,
      'message': message,
      'estimated_days': estimatedDays,
    }) as Map<String, dynamic>;
    return Quote.fromJson(data);
  }

  Future<void> acceptQuote(String projectId, int quoteId) async {
    await _api.post('/api/mobile/projects/$projectId/quotes/$quoteId/accept');
  }

  Future<void> completeProject(String projectId, {int? workerId}) async {
    await _api.post('/api/mobile/projects/$projectId/complete',
        body: {'worker_id': workerId});
  }

  // ---- Reviews ----------------------------------------------------------
  Future<Review> createReview({
    required String projectId,
    required int workerId,
    required int rating,
    String? comment,
  }) async {
    final data = await _api.post('/api/mobile/projects/$projectId/review',
        body: {
      'worker_id': workerId,
      'rating': rating,
      'comment': comment,
    }) as Map<String, dynamic>;
    return Review.fromJson(data);
  }

  Future<List<Review>> workerReviews(int workerId) async {
    final data = await _api.get('/api/mobile/workers/$workerId/reviews')
        as List;
    return data
        .map((e) => Review.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Chat -------------------------------------------------------------
  /// Get or create the conversation thread for (customer, worker, project).
  Future<int> openConversation({
    String? projectId,
    int otherUserId = 0,
  }) async {
    final data = await _api.post('/api/mobile/conversations', body: {
      'project_id': projectId,
      'other_user_id': otherUserId,
    }) as Map<String, dynamic>;
    return data['id'] as int;
  }

  Future<List<Conversation>> conversations() async {
    final data = await _api.get('/api/mobile/conversations') as List;
    return data
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Message>> messages(int conversationId, {int after = 0}) async {
    final data = await _api.get(
            '/api/messages/$conversationId${after > 0 ? '?after=$after' : ''}')
        as List;
    return data
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Message> sendText(int conversationId, String text) async {
    final data = await _api.post('/api/messages/$conversationId', body: {
      'content': text,
      'message_type': 'text',
    }) as Map<String, dynamic>;
    return Message.fromJson(data);
  }

  Future<Message> sendImage(int conversationId, File image) async {
    final url = await _api.uploadPhoto(image);
    final data = await _api.post('/api/messages/$conversationId', body: {
      'image_url': url,
      'message_type': 'image',
    }) as Map<String, dynamic>;
    return Message.fromJson(data);
  }

  // ---- Notifications ----------------------------------------------------
  Future<List<AppNotification>> notifications() async {
    final data = await _api.get('/api/notifications') as List;
    return data
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
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
}