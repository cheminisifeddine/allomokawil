import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../models/project.dart';
import '../../widgets/big_button.dart';

/// Post a new project (client). Fields: title, category, wilaya/commune,
/// optional budget, urgency, photo attach. Big touch targets throughout.
class ProjectNewScreen extends StatefulWidget {
  const ProjectNewScreen({super.key});

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

  String? _category;
  String? _wilaya;
  UrgencyLevel _urgency = UrgencyLevel.flexible;
  final List<XFile> _images = [];
  bool _busy = false;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _budgetMin.dispose();
    _budgetMax.dispose();
    _commune.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(limit: 6);
    if (files.isNotEmpty) setState(() => _images.addAll(files));
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _category == null || _wilaya == null) {
      _toast('أكمل العنوان، التخصص والولاية');
      return;
    }
    setState(() => _busy = true);
    try {
      final urls = <String>[];
      for (final f in _images) {
        final url = await _repo.uploadDocument(File(f.path));
        urls.add(url);
      }
      await _repo.createProject(
        title: _title.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        category: _category!,
        wilaya: _wilaya,
        commune: _commune.text.trim().isEmpty ? null : _commune.text.trim(),
        budgetMin: _intOrNull(_budgetMin.text),
        budgetMax: _intOrNull(_budgetMax.text),
        urgency: _urgency,
        images: urls,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم نشر مشروعك بنجاح ✔')));
      }
    } on Exception catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _intOrNull(String v) {
    final n = int.tryParse(v.trim());
    return (n == null || n <= 0) ? null : n;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('انشر مشروعك')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'عنوان المشروع',
                  hintText: 'مثال: ترميم فيلا في الجزائر العاصمة',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _desc,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'وصف المشروع',
                  hintText: 'اشرح ما تريد إنجازه...',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 16),
              const _SectionLabel('التخصص'),
              const SizedBox(height: 8),
              _CategoryPicker(
                  selected: _category, onSelect: (v) => setState(() => _category = v)),
              const SizedBox(height: 16),
              const _SectionLabel('الولاية'),
              const SizedBox(height: 8),
              _PickerField(
                value: _wilaya == null ? null : Taxonomy.wilayaName(_wilaya!),
                hint: 'اختر الولاية',
                onTap: _pickWilaya,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _commune,
                decoration: const InputDecoration(
                  labelText: 'البلدية (اختياري)',
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
              const SizedBox(height: 16),
              const _SectionLabel('الميزانية (اختياري)'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _budgetMin,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'من', suffixText: 'دج'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _budgetMax,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'إلى', suffixText: 'دج'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SectionLabel('الاستعجال'),
              const SizedBox(height: 8),
              _UrgencySelector(
                  selected: _urgency,
                  onChanged: (v) => setState(() => _urgency = v)),
              const SizedBox(height: 16),
              const _SectionLabel('صور المشروع (اختياري)'),
              const SizedBox(height: 8),
              _ImageAttach(images: _images, onPick: _pickImages),
              const SizedBox(height: 24),
              BigButton(
                label: 'نشر المشروع',
                icon: Icons.send,
                loading: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickWilaya() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => ListView(
        children: [
          for (final w in Taxonomy.wilayas)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(w.name),
              onTap: () => Navigator.pop(context, w.id),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _wilaya = picked);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700));
}

class _PickerField extends StatelessWidget {
  final String? value;
  final String hint;
  final VoidCallback onTap;

  const _PickerField(
      {required this.value, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.expand_more, color: Color(0xFF6E6E73)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                    color: value == null ? const Color(0xFF6E6E73) : null,
                    fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  final String? selected;
  final void Function(String) onSelect;

  const _CategoryPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in Taxonomy.categories)
          ChoiceChip(
            label: Text('${c.icon} ${c.name}'),
            selected: selected == c.slug,
            onSelected: (_) => onSelect(c.slug),
          ),
      ],
    );
  }
}

class _UrgencySelector extends StatelessWidget {
  final UrgencyLevel selected;
  final void Function(UrgencyLevel) onChanged;

  const _UrgencySelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const opts = <(UrgencyLevel, String)>[
      (UrgencyLevel.flexible, 'بدون استعجال'),
      (UrgencyLevel.withinWeek, 'خلال أسبوع'),
      (UrgencyLevel.withinMonth, 'خلال شهر'),
      (UrgencyLevel.urgent, 'عاجل'),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final o in opts)
          ChoiceChip(
            label: Text(o.$2),
            selected: selected == o.$1,
            onSelected: (_) => onChanged(o.$1),
          ),
      ],
    );
  }
}

class _ImageAttach extends StatelessWidget {
  final List<XFile> images;
  final VoidCallback onPick;

  const _ImageAttach({required this.images, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EFEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined,
                          color: Color(0xFF6E6E73)),
                      SizedBox(height: 4),
                      Text('أضف صورة',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6E6E73))),
                    ],
                  ),
                ),
              ),
              for (final img in images)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(img.path),
                        width: 88, height: 88, fit: BoxFit.cover),
                  ),
                ),
            ],
          ),
        ),
        if (images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${images.length} صورة',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6E6E73))),
          ),
      ],
    );
  }
}