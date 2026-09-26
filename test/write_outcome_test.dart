// Proves the other half of the unconfirmed-write fix: when the app refuses to
// guess a write's outcome it must still *find out*.
//
// `errWriteUnconfirmed` tells the user to check the list. That instruction was
// a lie in practice — the write screens re-read nothing, so the list the user
// was told to check was the stale one on screen. These tests pin the two pieces
// that make the sentence true: the predicate that recognises the failure, and
// the probe that re-reads the list and reports what the server actually holds.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/l10n/error_copy.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/l10n/write_outcome.dart';
import 'package:allomokawil/src/core/network/api_client.dart';

void main() {
  group('isWriteUnconfirmed', () {
    test('recognises exactly the network layer\'s unconfirmed write', () {
      expect(isWriteUnconfirmed(ApiException(S.errWriteUnconfirmed)), isTrue);
    });

    test('ignores every other failure a write can produce', () {
      // Each of these carries its own sentence, which already tells the user
      // what to do. Refetching for them would spend a request to learn nothing.
      for (final message in [
        S.errOffline,
        S.errTimeout,
        S.errServer,
        S.errValidation,
        S.errUnauthorized,
        S.errConflict,
        S.errUnexpected,
        'رقم الهاتف أو كلمة المرور غير صحيحة',
      ]) {
        expect(isWriteUnconfirmed(ApiException(message)), isFalse,
            reason: '"$message" must not trigger a re-read');
      }
    });

    test('is not fooled by a non-ArabicCopyError or a null', () {
      expect(isWriteUnconfirmed(Exception(S.errWriteUnconfirmed)), isFalse);
      expect(isWriteUnconfirmed(null), isFalse);
      // A status must not change the answer: the message is the contract.
      expect(isWriteUnconfirmed(ApiException(S.errWriteUnconfirmed,
          statusCode: 500)), isTrue);
    });
  });

  group('resolveWriteOutcome', () {
    test('reports landed when the re-read finds the row', () async {
      final outcome = await resolveWriteOutcome(recheck: () async => true);
      expect(outcome, WriteOutcome.landed);
    });

    test('reports missing when the re-read does not find it', () async {
      final outcome = await resolveWriteOutcome(recheck: () async => false);
      expect(outcome, WriteOutcome.missing);
    });

    test('a failed re-read is unknown, never a guess', () async {
      // The critical one. The phone is still offline, so the re-read proves
      // nothing. Reporting `missing` here would tell the user their write
      // failed when it may well have landed — the exact duplicate this rule
      // exists to prevent.
      final outcome = await resolveWriteOutcome(
          recheck: () async => throw ApiException(S.errOffline));
      expect(outcome, WriteOutcome.unknown);
    });

    test('re-reads once and does not retry on its own', () async {
      var calls = 0;
      await resolveWriteOutcome(recheck: () async {
        calls++;
        return true;
      });
      expect(calls, 1);
    });
  });

  group('copy', () {
    test('every outcome is Arabic, actioned, and never Latin', () {
      for (final outcome in WriteOutcome.values) {
        final copy = writeOutcomeCopy(outcome);
        expect(isArabicCopy(copy), isTrue, reason: copy);
        expect(RegExp(r'[A-Za-z]').hasMatch(copy), isFalse, reason: copy);
      }
    });

    test('landed says the write is fine, missing says retry', () {
      expect(writeOutcomeCopy(WriteOutcome.landed), S.writeUnconfirmedLanded);
      expect(writeOutcomeCopy(WriteOutcome.missing), S.writeUnconfirmedMissing);
      expect(writeOutcomeCopy(WriteOutcome.unknown), S.writeUnconfirmedUnknown);
      expect(S.writeUnconfirmedLanded, contains('نجاح'));
      expect(S.writeUnconfirmedMissing, contains('أعد المحاولة'));
      expect(S.writeUnconfirmedUnknown, contains('تحقّق'));
    });

    test('unknown never claims the write failed', () {
      // The dangerous phrasing would be «الطلب لم يصل» on a screen that does
      // not know. It may only say the check itself failed.
      expect(S.writeUnconfirmedUnknown, isNot(contains('لم يصل')));
      expect(S.writeUnconfirmedUnknown, isNot(contains('فشل')));
    });

    test('the re-read line is Arabic too', () {
      expect(isArabicCopy(S.writeUnconfirmedRecheck), isTrue);
      expect(RegExp(r'[A-Za-z]').hasMatch(S.writeUnconfirmedRecheck), isFalse);
    });
  });
}
