import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/text/dz_number.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../widgets/category_grid.dart';
import '../../widgets/number_field.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/write_outcome.dart';
import '../../data/profile_write_outcome.dart';

/// Edit the contractor's own profile.
///
/// Until now a contractor could only READ their profile, so a profile could
/// never be completed from the app — which left the marketplace without usable
/// supply. Every field here is optional except the name and the trades, so a
/// half-finished profile can still be saved and improved later.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final Repository _repo;

  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _years = TextEditingController();
  final _minPrice = TextEditingController();
  final _maxPrice = TextEditingController();

  final Set<String> _specialties = {};
  bool _available = true;
  /// The slider's own opening position, reused when a profile never set one.
  /// The slider's floor is 1 and the backend's default is 30, so 0 is not a
  /// value this screen can show and the old `clamp(1, 200)` was hiding that.
  static const _kDefaultRadiusKm = 30.0;
  double _radius = _kDefaultRadiusKm;

  bool _started = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Whether the row this form edits is actually **in hand**.
  ///
  /// Not `!_error`: a refusal below the button sets `_error` too, and on a
  /// loaded form that must not blank the boxes. This is the one flag that
  /// means "these boxes hold the server's values", and it is the difference
  /// between a form and a machine for overwriting a profile with empties.
  ///
  /// Set on the first successful read, and **cleared by nothing** — a retry
  /// that fails again must not restore a form still holding the previous
  /// answer, because the PATCH below would then be sending a stale row.
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    _repo = Repository(AppScope.of(context).api);
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _years.dispose();
    _minPrice.dispose();
    _maxPrice.dispose();
    super.dispose();
  }

  /// Re-reads the profile, and is the **only** way this screen ever leaves the
  /// failed state.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _repo.myProfile();
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _name.text = p.fullName;
        _bio.text = p.bio ?? '';
        _years.text = p.experienceYears > 0 ? '${p.experienceYears}' : '';
        _minPrice.text = p.priceRangeMin != null ? '${p.priceRangeMin}' : '';
        _maxPrice.text = p.priceRangeMax != null ? '${p.priceRangeMax}' : '';
        _specialties
          ..clear()
          // Legacy rows may still hold a slug dialect we no longer write.
          ..addAll(p.specialties.map(Taxonomy.canonical));
        _available = p.isAvailable;
        // A profile that never set a radius opens on the slider's own default
        // rather than on 0, which the slider has no position for. See
        // [serviceRadiusAr]: null here means the same thing it means there.
        _radius =
            (p.serviceRadiusKm ?? _kDefaultRadiusKm.round()).clamp(1, 200).toDouble();
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

  Future<void> _save() async {
    final name = _name.text.trim();
    // Folded parse — `٨` on an Arabic keypad and `2.500` are the same 2500 here.
    final min = DzNumber.tryParse(_minPrice.text);
    final max = DzNumber.tryParse(_maxPrice.text);
    final years = DzNumber.tryParse(
      _years.text,
      max: DzNumber.maxExperienceYears,
    );

    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسمك كما تريد أن يظهر للمشترين');
      return;
    }
    if (_specialties.isEmpty) {
      setState(() => _error = 'اختر تخصصاً واحداً على الأقل');
      return;
    }
    // Empty stays valid: every one of these is optional. A non-empty field that
    // did not yield a number is not optional, it is a mistake to name.
    if (_years.text.trim().isNotEmpty && years == null) {
      setState(() => _error =
          'سنوات الخبرة يجب أن تكون رقماً بين 0 و ${DzNumber.maxExperienceYears}');
      return;
    }
    for (final f in [_minPrice, _maxPrice]) {
      if (f.text.trim().isNotEmpty && DzNumber.tryParse(f.text) == null) {
        setState(() => _error = 'أسعارك يجب أن تكون أرقاماً بالدينار');
        return;
      }
    }
    if (min != null && max != null && min > max) {
      setState(() => _error = 'أدنى سعر يجب أن يكون أقل من أعلى سعر');
      return;
    }

    // The values this form is about to send, captured **before** the PATCH
    // leaves. It is the only handle on a row whose answer is in flight, and it
    // is the other half of the defect: the PATCH answers 200 with whatever the
    // server decided to keep, so the answer cannot tell us whether *our* value
    // is the one in it.
    final sent = ProfileSnapshot.form(
      fullName: name,
      bio: _bio.text.trim(),
      specialties: _specialties,
      experienceYears: years ?? 0,
      priceRangeMin: min,
      priceRangeMax: max,
      serviceRadiusKm: _radius.round(),
      isAvailable: _available,
    );

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _repo.updateMyProfile(
        fullName: name,
        bio: _bio.text.trim(),
        specialties: _specialties.toList(),
        experienceYears: years ?? 0,
        priceRangeMin: min,
        priceRangeMax: max,
        serviceRadiusKm: _radius.round(),
        isAvailable: _available,
      );
      if (!mounted) return;
      // A 200 is not a confirmation that the form's own values were kept, so
      // the answer is checked against the server before the screen claims
      // anything. This used to be `showSnackBar(«تم حفظ
      // ملفك بنجاح»); pop(updated)`, which
      // asserted a save the client had never verified — and the one case that
      // mattered was a **cleared** field, which the old body builder dropped
      // entirely. See `profile_write_outcome.dart`.
      final result = await resolveProfileWriteOutcome(
        sent: sent,
        fetch: _repo.myProfile,
      );
      if (!mounted) return;
      // The fresh row when there is one, the echoed one otherwise: popping with
      // the server's own copy is what stops the caller from drawing a profile
      // that the database does not hold. `unknown` still pops — the PATCH did
      // answer, so this screen is done — it just refuses to claim it verified.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(profileWriteOutcomeCopy(result))));
      // Only a **verified** save closes the form. The other two keep the
      // contractor on the page with his own values still in the boxes, which is
      // the only way either sentence can be read: a toast on a route that has
      // already been popped takes its message with it, so the user would be
      // told something he never got to see. Popping on `unknown` in particular
      // would claim more than the app knows — the PATCH answered, but nothing
      // has confirmed the server kept *these* values.
      if (result.outcome != WriteOutcome.landed) {
        setState(() => _saving = false);
        return;
      }
      Navigator.of(context).pop(result.fresh ?? updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorCopy(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل ملفي')),
      // A read that failed gets the shared dead-read state and nothing else.
      //
      // The bug this replaces: `_error` used to be set here and the **whole
      // form rendered anyway** — every box empty, the save button live. That
      // is not a cosmetic error, it is data loss with a green result. The PATCH
      // this screen sends is unconditional (see `Repository.updateMyProfile`),
      // so one save from a form that never loaded writes '' and null over a
      // real biography, real years, real prices and a real radius; the
      // verification this screen is proud of then re-reads, finds the server
      // holding exactly what was just destroyed, and reports «تم حفظ ملفك
      // بنجاح». Every sibling that loads a body already refuses to draw
      // anything but a retry in this state (`worker_profile_screen.dart:151`,
      // `project_detail_screen.dart:355`, `subscription_screen`); this form was
      // the only one in the app that treated a failed read as a good one.
      body: _loading
          ? const SkeletonFormPage(fields: 5)
          : !_loaded
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: EmptyView(
                      icon: Icons.error_outline_rounded,
                      title: 'تعذّر تحميل الملف',
                      message: _error,
                      actionLabel: 'إعادة المحاولة',
                      onAction: _load,
                      danger: true,
                    ),
                  ),
                )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
              children: [
                // The error is rendered **once**, in the pinned footer. It used
                // to be drawn here as well -- the same string, in a red card at
                // the top of the form and again in red type under the save
                // button. This position is also the wrong one: it is the first
                // child of a *lazy* list, so after the user has scrolled down
                // to reach the form's last field and taps the pinned save, it
                // is not built at all. Printing it only here would have made a
                // refused save show nothing at all.
                const SectionTitle('الاسم الظاهر', icon: Icons.badge_rounded),
                TextField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'مثال: عمي رشيد — بناء وتشطيب',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SectionTitle('تخصصاتك', icon: Icons.handyman_rounded),
                const _Hint(
                    'اختر كل المهن التي تتقنها. ظهورك يزيد مع كل تخصص.'),
                const SizedBox(height: 10),
                CategoryGridMultiTiles(
                  selected: _specialties,
                  onToggle: (slug) => setState(() {
                    if (!_specialties.remove(slug)) _specialties.add(slug);
                    _error = null;
                  }),
                ),
                const SectionTitle('نبذة عنك', icon: Icons.notes_rounded),
                TextField(
                  controller: _bio,
                  maxLines: 4,
                  maxLength: 600,
                  decoration: const InputDecoration(
                    hintText:
                        'عرّف بنفسك: كم سنة خبرة، ما الذي تتقنه، ومنطقتك...',
                  ),
                ),
                const SectionTitle('سنوات الخبرة',
                    icon: Icons.timeline_rounded),
                NumberField(
                  controller: _years,
                  hintText: 'مثال: 8',
                  suffixText: 'سنة',
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SectionTitle('أسعارك (دج)', icon: Icons.payments_rounded),
                const _Hint('اتركهما فارغين إذا كنت تفضل التسعير حسب المشروع.'),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('من (دج)'),
                          const SizedBox(height: 6),
                          NumberField(
                            controller: _minPrice,
                            hintText: '2500',
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('إلى (دج)'),
                          const SizedBox(height: 6),
                          NumberField(
                            controller: _maxPrice,
                            hintText: '8000',
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SectionTitle('نطاق الخدمة', icon: Icons.radar_rounded),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _radius,
                        min: 1,
                        max: 200,
                        divisions: 199,
                        label: '${_radius.round()} كم',
                        activeColor: AppTheme.navy,
                        onChanged: (v) => setState(() => _radius = v),
                      ),
                    ),
                    SizedBox(
                      width: 74,
                      child: Text(
                        '${_radius.round()} كم',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          color: AppTheme.navy,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: AppTheme.cardDecoration,
                  child: SwitchListTile.adaptive(
                    value: _available,
                    activeThumbColor: AppTheme.navy,
                    onChanged: (v) => setState(() => _available = v),
                    title: const Text(
                      'متاح لاستقبال مشاريع جديدة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navy,
                      ),
                    ),
                    subtitle: const Text(
                      'عند الإيقاف يبقى ملفك ظاهراً لكن بدون استقبال طلبات',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: AppTheme.fsCaption,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
              ],
            ),
      // Pinned, not at the end of the list: the form is longer than the
      // viewport, so a save button below the fold reads as "no way to save".
      // No pinned bar at all while the row is not in hand: a save button under
      // an error is a control that says "your empty boxes are a decision the
      // server will obey", which is the exact false promise above. The retry in
      // the body is the only action this state offers.
      bottomNavigationBar: !_loaded
          ? null
          : StickyCta(
              child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The one and only error surface on this screen. It lives in
            // `bottomNavigationBar`, so it is mounted from the first frame and
            // never scrolls away: the refusal appears beside the button the
            // user just pressed, which is the only place it can be read at the
            // moment it is true. `fsMeta` is what the removed duplicate used,
            // so deleting it downgrades nothing.
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTheme.fsMeta,
                    height: 1.5,
                    color: AppTheme.danger,
                  ),
                ),
              ),
                  PrimaryButton(
                    label: 'حفظ الملف',
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
    );
  }
}

/// A small always-visible label for a field. Placeholders vanish once a value
/// is typed, which left the two price boxes unlabelled and ambiguous.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: AppTheme.fsCaption,
        fontWeight: FontWeight.w700,
        color: AppTheme.navy,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTheme.fsCaption,
          height: 1.6,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }
}
