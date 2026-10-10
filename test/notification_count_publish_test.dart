// The bell must be able to ANSWER its own question from the centre's read.
//
// The notification centre now reads `GET /api/unread` for itself -- the
// shortfall band and «تعليم الكل كمقروء» both need the server's count, and a
// list the server has already capped cannot supply it. The bell reads the same
// endpoint on every resume, so without a way to hand the number over, every
// visit to the centre spent **two** reads of one question on a 2-core box with
// no swap.
//
// `NotificationCountTrust.publish` is that hand-off, and it is the only thing
// standing between the fix for the capped list and a doubled round-trip. It was
// added with zero tests, which is exactly the gap this file closes: the two
// guards in `unread_round_trip_test.dart` hold every `/api/unread` open behind
// a gate, so the centre never publishes in those fixtures and **a mutation that
// made the bell trust a stale published number survived them both**. Measured,
// not assumed -- see the mutation note at the bottom.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/notification_count_trust.dart';

void main() {
  group('the count the centre publishes', () {
    test('is null before anything has been read', () {
      // Null is not zero. A cold app has no server number at all, and the bell
      // must therefore go to the network -- treating this as 0 would paint an
      // empty pip on first launch and never ask.
      final trust = NotificationCountTrust();
      expect(trust.confirmedCount, isNull);
      expect(trust.unconfirmed, isFalse);
    });

    test('is the number the read returned', () {
      final trust = NotificationCountTrust()..publish(140);
      expect(trust.confirmedCount, 140);
      expect(trust.unconfirmed, isFalse);
    });

    // The direction that matters: a withdrawn flag must come back when a real
    // read lands, because that read is the only evidence that can restore it.
    test('publishing restores a withdrawn flag', () {
      final trust = NotificationCountTrust()..withdraw();
      expect(trust.unconfirmed, isTrue);
      trust.publish(3);
      expect(trust.unconfirmed, isFalse,
          reason: 'the server answered; the count is its number again');
      expect(trust.confirmedCount, 3);
    });

    // A published number is evidence, not a mood. Withdrawing is about
    // confidence in what is PAINTED; it must not erase what the server last
    // said, or a header resuming one moment later would have nothing to show
    // and would have to guess or re-ask.
    test('withdrawing keeps the published number on record', () {
      final trust = NotificationCountTrust()..publish(7);
      trust.withdraw();
      expect(trust.unconfirmed, isTrue);
      expect(trust.confirmedCount, 7,
          reason: 'a withdrawal says "do not trust this", not "forget it"');
    });

    // The listener is what turns the publish into a repaint, so a publish that
    // changed nothing must stay quiet and a publish that moved must not.
    test('publishing the same number twice notifies once', () {
      var fired = 0;
      final trust = NotificationCountTrust()..addListener(() => fired++);
      trust.publish(5);
      expect(fired, 1);
      trust.publish(5);
      expect(fired, 1,
          reason: 'a bell already holding 5 must not be woken for 5');
      trust.publish(6);
      expect(fired, 2, reason: 'a moved count is news');
    });

    // The two signals must not be conflated into one notification storm.
    test('a publish on a withdrawn flag fires exactly once', () {
      var fired = 0;
      final trust = NotificationCountTrust()..withdraw();
      trust.addListener(() => fired++);
      trust.publish(2);
      expect(fired, 1,
          reason: 'restoring confidence and moving the number are one event '
              'here, not two');
      expect(trust.confirmedCount, 2);
      expect(trust.unconfirmed, isFalse);
    });
  });

  // The mutation this file exists for, recorded because a guard that cannot be
  // seen failing is a decoration. Making `_refresh` in `notifications_bell.dart`
  // accept a published count on a FORCED read (dropping `!force &&`) kept
  // `unread_round_trip_test.dart` **fully green** across both of its cases:
  // every `/api/unread` in that fixture is held open behind a gate, so the
  // centre never publishes, the published value is null, and the mutation has
  // nothing to act on. Those two cases pin the pop-back; they cannot see this
  // path, and the gap between them is why `confirmedCount` is pinned above
  // rather than being left to be read by a fixture that happens not to use it.
}
