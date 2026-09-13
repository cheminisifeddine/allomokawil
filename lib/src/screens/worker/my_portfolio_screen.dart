import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../models/worker.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/strings.dart';

/// "My work gallery" — the contractor's own past-work uploader.
///
/// Why it exists: the public profile already RENDERED a portfolio grid, but
/// nothing in the app could put a picture into it, so every contractor profile
/// showed an empty gallery and clients had no reason to trust one over another.
/// A contractor now opens this from their profile, adds photos of finished jobs
/// from the camera or the gallery, and sees them appear on the same grid the
/// clients see.
///
/// Each photo is uploaded to R2 and then registered against the profile, one at
/// a time: on a phone on a mobile network, uploading four photos in parallel is
/// how a weak uplink drops all four.
class MyPortfolioScreen extends StatefulWidget {
  const MyPortfolioScreen({super.key});

  @override
  State<MyPortfolioScreen> createState() => _MyPortfolioScreenState();
}

class _MyPortfolioScreenState extends State<MyPortfolioScreen> {
  late final Repository _repo;
  bool _scopeReady = false;

  WorkerProfile? _worker;
  List<String> _images = const [];

  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// How many photos are in flight, so the button can say so instead of sitting
  /// silent through a slow mobile upload.
  int _uploadedThisRun = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final worker = await _repo.myProfile();
      final images = await _repo.portfolioImages(worker.id);
      if (!mounted) return;
      setState(() {
        _worker = worker;
        _images = images;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorCopy(e);
      });
    }
  }

  /// Asks where the photo comes from, in the two words a user knows.
  Future<void> _addPhoto() async {
    if (_busy) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('أضف صورة من أعمالك',
                  textAlign: TextAlign.center,
                  style: AppTheme.h2.copyWith(color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text('صورة واضحة للعمل بعد الانتهاء تجلب لك عروضاً أكثر.',
                  textAlign: TextAlign.center,
                  style: AppTheme.caption
                      .copyWith(color: AppTheme.textSecondary, height: 1.6)),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'الكاميرا',
                icon: Icons.photo_camera_rounded,
                onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'من معرض الصور',
                icon: Icons.photo_library_rounded,
                onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    await _pickAndUpload(source);
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    // `imageQuality` keeps a 12-megapixel photo from becoming a 6 MB upload on a
    // 3G connection; the gallery only needs to look good, not be printable.
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 78,
      maxWidth: 1600,
    );
    if (picked == null) return;

    final worker = _worker;
    if (worker == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await _repo.uploadDocument(File(picked.path));
      await _repo.addPortfolioImage(worker.id, imageUrl: url);
      if (!mounted) return;
      setState(() {
        _images = [..._images, url];
        _uploadedThisRun++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة الصورة إلى معرض أعمالك')),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = errorCopy(e, fallback: S.errUpload));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معرض أعمالي'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _loading
          ? const SkeletonGrid()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                  children: [
                    if (_error != null) ...[
                      AppCard(
                        color: AppTheme.dangerWash,
                        borderColor: AppTheme.danger,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 20, color: AppTheme.danger),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_error!,
                                  style: AppTheme.caption.copyWith(
                                      color: AppTheme.danger, height: 1.6)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_images.isNotEmpty) _Header(count: _images.length, uploaded: _uploadedThisRun),
                    if (_images.isNotEmpty) const SizedBox(height: 12),
                    _Gallery(
                      images: _images,
                      busy: _busy,
                      onAdd: _addPhoto,
                    ),
                    const SizedBox(height: 18),
                    PrimaryButton(
                      key: const Key('portfolio-add'),
                      label: _busy ? 'جارٍ رفع الصورة...' : 'أضف صورة من أعمالك',
                      icon: _busy
                          ? Icons.cloud_upload_outlined
                          : Icons.add_a_photo_outlined,
                      loading: _busy,
                      onPressed: _busy ? null : _addPhoto,
                    ),
                    const SizedBox(height: 14),
                    const _TipsCard(),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Progress line: how many photos are on the profile right now.
class _Header extends StatelessWidget {
  final int count;
  final int uploaded;

  const _Header({required this.count, required this.uploaded});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppTheme.successWash,
      borderColor: AppTheme.successWash,
      child: Row(
        children: [
          const IconBubble(
            icon: Icons.photo_library_rounded,
            tint: AppTheme.success,
            wash: AppTheme.surface,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count صورة في معرض أعمالك',
                    style: AppTheme.label
                        .copyWith(fontSize: AppTheme.fsSmall, color: AppTheme.success)),
                const SizedBox(height: 2),
                Text(
                  uploaded > 0
                      ? 'أضفت $uploaded صورة في هذه الجلسة.'
                      : 'هذه الصور يراها كل صاحب مشروع في ملفك.',
                  style: AppTheme.caption.copyWith(
                      color: AppTheme.success, fontSize: AppTheme.fsCaption, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The gallery grid, with its own "add" tile as the first cell — the natural
/// place to put a missing picture.
class _Gallery extends StatelessWidget {
  final List<String> images;
  final bool busy;
  final VoidCallback onAdd;

  const _Gallery({required this.images, required this.busy, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        _AddTile(busy: busy, onTap: onAdd),
        for (final url in images) _PhotoTile(url: url),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;

  const _AddTile({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accentWash,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppTheme.accent, width: 1.4),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, size: 28, color: AppTheme.accentDeep),
                      SizedBox(height: 2),
                      Text('أضف',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: AppTheme.fsCaption,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentDeep)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;

  const _PhotoTile({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: AppTheme.lineSoft,
          child: Center(
            child: Icon(Icons.image_rounded, size: 26, color: AppTheme.textMuted),
          ),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const ColoredBox(color: AppTheme.lineSoft),
      ),
    );
  }
}

/// Short, concrete advice — contractors who have never had a portfolio do not
/// know which photos sell the work.
class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    const tips = [
      'صوّر العمل في وضح النهار وبعد الانتهاء.',
      'أضف صوراً لثلاث مراحل على الأقل: قبل، أثناء، بعد.',
      'صورة واحدة لكل نوع من الأعمال التي تتقنها.',
    ];
    return AppCard(
      color: AppTheme.infoWash,
      borderColor: AppTheme.infoWash,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  size: 19, color: AppTheme.info),
              const SizedBox(width: 8),
              Text('نصائح لصور أفضل',
                  style: AppTheme.label
                      .copyWith(fontSize: AppTheme.fsSmall, color: AppTheme.info)),
            ],
          ),
          const SizedBox(height: 8),
          for (final t in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 6, right: 6),
                    child: Icon(Icons.circle,
                        size: 5, color: AppTheme.info),
                  ),
                  Expanded(
                    child: Text(t,
                        style: AppTheme.caption.copyWith(
                            color: AppTheme.info, height: 1.6)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'أعضاء ${Taxonomy.categories.length} مهنة يمكنهم إضافة صورهم.',
            style: AppTheme.caption
                .copyWith(color: AppTheme.info, fontSize: AppTheme.fsBadge, height: 1.5),
          ),
        ],
      ),
    );
  }
}
