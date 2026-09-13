import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../widgets/ui.dart';
import '../../core/l10n/error_copy.dart';

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
  // No pre-cast vote. This used to open on 5 stars, so the fastest path
  // through the screen was "tap submit" and every rushed review was a
  // five — the picker's own scale was never even drawn. It starts empty and
  // `_submit` refuses to send nothing.
  int _rating = 0;
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اختر عدد النجوم أولاً')));
      return;
    }
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
            const SnackBar(content: Text('شكراً لك، تم إرسال التقييم')));
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorCopy(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Five 56 dp stars need 280 dp of clear width. A 392 dp phone spends 20 + 16
    // per side on the page and the card and is comfortable; a 320 dp one only
    // has 40 dp to give in total, so there the card drops its own inset and the
    // page keeps 8. Measured on the rendered tree at both widths.
    final pagePad = MediaQuery.sizeOf(context).width >= 360 ? 20.0 : 8.0;
    return Scaffold(
      appBar: AppBar(title: const Text('قيّم المقاول')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: EdgeInsets.fromLTRB(pagePad, 14, pagePad, 28),
              children: [
                Text('كيف كانت تجربتك مع المقاول؟',
                    textAlign: TextAlign.center, style: AppTheme.h1),
                const SizedBox(height: 6),
                Text('اضغط على النجوم لتقييم عمله.',
                    textAlign: TextAlign.center, style: AppTheme.bodySoft),
                const SizedBox(height: 18),
                AppCard(
                  // The picker owns the whole card. At 320 dp the usual 16 dp
                  // card inset left its Row 246 dp for five 56 dp targets and the
                  // row overflowed by 34 dp (RenderFlex, 13 Sep), which the star
                  // clamp could not fix by itself: 5 x 56 = 280 > 246. The label
                  // below keeps the inset by hand, so the card still reads as one.
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: _StarPicker(
                          value: _rating,
                          onChanged: (v) => setState(() => _rating = v),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.accentWash,
                            borderRadius: BorderRadius.circular(AppTheme.rPill),
                          ),
                          child: Text(_label(_rating),
                              style: AppTheme.label.copyWith(
                                  fontSize: AppTheme.fsBody, color: AppTheme.accentDeep)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
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
                PrimaryButton(
                  label: 'إرسال التقييم',
                  icon: Icons.send_rounded,
                  loading: _busy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    // One star is iconography for "reviews". Five of them next
                    // to the word "trust" is a score nobody earned — and this
                    // screen is where the user is about to set a real one.
                    const Icon(Icons.star_rounded,
                        size: 16, color: AppTheme.star),
                    Text('التقييمات تبني الثقة في السوق',
                        style: AppTheme.caption
                            .copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _label(int r) {
    switch (r) {
      case 0:
        return 'اختر تقييماً';
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

/// Large tap-to-rate stars: every star keeps a >= 48px touch target and the
/// row is sized from the available width so it can never overflow.
class _StarPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _StarPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Five stars, never below the 56 dp target, and never wider than the
        // band the screen actually gives them (the card hands the picker its
        // whole width; the clamp can only round the size up to 56, so any parent
        // under 280 dp has to be fixed at the call site, not here).
        final star = (constraints.maxWidth / 5)
            .clamp(AppTheme.tapMin, 58.0)
            .toDouble();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var n = 1; n <= 5; n++)
              SizedBox(
                width: star,
                height: star,
                child: InkWell(
                  onTap: () => onChanged(n),
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                  child: Center(
                    child: Icon(
                      n <= value
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: star * 0.78,
                      color: n <= value ? AppTheme.star : AppTheme.starEmpty,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
