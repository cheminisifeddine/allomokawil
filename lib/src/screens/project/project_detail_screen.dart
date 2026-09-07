import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../models/enums.dart';
import '../../models/project.dart';
import '../../models/quote_review.dart';
import '../../widgets/big_button.dart';
import '../../widgets/rating_stars.dart';
import '../chat/chat_screen.dart';
import '../review/review_screen.dart';

/// Full project view: info, photos, and the quotes workflow.
/// - customer/owner: browse quotes, accept one (rejects the rest), complete.
/// - worker: submit a quote or chat with the owner.
class ProjectDetailScreen extends StatefulWidget {
  final String projectId;
  final Repository repo;

  const ProjectDetailScreen(
      {super.key, required this.projectId, required this.repo});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late Future<Project> _project;
  late Future<List<Quote>> _quotes;

  UserRole get _role => AppScope.of(context).auth.role;
  bool get _isOwner => _role == UserRole.customer;

  @override
  void initState() {
    super.initState();
    _project = widget.repo.getProject(widget.projectId);
    _quotes = widget.repo.projectQuotes(widget.projectId);
  }

  void _reload() {
    setState(() {
      _project = widget.repo.getProject(widget.projectId);
      _quotes = widget.repo.projectQuotes(widget.projectId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isOwner ? 'تفاصيل مشروعك' : 'تفاصيل المشروع')),
      body: FutureBuilder<Project>(
        future: _project,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('تعذّر تحميل المشروع'));
          }
          final project = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Photos(images: project.images),
                  const SizedBox(height: 14),
                  Text(project.title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    '${Taxonomy.categoryIcon(project.category)} ${Taxonomy.categoryName(project.category)}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text('📍 ${Taxonomy.wilayaName(project.wilaya)}'
                      '${project.commune == null ? '' : ' — ${project.commune}'}',
                      style: const TextStyle(fontSize: 13)),
                  if (project.description != null) ...[
                    const SizedBox(height: 12),
                    Text(project.description!,
                        style: const TextStyle(
                            fontSize: 14, height: 1.6, color: Color(0xFF3A3A3C))),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (project.budgetMin != null || project.budgetMax != null)
                        Chip(
                            label: Text(project.budgetLabel),
                            avatar:
                                const Icon(Icons.payments_outlined, size: 18)),
                      const SizedBox(width: 8),
                      Chip(label: Text(_urgencyLabel(project.urgency))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _QuotesSection(
                    repo: widget.repo,
                    project: project,
                    quotesFuture: _quotes,
                    isOwner: _isOwner,
                    onChanged: _reload,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _urgencyLabel(UrgencyLevel u) {
    switch (u) {
      case UrgencyLevel.urgent:
        return '⌛ عاجل';
      case UrgencyLevel.withinWeek:
        return 'خلال أسبوع';
      case UrgencyLevel.withinMonth:
        return 'خلال شهر';
      case UrgencyLevel.flexible:
        return 'بدون استعجال';
    }
  }
}

class _Photos extends StatelessWidget {
  final List<String> images;
  const _Photos({required this.images});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFFF0EFEB),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.home_work_outlined,
            size: 48, color: Color(0xFFB9B8B2)),
      );
    }
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(images[i],
              width: 280, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                  width: 280,
                  color: const Color(0xFFF0EFEB),
                  child: const Icon(Icons.photo_outlined))),
        ),
      ),
    );
  }
}

class _QuotesSection extends StatefulWidget {
  final Repository repo;
  final Project project;
  final Future<List<Quote>> quotesFuture;
  final bool isOwner;
  final VoidCallback onChanged;

  const _QuotesSection({
    required this.repo,
    required this.project,
    required this.quotesFuture,
    required this.isOwner,
    required this.onChanged,
  });

  @override
  State<_QuotesSection> createState() => _QuotesSectionState();
}

