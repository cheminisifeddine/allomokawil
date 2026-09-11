import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/repository.dart';
import '../../models/enums.dart';
import '../../models/quote_review.dart';
import '../../models/worker.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/rating_stars.dart';
import '../chat/chat_screen.dart';

/// Public contractor profile: bio, specialties, price range, portfolio
/// gallery, reviews + contact.
class WorkerProfileScreen extends StatefulWidget {
  final int workerId;
  const WorkerProfileScreen({super.key, required this.workerId});

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  late final Repository _repo;
  late Future<WorkerProfile> _profile;
  late final Future<List<Review>> _reviews;
  late final Future<List<String>> _portfolio;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
    _profile = _repo.getWorker(widget.workerId);
    _reviews = _repo.workerReviews(widget.workerId);
    _portfolio = _repo.portfolioImages(widget.workerId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ملف المقاول')),
      body: FutureBuilder<WorkerProfile>(
        future: _profile,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Text('تعذّر تحميل الملف: ${snap.error.toString()}'));
          }
          final w = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Header(worker: w),
                  const SizedBox(height: 18),
                  if (w.bio != null) ...[
                    const _Label('نبذة'),
                    const SizedBox(height: 6),
                    Text(w.bio!, style: const TextStyle(height: 1.6)),
                    const SizedBox(height: 14),
                  ],
                  const _Label('التخصصات'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in w.specialties)
                        Chip(label: Text(s)),
                      if (w.specialties.isEmpty) const Chip(label: Text('غير محدد')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _Label('تفاصيل العمل'),
                  const SizedBox(height: 8),
                  _DetailRow(
                      icon: Icons.work_outline,
                      text: '${w.experienceYears} سنة خبرة'),
                  if (w.priceRangeMin != null || w.priceRangeMax != null)
                    _DetailRow(
                        icon: Icons.payments_outlined,
                        text: _priceLabel(w)),
                  _DetailRow(
                      icon: Icons.radar,
                      text: 'نصف قطر الخدمة: ${w.serviceRadiusKm} كم'),
                  if (w.wilaya != null)
                    _DetailRow(icon: Icons.location_on_outlined, text: '${w.wilaya}'),
                  const SizedBox(height: 18),
                  _PortfolioGrid(portfolio: _portfolio),
                  const SizedBox(height: 18),
                  _ReviewsSection(reviews: _reviews),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                    projectId: null,
                                    otherUserId: w.userId,
                                    otherName: w.fullName,
                                    repo: _repo,
                                  ))),
                      icon: const Icon(Icons.chat_outlined),
                      label: Text('مراسلة  ${w.fullName}'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _priceLabel(WorkerProfile w) {
    if (w.priceRangeMin != null && w.priceRangeMax != null) {
      return 'السعر: ${w.priceRangeMin} - ${w.priceRangeMax} دج';
    }
    if (w.priceRangeMax != null) return 'السعر: حتى ${w.priceRangeMax} دج';
    return 'السعر: من ${w.priceRangeMin} دج';
  }
}

class _Header extends StatelessWidget {
  final WorkerProfile worker;
  const _Header({required this.worker});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white24,
            backgroundImage:
                worker.avatarUrl != null ? NetworkImage(worker.avatarUrl!) : null,
            child: worker.avatarUrl == null
                ? Text(worker.fullName.isEmpty
                    ? '؟'
                    : worker.fullName.characters.first,
                    style: const TextStyle(
                        fontSize: 26, color: Colors.white))
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(worker.fullName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    RatingStars(rating: worker.avgRating, size: 16),
                    const SizedBox(width: 6),
                    Text('${worker.avgRating.toStringAsFixed(1)} (${worker.totalReviews})',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${worker.totalCompletedJobs} مشروع منجز • استجابة خلال ${worker.responseTimeHours ?? 0}h',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (worker.verificationStatus == VerificationStatus.verified) ...[
                  const SizedBox(height: 6),
                  const Row(children: [
                    Icon(Icons.verified, size: 15, color: Color(0xFF7ED957)),
                    SizedBox(width: 5),
                    Text('مقاول موثّق',
                        style: TextStyle(
                            color: Color(0xFF7ED957),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700));
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xFF16213E)),
          const SizedBox(width: 8),
          Text(text),
        ]),
      );
}

class _PortfolioGrid extends StatelessWidget {
  final Future<List<String>> portfolio;
  const _PortfolioGrid({required this.portfolio});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('معرض الأعمال'),
        const SizedBox(height: 8),
        FutureBuilder<List<String>>(
          future: portfolio,
          builder: (context, snap) {
            final urls = snap.data ?? const [];
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 80, child: Center(child: CircularProgressIndicator()));
            }
            if (urls.isEmpty) {
              return const Text('لم يضف صوراً بعد',
                  style: TextStyle(color: Color(0xFF6E6E73)));
            }
            return SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: urls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(urls[i],
                      width: 190, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 190,
                          color: const Color(0xFFF0EFEB),
                          child: const Center(child: Icon(Icons.image_outlined)))),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  final Future<List<Review>> reviews;
  const _ReviewsSection({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('التقييمات'),
        const SizedBox(height: 8),
        FutureBuilder<List<Review>>(
          future: reviews,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 60, child: Center(child: CircularProgressIndicator()));
            }
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return const EmptyState(
                  icon: Icons.rate_review_outlined,
                  title: 'لا تقييمات بعد');
            }
            return Column(
              children: [
                for (final r in list)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE8E7E3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            RatingStars(rating: r.rating.toDouble(), size: 14),
                            const Spacer(),
                            Text(r.customerFullName,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF6E6E73))),
                          ],
                        ),
                        if (r.comment != null) ...[
                          const SizedBox(height: 8),
                          Text(r.comment!),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}