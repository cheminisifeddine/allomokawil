# Golden baselines

One PNG per main screen, produced by the `goldens:` test in
`test/design_shots_test.dart` and compared on every `flutter test` run.

They are the difference between "the tick that changed a screen also looked at
it" and "the suite refuses to let a screen silently change": `_shoot` writes
its captures to `/tmp`, which no reviewer ever sees, while these live in the
repository and fail the gate with a pixel-diff report.

## Regenerating

Only on purpose, and only after reading the diff:

```bash
flutter test --update-goldens test/design_shots_test.dart
```

Flutter writes the diff artifacts of a failed run into `test/failures/`
(`*_masterImage.png`, `*_testImage.png`, `*_maskedDiff.png`), which is how you
see *what* moved before deciding whether the new render is correct or a bug.

## Rules

- A golden is only valid for the engine that produced it. A Flutter upgrade
  fails all of them once — read the diffs, then re-baseline. Do not delete the
  test to make the suite green.
- Rendering is deterministic here: `flutter test` runs the same widget tree, the
  same committed Cairo faces (`assets/fonts/`), the same MaterialIcons font and
  the same 392x850 / devicePixelRatio 1.0 canvas every time. If a baseline
  flickers between runs, the screen has an unseeded animation or a time/random
  dependency — fix that, do not re-baseline around it.
- Re-baselining is a commit that names the screens it re-shot and why.
- **Time is injected, never read.** A screen whose pixels contain «قبل ساعة»
  must take the clock it measures against as a parameter (`NotificationsScreen`
  does: `clock:`), because a baseline rendered against `DateTime.now()` is only
  correct for the hour it was captured in. `15_notifications` was not, it
  drifted 171 px at an hour boundary and failed the whole `flutter test` gate 50
  minutes after the baseline was committed. `_pinnedClock` in
  `test/design_shots_test.dart` is that fixed instant, in **UTC** so the
  baseline does not also depend on the box's timezone, and two tests keep it
  that way.
- **The local timezone is part of the environment.** These baselines are
  rendered on this box, in CET. `12_chat` prints the clock of each message
  through `chatClock`, which is local `HH:mm` on purpose (a user reads his own
  wall clock), so running the suite under another `TZ` diffs two clock labels —
  measured `TZ=Pacific/Kiritimati` -> 125 px in two small bands, and
  `TZ=Pacific/Midway` the same. That is not a layout bug and re-baselining is
  not the fix: either run in CET or give the thread an injectable formatter.
  `15_notifications` is already immune; it passes under both of those zones.
- These files are original renders of this app. No third-party screenshot or
  brand asset is ever added here.
