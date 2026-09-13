import 'package:flutter/material.dart';

import '../core/theme/motion.dart';

/// Makes an already-tappable control visibly answer the finger.
///
/// Wraps the widget, it does not replace it: the inner [ElevatedButton] or
/// [InkWell] still owns the gesture. That is deliberate — a `Listener` sees the
/// pointer without joining the gesture arena, so a button wrapped in
/// [Pressable] cannot swallow a tap, break a drag, or change what
/// `tester.tap()` hits. The only thing this adds is a 3 % shrink on press-in,
/// which is what tells a user their thumb landed before anything happens on the
/// network.
///
/// The press is called off when the finger slides more than
/// [AppMotion.pressSlop] px, so scrolling a list does not leave a trail of
/// buttons stuck in their pressed state.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// False for a disabled or loading button: nothing to respond to.
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shrink = AnimationController(
    vsync: this,
    duration: AppMotion.press,
    reverseDuration: AppMotion.press,
  );

  Offset? _downAt;
  bool _pressed = false;

  @override
  void dispose() {
    _shrink.dispose();
    super.dispose();
  }

  /// Same switch the skeleton loader honours: the OS setting that asks the app
  /// to stop moving. A user who turned motion off gets no shrink, and no
  /// half-finished scale left behind either.
  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled || _reduceMotion) return;
    _downAt = event.position;
    _pressed = true;
    _shrink.forward();
  }

  void _onMove(PointerMoveEvent event) {
    if (!_pressed) return;
    final Offset? from = _downAt;
    if (from == null) return;
    if ((event.position - from).distance > AppMotion.pressSlop) _release();
  }

  void _release() {
    if (!_pressed) return;
    _pressed = false;
    _downAt = null;
    _shrink.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _reduceMotion) return widget.child;
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _shrink,
        builder: (BuildContext context, Widget? child) {
          final double t = AppMotion.enter.transform(_shrink.value);
          return Transform.scale(
            scale: 1 - (1 - AppMotion.pressScale) * t,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Fades a list row up into place the first time it is built.
///
/// One shot, at [AppMotion.reveal], on [AppMotion.enter] — the same tempo as a
/// page push, so a card arriving in a list and a screen arriving on top of this
/// one feel like the same app. There is no stagger and no delay timer: rows
/// that wait for a timer are rows a widget test has to wait for too, and a
/// pending timer at the end of a test is a failure.
///
/// Hit testing ignores the lift (`transformHitTests: false`), so a row is
/// tappable where it sits in the layout even while it is still moving — the
/// animation cannot move a button out from under a thumb, and it cannot move a
/// target away from `tester.tap()` either.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child});

  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.reveal,
  );

  late final Animation<double> _lift = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce motion: the row is simply there. Not a shorter animation — none.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _lift,
      builder: (BuildContext context, Widget? child) {
        final double t = _lift.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, AppMotion.revealOffset * (1 - t)),
            transformHitTests: false,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
