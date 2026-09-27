// The store contract of the duplicate-prevention mark.
//
// Split from `chat_mark_not_saved_test.dart` for one reason, and it is the
// reason the whole file used to be worth nothing: **these tests name
// `markUncertain`'s return value, so they cannot compile against the source
// they are written for.** Run against the unfixed file, the *whole* test file
// dies at load with «This expression has type void and can't be used», the
// widget tests never run, and the output looks like a red test while proving
// nothing. That is the same mistake as last tick's, in a new costume.
//
// So the widget tests — which assert on the sentences on screen and use no new
// API at all — are the behavioural proof, and they run against both versions.
// This file is the unit contract on top, and it is red on the fixed source
// only if the return value is wrong.
//
// What the bool is for, restated once so the two files agree: a record the
// server refused is re-sent on the next thread open, and a record marked
// `unconfirmed` is not. That mark is one stored word, it is the app's only
// defence against a duplicate, and both of its writes were previously silent
// about failing.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/models/chat.dart';

const _typed = 'العنوان: حسين داي، الطابق الثالث';

/// Takes every write. The control: a store that never refuses must never be
/// reported as refusing.
class _AcceptAll implements OutboxStore {
  String? raw;
  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async => raw = value;
}

/// Refuses every write, the way a full disk does, and leaves whatever was
/// already on the disk exactly as it was.
class _DeclineAll implements OutboxStore {
  _DeclineAll(this._backing);

  final OutboxStore _backing;

  @override
  Future<Object?> read() => _backing.read();

  @override
  Future<void> write(String raw) async =>
      throw StateError('preferences refused to store the queue');
}

void main() {
  group('the mark that stops a duplicate reaching the disk', () {
    test('a store that takes every write answers true, and never refuses',
      () async {
    // The control. Every widget test below runs on a store that refuses; if
    // the screen also printed the warning here, the warning would be measuring
    // nothing but the test's own setup.
    final store = _AcceptAll();
    final outbox = ChatOutbox(store: store);
    final record = await outbox.add(conversationId: 5, text: _typed);
    expect(await outbox.markUncertain(record.id,
        uncertain: SendState.unconfirmed), isTrue);
    expect(decodeOutbox(store.raw).single.uncertain, SendState.unconfirmed,
        reason: 'nothing was refused, so the mark must be on the disk');
  });

  test('a store that accepts it answers true, and the record is marked',
        () async {
      // The healthy case first, so a later "false" is not the default value
      // leaking through. This is the discipline the enqueue fix needed and the
      // one that catches a `markUncertain` that always answers false.
      final store = MemoryOutboxStore();
      final outbox = ChatOutbox(store: store);
      final record = await outbox.add(conversationId: 5, text: _typed);

      expect(await outbox.markUncertain(record.id,
          uncertain: SendState.unconfirmed), isTrue,
          reason: 'a mark that reached the disk must be reported as such');
      final back = await ChatOutbox(store: store).pendingFor(5);
      expect(back.single.uncertain, SendState.unconfirmed);
    });

    test('a store that refuses it answers false, and the record is unmarked',
        () async {
      // The defect, at the level it is caused. A false that is thrown away is
      // the bug; the caller cannot act on what it was never told.
      final backing = MemoryOutboxStore();
      final outbox = ChatOutbox(store: _DeclineAll(backing));
      final healthy = ChatOutbox(store: backing);
      final record = await healthy.add(conversationId: 5, text: _typed);

      expect(
          await outbox.markUncertain(record.id,
              uncertain: SendState.unconfirmed),
          isFalse,
          reason: 'the mark did not reach the disk, and that is the one fact '
              'that decides whether the next cold start re-sends a message the '
              'server may already hold');

      // And the disk genuinely still says «safe to send». Without this the
      // false could be a lie in the *safe* direction, and the duplicate would
      // be prevented by accident.
      final back = await ChatOutbox(store: backing).pendingFor(5);
      expect(back.single.uncertain, isNull,
          reason: 'the refusal must leave the old queue in place, which is '
              'exactly why the mark matters');
    });

    test('a refused clear is reported too, not only a refused mark', () async {
      // The other direction, and the more easily forgotten one: the record was
      // marked earlier, a re-read proved the words are absent, and clearing the
      // mark is what makes the message retryable again. Silently failing it
      // strands the message on the phone with no way to send it.
      final backing = MemoryOutboxStore();
      final healthy = ChatOutbox(store: backing);
      final record = await healthy.add(
          conversationId: 5, text: _typed, uncertain: SendState.unconfirmed);
      final declining = ChatOutbox(store: _DeclineAll(backing));

      expect(await declining.markUncertain(record.id, uncertain: null), isFalse,
          reason: 'the record is still marked on the disk, so it will come '
              'back after a restart with no retry affordance');
      final back = await ChatOutbox(store: backing).pendingFor(5);
      expect(back.single.uncertain, SendState.unconfirmed);
    });

    test('an id the queue does not hold is not an error and costs no write',
        () async {
      // Both early returns report true, deliberately: a record that is not on
      // the disk cannot be read back and re-sent, so the invariant already
      // holds without a write, and there is nothing to warn the user about.
      final store = MemoryOutboxStore();
      final outbox = ChatOutbox(store: store);
      expect(await outbox.markUncertain('5.0.0',
          uncertain: SendState.unconfirmed), isTrue);

      // Already the requested state: same answer, same reason, and the store
      // is never asked to write — which is what keeps this true on a device
      // that declines everything.
      final record =
          await outbox.add(conversationId: 5, text: _typed, uncertain: SendState.unconfirmed);
      final declining = ChatOutbox(store: _DeclineAll(store));
      expect(
          await declining.markUncertain(record.id,
              uncertain: SendState.unconfirmed),
          isTrue,
          reason: 'the disk already holds the mark being asked for, so a '
              'device that refuses writes changes nothing here');
    });
  });
}
