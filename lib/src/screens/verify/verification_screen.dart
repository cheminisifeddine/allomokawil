import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../models/enums.dart';
import '../../models/worker.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../../core/l10n/error_copy.dart';

/// Contractor verification: upload auto-entrepreneur/artisan card + ID +
/// selfie. This is the trust gate that powers "verified contractor" badges.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final Repository _repo;
  Future<WorkerProfile>? _profile;
  final List<(String, XFile?)> _docs = [
    ('auto_entrepreneur_card', null),
    ('selfie', null),
    ('national_id_front', null),
  ];

  /// Proof of skill — optional, and deliberately NOT part of the progress bar.
  /// A certificate is what separates two contractors who both have no reviews
  /// yet, but demanding one to appear in the marketplace would keep capable
  /// artisans out, so the slot is offered and never required.
  final List<XFile?> _certs = [null, null];

  bool _busy = false;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
    _profile = _repo.myProfile();
  }

  /// Re-issues the profile request behind the error state.
  void _retry() {
    setState(() => _profile = _repo.myProfile());
  }

  Future<void> _pickCert(int index) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _certs[index] = file);
    }
  }

  Future<void> _pickFor(int index) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _docs[index] = (_docs[index].$1, file);
      });
    }
  }

  Future<void> _submit(WorkerProfile worker) async {
    if (_docs.any((d) => d.$2 == null)) {
      _$toast('أرفق كل المستندات المطلوبة');
      return;
    }
    setState(() => _busy = true);
    try {
      final documents = <Map<String, dynamic>>[];
      for (final d in _docs) {
        final url = await _repo.uploadDocument(File(d.$2!.path));
        documents.add({'document_type': d.$1, 'document_url': url});
      }
      // Uploaded one at a time on purpose: certificates can be several
      // megabytes each and a mobile uplink drops parallel uploads.
      for (final c in _certs) {
        if (c == null) continue;
        final url = await _repo.uploadDocument(File(c.path));
        documents.add({'document_type': 'certificate', 'document_url': url});
      }
      await _repo.submitVerification(worker.id, documents);
      if (!mounted) return;
      // Stay put and re-read the profile. The point is that he SEES the
      // dossier turn into "under review" — popping straight back home was how
      // a successful upload came to look like nothing had happened.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم إرسال مستنداتك، بانتظار المراجعة')));
      setState(() {
        _busy = false;
        _profile = _repo.myProfile();
      });
      return;
    } on Exception catch (e) {
      _$toast(errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _$toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('توثيق الحساب')),
      body: FutureBuilder<WorkerProfile>(
        future: _profile,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonFormPage(fields: 4);
          }
          if (snap.hasError) {
            return EmptyView(
              icon: Icons.error_outline_rounded,
              title: 'تعذّر جلب ملفك',
              message: errorCopy(snap.error),
              actionLabel: 'إعادة المحاولة',
              onAction: _retry,
              danger: true,
            );
          }
          final worker = snap.data!;
          final status = worker.verificationStatus;
          final verified = status == VerificationStatus.verified;
          // Deliberately NOT `status == pending`: a brand-new profile is stored
          // as pending too, so keying off the status alone would tell a man who
          // has sent nothing that he is under review. Documents actually
          // sitting in the queue are what make it true.
          final underReview = worker.dossierUnderReview;
          final rejected = status == VerificationStatus.rejected;
          final done = _docs.where((d) => d.$2 != null).length;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  if (verified)
                    const _VerifiedBanner()
                  else if (underReview)
                    _UnderReviewPanel(onRefresh: _retry)
                  else ...[
                    if (rejected) ...[
                      const _RejectedBanner(),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'لكي تظهر للموكلين وتحصل على شارة "موثّق"، أرفق المستندات التالية.',
                      style: AppTheme.body,
                    ),
                    const SizedBox(height: 12),
                    // Reassuring note: says why the documents are needed.
                    AppCard(
                      color: AppTheme.infoWash,
                      borderColor: AppTheme.infoWash,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: 20, color: AppTheme.info),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'نطلب هذه المستندات للتحقق من هويتك فقط ولحماية كل الأطراف. '
                              'تبقى صورك خاصة ثم تُحذف بعد المراجعة، ولا تظهر لأي طرف آخر.',
                              style: AppTheme.bodySoft.copyWith(
                                  fontSize: AppTheme.fsMeta, color: AppTheme.info),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ProgressCard(done: done, total: _docs.length),
                    const SectionTitle('المستندات المطلوبة',
                        icon: Icons.folder_open_rounded),
                    _DocCard(
                      index: 0,
                      label: 'بطاقة المقاول (auto-entrepreneur)',
                      icon: Icons.badge_outlined,
                      tint: AppTheme.navy,
                      wash: AppTheme.lineSoft,
                      file: _docs[0].$2,
                      onPick: () => _pickFor(0),
                    ),
                    _DocCard(
                      index: 1,
                      label: 'صورة شخصية (سيلفي)',
                      icon: Icons.photo_camera_front_outlined,
                      tint: AppTheme.accentDeep,
                      wash: AppTheme.accentWash,
                      file: _docs[1].$2,
                      onPick: () => _pickFor(1),
                    ),
                    _DocCard(
                      index: 2,
                      label: 'بطاقة التعريف (وجه)',
                      icon: Icons.credit_card_outlined,
                      tint: AppTheme.info,
                      wash: AppTheme.infoWash,
                      file: _docs[2].$2,
                      onPick: () => _pickFor(2),
                    ),
                    const SizedBox(height: 6),
                    const SectionTitle('شهادات ودبلومات (اختياري)',
                        icon: Icons.workspace_premium_rounded),
                    Text(
                      'إن كانت بحوزتك شهادة تكوين أو دبلوم حرفة فأضفها هنا. '
                      'تظهر في ملفك وترفع ثقة أصحاب المشاريع بك، خاصة إن كنت جديداً بلا تقييمات.',
                      style: AppTheme.bodySoft
                          .copyWith(fontSize: AppTheme.fsMeta, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _certs.length; i++)
                      _DocCard(
                        index: null,
                        label: i == 0 ? 'شهادة تكوين أو دبلوم' : 'شهادة إضافية',
                        icon: Icons.workspace_premium_rounded,
                        tint: AppTheme.accentDeep,
                        wash: AppTheme.accentWash,
                        file: _certs[i],
                        onPick: () => _pickCert(i),
                      ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'إرسال المستندات',
                      icon: Icons.upload_file_outlined,
                      loading: _busy,
                      onPressed: () => _submit(worker),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 15, color: AppTheme.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'تُراجع المستندات خلال 24-48 ساعة. تُحذف صور المستندات من الخادم بعد المراجعة.',
                            style: AppTheme.caption.copyWith(fontSize: AppTheme.fsBadge),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// What a contractor sees after a successful submission.
///
/// This is the receipt: what we received, that a second upload is not needed,
/// and when to expect an answer. Without it the app answered "did my documents
/// arrive?" with three empty slots.
class _UnderReviewPanel extends StatelessWidget {
  const _UnderReviewPanel({required this.onRefresh});

  final VoidCallback onRefresh;

  static const List<(IconData, String)> _received = [
    (Icons.badge_outlined, 'بطاقة المقاول (auto-entrepreneur)'),
    (Icons.photo_camera_front_outlined, 'صورة شخصية (سيلفي)'),
    (Icons.credit_card_outlined, 'بطاقة التعريف (وجه)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: AppTheme.infoWash,
          borderColor: AppTheme.infoWash,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBubble(
                icon: Icons.hourglass_top_rounded,
                tint: AppTheme.info,
                wash: AppTheme.surface,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مستنداتك قيد المراجعة',
                        style: AppTheme.label.copyWith(
                            fontSize: AppTheme.fsLead, color: AppTheme.info)),
                    const SizedBox(height: 8),
                    Text(
                      'استلمنا مستنداتك ولا تحتاج لإعادة إرسالها. '
                      'يراجعها فريقنا خلال 24-48 ساعة.',
                      style: AppTheme.bodySoft.copyWith(
                          fontSize: AppTheme.fsMeta,
                          height: 1.6,
                          color: AppTheme.info),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle('ما استلمناه', icon: Icons.inventory_2_outlined),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < _received.length; i++) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 20, color: AppTheme.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_received[i].$2, style: AppTheme.body),
                    ),
                    Text('تم الاستلام',
                        style: AppTheme.caption.copyWith(
                            fontSize: AppTheme.fsBadge,
                            color: AppTheme.success)),
                  ],
                ),
                if (i != _received.length - 1)
                  const Divider(height: 20, color: AppTheme.lineSoft),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SecondaryButton(
          label: 'تحديث الحالة',
          icon: Icons.refresh_rounded,
          onPressed: onRefresh,
        ),
        const SizedBox(height: 16),
        Text(
          'ستصلك إشعار عند القبول أو إن احتجنا تصحيحاً. '
          'لا يمكن الإرسال مرة أخرى وأنت قيد المراجعة.',
          style: AppTheme.caption.copyWith(fontSize: AppTheme.fsBadge),
        ),
      ],
    );
  }
}

