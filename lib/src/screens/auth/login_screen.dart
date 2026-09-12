// Sign-in screen — calm card form, labels ABOVE the fields, one amber action.
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../models/enums.dart';
import '../../widgets/ui.dart';
import 'register_screen.dart';

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
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = AppScope.of(context).auth;
    if (_phone.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'أدخل رقم الهاتف وكلمة المرور');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.login(
          phone: _phone.text.trim(),
          password: _password.text,
          rememberMe: _remember);
      // The root gate listens to AuthState: unwind to it so it swaps in RoleHome.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// No account yet? Register starts on the client tile and the register screen
  /// lets the user switch to the contractor tile before submitting.
  void _goRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RegisterScreen(role: UserRole.customer),
      ),
    );
  }

  /// Clear the notice as soon as the user edits something.
  void _touch() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          S.loginTitle,
          style: AppTheme.label.copyWith(fontSize: 18, color: AppTheme.textPrimary),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppTheme.pagePad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Center(
                child: IconBubble(
                  icon: Icons.lock_outline_rounded,
                  tint: AppTheme.navy,
                  wash: AppTheme.accentWash,
                  size: 64,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                S.loginSubtitle,
                textAlign: TextAlign.center,
                style: AppTheme.body.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 22),
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel(text: S.phone, icon: Icons.phone_android_rounded),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _touch(),
                      decoration: _input(
                        icon: Icons.phone_android_rounded,
                        hint: S.phoneHint,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _FieldLabel(text: S.password, icon: Icons.lock_outline_rounded),
                    TextField(
                      controller: _password,
                      obscureText: !_showPassword,
                      onChanged: (_) => _touch(),
                      onSubmitted: (_) => _submit(),
                      decoration: _input(
                        icon: Icons.lock_outline_rounded,
                        suffix: IconButton(
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 21,
                            color: AppTheme.textSecondary,
                          ),
                          tooltip: _showPassword
                              ? 'إخفاء كلمة المرور'
                              : 'إظهار كلمة المرور',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _RememberRow(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _FormNotice(message: _error!),
                    ],
                    const SizedBox(height: 18),
                    PrimaryButton(
                      label: S.login,
                      icon: Icons.login_rounded,
                      loading: _busy,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(S.noAccount, style: AppTheme.bodySoft),
                  TextButton(
                    onPressed: _goRegister,
                    child: Text(
                      S.createAccount,
                      style: AppTheme.label
                          .copyWith(fontSize: 15, color: AppTheme.info),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared field decoration: white-page card -> soft grey input, hairline border,
/// navy focus ring. Colours are all named so nothing can inherit itself away.
InputDecoration _input({required IconData icon, String? hint, Widget? suffix}) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: AppTheme.surfaceAlt,
    prefixIcon: Icon(icon, size: 21, color: AppTheme.textSecondary),
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      borderSide: const BorderSide(color: AppTheme.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      borderSide: const BorderSide(color: AppTheme.navy, width: 2),
    ),
    errorStyle: AppTheme.caption.copyWith(color: AppTheme.danger),
  );
}

/// Big label sitting ABOVE its field — far easier to read than a floating label
/// for users who are not confident readers.
class _FieldLabel extends StatelessWidget {
  final String text;
  final IconData icon;

  const _FieldLabel({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.label
                  .copyWith(fontSize: 15.5, color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gentle "remember me" row with a full-width tap target.
class _RememberRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RememberRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Row(
            children: [
              Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppTheme.accent,
                checkColor: AppTheme.navy,
                side: const BorderSide(color: AppTheme.line, width: 1.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  S.rememberMe,
                  style: AppTheme.label
                      .copyWith(fontSize: 15, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Friendly inline error area — replaces the raw red snackbar string.
class _FormNotice extends StatelessWidget {
  final String message;

  const _FormNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.dangerWash,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.danger),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 20, color: AppTheme.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.label
                  .copyWith(color: AppTheme.danger, fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
