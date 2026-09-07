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
  }) async {
    final q = <String>[
      if (category != null) 'category=$category',
      if (wilaya != null) 'wilaya=$wilaya',
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

  // ---- Projects ---------------------------------------------------------
  /// The signed-in contractor's own profile (for verification & portfolio).
  Future<WorkerProfile> myProfile() async {
    final data = await _api.get('/api/mobile/my/profile')
        as Map<String, dynamic>;
    return WorkerProfile.fromJson(data);
  }

  Future<List<Project>> browseProjects({
    String? category,
    String? wilaya,
    ProjectStatus? status,
    int page = 1,
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
    return (data as num?)?.toInt() ?? 0;
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