import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/l10n/snack.dart';
import '../core/location/locator.dart';

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
/// Nothing is drawn on the happy path. A refusal is not an error, so nothing is
/// said about it — the app simply keeps the manual wilaya pickers it always had.
///
/// What it does draw is the case that used to be invisible: a fix that failed for
/// a reason the user can act on (the location toggle off, a permission blocked in
/// Settings, no signal indoors). Those are the three that are *not* refusals, and
/// until now they died in a `catch` with no sentence and no button — while
/// silently spending the one-shot that gates this very question. So the launch
/// says what to change and, when the cure is a settings trip, offers the trip.
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // **No `catch` here, and the removal is the fix.** An earlier revision of
      // this wrap carried `catch (_) {}`, and `failure_reported_test.dart`
      // refused the commit: the empty-catch census is an *equality* assertion,
      // so a tenth silent catch cannot land. The guard was right and the catch
      // was wrong three times over:
      //   1. **Unreachable.** `detectQuietly` has its own catch-all and
      //      `askAndDetect` has one on each arm, so nothing here can throw.
      //   2. **Silent**, which is the defect the census exists to catch — a
      //      launch-path failure dropped with no record of any kind.
      //   3. It contradicted `CrashReporter`, whose own doc says the opposite:
      //      "Swallowing the error instead is a founder decision, not a
      //      diagnostics one." `main` installs that reporter at boot and its
      //      `PlatformDispatcher.onError` captures any async error from here.
      // So an unexpected throw is *reported* on the way out, which is what
      // `PlaceState._reportStoreFailure` exists to do for its tolerated writes.
      //
      // Quietly first: a launch that already holds the permission must not
      // show a dialog again. Only a phone that was never asked gets the
      // question.
      final ok = await place.detectQuietly();
      if (!mounted) return;
      // **Awaited, which is the whole fix.** This was a bare
      // `place.askAndDetect()` inside a `.then` arm, so the *chain* moved on
      // to the note while the asked detect was still parked on its first
      // `await` — and `askAndDetect` opens with `lastFailure = null`
      // synchronously, before anything can throw. The field the note reads
      // was therefore null on every launch, for every failure it exists to
      // report: three non-refusals that this widget's own doc says are named
      // were silent, with no error anywhere to say so. The cure was not a
      // retry or a different sentence; it was reading the answer after the
      // question was answered.
      if (!ok && !place.asked) await place.askAndDetect();
      // The quiet arm can fail for the same reasons the asked one does, and it
      // reports them through the same field. Read after **both**, so a launch
      // that never needed to ask still says so if it tried and was stopped.
      if (!mounted) return;
      final failure = place.lastFailure;
      if (failure != null) _say(failure);
    });
  }

  /// One sentence, and the cure only where the cure is a settings trip.
  ///
  /// The action stays «الإعدادات» and never «إعادة المحاولة» for the same reason
  /// `DetectLocationButton` keeps it: a retry-shaped button here would re-run a
  /// permission request the phone has already refused to show.
  void _say(LocationFailure failure) {
    if (failure.opensSettings) {
      showNoteWithAction(
        context,
        failure.messageAr,
        actionLabel: 'الإعدادات',
        onAction: Locator.openSettings,
      );
      return;
    }
    showNote(context, failure.messageAr);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
