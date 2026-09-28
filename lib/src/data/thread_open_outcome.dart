// Answering «did my conversation open» when the server never said.
//
// Found 28 Sep 2026 by the audit the last two ticks ended on. The backlog
// recorded `openConversation` as "a write with no resolved unconfirmed path",
// which is true and is also the least interesting thing about it.
//
// The write it is answering is `POST /api/mobile/conversations` — a
// **get-or-create**: the same (customer, worker, project) triple resolves to
// the same row, so it is not a row-creating write the way a project or a quote
// is. It is the one write in this app whose *failure* is the interesting half,
// because `_ChatScreenState._bootstrap` does this with it:
//
//     var convId = widget.conversationId;
//     convId ??= await widget.repo.openConversation(...);
//     _convId = convId;
//     await _load();
//     } catch (_) { refused = true; }        // <-- the whole catch
//
// Every failure of that POST is folded into `refused = true`, which is
// [ChatScreen]'s **read** error: the page then says «تعذّر جلب الرسائل» and
// offers «إعادة المحاولة» wired to `_bootstrap` — which runs the POST again.
// So the thread that failed to *open* is announced as a thread that failed to
// *load*, and the only button on the page re-issues the write. Nothing in the
// app ever distinguishes «the request left this phone and nobody answered» from
// «the server said no», and the one thing this app is built not to do — guess
// about a write — is what this screen does by construction.
//
// Two defects, and they are different in kind:
//
//  * **the sentence is about the wrong call.** [S.errWriteUnconfirmed] is the
//    network layer refusing to guess. Printing a *read* failure for a write
//    the app itself flagged as ambiguous is the copy version of the same
//    mistake, and it tells the user to fix his Wi-Fi over a request that had
//    already left the device.
//
//  * **the retry is a duplicate creator.** Whether re-POSTing can create a
//    second row depends on a server contract this client cannot see
//    (README calls the route "list / open conversation"; the repository comment
//    says "Get or create"). If it is get-or-create, the second POST is
//    harmless. If it is a plain insert guarded by a unique index, the retry on
//    the page that exists *only* to explain the failure is what creates the
//    duplicate thread — and the user is the one pressing it.
//
// The rule here is the same one every other file in this family lands on, and
// for the same reason: **the app must not guess about a write.** What the
// answer *is* depends on the answer the server gives, and the app cannot
// manufacture it. So this file does not ask "did the conversation get created?"
// — it asks the only question a phone can answer, which is "does a thread for
// these people and this project already exist?", and it deliberately reports
// the three cases separately rather than collapsing the one that is safe to
// retry into the same word as the one that is not.
//
// **The two retryable cases are separated, and that is the whole point.** A
// `missing` thread (the server answered, and there is no such conversation) and
// an `unknown` one (the re-read itself could not run — the phone is still
// offline) both end in «تحقّق من القائمة», and both point at the inbox rather
// than at this page's own retry button. Re-POSTing on a screen that has already
// declared it cannot read the server is how a get-or-create turns into a second
// thread; the inbox is a **GET**, it answers with the truth if the answer
// exists, and it costs one request instead of one request plus a possible
// duplicate.
library;

import '../core/l10n/strings.dart';
import '../core/l10n/write_outcome.dart';
import '../models/chat.dart';

/// What the re-read of the inbox proved about a thread that would not open.
enum ThreadOpenOutcome {
  /// The inbox holds a thread for this (customer, worker, project) triple. The
  /// write landed — or a row already existed and the open call was a no-op —
  /// and either way the user is already in the right conversation.
  landed,

  /// The inbox came back without it. The server answered and there is no such
  /// conversation, so the write really did not land.
  missing,

  /// The re-read failed. The phone cannot read the server at all, which proves
  /// nothing about a write that may already be on it.
  unknown,
}

/// True when [row] is the thread [otherUserId] and [projectId] would open.
///
/// [me] is this account's user id. The inbox is a **GET** of the signed-in
/// user's own conversations, so identity is available without a second
/// request — and without it the predicate would match *any* thread with a
/// matching id, which is a stranger's conversation in an inbox the app is not
/// rendering.
///
/// The peer test is symmetric on purpose: `customer_id` and `worker_user_id`
/// name the two sides, and which one is "me" depends on which role this
/// account holds. Comparing only one of them is the bug a role-only lookup
/// invites — a contractor's own list row has him in `worker_user_id`.
///
/// A `null` [projectId] is a thread with no project behind it, and the server
/// stores exactly that as a NULL `project_id`. It is compared as strings so a
/// D1 value that came back as a number and a Dart `String?` still match; the
/// model does the same conversion on the way in.
bool inboxHoldsThread({
  required List<Conversation> inbox,
  required int me,
  required int otherUserId,
  String? projectId,
}) =>
    inbox.any((c) =>
        c.id != 0 &&
        (c.customerId == me && c.workerUserId == otherUserId ||
            c.customerId == otherUserId && c.workerUserId == me) &&
        (c.projectId ?? '') == (projectId ?? ''));

/// Runs the honest re-read for a thread that would not open, and classifies it.
///
/// Same contract as every other write in the app: it must not throw, and a
/// second network failure while one is already being reported is
/// [ThreadOpenOutcome.unknown] — never `missing`, because «did not open» is
/// what makes a user press the button that opens it again.
Future<ThreadOpenOutcome> resolveThreadOpenOutcome({
  required Future<List<Conversation>> Function() inbox,
  required int me,
  required int otherUserId,
  String? projectId,
}) async {
  List<Conversation> rows;
  try {
    rows = await inbox();
  } catch (_) {
    return ThreadOpenOutcome.unknown;
  }
  return inboxHoldsThread(
          inbox: rows, me: me, otherUserId: otherUserId, projectId: projectId)
      ? ThreadOpenOutcome.landed
      : ThreadOpenOutcome.missing;
}

/// The sentence for a thread the app re-read the inbox to find out about.
///
/// Its own copy, and not [writeOutcomeCopy], for the same reason
/// `dossierOutcomeCopy` is: the shared line is a claim about *finding a row*
/// — «وجدناه في القائمة» — and the user's question is not «is there a row» but
/// «can I talk to this person».
///
/// **No outcome here offers a retry on this page.** That is the design, not an
/// omission: the button wired to this screen's failure state re-runs the POST,
/// and «أعد المحاولة» next to that button is an instruction to create a second
/// conversation. The inbox is a GET, it is always true that it can be opened,
/// and it is where a thread that really exists will be if the open call landed.
/// So all three sentences send him there.
String threadOpenOutcomeCopy(ThreadOpenOutcome outcome) => switch (outcome) {
      ThreadOpenOutcome.landed => S.threadUnconfirmedLanded,
      ThreadOpenOutcome.missing => S.threadUnconfirmedMissing,
      // Its own string, and not `writeOutcomeCopy(WriteOutcome.unknown)`. The
      // shared line ends in «قبل إعادة المحاولة», and on this page a retry is
      // the POST — so reusing it would make the app instruct the user to
      // re-issue the write in the one case where it has just proved the server
      // is unreachable. `test/thread_open_outcome_test.dart` pins that no
      // outcome carries S.retry.
      ThreadOpenOutcome.unknown => S.threadUnconfirmedUnknown,
    };
