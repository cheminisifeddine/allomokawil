/// The half of a failed write that the app can still answer.
///
/// [S.errWriteUnconfirmed] tells the user to check the list before retrying —
/// but a screen that keeps its stale list is asking him to check something that
/// is not there. This file is what turns that instruction into something the
/// screen can do: one typed predicate, and one probe that re-reads the list and
/// reports whether the row actually landed.
///
/// The rule is deliberately narrow. Only the network layer's own
/// *unconfirmed-write* failure qualifies: the request left the phone, no answer
/// arrived in time, and the app refused to guess. Every other failure — a 4xx,
/// a validation error, an outright dead network — is answered by its own
/// sentence, and refetching for those would spend a request to learn something
/// the message already said.
library;

import 'error_copy.dart';
import 'strings.dart';

/// True when [error] is the network layer refusing to guess a write's outcome.
///
/// Checks the message rather than the exception type on purpose: `ApiException`
/// is thrown for every status the API can return, and the day a new failure
/// wants this same treatment a type would mean editing five screens. The string
/// is the contract, and [S.errWriteUnconfirmed] is a `const`, so this stays a
/// pointer comparison at runtime.
bool isWriteUnconfirmed(Object? error) =>
    error is ArabicCopyError && error.message == S.errWriteUnconfirmed;

/// What re-reading the list proved about a write whose answer never came.
enum WriteOutcome {
  /// The row is on the server. The write landed; showing it is the whole point.
  landed,

  /// The list came back without it. The write did not reach the server and the
  /// user may safely retry.
  missing,

  /// The re-read itself failed — the phone is still offline. This is NOT proof
  /// the write failed, and the copy must never say so.
  unknown,
}

/// Runs [recheck] — a fresh read of the list the failed write belonged to — and
/// classifies the answer.
///
/// [recheck] is a bare read (`myProjects()`, `projectQuotes(id)`, …) that returns
/// whether the row is in the fresh result. It must never throw: a second network
/// failure while we are already reporting one would replace the honest
/// «outcome unknown» with a stack trace, so a throw is caught and read as
/// [WriteOutcome.unknown].
///
/// The [isMine] hook is not needed by the callers that pass a fresh list, but it
/// keeps the probe honest for the cases where identity is more than an id: a
/// published project is recognised by its id when the server returns one, and by
/// its title otherwise, because a project created in this session has no id yet.
Future<WriteOutcome> resolveWriteOutcome({
  required Future<bool> Function() recheck,
}) async {
  try {
    return await recheck() ? WriteOutcome.landed : WriteOutcome.missing;
  } catch (_) {
    return WriteOutcome.unknown;
  }
}

/// The sentence for [outcome] — the answer to the question
/// [S.errWriteUnconfirmed] leaves open.
///
/// [S.writeUnconfirmedUnknown] is intentionally not a "try again": the app does
/// not know, and saying so is the only honest line. It is also the only outcome
/// whose copy `test/error_copy_test.dart` is allowed to let through without an
/// action verb, because there is no action that is true right now.
String writeOutcomeCopy(WriteOutcome outcome) => switch (outcome) {
      WriteOutcome.landed => S.writeUnconfirmedLanded,
      WriteOutcome.missing => S.writeUnconfirmedMissing,
      WriteOutcome.unknown => S.writeUnconfirmedUnknown,
    };