/// Shown when a reviewer refused an earlier submission. The form below is the
/// resubmission path, so this banner only has to say what happened.
class _RejectedBanner extends StatelessWidget {
  const _RejectedBanner();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppTheme.dangerWash,
      borderColor: AppTheme.dangerWash,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconBubble(
            icon: Icons.report_gmailerrorred_rounded,
            tint: AppTheme.danger,
            wash: AppTheme.surface,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'لم تُقبل مستنداتك السابقة. تأكد أن الصور واضحة وأنها كلها لك، ثم أعد الإرسال.',
              style: AppTheme.body.copyWith(
                  fontSize: AppTheme.fsMeta, color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedBanner extends StatelessWidget {
  const _VerifiedBanner();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppTheme.successWash,
      borderColor: AppTheme.successWash,
      child: Row(
        children: [
          const IconBubble(
            icon: Icons.verified_rounded,
            tint: AppTheme.success,
            wash: AppTheme.surface,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('حسابك موثّق. يمكنك استقبال المشاريع.',
                style: AppTheme.label
                    .copyWith(fontSize: AppTheme.fsSmall, color: AppTheme.success)),
          ),
        ],
      ),
    );
  }
}

/// "You completed n of 3 documents" progress readout.
class _ProgressCard extends StatelessWidget {
  final int done;
  final int total;

