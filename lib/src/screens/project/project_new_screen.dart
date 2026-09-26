import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/text/arabic_search.dart';
import '../../core/text/dz_number.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../data/communes.dart';
import '../../data/commune_count_copy.dart';
import '../../data/project_photo_count_copy.dart';
import '../../data/project_photo_limit.dart';
import '../../core/location/locator.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../widgets/detect_location.dart';
import '../../models/project.dart';
import '../../widgets/category_grid.dart';
import '../../widgets/number_field.dart';
import '../../widgets/a11y.dart';
import '../../widgets/net_image.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/write_outcome.dart';
import '../../core/l10n/strings.dart';

/// Post a new project (client).
///
/// Layout rules that matter for this app's audience:
///  * Every section has a numbered Arabic label sitting ABOVE its control, so
///    the user always knows what is being asked without reading small print.
///  * The specialty picker is a fixed 3-column grid of [SelectableTile]s with
///    explicit colours. The previous version used Material `ChoiceChip` inside a
///    `Wrap`, which rendered the label white-on-white (invisible) and produced a
///    ragged 2-column layout.
///  * The publish button lives in a sticky bottom bar, so the primary action is
///    always on screen instead of buried under a long scroll.
class ProjectNewScreen extends StatefulWidget {
  /// Null = post a new project. A project = edit that one (same form, same
  /// validation, PATCH instead of POST) — the owner may only edit while the
  /// project is still `open`, which the API enforces and the detail screen
  /// only offers the button when it holds.
  final Project? initial;

  const ProjectNewScreen({super.key, this.initial});

  @override
  State<ProjectNewScreen> createState() => _ProjectNewScreenState();
}

class _ProjectNewScreenState extends State<ProjectNewScreen> {
  late final Repository _repo;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _budgetMin = TextEditingController();
  final _budgetMax = TextEditingController();
  final _commune = TextEditingController();

  /// The trades this job needs. A founder's ask made this a set: one job can be
  /// structure + renovation + turnkey finishing, all in once.
  final Set<String> _categories = <String>{};
  String? _wilaya;

  /// Set when the wilaya was filled from the phone's position rather than from
  /// the picker. The form says so out loud: a guessed locality must never pass
  /// for a chosen one.
  DetectedPlace? _detected;
  UrgencyLevel _urgency = UrgencyLevel.flexible;
  final List<XFile> _images = [];

  /// Photos the project already has, as URLs. They are never re-uploaded; an
  /// edit sends them back untouched so dropping one in the UI really removes
  /// it from the project instead of silently re-adding it.
  final List<String> _keptImages = [];
  bool _busy = false;

  /// The form's own scroll position.
  ///
  /// Without a controller the page still scrolls, but every return from a
  /// picker let Flutter put focus back on the form's first text field and
  /// scroll it into view — the very top. The founder, verbatim: «when i choise
  /// a wilaya or city i get scrolled up to the top of the page fix it». Holding
  /// the controller means the form can put the reader back where he was.
  final _scroll = ScrollController();

