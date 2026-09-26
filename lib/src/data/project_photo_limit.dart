// How many photos one project may carry, in one place.
//
// Found on 26 Sep 2026 while auditing the attach-strip count that shipped the
// previous cycle. The count was right; the **cap behind it was not**, and the two
// together mean the app cannot make a claim about a total.
//
// The strip had two independent limits that were both wrong:
//
//   * `pickMultiImage(limit: 6)` — a limit on **one selection**, not on the
//     running total. A client who picked 5 and then tapped add again and picked
//     6 ended up with 11 photos;
//   * the add tile was drawn while `images.length < 6` — a test of the *new*
//     picks only, so on the **edit** path it never looked at the photos the
//     project already had.
//
// Together those two meant a project with six existing photos still showed
// «أضف صورة» to a client editing it, and he could push it to twelve and post it.
// There was no ceiling on the total at all, only on how many he could grab in
// one go. The line under the strip counts the new picks, so at eleven total the
// screen showed «6 صور مضافة» and a project card that carried more photos than
// the strip was ever able to describe.
//
// The cap is a real constraint — `POST /api/projects` stores the array with no
// ceiling of its own, and every screen that renders them builds one `PageView`
// child per URL — so a cap belongs here rather than in a `< 6` inside a build
// method, where a fourth call site would be free to disagree with it.
//
// **Ten is the number, and it is the number the copy already assumed.** The
// 11+ arm in `project_photo_count_copy.dart` documented the total as "at most
// ten"; this file is what makes that true, so the count and the cap can no
// longer tell different stories.
library;

/// How many photos one project may carry, kept and newly picked together.
const int kMaxProjectPhotos = 10;

/// How many more photos a project can take: `kept` already on the project,
/// `picked` chosen in this session.
///
/// Clamped at zero, because the caller uses it in two ways that both need a
/// floor: the add tile hides on a non-positive room, and the picker is handed a
/// limit — and `limit: 0` is not "pick nothing", it is "no limit" to
/// `image_picker`, which is the opposite of what a full project wants.
int projectPhotoRoom(int kept, int picked) {
  final room = kMaxProjectPhotos - kept - picked;
  return room < 0 ? 0 : room;
}
