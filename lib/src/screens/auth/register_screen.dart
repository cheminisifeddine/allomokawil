// Create-account screen — role choice tiles + calm card form, labels above the
// fields, Arabic inline validation. Colours come from AppTheme only.
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/text/dz_phone.dart';
import '../../core/theme/app_theme.dart';
import '../../models/enums.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/ui.dart';

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
  // Set once the user has tried to submit, so the phone field can show why it
  // objected instead of only the form-level notice at the bottom.
  bool _phoneTried = false;
  bool _showPassword = false;
  bool _showConfirm = false;
  String? _error;
  // Starts on the role the caller picked; the two tiles below can change it.
  late UserRole _role = widget.role;

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
      setState(() {
        _phoneTried = true;
        _error = 'أكمل الحقول المطلوبة';
      });
      return;
    }
    // The number is checked here, not by the server: a bad phone is caught before
    // a round trip and the field explains itself in Arabic.
    if (!DzPhone.isValid(_phone.text)) {
      setState(() {
        _phoneTried = true;
        _error = S.phoneInvalid;
      });
      return;
    }
    if (pwd.length < 8) {
      setState(() => _error = 'كلمة المرور يجب أن تكون 8 أحرف على الأقل');
      return;
    }
    if (pwd != _confirm.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.register(
        phone: DzPhone.canonical(_phone.text),
        email: _email.text.trim().isEmpty ? '' : _email.text.trim(),
        fullName: _name.text.trim(),
        password: pwd,
        role: _role,
      );
      // Account created and the session persisted: unwind every auth screen so
      // the root gate (which listens to AuthState) shows the role-aware home.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Clear the notice as soon as the user edits something.
  void _touch() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final isWorker = _role == UserRole.worker;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isWorker ? S.workerLabel : S.customerLabel,
          style: AppTheme.label
              .copyWith(fontSize: 18, color: AppTheme.textPrimary),
        ),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppTheme.pagePad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                S.registerTitle,
                style: AppTheme.h1.copyWith(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                isWorker ? S.workerDesc : S.customerDesc,
                style: AppTheme.bodySoft,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              const _FieldLabel(text: 'نوع الحساب', icon: Icons.badge_outlined),
              Row(
                children: [
                  Expanded(
                    child: SelectableTile(
                      icon: Icons.home_work_outlined,
                      label: S.customerLabel,
                      selected: _role == UserRole.customer,
                      tint: AppTheme.info,
                      wash: AppTheme.infoWash,
                      height: 96,
                      onTap: () => setState(() => _role = UserRole.customer),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableTile(
                      icon: Icons.build_outlined,
                      label: S.workerLabel,
                      selected: _role == UserRole.worker,
                      tint: AppTheme.accentDeep,
                      wash: AppTheme.accentWash,
                      height: 96,
                      onTap: () => setState(() => _role = UserRole.worker),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel(
                        text: S.fullName, icon: Icons.person_outline_rounded),
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => _touch(),
                      decoration: _input(icon: Icons.person_outline_rounded),
                    ),
                    const SizedBox(height: 18),
                    DzPhoneField(
                      controller: _phone,
                      forceValidate: _phoneTried,
                      onChanged: _touch,
                    ),
                    const SizedBox(height: 18),
                    const _FieldLabel(
                        text: S.email, icon: Icons.mail_outline_rounded),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _touch(),
                      decoration: _input(icon: Icons.mail_outline_rounded),
                    ),
                    const SizedBox(height: 18),
                    const _FieldLabel(
                        text: S.password, icon: Icons.lock_outline_rounded),
                    TextField(
                      controller: _password,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _touch(),
                      decoration: _input(
                        icon: Icons.lock_outline_rounded,
                        suffix: _RevealButton(
                          shown: _showPassword,
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _FieldLabel(
                        text: S.confirmPassword,
                        icon: Icons.lock_outline_rounded),
                    TextField(
                      controller: _confirm,
                      obscureText: !_showConfirm,
                      onChanged: (_) => _touch(),
                      decoration: _input(
                        icon: Icons.lock_outline_rounded,
                        suffix: _RevealButton(
                          shown: _showConfirm,
                          onPressed: () =>
                              setState(() => _showConfirm = !_showConfirm),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _FormNotice(message: _error!),
                    ],
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: S.createAccount,
                      icon: isWorker
                          ? Icons.build_outlined
                          : Icons.home_work_outlined,
                      loading: _busy,
                      onPressed: _submit,
                    ),
                    if (isWorker) ...[
                      const SizedBox(height: 14),
                      const _WorkerNote(),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared field decoration: soft grey input on the white card, hairline border,
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

/// Eye toggle that lets the user actually read what they typed.
class _RevealButton extends StatelessWidget {
  final bool shown;
  final VoidCallback onPressed;

  const _RevealButton({required this.shown, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        shown ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        size: 21,
        color: AppTheme.textSecondary,
      ),
      tooltip: shown ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
    );
  }
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

/// Calm information banner shown only for contractor accounts.
class _WorkerNote extends StatelessWidget {
  const _WorkerNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.infoWash,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.info),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_outlined, size: 20, color: AppTheme.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'بعد التسجيل يجب التحقق من بطاقة الإسالتكار/المقاول لعرض خدماتك',
              style: AppTheme.caption
                  .copyWith(color: AppTheme.info, fontSize: 13, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