  bool get _isEdit => widget.initial != null;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
    final existing = widget.initial;
    if (existing != null) {
      _title.text = existing.title;
      _desc.text = existing.description ?? '';
      _budgetMin.text = existing.budgetMin?.toString() ?? '';
      _budgetMax.text = existing.budgetMax?.toString() ?? '';
      _commune.text = existing.commune ?? '';
      _categories
        ..clear()
        ..addAll(existing.allCategories);
      _wilaya = existing.wilaya;
      _urgency = existing.urgency;
      _keptImages.addAll(existing.images);
    } else {
      // A place the app already knows — detected when the app opened, so the
      // offer and the form agree on where the visitor is. No dialog here: the
      // launch already asked. Then the quiet attempt, for the case where
      // permission is held but the launch had not resolved a wilaya yet.
      final known = AppScope.maybeOf(context)?.place.place;
      if (known != null) {
        // Before the first build, so no setState: the field is filled on the
        // frame that draws it.
        _seedFromPhone(known);
      } else {
        _autoDetectQuietly();
      }
    }
  }

  /// Marks the wilaya as read from the phone rather than chosen. Split out so
  /// the seed above runs before the first build, without a setState.
  void _seedFromPhone(DetectedPlace place) {
    _detected = place;
    _wilaya = place.wilayaId;
  }

  Future<void> _autoDetectQuietly() async {
    try {
      if (!await Locator.canDetectQuietly()) return;
      final place = await Locator.detect();
      if (!mounted || _wilaya != null) return;
      await _applyPlace(place);
    } catch (_) {
      // Quiet by design: a silent fill that fails stays silent.
    }
  }

  /// Fills the wilaya, and the commune when the reading names one that this
  /// wilaya actually has (the device may answer in Latin, so the match runs
  /// through the same offline index the picker searches).
  Future<void> _applyPlace(DetectedPlace place) async {
    setState(() {
      _detected = place;
      _wilaya = place.wilayaId;
    });
    final named = place.commune;
    if (named == null || _commune.text.trim().isNotEmpty) return;
    try {
      await CommuneIndex.instance.load();
      final hits = CommuneIndex.instance.search(place.wilayaId, named, limit: 5);
      if (hits.isNotEmpty && mounted) {
        setState(() => _commune.text = hits.first.name);
      }
    } catch (_) {
      // A commune is optional; the wilaya is the answer that matters.
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _title.dispose();
    _desc.dispose();
    _budgetMin.dispose();
    _budgetMax.dispose();
    _commune.dispose();
    super.dispose();
  }

  /// Opens a picker without losing the reader's place.
  ///
  /// Two things happen around every sheet: the focus is dropped first, because
  /// that is what Flutter uses to scroll the form back to the top when the
  /// sheet closes, and the offset is measured before and restored after, so the
  /// return is exact even if the keyboard resized the page in between.
  Future<T?> _detour<T>(Future<T?> Function() open) async {
    final offset = _scroll.hasClients ? _scroll.offset : null;
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await open();
    _restoreScroll(offset);
    return result;
  }

  void _restoreScroll(double? offset) {
    if (offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      final want = offset.clamp(0.0, max);
      if ((_scroll.offset - want).abs() > 0.5) _scroll.jumpTo(want);
    });
  }

  /// Photos this project may still take: the cap minus what it already has and
  /// what has been picked this session.
  ///
  /// The old call passed `limit: 6` to the picker, which is a limit on **one
  /// selection** and not on the total — a client who picked 5 and then came back
  /// for 6 more ended up posting eleven photos, on a screen whose own counter
  /// had no way to describe a number that high. It is also the only place the
  /// cap can be enforced *before* the gallery opens, because the picker is the
  /// one moment the phone still knows how many there will be.
  int get _photoRoom => projectPhotoRoom(_keptImages.length, _images.length);

  Future<void> _pickImages() async {
    final room = _photoRoom;
    if (room <= 0) {
      _toast(S.errProjectPhotoCap);
      return;
    }
    final picker = ImagePicker();
    // The cap is passed down as well as up: the OS picker is told the room, and
    // the result is trimmed to it. Both, because the limit is a request — on a
    // stock Android build it is honoured, and a mis-wired or overridden picker
    // can still hand back the whole gallery. A project that accepted whatever
    // arrived would be the one place in the app with no bound on its size.
    final files = await picker.pickMultiImage(limit: room);
    if (files.isEmpty) return;
    setState(() => _images.addAll(files.take(room)));
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _categories.isEmpty || _wilaya == null) {
      _toast('أكمل العنوان، التخصص والولاية');
      return;
    }
    final budgetError = _budgetError;
    if (budgetError != null) {
      _toast(budgetError);
      return;
    }
    setState(() => _busy = true);
    // The one handle we will have on a row the server may already have created
    // while its answer was in flight, so it is read before the write, not after.
    final publishedTitle = _title.text.trim();
    try {
      final urls = <String>[];
      for (final f in _images) {
        final url = await _repo.uploadDocument(File(f.path));
        urls.add(url);
      }
      final allImages = <String>[..._keptImages, ...urls];
      final editing = widget.initial;
      if (editing != null) {
        await _repo.updateProject(
          editing.id,
          title: _title.text.trim(),
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          category: _categories.first,
          categories: _categories.toList(),
          wilaya: _wilaya,
          commune: _commune.text.trim().isEmpty ? null : _commune.text.trim(),
          budgetMin: _budgetMinValue,
          budgetMax: _budgetMaxValue,
          urgency: _urgency,
          images: allImages,
        );
        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('تم حفظ التعديل')));
        }
        return;
      }
      await _repo.createProject(
        title: publishedTitle,
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        category: _categories.first,
        categories: _categories.toList(),
        wilaya: _wilaya,
        commune: _commune.text.trim().isEmpty ? null : _commune.text.trim(),
        budgetMin: _budgetMinValue,
        budgetMax: _budgetMaxValue,
        urgency: _urgency,
        images: urls,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم نشر مشروعك بنجاح')));
      }
    } catch (e) {
      if (isWriteUnconfirmed(e)) {
        // The app refused to guess whether «انشر مشروعك» landed, and told the
        // user to check the list. So check it — right now, from this screen —
        // and answer the question with what the server actually holds.
        _toast(S.writeUnconfirmedRecheck);
        final outcome = await resolveWriteOutcome(
          recheck: () async {
            final rows = await _repo.myProjects();
            return rows.any((p) => p.title.trim() == publishedTitle);
          },
        );
        if (!mounted) return;
        _toast(writeOutcomeCopy(outcome));
        return;
      }
      _toast(errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The budget ends as the user actually wrote them — Arabic-Indic digits,
  /// `25.000` grouping and a pasted `دج` all included. Null means "no usable
  /// number in this field".
  int? get _budgetMinValue => DzNumber.tryParse(_budgetMin.text);
  int? get _budgetMaxValue => DzNumber.tryParse(_budgetMax.text);

  /// Arabic explanation for a budget that cannot be posted, or null when the
  /// row is fine. Empty is always fine — the budget is optional.
  String? get _budgetError {
    for (final c in [_budgetMin, _budgetMax]) {
      if (c.text.trim().isNotEmpty && DzNumber.digits(c.text).isEmpty) {
        return 'الميزانية يجب أن تكون رقماً بالدينار';
      }
    }
    final min = _budgetMinValue;
    final max = _budgetMaxValue;
    if (min != null && max != null && min > max) {
      return 'الحد الأدنى أكبر من الحد الأعلى — صحّح الميزانية';
    }
    return null;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickWilaya() async {
    final picked = await _detour(() => showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _WilayaSheet(),
        ));
    if (picked == null) return;
    // A commune only means something inside its wilaya: keeping حسين داي
    // selected after switching to وهران would post a project that cannot exist.
    setState(() {
      if (picked != _wilaya) _commune.clear();
      _wilaya = picked;
      // Chosen by hand now, so the GPS note stops claiming it.
      _detected = null;
    });
  }

  Future<void> _pickCommune() async {
    if (_wilaya == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر الولاية أولاً')),
      );
      return;
    }
    final wilaya = _wilaya!;
    final picked = await _detour(() => showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _CommuneSheet(
            wilayaId: wilaya,
            wilayaName: Taxonomy.wilayaName(wilaya),
          ),
        ));
    if (picked != null) setState(() => _commune.text = picked);
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        _title.text.trim().isNotEmpty && _categories.isNotEmpty && _wilaya != null;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'عدّل مشروعك' : 'انشر مشروعك')),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Intro banner ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.infoWash,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                ),
                child: Row(
                  children: [
                    Icon(
                        _isEdit
                            ? Icons.edit_note_rounded
                            : Icons.tips_and_updates_rounded,
                        color: AppTheme.info,
                        size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isEdit
                            ? 'عدّل ما تريد ثم اضغط حفظ — لا يمكن التعديل بعد اختيار مقاول'
                            : 'املأ المعلومات وسيتواصل معك الحرفيون بعروضهم',
                        style: AppTheme.bodySoft
                            .copyWith(fontSize: AppTheme.fsMeta, color: AppTheme.info),
                      ),
                    ),
                  ],
                ),
              ),

              const _StepLabel(1, 'عنوان المشروع', required: true),
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'مثال: ترميم فيلا في الجزائر العاصمة',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),

              const _StepLabel(2, 'وصف المشروع'),
              TextField(
                controller: _desc,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'اشرح ما تريد إنجازه، المساحة، والمواد المطلوبة...',
                ),
              ),

              const _StepLabel(3, 'التخصصات المطلوبة', required: true),
              Text(
                'يمكنك اختيار أكثر من تخصص لنفس المشروع.',
                style: AppTheme.caption.copyWith(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 8),
              CategoryGridMultiTiles(
                selected: _categories,
                onToggle: (v) => setState(() {
                  if (!_categories.remove(v)) _categories.add(v);
                }),
              ),

              const _StepLabel(4, 'مكان المشروع', required: true),
              _PickerField(
                value: _wilaya == null ? null : Taxonomy.wilayaName(_wilaya!),
                hint: 'اختر الولاية',
                icon: Icons.location_on_rounded,
                onTap: _pickWilaya,
              ),
              const SizedBox(height: 10),
              _PickerField(
                value:
                    _commune.text.trim().isEmpty ? null : _commune.text.trim(),
                hint: _wilaya == null
                    ? 'اختر الولاية أولاً'
                    : 'اختر البلدية (اختياري)',
                icon: Icons.location_city_rounded,
                onTap: _pickCommune,
              ),
              const SizedBox(height: 10),
              // One tap fills the two fields above from the phone's position.
              DetectLocationButton(
                label: 'حدّد موقعي تلقائياً',
                onDetected: _applyPlace,
              ),
              if (_detected != null)
                DetectedPlaceNote(
                  place: _detected!,
                  onClear: () => setState(() {
                    _detected = null;
                    _wilaya = null;
                    _commune.clear();
                  }),
                ),

              const _StepLabel(5, 'الميزانية التقديرية'),
              Row(
                children: [
                  Expanded(
                    child: NumberField(
                      controller: _budgetMin,
                      hintText: 'من',
                      suffixText: 'دج',
                      // Live, so reversing the two ends is visible while typing
                      // rather than at publish time.
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NumberField(
                      controller: _budgetMax,
                      hintText: 'إلى',
                      suffixText: 'دج',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_budgetError != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 16, color: AppTheme.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _budgetError!,
                        style: AppTheme.caption
                            .copyWith(fontSize: AppTheme.fsCaption, color: AppTheme.danger),
                      ),
                    ),
                  ],
                )
              else
                Text('اتركها فارغة إذا لم تكن متأكداً من التكلفة',
                    style: AppTheme.caption),

              const _StepLabel(6, 'متى تريد البدء؟'),
              _UrgencySelector(
                selected: _urgency,
                onChanged: (v) => setState(() => _urgency = v),
              ),

              const _StepLabel(7, 'صور المشروع'),
              if (_keptImages.isNotEmpty) ...[
                Text('الصور المحفوظة', style: AppTheme.bodySoft),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _keptImages.length; i++)
                      _KeptPhoto(
                        url: _keptImages[i],
                        onRemove: () =>
                            setState(() => _keptImages.removeAt(i)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              _ImageAttach(
                images: _images,
                keptCount: _keptImages.length,
                onPick: _pickImages,
                onRemove: (i) => setState(() => _images.removeAt(i)),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),

      // ── Always-visible primary action ────────────────────────────────
      bottomNavigationBar: StickyCta(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!ready)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'العنوان، التخصص والولاية مطلوبة',
                  style: AppTheme.caption
                      .copyWith(fontSize: AppTheme.fsCaption, color: AppTheme.accentDeep),
                ),
              ),
            PrimaryButton(
              label: _isEdit ? 'احفظ التعديل' : 'نشر المشروع',
              icon: _isEdit ? Icons.save_rounded : Icons.send_rounded,
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// One photo the project already has, shown while editing so it can be
/// dropped. Network images are fine to fail here: the project's own URL is
/// what it is, and a broken one still has to be removable.
class _KeptPhoto extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;

  const _KeptPhoto({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          child: NetImage(
            url,
            semanticLabel: 'صورة المشروع',
            width: 78,
            height: 78,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 78,
              height: 78,
              color: AppTheme.surfaceAlt,
              child: const Icon(Icons.broken_image_outlined,
                  color: AppTheme.textMuted),
            ),
          ),
        ),
        Positioned(
          top: -6,
          left: -6,
          child: Semantics(
            label: 'حذف الصورة',
            button: true,
            child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: AppTheme.danger, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    color: AppTheme.onNavy, size: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Section header for the form.
///
/// Deliberately NOT a numbered circle: an outlined/filled circle next to a list
/// of options reads as a *radio button*, so users tried to "select" a section
/// instead of filling it. A small accent bar plus bold text reads unmistakably
/// as a heading.
class _StepLabel extends StatelessWidget {
  final String text;
  final bool required;

  /// The leading int is an ordinal ("step 1, 2, 3…") kept so call sites read
  /// naturally; it is intentionally not drawn.
  const _StepLabel(int step, this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(AppTheme.rXs),
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(text, style: AppTheme.h2.copyWith(fontSize: AppTheme.fsLead)),
          ),
          if (required) ...[
            const SizedBox(width: 5),
            Text('*',
                style:
                    AppTheme.h2.copyWith(fontSize: AppTheme.fsLead, color: AppTheme.danger)),
          ],
        ],
      ),
    );
  }
}

/// Tappable field that opens a picker sheet.
class _PickerField extends StatelessWidget {
  final String? value;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;

  const _PickerField({
    required this.value,
    required this.hint,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final empty = value == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: AppTheme.fieldPad,
          decoration: AppTheme.fieldDecorationOf(),
          child: Row(
            children: [
              Icon(icon, size: 21, color: AppTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value ?? hint,
                  style: AppTheme.body.copyWith(
                    fontSize: AppTheme.fsBody,
                    color: empty ? AppTheme.textMuted : AppTheme.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.expand_more_rounded,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable wilaya picker — 58 entries is too many to hunt through blind.
class _WilayaSheet extends StatefulWidget {
  const _WilayaSheet();

  @override
  State<_WilayaSheet> createState() => _WilayaSheetState();
}

class _WilayaSheetState extends State<_WilayaSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    // Folded, not raw: a user hunting for الجزائر may type الجزاير or drop the
    // hamza, and the code path (16) has to keep working alongside the name.
    final list = Taxonomy.wilayas
        .where((w) => ArabicSearch.matches(_q, [w.name, w.id]))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(
                hintText: 'ابحث عن ولاية...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyView(
                    icon: Icons.search_off_rounded,
                    title: 'لا توجد نتائج',
                  )
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final w = list[i];
                      return ListTile(
                        leading: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.lineSoft,
                            borderRadius: BorderRadius.circular(AppTheme.rSm),
                          ),
                          child: Text(
                            w.id,
                            style: AppTheme.label.copyWith(
                                fontSize: AppTheme.fsCaption, color: AppTheme.textSecondary),
                          ),
                        ),
                        title: Text(w.name, style: AppTheme.label),
                        onTap: () => Navigator.pop(context, w.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Searchable commune picker for the wilaya already chosen.
///
/// 57 options in the largest wilaya is more than anyone wants to scroll blind,
/// so the list opens filtered by typing. Matching is folded and bilingual
/// ([CommuneIndex.search]), and a name that is not in the list can still be
/// used as typed — the dataset must never be the reason a project cannot be
/// posted.
class _CommuneSheet extends StatefulWidget {
  const _CommuneSheet({required this.wilayaId, required this.wilayaName});

  final String wilayaId;
  final String wilayaName;

  @override
  State<_CommuneSheet> createState() => _CommuneSheetState();
}

class _CommuneSheetState extends State<_CommuneSheet> {
  String _q = '';
  bool _loading = true;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    CommuneIndex.instance.forWilaya(widget.wilayaId).then((list) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _total = list.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = CommuneIndex.instance;
    final shown = index.search(widget.wilayaId, _q);
    final matches = index.searchCount(widget.wilayaId, _q);
    final typed = _q.trim();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
            child: Row(
              children: [
                const Icon(Icons.location_city_rounded,
                    size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.wilayaName,
                    style: AppTheme.label.copyWith(fontSize: AppTheme.fsBody),
                  ),
                ),
                if (!_loading)
                  Text(
                    communeCountAr(_total),
                    style: AppTheme.caption.copyWith(color: AppTheme.textMuted),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'ابحث عن بلدية...',
                prefixIcon: const Icon(Icons.search_rounded),
                // Static decoration on purpose: swapping the suffix in and out
                // as text arrives rebuilds the decorator mid-keystroke, and the
                // field stops delivering edits (typing looked ignored). The
                // button is always present and simply disabled while empty.
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppTheme.textSecondary,
                  tooltip: 'مسح البحث',
                  onPressed:
                      typed.isEmpty ? null : () => setState(() => _q = ''),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const SkeletonRowList()
                : shown.isEmpty
                    ? Column(
                        children: [
                          const Expanded(
                            child: EmptyView(
                              icon: Icons.search_off_rounded,
                              title: 'لا توجد بلدية بهذا الاسم',
                            ),
                          ),
                          if (typed.isNotEmpty)
                            // Escape hatch: the list is authoritative, but a user
                            // whose commune was merged or renamed must not be
                            // stuck — whatever they typed is accepted.
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      Navigator.pop(context, typed),
                                  icon:
                                      const Icon(Icons.edit_rounded, size: 18),
                                  label: Text('استعمل "$typed" كما كتبتها'),
                                ),
                              ),
                            ),
                        ],
                      )
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: shown.length + 1,
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                              child: Text(
                                communeCountAr(matches),
                                style: AppTheme.caption
                                    .copyWith(color: AppTheme.textMuted),
                              ),
                            );
                          }
                          final c = shown[i - 1];
                          return ListTile(
                            leading: const Icon(
                              Icons.place_outlined,
                              color: AppTheme.textSecondary,
                            ),
                            title: Text(c.name, style: AppTheme.label),
                            subtitle: Text(
                              c.latin,
                              style: AppTheme.caption
                                  .copyWith(color: AppTheme.textMuted),
                            ),
                            onTap: () => Navigator.pop(context, c.name),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Urgency picker — explicit colours, wraps instead of overflowing.
class _UrgencySelector extends StatelessWidget {
  final UrgencyLevel selected;
  final void Function(UrgencyLevel) onChanged;

  const _UrgencySelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const opts = <(UrgencyLevel, String, IconData)>[
      (UrgencyLevel.flexible, 'بدون استعجال', Icons.event_available_rounded),
      (UrgencyLevel.withinWeek, 'خلال أسبوع', Icons.date_range_rounded),
      (UrgencyLevel.withinMonth, 'خلال شهر', Icons.calendar_month_rounded),
      (UrgencyLevel.urgent, 'عاجل جداً', Icons.bolt_rounded),
    ];
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final o in opts)
          _UrgencyPill(
            label: o.$2,
            icon: o.$3,
            selected: selected == o.$1,
            danger: o.$1 == UrgencyLevel.urgent,
            onTap: () => onChanged(o.$1),
          ),
      ],
    );
  }
}

class _UrgencyPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  const _UrgencyPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.danger,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = danger ? AppTheme.danger : AppTheme.navy;
    final wash = danger ? AppTheme.dangerWash : AppTheme.accentWash;

    return Material(
      color: Colors.transparent,
      child: A11y.button(
        selected: selected,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          // v19 x2 + the 18.9 dp row = 56.9 dp: a pill that sets how urgent a
          // project is has to be tappable by the same hand that types the title.
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 19),
          decoration: BoxDecoration(
            color: selected ? wash : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            border: Border.all(
              color: selected ? tint : AppTheme.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 17, color: selected ? tint : AppTheme.textSecondary),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppTheme.label.copyWith(
                  fontSize: AppTheme.fsMeta,
                  color: selected ? tint : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}

/// Photo attach strip with removable thumbnails.
class _ImageAttach extends StatelessWidget {
  final List<XFile> images;

  /// Photos the project already carried when the form opened. Counted into the
  /// cap, never into the line under the strip: a client editing a project with
  /// six photos on it is adding photos, not posting six new ones.
  final int keptCount;

  final VoidCallback onPick;
  final void Function(int index) onRemove;

  const _ImageAttach({
    required this.images,
    required this.keptCount,
    required this.onPick,
    required this.onRemove,
  });

  /// Room left on the project, kept and picked together.
  int get _room => projectPhotoRoom(keptCount, images.length);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // The old gate was `images.length < 6`, which never saw the kept
              // photos: a project with six photos still offered «أضف صورة» to
              // the client editing it.
              if (_room > 0)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPick,
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                    child: Container(
                      width: 96,
                      decoration: AppTheme.fieldDecorationOf(
                        fill: AppTheme.cardFill,
                        border: AppTheme.navy,
                        borderWidth: 1.5,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_rounded,
                              color: AppTheme.navy, size: 24),
                          const SizedBox(height: 6),
                          Text('أضف صورة',
                              style: AppTheme.label.copyWith(fontSize: AppTheme.fsCaption)),
                        ],
                      ),
                    ),
                  ),
                ),
              for (var i = 0; i < images.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 9),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.rMd),
                        child: Image.file(
                          File(images[i].path),
                          semanticLabel: 'صورة المشروع ${i + 1}',
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: A11y.tap(
                          label: 'حذف الصورة ${i + 1}',
                          child: GestureDetector(
                          onTap: () => onRemove(i),
                          // The disc stays 26 dp; the target around it is the
                          // full 56. This is the smallest control on the screen
                          // where losing a photo means re-picking it.
                          child: SizedBox(
                            width: AppTheme.tapMin,
                            height: AppTheme.tapMin,
                            child: Center(
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: const BoxDecoration(
                                  color: AppTheme.danger,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded,
                                    size: 16, color: AppTheme.onNavy),
                              ),
                            ),
                          ),
                        )),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          images.isEmpty
              ? 'أضف صوراً لعملك — الصور الجيدة تجلب عروضاً أكثر'
              : addedPhotosLineAr(images.length),
          style: AppTheme.caption,
        ),
      ],
    );
  }
}
