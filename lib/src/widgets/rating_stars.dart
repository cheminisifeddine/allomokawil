// Single source of truth for the star widget.
//
// It lives in the shared UI kit now (it gained an optional review count and a
// half-star state). This file re-exports it so older imports keep compiling
// and the app can never end up with two conflicting `RatingStars` classes.
export 'ui.dart' show RatingStars;
