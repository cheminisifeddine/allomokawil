import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/strings.dart';
import '../core/text/dz_phone.dart';
import '../core/theme/app_theme.dart';

/// The phone field every account is created and signed in with.
///
/// Why it exists: on an Algerian phone the same number arrives as `0550123456`,
/// `0550 12 34 56`, `+213 550 12 34 56`, `00213 550 12 34 56` or `٠٥٥٠١٢٣٤٥٦`
/// straight out of a contact card. A plain `TextField` posted all of those
/// verbatim and the server answered `رقم الهاتف غير صحيح` — for numbers that are
/// perfectly correct. This field does three things instead:
///
///   1. live grouping (`05 50 12 34 56`) so the number can be read back and
///      mis-typing is visible before submitting,
///   2. one Arabic inline error, using the same rule the API enforces,
///   3. paste-proofing: spaces, dashes, a country code and Arabic-Indic digits
///      are all accepted rather than rejected.
///
/// There is deliberately NO prefix picker on the field. An earlier build carried
/// a tappable `0X` / `+213` chip; to a user who has never seen a country-code
/// selector it reads as a stray label with a mystery arrow, and it asked them to
/// understand a distinction the field already handles on its own — every shape
/// of the number is folded into `05 50 12 34 56` by the input formatter below.
///
/// The controller is owned by the screen (the screens read it on submit), and
/// the digits it holds are grouped for display — always send
/// `DzPhone.canonical(controller.text)` to the API.
class DzPhoneField extends StatefulWidget {
  final TextEditingController controller;

  /// Fires on every edit so the screen can clear its own notice.
  final VoidCallback? onChanged;

  /// Set true after a submit attempt: the field then shows its error even when
  /// it is empty or was never blurred.
  final bool forceValidate;

  /// Arabic label rendered above the field.
  final String label;

  const DzPhoneField({
    super.key,
    required this.controller,
    this.onChanged,
    this.forceValidate = false,
    this.label = S.phone,
  });

  @override
  State<DzPhoneField> createState() => _DzPhoneFieldState();
}

class _DzPhoneFieldState extends State<DzPhoneField> {
  final FocusNode _focus = FocusNode();
  bool _blurred = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  /// Rebuild for the focus ring, and remember that the field was left once so a
  /// half-typed number is not shouted at while the user is still typing it.
  void _onFocus() {
    setState(() {
      if (!_focus.hasFocus) _blurred = true;
    });
  }

  String? _errorFor({required bool hasInput, required bool valid}) {
    if (valid) return null;
    if (!hasInput) return widget.forceValidate ? S.phoneRequired : null;
    // A number that is already as long as it can be and still wrong (a landline
    // 02x/03x/04x, or a stray digit) is worth flagging immediately; a shorter one
    // is simply not finished yet.
    final typed = DzPhone.digits(widget.controller.text).length;
    if (typed >= DzPhone.localLength) return S.phoneInvalid;
    if (_blurred || widget.forceValidate) return S.phoneInvalid;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.controller.text;
    final hasInput = DzPhone.digits(raw).isNotEmpty;
    final valid = DzPhone.isValid(raw);
    final error = _errorFor(hasInput: hasInput, valid: valid);
    final focused = _focus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.phone_android_rounded,
                  size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: AppTheme.label
                      .copyWith(fontSize: 15.5, color: AppTheme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: AppTheme.tapMin),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: error != null
                  ? AppTheme.danger
                  : (focused ? AppTheme.navy : AppTheme.line),
              width: (focused || error != null) ? 1.8 : 1,
            ),
          ),
          child: TextField(
            key: const Key('dz-phone-input'),
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            // Digits read left-to-right even inside an RTL page, but the number
            // sits against the right edge, where an Algerian reader looks for it.
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            inputFormatters: const [DzPhoneInputFormatter()],
            style: AppTheme.body.copyWith(
                color: AppTheme.textPrimary, letterSpacing: 1.1),
            onChanged: (_) {
              setState(() {});
              widget.onChanged?.call();
            },
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: S.phoneHint,
              hintTextDirection: TextDirection.ltr,
              hintStyle: AppTheme.body.copyWith(
                  color: AppTheme.textMuted, letterSpacing: 1.1),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              suffixIcon: valid
                  ? const Padding(
                      padding: EdgeInsets.only(left: 6, right: 12),
                      child: Icon(Icons.check_circle_rounded,
                          size: 21, color: AppTheme.success),
                    )
                  : null,
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 4, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 16, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error,
                    key: const Key('dz-phone-error'),
                    style: AppTheme.caption.copyWith(
                        color: AppTheme.danger, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Keeps the field holding grouped digits in the one shape the app reads back,
/// and turns anything pasted into that shape instead of rejecting it.
///
/// `0550-12-34-56`, `+213 550 12 34 56`, `00213550123456`, `٠٥٥٠١٢٣٤٥٦` and a
/// digit-by-digit typing of `+213****3456` all end up as `05 50 12 34 56` —
/// always the local reading, because that is the one the API canonicalises to
/// and the one an Algerian user recognises on screen.
class DzPhoneInputFormatter extends TextInputFormatter {
  const DzPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = DzPhone.digits(newValue.text);
    // A real number is at most `00213` + 9 digits; anything past that is not a
    // number, and the cap below keeps the field from growing without bound.
    if (digits.length > 20) digits = digits.substring(0, 20);
    // `groupLocal` canonicalises before it groups, so the country code has to be
    // recognised while it is still there. Capping first is how `00213550123456`
    // lost its last two digits and became a wrong-but-plausible number.
    final text = DzPhone.groupLocal(digits);
    // The caret always lands at the end: with a mask this short, editing in the
    // middle is not a flow anybody uses, and a drifting caret is worse.
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
