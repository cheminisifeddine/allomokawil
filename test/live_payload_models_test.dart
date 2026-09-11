import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/models/notification.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/models/quote_review.dart';
import 'package:allomokawil/src/models/worker.dart';

/// Payloads copied verbatim from the live API
/// (https://allomokawil.colisify.com) so a backend field rename breaks the
/// suite instead of the app.
Map<String, dynamic> _decode(String s) =>
    jsonDecode(s) as Map<String, dynamic>;

const _workerJson = '''
{"id":16,"user_id":31,"bio":null,"specialties":[],"experience_years":0,
 "price_range_min":null,"price_range_max":null,"service_radius_km":30,
 "is_available":1,"is_identity_verified":0,"is_certificate_verified":0,
 "verification_status":"pending","subscription_plan":"free_trial","avg_rating":5,
 "total_reviews":1,"total_completed_jobs":1,"response_time_hours":null,
 "cover_image_url":null,"created_at":"2026-09-11 20:23:45",
 "updated_at":"2026-09-11 20:23:45","full_name":"مقاول تجربة",
 "phone":"077442495","user_wilaya":"16","avatar_url":null}''';

const _projectJson = '''
{"id":"b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551",
 "customer_id":30,"title":"دهان شقة 3 غرف","description":"دهان كامل مع تحضير الجدران",
 "category":"painting","images":[],"wilaya":"16","commune":"حسين داي",
 "latitude":null,"longitude":null,"budget_min":60000,"budget_max":90000,
 "urgency":"within_week","status":"open","selected_worker_id":null,
 "created_at":"2026-09-11 20:23:44","updated_at":"2026-09-11 20:23:44"}''';

const _quoteJson = '''
{"id":13,"project_id":"b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551",
 "worker_id":16,"amount":75000,"message":"جاهز للبدء فوراً","estimated_days":5,
 "status":"pending","created_at":"2026-09-11 20:23:45",
 "updated_at":"2026-09-11 20:23:45","worker_full_name":"مقاول تجربة",
 "worker_avatar_url":null,"worker_avg_rating":0,"worker_total_reviews":0,
 "worker_verification_status":"pending"}''';

const _conversationJson = '''
{"id":5,"customer_id":30,"worker_user_id":31,
 "project_id":"b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551",
 "last_message_at":"2026-09-11 20:23:47","created_at":"2026-09-11 20:23:47",
 "other_user_name":"مقاول تجربة","other_user_avatar":null,
 "last_message_content":"مرحبا، متى يمكنك البدء؟","unread_count":0}''';

const _messageJson = '''
{"id":11,"conversation_id":5,"sender_id":30,"content":"مرحبا، متى يمكنك البدء؟",
 "image_url":null,"message_type":"text","is_read":0,
 "created_at":"2026-09-11 20:23:47"}''';

const _notificationJson = '''
{"id":15,"user_id":30,"type":"new_quote","title":"عرض جديد على مشروعك",
 "body":"جاهز للبدء فوراً",
 "link":"/dashboard/projects/b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551",
 "is_read":0,"created_at":"2026-09-11 20:23:45"}''';

/// The live API stores review images as a JSON *string*, not an array.
const _reviewJson = '''
{"id":5,"project_id":"b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551",
 "customer_id":30,"worker_id":16,"rating":5,"comment":"عمل ممتاز","images":"[]",
 "is_visible":1,"created_at":"2026-09-11 20:23:50",
 "customer_full_name":"زبون تجربة","customer_avatar_url":null}''';

void main() {
  test('WorkerProfile parses a live worker payload (wilaya comes from user_wilaya)', () {
    final w = WorkerProfile.fromJson(_decode(_workerJson));
    expect(w.id, 16);
    expect(w.userId, 31);
    expect(w.fullName, 'مقاول تجربة');
    expect(w.isAvailable, isTrue); // wire value is the int 1
    expect(w.avgRating, 5);
    expect(w.totalCompletedJobs, 1);
    expect(w.verificationStatus.name, 'pending');
    expect(w.wilaya, '16');
  });

  test('Project parses a live project payload', () {
    final p = Project.fromJson(_decode(_projectJson));
    expect(p.title, 'دهان شقة 3 غرف');
    expect(p.category, 'painting');
    expect(p.urgency, UrgencyLevel.withinWeek);
    expect(p.status, ProjectStatus.open);
    expect(p.budgetLabel, '60000 - 90000 دج');
  });

  test('Project survives a project posted without a wilaya', () {
    final json = _decode(_projectJson)..['wilaya'] = null;
    expect(() => Project.fromJson(json), returnsNormally);
    expect(Project.fromJson(json).wilaya, '');
  });

  test('Quote parses a live quote payload with worker info joined', () {
    final q = Quote.fromJson(_decode(_quoteJson));
    expect(q.id, 13);
    expect(q.amount, 75000);
    expect(q.estimatedDays, 5);
    expect(q.workerFullName, 'مقاول تجربة');
  });

  test('Conversation and Message parse live chat payloads', () {
    final c = Conversation.fromJson(_decode(_conversationJson));
    expect(c.id, 5);
    expect(c.workerUserId, 31);
    expect(c.otherUserName, 'مقاول تجربة');
    expect(c.lastMessageContent, 'مرحبا، متى يمكنك البدء؟');

    final m = Message.fromJson(_decode(_messageJson));
    expect(m.id, 11);
    expect(m.senderId, 30);
    expect(m.type, MessageType.text);
  });

  test('Review tolerates images being a JSON string', () {
    final r = Review.fromJson(_decode(_reviewJson));
    expect(r.rating, 5);
    expect(r.comment, 'عمل ممتاز');
    expect(r.images, isEmpty);
    expect(r.customerFullName, 'زبون تجربة');
  });

  test('AppNotification parses a live notification payload', () {
    final n = AppNotification.fromJson(_decode(_notificationJson));
    expect(n.id, 15);
    expect(n.type, 'new_quote');
    expect(n.title, 'عرض جديد على مشروعك');
    expect(n.isRead, 0);
  });

  test('unreadCount reads {"unread": n} instead of throwing a cast error', () async {
    final api = ApiClient(
      httpClient: MockClient(
        (_) async => http.Response('{"unread":2}', 200,
            headers: {'content-type': 'application/json'}),
      ),
      baseUrls: ['https://x.test'],
    );
    expect(await Repository(api).unreadCount(), 2);
  });
}
