import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/photo_count_copy.dart';
import '../../data/portfolio_allowance.dart';
import '../../data/repository.dart';
import '../../models/worker.dart';
import '../../widgets/a11y.dart';
import '../../widgets/net_image.dart';
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

  /// How many photos the plan allows, once the server has answered.
  ///
  /// Null until it does, and the gallery is **not** gated while it is null: an
  /// allowance read that has not arrived yet must not close the screen a
  /// contractor opened to see his work. The gate is a courtesy to the plan, not
  /// the guard on the door — BACKEND-API is the only thing that can actually
  /// refuse an upload, and until it does, failing open is the honest state.
  PortfolioAllowance? _allowance;

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
      // Read **after** the gallery is on screen, so a plan that never loads is
      // a missing progress line and not a spinner that never resolves. The two
      // are separate requests and the gallery is the one the contractor came
      // for.
      await _loadAllowance(images.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorCopy(e);
      });
    }
  }

  /// Reads the plan's portfolio allowance, failing open.
  ///
  /// A contractor whose plan cannot be read keeps the whole screen he had
  /// before this existed: the gate appears when the server answers and never
  /// takes away a working gallery. A plan call that throws is not an error the
  /// contractor did anything about, so it is swallowed and the limit stays
  /// unknown.
  Future<void> _loadAllowance(int used) async {
    try {
      final status = (await _repo.subscription()).current;
      if (!mounted) return;
      setState(() {
        _allowance =
            PortfolioAllowance.fromLimit(status.portfolioLimit, used: used);
      });
    } catch (_) {
      // Unknown limit, on purpose. See [_allowance].
    }
  }

  /// Asks where the photo comes from, in the two words a user knows.
  Future<void> _addPhoto() async {
    if (_busy) return;
    // The add tile and the button below both hide on a full gallery, so this
    // is the third gate rather than the first: it is here because a limit the
    // user can only discover by hitting it is the defect the project cap had.
    final allowance = _allowance;
    if (allowance != null && allowance.isFull) return;
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
        // The count that decides the gate is the server's, and the server has
        // just been told about one more photo. A local counter would agree with
        // the server until the first failed upload, and then never again.
        final a = _allowance;
        if (a != null) {
          _allowance = PortfolioAllowance(limit: a.limit, used: _images.length);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة الصورة إلى معرض أعمالك')),
      );
    } catch (e) {
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
                    if (_images.isNotEmpty)
                      _Header(
                        count: _images.length,
                        uploaded: _uploadedThisRun,
                        allowance: _allowance,
                      ),
                    if (_images.isNotEmpty) const SizedBox(height: 12),
                    _Gallery(
                      images: _images,
                      busy: _busy,
                      onAdd: _addPhoto,
                      // Null means the plan has not answered, and the tile stays:
                      // an allowance that has not loaded is not a full gallery.
                      showAdd: !(_allowance?.isFull ?? false),
                    ),
                    const SizedBox(height: 18),
                    // One sentence where the button was, so a full gallery says
                    // which limit it hit instead of showing nothing. A missing
                    // control on its own reads as a broken screen.
                    if (_allowance?.isFull ?? false)
                      _FullNotice(allowance: _allowance!)
                    else
                      PrimaryButton(
                        key: const Key('portfolio-add'),
                        label:
                            _busy ? 'جارٍ رفع الصورة...' : 'أضف صورة من أعمالك',
                        icon: _busy
                            ? Icons.cloud_upload_outlined
                            : Icons.add_a_photo_outlined,
                        loading: _busy,
                        onPressed: _busy ? null : _addPhoto,
                      ),
                    const SizedBox(height: 14),
                  // The photo-tips card was removed on the founder's call — the
                  // portfolio screen shows the gallery and the add button, and
                  // nothing else competes with them.
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

  /// Null while the plan is still being read, in which case this card says
  /// what it has always said.
  final PortfolioAllowance? allowance;

  const _Header({
    required this.count,
    required this.uploaded,
    required this.allowance,
  });

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
                Text(portfolioCountLineAr(count),
                    style: AppTheme.label
                        .copyWith(fontSize: AppTheme.fsSmall, color: AppTheme.success)),
                const SizedBox(height: 2),
                Text(
                  _subLine(),
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

/// The second line, in the order that answers the question he came with.
///
/// What he has uploaded this sitting is the least useful thing to say once the
/// plan matters, so the room left takes that slot, and the session count moves
/// under it. A full gallery overrides both: the limit is the whole message.
///
/// Null is silence by contract — a plan that never answered leaves this card
/// saying exactly what it said before the allowance existed.
String _subLine() {
  final a = allowance;
  if (a == null) {
    return uploaded > 0
        ? uploadedThisSessionAr(uploaded)
        : 'هذه الصور يراها كل صاحب مشروع في ملفك.';
  }
  if (a.isFull) return portfolioFullLineAr(a.limit);
  if (a.isUnlimited) return portfolioUnlimitedLineAr();
  return portfolioLeftLineAr(a.left!, a.limit);
}
}

/// Stands in for the add button when the plan's gallery is full.
///
/// It offers the one action that lifts the limit, because a screen that only
/// says "no" leaves the contractor with nothing to do about it — the same
/// reasoning the 402 paywall on the bid button documents.
class _FullNotice extends StatelessWidget {
  const _FullNotice({required this.allowance});

  final PortfolioAllowance allowance;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('portfolio-full'),
      color: AppTheme.accentWash,
      child: Row(
        children: [
          const IconBubble(
            icon: Icons.lock_outline_rounded,
            tint: AppTheme.accentDeep,
            wash: AppTheme.surface,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(portfolioFullLineAr(allowance.limit),
                    style: AppTheme.label.copyWith(
                        fontSize: AppTheme.fsSmall, color: AppTheme.accentDeep)),
                const SizedBox(height: 2),
                Text('رقّي خطتك لتضيف صوراً أكثر إلى معرض أعمالك.',
                    style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fsCaption,
                        height: 1.5)),
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

  /// False when the plan's allowance is spent, so the grid does not keep
  /// offering a cell that goes nowhere.
  final bool showAdd;

  const _Gallery({
    required this.images,
    required this.busy,
    required this.onAdd,
    required this.showAdd,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        if (showAdd) _AddTile(busy: busy, onTap: onAdd),
        for (var i = 0; i < images.length; i++)
          _PhotoTile(url: images[i], index: i),
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
      child: A11y.button(enabled: !busy, child: InkWell(
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
      )),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final int index;

  const _PhotoTile({required this.url, required this.index});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: NetImage(
        url,
        semanticLabel: 'صورة من أعمالي ${index + 1}',
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
