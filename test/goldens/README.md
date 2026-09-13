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

Flutter writes the diff artifacts of a failed run into
`test/goldens/failures/` (`*_masterImage.png`, `*_testImage.png`,
`*_maskedDiff.png`), which is how you see *what* moved before deciding whether
the new render is correct or a bug.

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
- These files are original renders of this app. No third-party screenshot or
  brand asset is ever added here.
