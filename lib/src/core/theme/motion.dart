import 'package:flutter/material.dart';

/// ── THE MOTION SPEC ─────────────────────────────────────────────────────
///
/// One tempo for the whole app. Before this file every animation picked its
/// own number: eight call sites typed `Duration(milliseconds: 140)` by hand, a
/// ninth typed 160, the rating picker re-coloured instantly, and a route push
/// ran Material's 300 ms zoom while the card that opened it faded in 140.
/// Nothing was wrong on its own; together the app moved at four speeds and
/// jumping between screens read as "cheap" even when the layout was right.
///
/// So: durations and curves are tokens here, and `test/motion_test.dart` fails
/// the build if a screen types its own animation duration again. This is the
/// same rule the type scale follows for `fontSize` — one ladder, no numbers
/// next to a scale entry.
///
/// The ladder is deliberately short. Five durations and two curves cover
/// everything the app does:
///
/// * [fast]    — colour/ink changing on a control that is already on screen.
/// * [press]   — a finger landing on a button. Shorter than [fast] on purpose:
///               press feedback that takes longer reads as lag, not as feedback.
/// * [reveal]  — a row or card arriving on a screen that has just been built.
/// * [screen]  — one screen replacing another.
/// * [shimmer] — the skeleton pulse, a loop rather than an entrance, so it is
///               the one duration that is *not* about a state change.
class AppMotion {
  AppMotion._();

  /// Colour or ink shifting on a control that is already visible.
  static const Duration fast = Duration(milliseconds: 140);

  /// A button answering a finger.
  static const Duration press = Duration(milliseconds: 90);

  /// A row arriving on a freshly built screen.
  static const Duration reveal = Duration(milliseconds: 200);

  /// One screen replacing another. Material's default is 300 ms of zoom;
  /// this is a shorter fade with a small lift.
  static const Duration screen = Duration(milliseconds: 240);

  /// The skeleton loader's pulse. A loop, not an entrance — the only duration
  /// here that a user is meant to stop noticing.
  static const Duration shimmer = Duration(milliseconds: 1300);

  /// Anything arriving on screen eases out: quick off the mark, gentle at the
  /// end, which is how a physical object settles.
  static const Curve enter = Curves.easeOutCubic;

  /// Anything leaving eases in: it accelerates away instead of drifting.
  static const Curve exit = Curves.easeInCubic;

  /// Where a button goes while a finger is on it. 3 % is enough to see and too
  /// little to notice as a movement.
  static const double pressScale = 0.97;

  /// How far a finger may slide before the press is called off — past this the
  /// user is scrolling the list, not pressing the button.
  static const double pressSlop = 12;

  /// How far a revealed row travels, in logical pixels. A fixed distance, not a
  /// fraction of the row: a short chip and a tall card lift by the same amount.
  static const double revealOffset = 8;

  /// How far the incoming page travels, as a fraction of its own height — a
  /// page is always screen-sized, so a fraction keeps the lift proportional on
  /// a 320 dp phone and on a tablet.
  static const double screenOffset = 0.02;

  /// Every animation duration the app is allowed to use, for the source scan in
  /// `test/motion_test.dart`. A duration outside this set is a new speed.
  static const List<Duration> all = <Duration>[
    fast,
    press,
    reveal,
    screen,
    shimmer,
  ];
}

/// The app's one page transition.
///
/// The incoming screen fades in and lifts a few pixels from the bottom while
/// the screen underneath dips very slightly in the same direction, so a push
/// reads as one movement instead of two independent ones. Both legs run on
/// [AppMotion.screen] and [AppMotion.enter] / [AppMotion.exit] — the same
/// tempo as a revealed list row, which is the point of the spec.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.screen;

  @override
  Duration get reverseTransitionDuration => AppMotion.screen;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;

    final Animation<double> arrive = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );
    final Animation<double> depart = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );

    return SlideTransition(
      // The page being covered sinks a touch; it never jumps.
      position: Tween<Offset>(
        begin: Offset.zero,
        end: Offset(0, -AppMotion.screenOffset),
      ).animate(depart),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, AppMotion.screenOffset),
          end: Offset.zero,
        ).animate(arrive),
        child: FadeTransition(opacity: arrive, child: child),
      ),
    );
  }
}
