import 'package:flutter/material.dart';

import '../core/app_scope.dart';

/// Asks for the phone's position once, at the top of the launch.
///
/// The founder's brief, verbatim:
///   «ask for gps fird thing when the user open the app so you show related
///    offers to him. And get accurate offers too»
///
/// It is a wrapper rather than a call inside a screen for one reason: the
/// launch has four possible first screens (the landing page, the boot skeleton,
/// the client home, the contractor home) and the question has to be asked
/// exactly once, whichever one the user lands on. Grepping for the answer is
/// the same wherever it lands: `AppScope.of(context).place`.
///
/// Nothing is drawn. A refusal is not an error, so nothing is said about it —
/// the app simply keeps the manual wilaya pickers it always had.
class PlaceWarmup extends StatefulWidget {
  final Widget child;

  const PlaceWarmup({super.key, required this.child});

  @override
  State<PlaceWarmup> createState() => _PlaceWarmupState();
}

class _PlaceWarmupState extends State<PlaceWarmup> {
  bool _kicked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kicked) return;
    _kicked = true;

    final place = AppScope.maybeOf(context)?.place;
    if (place == null) return;

    // After the frame: a permission dialog is a platform round trip and must
    // never sit between the user and the first painted screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Quietly first: a launch that already holds the permission must not show
      // a dialog again. Only a phone that was never asked gets the question.
      place.detectQuietly().then((ok) {
        if (ok || !mounted) return;
        if (!place.asked) place.askAndDetect();
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