  const _ProgressCard({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final complete = total > 0 && done == total;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                complete
                    ? Icons.check_circle_rounded
                    : Icons.upload_file_rounded,
                size: 20,
                color: complete ? AppTheme.success : AppTheme.navy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  complete
                      ? 'كل المستندات جاهزة للإرسال'
                      : 'أكملت $done من $total مستندات',
                  style: AppTheme.label,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 8,
              backgroundColor: AppTheme.line,
              color: complete ? AppTheme.success : AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// One document slot: whole card is tappable, thumbnail + status once chosen.
class _DocCard extends StatelessWidget {
  /// 1-based position among the REQUIRED documents, or null for the optional
  /// certificate slots. An optional slot must not carry the next number: the
  /// progress card counts three documents, so a "4" reads as a fourth duty.
  final int? index;
  final String label;
  final IconData icon;
  final Color tint;
  final Color wash;
  final XFile? file;
  final VoidCallback onPick;

  const _DocCard({
    this.index,
    required this.label,
    required this.icon,
    required this.tint,
    required this.wash,
    required this.file,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final chosen = file != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onPick,
        padding: AppTheme.cardPad,
        borderColor: chosen ? AppTheme.success : AppTheme.line,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              child: SizedBox(
                width: 58,
                height: 58,
                child: chosen
                    ? Image.file(
                        File(file!.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: IconBubble(
                              icon: icon, tint: tint, wash: wash, size: 58),
                        ),
                      )
                    : IconBubble(icon: icon, tint: tint, wash: wash, size: 58),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppTheme.navy,
                          shape: BoxShape.circle,
                        ),
                        child: index == null
                            ? const Icon(Icons.add_rounded,
                                size: 14, color: Colors.white)
                            : Text('${index! + 1}',
                                style: AppTheme.caption.copyWith(
                                    fontSize: AppTheme.fsCaption, color: AppTheme.onNavy)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: AppTheme.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (chosen)
                    const StatusPill(
                      label: 'تم الاختيار',
                      color: AppTheme.success,
                      wash: AppTheme.successWash,
                      icon: Icons.check_circle_rounded,
                    )
                  else
                    StatusPill(
                      label: index == null ? 'أضف شهادة' : 'اضغط للإضافة',
                      color: AppTheme.info,
                      wash: AppTheme.infoWash,
                      icon: Icons.add_a_photo_outlined,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              chosen ? Icons.sync_rounded : Icons.touch_app_rounded,
              size: 22,
              color: chosen ? AppTheme.navy : AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
