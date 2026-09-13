/// The device-side record of failures the app could not recover from.
///
/// Before this file an uncaught exception left nothing behind: the screen froze,
/// or the app jumped back to the landing page, and the user could only say "it
/// closed". A crash that writes a line is a bug we can find from a phone in Bou
/// Saâda without a debugger attached, so the log is deliberately dumb — a
/// bounded list of strings, no SDK, no network, no third-party code.
///
/// Invariants, enforced by `test/crash_reporter_test.dart` and by
/// `tool/crash_log_check.dart` (which runs on the plain Dart VM, so it survives
/// a tick where an orphaned `flutter_tester` makes a test run unsafe):
///  * the list never grows past [CrashLog.limit],
///  * every stored field is length-capped, so one pathological error cannot
///    fill the log,
///  * a corrupt, truncated or unknown-schema line reads back as "no record",
///  * nothing here throws — a crash log that crashes is worse than no log.
library;

import 'dart:convert';

/// One captured failure: when it happened, which hook caught it, the exception's
/// own text, and the top of its stack.
class CrashRecord {
  const CrashRecord({
    required this.at,
    required this.kind,
    required this.message,
    this.detail = '',
  });

  /// When the hook caught it, device-local time.
  final DateTime at;

  /// Which hook caught it: `flutter`, `async`, `startup` or `zone`.
  final String kind;

  /// `error.toString()`, capped. Never the raw object: an object graph cannot be
  /// written to preferences, and its `toString` may itself throw.
  final String message;

  /// The stack, or the call site's own context. Capped as well.
  final String detail;

  static const int maxMessage = 400;
  static const int maxDetail = 900;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toUtc().toIso8601String(),
        'kind': kind,
        'message': message,
        'detail': detail,
      };

  /// Rebuilds a record from decoded storage, or returns null when the value is
  /// not one. Phone storage is not a controlled environment: a truncated write,
  /// a record from an older schema and a hand-edited file all have to read as
  /// absent rather than throw on top of the crash being recorded.
  static CrashRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse(_string(raw['at']));
    final message = _string(raw['message']);
    if (at == null || message.isEmpty) return null;
    final kind = _string(raw['kind']);
    return CrashRecord(
      at: at.toLocal(),
      kind: kind.isEmpty ? 'unknown' : kind,
      message: trim(message, maxMessage),
      detail: trim(_string(raw['detail']), maxDetail),
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  /// Clamps [value] to [max] characters, marking where it was cut.
  static String trim(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max - 1)}…';

  @override
  String toString() => '[$kind] $message';
}

/// A bounded, newest-last list of [CrashRecord]s plus its storage format.
class CrashLog {
  CrashLog({this.limit = 20})
      : assert(limit > 0, 'a crash log with no room in it is not a log');

  /// How many failures are kept. Small on purpose: this is a diagnostic trail
  /// for the next support message, not an analytics store, and the whole list is
  /// rewritten on every crash.
  final int limit;

  final List<CrashRecord> _records = <CrashRecord>[];

  /// A copy, oldest first.
  List<CrashRecord> get records => List<CrashRecord>.unmodifiable(_records);

  int get length => _records.length;
  bool get isEmpty => _records.isEmpty;
  bool get isNotEmpty => _records.isNotEmpty;
  CrashRecord? get latest => _records.isEmpty ? null : _records.last;

  /// Appends [record], dropping the oldest ones once [limit] is reached.
  void add(CrashRecord record) {
    _records.add(record);
    if (_records.length > limit) {
      _records.removeRange(0, _records.length - limit);
    }
  }

  /// What storage holds: one JSON object per line.
  List<String> toLines() =>
      <String>[for (final record in _records) jsonEncode(record.toJson())];

  /// Reads stored lines back and returns how many were understood.
  ///
  /// Junk is dropped one line at a time rather than failing the whole read:
  /// losing a single corrupt line is acceptable, refusing to show the other
  /// nineteen is not. Lines are appended, so this is meant for a log that was
  /// just constructed at boot.
  int loadLines(Iterable<String> lines) {
    var read = 0;
    for (final line in lines) {
      CrashRecord? record;
      try {
        record = CrashRecord.fromJson(jsonDecode(line));
      } catch (_) {
        record = null;
      }
      if (record == null) continue;
      add(record);
      read++;
    }
    return read;
  }

  /// The whole log as one plain-text block, newest last — what a support reply
  /// carries.
  String describe() => _records
      .map((r) => '${r.at.toIso8601String()}\t${r.kind}\t${r.message}')
      .join('\n');

  void clear() => _records.clear();
}