class _QuotesSectionState extends State<_QuotesSection> {
  Future<void> _accept(Quote q) async {
    await widget.repo.acceptQuote(widget.project.id, q.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم قبول العرض ✔ سيتم رفض باقي العروض')));
      widget.onChanged();
    }
  }

  Future<void> _complete() async {
    await widget.repo.completeProject(widget.project.id);
    if (mounted) {
      final workerId = widget.project.selectedWorkerId ?? 0;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReviewScreen(
              projectId: widget.project.id, workerId: workerId, repo: widget.repo)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('العروض',
            style:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        FutureBuilder<List<Quote>>(
          future: widget.quotesFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()));
            }
            final quotes = snap.data ?? const [];
            if (quotes.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8E7E3)),
                ),
                child: Column(
                  children: [
                    const Text('لا عروض بعد'),
                    const SizedBox(height: 12),
                    if (widget.isOwner)
                      const Text('شارك مشروعك ليصل إلى المقاولين',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF6E6E73))),
                    if (!widget.isOwner)
                      BigButton(
                        label: 'قدّم عرضك',
                        icon: Icons.request_quote_outlined,
                        onPressed: () => _showBidSheet(),
                      ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final q in quotes) _QuoteTile(quote: q, isOwner: widget.isOwner, onAccept: () => _accept(q)),
                if (!widget.isOwner && widget.project.status == ProjectStatus.open)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: BigButton(
                      label: 'قدّم عرضك',
                      icon: Icons.request_quote_outlined,
                      onPressed: () => _showBidSheet(),
                    ),
                  ),
                if (widget.isOwner &&
                    widget.project.status == ProjectStatus.inProgress)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlineButtonOnly(
                      label: 'أكمل المشروع وتقييم',
                      onPressed: _complete,
                    ),
                  ),
              ],
            );
          },
        ),
        if (!widget.isOwner)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(
                        projectId: widget.project.id,
                        otherUserId: widget.project.customerId,
                        repo: widget.repo))),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('مراسلة صاحب المشروع'),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showBidSheet() async {
    final amount = TextEditingController();
    final message = TextEditingController();
    final days = TextEditingController();
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('قدّم عرضك',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'المبلغ (دج)', suffixText: 'دج'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'مدة الإنجاز (أيام)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: message,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'رسالتك (اختياري)'),
            ),
            const SizedBox(height: 18),
            BigButton(
              label: 'إرسال العرض',
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (submitted == true) {
      if (!mounted) return;
      final amt = int.tryParse(amount.text.trim());
      if (amt == null || amt < 1000) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('المبلغ يجب أن يكون 1000 دج على الأقل')));
      } else {
        try {
          await widget.repo.submitQuote(
            projectId: widget.project.id,
            amount: amt,
            message: message.text.trim().isEmpty ? null : message.text.trim(),
            estimatedDays: int.tryParse(days.text.trim()),
          );
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('تم إرسال عرضك ✔')));
            widget.onChanged();
          }
        } on Exception catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.toString())));
          }
        }
      }
    }
  }
}

class _QuoteTile extends StatelessWidget {
  final Quote quote;
  final bool isOwner;
  final VoidCallback onAccept;

  const _QuoteTile(
      {required this.quote, required this.isOwner, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              const Icon(Icons.person, color: Color(0xFF16213E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(quote.workerFullName,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700)),
              ),
              RatingStars(rating: quote.workerAvgRating, size: 14),
            ],
          ),
          const SizedBox(height: 10),
          Text('المبلغ: ${quote.amount} دج',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
          if (quote.estimatedDays != null)
            Text('مدة الإنجاز: ${quote.estimatedDays} يوم'),
          if (quote.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(quote.message!,
                  style: const TextStyle(color: Color(0xFF3A3A3C))),
            ),
          if (isOwner)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: FilledButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('قبول العرض'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Secondary helper exported for reuse.
class OutlineButtonOnly extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const OutlineButtonOnly({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: const Color(0xFF16213E),
          side: const BorderSide(color: Color(0xFF16213E)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}