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
  double _radius = 30;

  bool _started = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

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

  Future<void> _load() async {
    try {
      final p = await _repo.myProfile();
      if (!mounted) return;
      setState(() {
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
        _radius = p.serviceRadiusKm.clamp(1, 200).toDouble();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ ملفك بنجاح')),
      );
      Navigator.of(context).pop(updated);
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
      body: _loading
          ? const SkeletonFormPage(fields: 5)
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
              children: [
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  _Notice(text: _error!),
                ],
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
                        fontSize: 12,
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
      bottomNavigationBar: StickyCta(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    height: 1.4,
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
        fontSize: 12.5,
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
          fontSize: 12.5,
          height: 1.6,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppTheme.cardPad,
      decoration: AppTheme.cardDecorationOf(
        fill: AppTheme.dangerWash,
        border: AppTheme.danger,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13.5,
                height: 1.5,
                color: AppTheme.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
