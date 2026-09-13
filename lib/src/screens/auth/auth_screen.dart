// Signing in and signing up, on ONE screen.
//
// Why: the app used to open on a role gate ("I'm a project owner" / "I'm a
// contractor") and only then ask whether you wanted to sign in or create an
// account — so a user who already had an account had to answer a question about
// their role, and everybody had to answer two questions before they could type
// anything. Both questions belong on the form itself: the sign-in/sign-up switch
// is a two-segment control at the top, and the role choice lives inside the
// create-account half, next to the fields it affects, with a plain-language
// explanation of what each role gets.
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/text/dz_phone.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../models/enums.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/ui.dart';
import '../../core/l10n/error_copy.dart';

/// Which half of the same form is on screen.
enum AuthMode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  /// The half to open on. Sign-up by default: a brand-new install is the common
  /// case, and the switch is one tap away.
  final AuthMode mode;

  /// Pre-selects the contractor tile when the user arrived from somewhere that
  /// already implied it (e.g. the "I'm a contractor" line on the landing page).
  final UserRole role;

  const AuthScreen(
      {super.key, this.mode = AuthMode.signUp, this.role = UserRole.customer});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();

  late AuthMode _mode = widget.mode;
  late UserRole _role = widget.role;

  bool _busy = false;
  // Set once the user has tried to submit, so the phone field can show why it
  // objected instead of only the form-level notice at the bottom.
  bool _phoneTried = false;
  bool _showPassword = false;
  bool _remember = false;
  String? _error;

  bool get _isSignUp => _mode == AuthMode.signUp;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Switching halves keeps whatever is already typed — the phone number is the
  /// same in both, and retyping it after a failed sign-in is how people give up.
  void _switchMode(AuthMode next) {
    if (next == _mode) return;
    setState(() {
      _mode = next;
      _error = null;
      _phoneTried = false;
    });
  }

  /// Clear the notice as soon as the user edits something.
  void _touch() {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    final auth = AppScope.of(context).auth;
    if (_isSignUp) {
      await _register(auth);
    } else {
      await _signIn(auth);
    }
  }

  Future<void> _signIn(dynamic auth) async {
    if (_phone.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() {
        _phoneTried = true;
        _error = 'أدخل رقم الهاتف وكلمة المرور';
      });
      return;
    }
    // Same rule as the API. Signing in with a number the server will normalise to
    // something else is exactly how "الرقم غير مسجل" happens for a valid account.
    if (!DzPhone.isValid(_phone.text)) {
      setState(() {
        _phoneTried = true;
        _error = S.phoneInvalid;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.login(
          phone: DzPhone.canonical(_phone.text),
          password: _password.text,
          rememberMe: _remember);
      // The root gate listens to AuthState: unwind to it so it swaps in RoleHome.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register(dynamic auth) async {
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
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWorker = _role == UserRole.worker;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ModeSwitch(mode: _mode, onChanged: _switchMode),
                    const SizedBox(height: 18),
                    Text(
                      _isSignUp ? 'أنشئ حسابك في دقيقة' : 'أهلاً بعودتك',
                      style: AppTheme.h1.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isSignUp
                          ? 'اختر نوع حسابك، ثم املأ بياناتك.'
                          : 'سجّل دخولك لمتابعة مشاريعك ورسائلك.',
                      style: AppTheme.bodySoft,
                    ),
                    const SizedBox(height: 18),
                    if (_isSignUp) ...[
                      const _FieldLabel(
                          text: 'نوع الحساب', icon: Icons.badge_outlined),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableTile(
                              icon: Icons.home_work_outlined,
                              label: S.customerLabel,
                              selected: _role == UserRole.customer,
                              tint: AppTheme.info,
                              wash: AppTheme.infoWash,
                              height: 92,
                              onTap: () =>
                                  setState(() => _role = UserRole.customer),
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
                              height: 92,
                              onTap: () =>
                                  setState(() => _role = UserRole.worker),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isWorker ? S.workerDesc : S.customerDesc,
                        style: AppTheme.caption.copyWith(
                            color: AppTheme.textSecondary, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                    ],
                    AppCard(
                      padding: AppTheme.cardPad,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isSignUp) ...[
                            const _FieldLabel(
                                text: S.fullName,
                                icon: Icons.person_outline_rounded),
                            TextField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.words,
                              onChanged: (_) => _touch(),
                              decoration:
                                  authInput(icon: Icons.person_outline_rounded),
                            ),
                            const SizedBox(height: 18),
                          ],
                          DzPhoneField(
                            controller: _phone,
                            forceValidate: _phoneTried,
                            onChanged: _touch,
                          ),
                          if (_isSignUp) ...[
                            const SizedBox(height: 14),
                            const _FieldLabel(
                                text: '${S.email} (اختياري)',
                                icon: Icons.mail_outline_rounded),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => _touch(),
                              decoration:
                                  authInput(icon: Icons.mail_outline_rounded),
                            ),
                          ],
                          const SizedBox(height: 18),
                          const _FieldLabel(
                              text: S.password,
                              icon: Icons.lock_outline_rounded),
                          TextField(
                            key: const Key('auth-password'),
                            controller: _password,
                            obscureText: !_showPassword,
                            textInputAction: _isSignUp
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onChanged: (_) => _touch(),
                            onSubmitted: (_) => _isSignUp ? null : _submit(),
                            decoration: authInput(
                              icon: Icons.lock_outline_rounded,
                              suffix: _RevealButton(
                                shown: _showPassword,
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword),
                              ),
                            ),
                          ),
                          if (!_isSignUp) ...[
                            _RememberRow(
                              value: _remember,
                              onChanged: (v) => setState(() => _remember = v),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            AuthNotice(message: _error!),
                          ],
                          const SizedBox(height: 18),
                          PrimaryButton(
                            key: const Key('auth-submit'),
                            label: _isSignUp ? S.createAccount : S.login,
                            icon: _isSignUp
                                ? Icons.person_add_alt_1_rounded
                                : Icons.login_rounded,
                            loading: _busy,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                    if (_isSignUp && isWorker) ...[
                      const SizedBox(height: 14),
                      const _WorkerNote(),
                    ],
                    const SizedBox(height: 18),
                    _SwitchPrompt(
                      isSignUp: _isSignUp,
                      onTap: () => _switchMode(
                          _isSignUp ? AuthMode.signIn : AuthMode.signUp),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brand mark plus a way back out of the auth screens.
class _TopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _TopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 18, 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('auth-back'),
            onPressed: onBack,
            icon: const Icon(Icons.arrow_forward_rounded,
                color: AppTheme.textPrimary),
            tooltip: S.back,
          ),
          const Spacer(),
          Text(
            S.appName,
            style: AppTheme.label
                .copyWith(fontSize: AppTheme.fsH2, color: AppTheme.textPrimary),
          ),
          const SizedBox(width: 8),
          Image.asset(
            'assets/brand/mark.png',
            // Decoration: the app name sits next to it.
            excludeFromSemantics: true,
            width: 44,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

/// The two-segment control at the top of the screen: the only choice a returning
/// user has to make before typing, and it needs no explanation.
class _ModeSwitch extends StatelessWidget {
  final AuthMode mode;
  final ValueChanged<AuthMode> onChanged;

  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final signUp = mode == AuthMode.signUp;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              key: const Key('auth-tab-signup'),
              label: 'حساب جديد',
              icon: Icons.person_add_alt_1_rounded,
              selected: signUp,
              onTap: () => onChanged(AuthMode.signUp),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _Segment(
              key: const Key('auth-tab-signin'),
              label: S.loginTitle,
              icon: Icons.login_rounded,
              selected: !signUp,
              onTap: () => onChanged(AuthMode.signIn),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.rXl),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            height: AppTheme.tapMin,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.rXl),
              boxShadow: selected ? AppTheme.softShadow : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 19,
                    color: selected ? AppTheme.navy : AppTheme.textMuted),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.label.copyWith(
                      fontSize: AppTheme.fsBody,
                      color: selected ? AppTheme.navy : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One line that flips the screen to the other half.
class _SwitchPrompt extends StatelessWidget {
  final bool isSignUp;
  final VoidCallback onTap;

  const _SwitchPrompt({required this.isSignUp, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(isSignUp ? S.haveAccount : S.noAccount, style: AppTheme.bodySoft),
        TextButton(
          onPressed: onTap,
          child: Text(
            isSignUp ? S.loginTitle : S.createAccount,
            style: AppTheme.label.copyWith(fontSize: AppTheme.fsBody, color: AppTheme.info),
          ),
        ),
      ],
    );
  }
}

/// Shared field decoration for the auth form: soft grey input on the white card,
/// hairline border, navy focus ring. Colours are all named so nothing can inherit
/// itself away.
InputDecoration authInput(
    {required IconData icon, String? hint, Widget? suffix}) {
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
                  .copyWith(fontSize: AppTheme.fsBody, color: AppTheme.textPrimary),
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
                    borderRadius: BorderRadius.circular(AppTheme.rXs)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  S.rememberMe,
                  style: AppTheme.label
                      .copyWith(fontSize: AppTheme.fsBody, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

/// Friendly inline error area — replaces the raw red snackbar string.
class AuthNotice extends StatelessWidget {
  final String message;

  const AuthNotice({super.key, required this.message});

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
                  .copyWith(color: AppTheme.danger, fontSize: AppTheme.fsSmall, height: 1.5),
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
              'بعد التسجيل أضف بطاقة المقاول أو الحرفي ووثائقك ليظهر حسابك موثوقاً للعملاء.',
              style: AppTheme.caption
                  .copyWith(color: AppTheme.info, fontSize: AppTheme.fsMeta, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
