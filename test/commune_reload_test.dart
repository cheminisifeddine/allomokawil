import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/communes.dart';

/// A load that failed must not be remembered as if it had succeeded.
///
/// `load()` is `_loading ??= _parse()`, so the cached future is the *attempt*,
/// not the *dataset*. A parse that throws leaves the failed future in the
/// field, and every later call re-awaits the same already-rejected future:
/// the app never tries again for the rest of the process, even after the
/// asset becomes readable. The commune picker opens empty, permanently, and
/// the user is told the commune is required for a wilaya the app has all
/// 1,541 communes for.
///
/// Only [resetForTest] clears it, and only tests call that — so in production
/// the failure is unrecoverable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'assets/data/communes_dz.json';

  const good =
      '{"wilayas":{"1":{"ar":"أدرار"}},"communes":{"1":[["أدرار","ADRAR"],'
      '["أZeneca","AZOUA"],["رقان","REGGANE"]]}}';

  /// Serves [body] for the dataset asset, counting every read of it.
  void serve(String? body, List<int> reads) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      if (message == null) return null;
      if (utf8.decode(message.buffer.asUint8List()) != key) return null;
      reads.add(1);
      if (body == null) throw Exception('asset missing');
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(body)));
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null));
  }

  test('a failed load is forgotten, so a later load can still succeed', () async {
    final index = CommuneIndex.instance..resetForTest();
    final reads = <int>[];

    // First attempt: the asset is unreadable (a corrupt build, a half-written
    // asset, a decode failure). The caller sees the real error.
    serve(null, reads);
    await expectLater(index.load(), throwsA(anything));
    expect(index.isLoaded, isFalse);

    // Second attempt, with the asset readable: must parse, not rethrow the
    // first failure forever.
    serve(good, reads);
    await index.load();
    expect(index.isLoaded, isTrue,
        reason: 'a retry after a failed load must work');
    expect(index.total, 3);
    expect(reads.length, 2, reason: 'the retry must actually re-read the asset');
  });

  test('a decode failure is as recoverable as a missing asset', () async {
    final index = CommuneIndex.instance..resetForTest();
    final reads = <int>[];

    serve('this is not json', reads);
    await expectLater(index.load(), throwsA(anything));
    expect(index.isLoaded, isFalse);

    serve(good, reads);
    await index.load();
    expect(index.total, 3);
  });

  test('concurrent callers share one load, not one load each', () async {
    final index = CommuneIndex.instance..resetForTest();
    final reads = <int>[];

    // **The asset read cannot prove this** — `rootBundle` dedupes concurrent
    // reads by itself, so a `load()` that dropped the in-flight future would
    // still read the file once and this assertion would still pass. The proof
    // has to be the *error*: callers that share an attempt see the identical
    // failure object, and callers that each parse their own see a different
    // one. A decode failure is used rather than a missing asset precisely
    // because the string is cached and the throw happens in this class, which
    // is where the sharing decision lives.
    serve('not json', reads);

    Future<Object?> attempt() async {
      try {
        await index.load();
        return null;
      } catch (error) {
        return error;
      }
    }

    final errors =
        await Future.wait<Object?>([attempt(), attempt(), attempt()]);
    for (final error in errors) {
      expect(error, isNotNull, reason: 'a bad asset must still raise');
    }
    expect(identical(errors[0], errors[1]), isTrue,
        reason: 'two callers must observe the same attempt, not two');
    expect(identical(errors[1], errors[2]), isTrue);
  });
}
