import 'package:flutter/material.dart';

import '../core/text/dz_number.dart';

/// The one numeric input in this app.
///
/// Every amount, year and day-count field goes through here so three things can
/// never drift apart between screens:
///
///   * it opens a **number keypad** (`TextInputType.number`), not the full text
///     keyboard a user has to hunt digits on;
///   * what it accepts is folded by [DzNumber] — `٢٥٠٠٠`, `25.000` and
///     `25 000 دج` all land as `25000`, and a fractional value is refused
///     instead of being rounded;
///   * it has one [maxDigits] cap, so no screen can accept a number the API
///     would store as garbage.
///
/// It is deliberately a thin wrapper over [TextField]: the decoration, the
/// theme and the RTL layout stay exactly as they were, which is why swapping a
/// bare `TextField` for this cannot move anything on screen.
class NumberField extends StatelessWidget {
  final TextEditingController controller;

  /// Arabic hint, e.g. 'من' or 'مثال: 8'.
  final String? hintText;

  /// Arabic floating label, e.g. 'المبلغ (دج)'.
  final String? labelText;

  /// Unit shown at the field's trailing edge, e.g. 'دج' or 'سنة'.
  final String? suffixText;

  /// Leading unit inside the field, e.g. 'كم'.
  final String? prefixText;

  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final String? errorText;
  final int maxDigits;

  const NumberField({
    super.key,
    required this.controller,
    this.hintText,
    this.labelText,
    this.suffixText,
    this.prefixText,
    this.onChanged,
    this.onEditingComplete,
    this.errorText,
    this.maxDigits = DzNumber.maxDigits,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [DzNumberInputFormatter(maxDigits: maxDigits)],
      textInputAction: TextInputAction.next,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        suffixText: suffixText,
        prefixText: prefixText,
        errorText: errorText,
      ),
    );
  }
}
