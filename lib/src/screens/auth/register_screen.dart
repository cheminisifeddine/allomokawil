import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../models/enums.dart';
import '../../widgets/big_button.dart';

class RegisterScreen extends StatefulWidget {
  final UserRole role;

  const RegisterScreen({super.key, required this.role});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = AppScope.of(context).auth;
    final pwd = _password.text;
    if (_name.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        pwd.isEmpty) {
      _toast('أكمل الحقول المطلوبة');
      return;
    }
    if (pwd.length < 8) {
      _toast('كلمة المرور يجب أن تكون 8 أحرف على الأقل');
      return;
    }
    if (pwd != _confirm.text) {
      _toast('كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() => _busy = true);
    try {
      await auth.register(
        phone: _phone.text.trim(),
        email: _email.text.trim().isEmpty ? '' : _email.text.trim(),
        fullName: _name.text.trim(),
        password: pwd,
        role: widget.role,
      );
      // If worker, nudge them to verification on next screen.
    } on Exception catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isWorker = widget.role == UserRole.worker;
    return Scaffold(
      appBar: AppBar(
        title: Text(isWorker ? S.workerLabel : S.customerLabel),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                S.registerTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: S.fullName,
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: S.phone,
                  hintText: S.phoneHint,
                  prefixIcon: Icon(Icons.phone_android),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: S.email,
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: S.password,
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: S.confirmPassword,
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 24),
              BigButton(
                label: S.createAccount,
                icon: isWorker ? Icons.build_outlined : Icons.home_work_outlined,
                loading: _busy,
                onPressed: _submit,
              ),
              if (isWorker) ...[
                const SizedBox(height: 14),
                const Text(
                  'بعد التسجيل يجب التحقق من بطاقة الإسالتكار/المقاول لعرض خدماتك',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF6E6E73)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}