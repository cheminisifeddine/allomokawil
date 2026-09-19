import 'package:flutter/material.dart';

import '../core/location/locator.dart';
import '../core/theme/app_theme.dart';
import 'ui.dart';

/// One tap asks the phone where it is and hands the answer back as a wilaya.
///
/// Every failure gets a sentence the user can act on, and the settings button
/// is offered only when opening the system settings is the actual cure.
class DetectLocationButton extends StatefulWidget {
  /// Called with the reading. The caller decides which fields it fills.
  final ValueChanged<DetectedPlace> onDetected;

  final String label;
  final bool expanded;

  const DetectLocationButton({
    super.key,
    required this.onDetected,
    this.label = 'حدّد موقعي تلقائياً',
    this.expanded = true,
  });

  @override
  State<DetectLocationButton> createState() => _DetectLocationButtonState();
}

class _DetectLocationButtonState extends State<DetectLocationButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final place = await Locator.detect();
      if (!mounted) return;
      widget.onDetected(place);
      _say(
        place.commune == null
            ? 'تم تحديد ولايتك: ${place.wilayaName}'
            : 'تم تحديد موقعك: ${place.wilayaName} — ${place.commune}',
      );
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      _say(failure.messageAr, settings: failure.opensSettings);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message, {bool settings = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: settings
            ? SnackBarAction(
                label: 'الإعدادات',
                onPressed: () => Locator.openSettings(),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SecondaryButton(
      label: _busy ? 'جاري تحديد الموقع...' : widget.label,
      icon: _busy ? null : Icons.my_location_rounded,
      expanded: widget.expanded,
      onPressed: _busy ? null : _run,
    );
  }
}

/// The quiet, self-explaining line that sits under a GPS-filled field: it says
/// where the value came from, because a wilaya the app guessed must never look
/// like a wilaya the user chose.
class DetectedPlaceNote extends StatelessWidget {
  final DetectedPlace place;
  final VoidCallback? onClear;

  const DetectedPlaceNote({super.key, required this.place, this.onClear});

  @override
  Widget build(BuildContext context) {
    final text = place.commune == null
        ? 'حُدِّد من موقع هاتفك: ${place.wilayaName}'
        : 'حُدِّد من موقع هاتفك: ${place.wilayaName} — ${place.commune}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.my_location_rounded,
              size: 15, color: AppTheme.accentDeep),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTheme.caption.copyWith(color: AppTheme.accentDeep),
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Text(
                'مسح',
                style: AppTheme.caption.copyWith(
                  color: AppTheme.textMuted,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
