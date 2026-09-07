import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../widgets/big_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = AppScope.of(context).auth;
    if (_phone.text.trim().isEmpty || _password.text.isEmpty) {
      _toast('أدخل رقم الهاتف وكلمة المرور');
      return;
    }
    setState(() => _busy = true);
    try {
      await auth.login(phone: _phone.text.trim(), password: _password.text, rememberMe: _remember);
      // RoleHome swaps in automatically once auth notifies.
    } on Exception catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(S.loginTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.loginSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6E6E73))),
              const SizedBox(height: 28),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: S.phone,
                  hintText: S.phoneHint,
                  prefixIcon: Icon(Icons.phone_android),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: S.password,
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? false),
                  ),
                  Expanded(child: Text(S.rememberMe, style: theme.textTheme.bodyMedium)),
                ],
              ),
              const SizedBox(height: 20),
              BigButton(
                label: S.login,
                loading: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}