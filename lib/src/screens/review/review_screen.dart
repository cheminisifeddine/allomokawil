import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../widgets/big_button.dart';
import '../../widgets/rating_stars.dart';

/// Post-project review: 1-5 stars + optional comment.
class ReviewScreen extends StatefulWidget {
  final String projectId;
  final int workerId;
  final Repository repo;

  const ReviewScreen({
    super.key,
    required this.projectId,
    required this.workerId,
    required this.repo,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _comment = TextEditingController();
  int _rating = 5;
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.repo.createReview(
        projectId: widget.projectId,
        workerId: widget.workerId,
        rating: _rating,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('شكراً لك، تم إرسال التقييم ✔')));
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('قيّم المقاول')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text('كيف كانت تجربتك مع المقاول؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              // Big 5-star picker with large tap targets.
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final n = i + 1;
                    return InkWell(
                      onTap: () => setState(() => _rating = n),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          n <= _rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 46,
                          color: n <= _rating
                              ? const Color(0xFFE0A458)
                              : const Color(0xFFD5D5D9),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(_label(_rating),
                    style: const TextStyle(
                        color: Color(0xFF6E6E73), fontSize: 13)),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _comment,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'تعليقك (اختياري)',
                  hintText: 'شارك تفاصيل التجربة...',
                  prefixIcon: Icon(Icons.rate_review_outlined),
                ),
              ),
              const SizedBox(height: 24),
              BigButton(
                label: 'إرسال التقييم',
                icon: Icons.send,
                loading: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RatingStars(rating: 5, size: 14),
                  SizedBox(width: 6),
                  Text('التقييمات تبني الثقة في السوق',
                      style:
                          TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _label(int r) {
    switch (r) {
      case 1:
        return 'سيئ جداً';
      case 2:
        return 'سيئ';
      case 3:
        return 'متوسط';
      case 4:
        return 'جيد';
      default:
        return 'ممتاز';
    }
  }
}