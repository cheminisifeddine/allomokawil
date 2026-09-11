import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../data/repository.dart';
import '../../models/enums.dart';
import '../../models/worker.dart';
import '../../widgets/big_button.dart';

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
      await _repo.submitVerification(worker.id, documents);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم إرسال مستنداتك، بانتظار المراجعة ✔')));
        Navigator.of(context).pop();
      }
    } on Exception catch (e) {
      _$toast(e.toString());
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
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('تعذّر جلب ملفك'));
          }
          final worker = snap.data!;
          final verified = worker.verificationStatus == VerificationStatus.verified;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (verified)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2E1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(children: [
                    Icon(Icons.verified, color: Color(0xFF2E7D32)),
                    SizedBox(width: 10),
                    Expanded(
                        child: Text('حسابك موثّق. يمكنك استقبال المشاريع.',
                            style: TextStyle(
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w700))),
                  ]),
                )
              else ...[
                const Text(
                  'لكي تظهر للموكلين وتحصل على شارة "موثّق"، أرفق المستندات التالية.',
                  style: TextStyle(fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 18),
                _DocRow(
                    index: 0,
                    label: 'بطاقة المقاول/الإسالتكار',
                    file: _docs[0].$2,
                    onPick: () => _pickFor(0)),
                const SizedBox(height: 10),
                _DocRow(
                    index: 1,
                    label: 'صورة شخصية (سيلفي)',
                    file: _docs[1].$2,
                    onPick: () => _pickFor(1)),
                const SizedBox(height: 10),
                _DocRow(
                    index: 2,
                    label: 'بطاقة التعريف (وجه)',
                    file: _docs[2].$2,
                    onPick: () => _pickFor(2)),
                const SizedBox(height: 22),
                BigButton(
                  label: 'إرسال المستندات',
                  icon: Icons.upload_file_outlined,
                  loading: _busy,
                  onPressed: () => _submit(worker),
                ),
                const SizedBox(height: 12),
                const Text(
                  'تُراجع المستندات خلال 24-48 ساعة. تُحذف صور المستندات من الخادم بعد المراجعة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73))),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  final int index;
  final String label;
  final XFile? file;
  final VoidCallback onPick;

  const _DocRow(
      {required this.index,
      required this.label,
      required this.file,
      required this.onPick});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E7E3)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 56,
                height: 56,
                color: const Color(0xFFF0EFEB),
                child: file != null
                    ? Image.file(File(file!.path), fit: BoxFit.cover)
                    : const Icon(Icons.add_a_photo_outlined,
                        color: Color(0xFF8A8A90)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(file == null ? 'أضف: $label' : label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          file == null ? FontWeight.w400 : FontWeight.w700)),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFC0C0C4)),
          ],
        ),
      ),
    );
  }
}