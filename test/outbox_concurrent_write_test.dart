// Two messages written at the same time must both survive the queue.
//
// Every mutator on ChatOutbox is a read-modify-write against one
// `SharedPreferences` key: read the whole JSON string, change it in memory,
// write it back. Nothing serialises them, so two overlapping mutations both
// read the same old blob, each adds its own row, and each writes back a queue
// holding only its own record — the other's message is gone from the device
// the instant the slower write lands.
//
// The write is the slowest thing on the send path by design: the last two
// cycles moved it to be the *first* thing a send does, so that Android cannot
// kill a draft. Making the queue durable put a wide read-modify-write window
// in front of every single send, which is what made this reachable in normal
// use rather than only in theory.
//
// The app creates two of these objects and hands both to a live screen:
// `AuthState` owns one and `ChatListScreen` builds another for the badges
// (chat_list_screen.dart:64), and `ChatScreen` shares whichever it is given
// (chat_screen.dart:118). Two threads open, or the inbox reads a badge while a
// send is being written, and the two objects write the same key with no
// shared lock. `_forgetQuietly` makes the overlap certain even on one object:
// it fires `remove` without awaiting it, from inside a `setState` callback.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/chat_outbox.dart';

/// Parks every write until the test says so, so two mutations can provably
/// overlap: each has read the blob and neither has written it back yet.
///
/// A store that only gated one write would hide the defect behind ordering —
/// which is the trap that a "second send is written first" store walks into
/// (see `_FirstWriteGatedStore` in chat_send_keeps_the_draft_test.dart). Here
/// *both* writes wait, so the lost record is a fact and not a schedule.
class _BarrierStore implements OutboxStore {
  final gate = Completer<void>();
  Object? raw;
  int writes = 0;

  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async {
    writes++;
    await gate.future;
    raw = value;
  }
}

void main() {
  test('two messages written at once both survive the queue', () async {
    final store = _BarrierStore();
    final outbox = ChatOutbox(store: store);

    // Both start on an empty queue, as two sends in the same instant would.
    final first = outbox.add(conversationId: 5, text: 'العنوان: حسين داي');
    final second = outbox.add(conversationId: 5, text: 'المقاول يصل غدا');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    store.gate.complete();
    final a = await first;
    final b = await second;

    // What the next cold start actually reads off the disk.
    final onDisk = decodeOutbox(store.raw);

    expect(onDisk.map((m) => m.text).toList(),
        <String>['العنوان: حسين داي', 'المقاول يصل غدا'],
        reason: 'a message the phone accepted must be on the disk, or the '
            'user sends an address and the app has forgotten it before the '
            'server ever hears about it');
    expect(onDisk.map((m) => m.id).toSet(), <String>{a.id, b.id},
        reason: 'the record the app returned to the bubble is the record that '
            'has to be in the queue — a record that exists only in memory '
            'protects nothing');
  });
}
