import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every key the live API sends is accounted for at one of two layers.
///
/// **Why this file exists.** Between `quote_limit` on 12 Sep and `wilaya_span`
/// on 26 Sep, nine defects were one bug in different clothes: the Worker
/// published a fact, the parser kept it, and no screen printed it.
/// `quote_limit`, `portfolio_limit`, `search_boost`, `wilaya_span`,
/// `auto_renew`, `renew_note_ar`, `worker_avatar_url`,
/// `worker_verification_status`, `amount_paid`. Every one was found by somebody
/// remembering to grep, because nothing else in the repo can see a dead field:
/// the code compiles, the tests pass, the row renders. Reading a model never
/// suggests a field is unused.
///
/// So the sweep runs on every `flutter test` instead, in two layers, because
/// the defects come in two shapes:
///
///  * **never read** — no file in `lib/` subscripts the key, so the field does
///    not exist on this side of the wire. [deliberatelyUnread].
///  * **read, but reaches no screen** — the key lands in a model, and no
///    file reachable from a screen or a widget ever names the field. This is
///    the `wilaya_span` shape and it is the one that reaches a customer.
///    [renderedNowhere].
///
/// The two allow-lists are the real content. A key the app does not need
/// belongs in one *with its reason* — never simply absent, because absent and
/// not-yet-checked look identical. Adding a name is a decision a human makes;
/// no test can make it, and nothing in the suite will make it for you.
///
/// **What layer 2 does not claim.** "Reachable from a screen" is the import
/// closure, so a helper counts: `priceMonth` is read in `plan_renewal_copy`
/// and printed on the subscription screen, and layer 2 calls it live. What it
/// cannot see is a field consumed by a getter on the model itself —
/// `autoRenew` is read by `BillingCatalogue.isPrepaid` in its own file, and
/// layer 2 calls that invisible. It is a lower bound, deliberately: it only
/// ever claims "reaches no screen", never "reaches one".
void main() {
  // ── Layer 1: no file in lib/ subscripts these at all ──────────────────
  // Each line is a promise that the absence is understood, not that it is fine.
  const Set<String> deliberatelyUnread = {
    // The server's own audit column. The app never shows "last edited", and
    // printing a project's edit time would invite a question the app cannot
    // answer — who edited it, and what changed. Kept server-side.
    'updated_at',
    // The billing tier, on a *public* worker row. Only the owner needs to
    // know it, and he reads it on the subscription screen from
    // `/api/mobile/subscription`. Putting it on the card a customer browses
    // would be a privacy leak for a number nobody is comparing.
    'subscription_plan',
    // Map coordinates. Every live project and every live worker sends null.
    // The app has no map and no distance sort and never had one, so a
    // coordinate with no surface is a column reserved for a map that does not
    // exist yet — not data the app is losing.
    'latitude',
    'longitude',
    // The prepaid term catalogue: four `durations` per plan (1/3/6/12 months)
    // with a discounted `amount` and `per_month`. A genuine gap, not an unused
    // key — the app cannot *order* a 3-month term, because filing one as a
    // 3-month term needs Worker source that is not on this host. Parked on
    // purpose; see IMPROVEMENT_BACKLOG. The name leaves this list the same tick
    // the Worker can be shown to STORE those terms rather than a month.
    //
    // **Corrected 27 Sep, against the live Worker.** This note used to read
    // «the Worker rejects any `period` it does not know», and that was wrong in
    // the way that matters: a rejection would be safe, and a silent accept is
    // not. Probing `POST /api/mobile/subscription` on a fresh account per
    // spelling, reading the STORED row back (not the ack):
    //   `3month` -> ack `period: "month", months: 1`  | STORED `period: "month"`
    //   `6month` -> ack `period: "month", months: 1`  | STORED `period: "month"`
    //   `quarter`-> ack `period: "month", months: 1`  | STORED `period: "month"`
    //   `month`  -> ack `period: "month", months: 1`  | STORED `period: "month"`
    //   `year`   -> ack `period: "year",  months: 12` | STORED `period: "year"`
    // Every answer was `ok: true`. So the Worker does not reject an unknown
    // term, it **accepts the order and files it as a month** — which is why the
    // app must not offer the 3/6-month terms it can see priced, and why the
    // card prints the term the server actually stored rather than the one that
    // was asked for.
    'durations',
    // `"payment_style": "prepaid"`. Redundant with `auto_renew: false` on the
    // same payload, which the app *does* read and print: `isPrepaid` is
    // `autoRenew == false`, shown beside the founder's own `renew_note_ar`.
    // Reading both would mean two flags that can disagree, on a screen that
    // has to pick one anyway.
    'payment_style',
  };

  // ── Layer 2: parsed into a model, named on no screen ──────────────────
  // `lib/` reads these, so layer 1 cannot see them. Each is a decision.
  const Map<String, String> renderedNowhere = {
    'nameFr':
        // `"name_fr": "Basique"` lands in Plan.nameFr and is printed by
        // nothing — three lines in the model and no reference outside them.
        // The app declares `supportedLocales: [ar, en]` and pins `locale: ar`,
        // so there is no French locale for a French name to appear in.
        // Printing one under an Arabic one with no way to choose the language
        // is the same dead field as wilaya_span a cycle earlier. The real fix
        // is an actual French locale: a product decision, not a field.
        'the app pins locale ar and has no French locale for a French name '
            'to appear in',
    'searchBoost':
        // A ranking weight the Worker applies when it sorts. The payload never
        // says how results rank, and every Arabic phrase for it («أولوية في
        // الظهور») promises a position the client cannot see or verify. It
        // belongs in the server's `features` strings, which reach every
        // install in an UPDATE with no release — and [wilayaSpan] above is the
        // proof that a hand-written promise next to a wrong number is worse
        // than no promise: gold's own feature said «ولايتك» while the server
        // priced it at three.
        'a rank weight with no visible rank to attach it to',
  };

  // Every key the live payloads carry, captured 27 Sep 2026 from
  // https://allomokawil.com — a live fetch, not a hand-written fixture, which
  // is how a stale field survives a rename on the Worker.
  const Map<String, List<String>> liveKeys = {
    '/api/mobile/workers/top': [
      'id', 'user_id', 'bio', 'specialties', 'experience_years',
      'price_range_min', 'price_range_max', 'service_radius_km',
      'is_available', 'is_identity_verified', 'is_certificate_verified',
      'verification_status', 'subscription_plan', 'avg_rating',
      'total_reviews', 'total_completed_jobs', 'response_time_hours',
      'cover_image_url', 'created_at', 'updated_at', 'full_name', 'phone',
      'user_wilaya', 'commune', 'avatar_url', 'search_boost', 'wilaya_name',
    ],
    '/api/mobile/projects': [
      'id', 'customer_id', 'title', 'description', 'category', 'images',
      'wilaya', 'commune', 'latitude', 'longitude', 'budget_min',
      'budget_max', 'urgency', 'status', 'selected_worker_id', 'created_at',
      'updated_at', 'categories', 'wilaya_name',
    ],
    '/api/mobile/plans': [
      'currency', 'commission_percent', 'commission_per_order', 'note_ar',
      'payment_style', 'auto_renew', 'renew_note_ar', 'plans',
    ],
  };

  // The plan rows one level down, where the money is.
  const List<String> planKeys = [
    'id', 'name_ar', 'name_fr', 'tagline_ar', 'price_month', 'price_year',
    'quote_limit', 'portfolio_limit', 'search_boost', 'wilaya_span',
    'features', 'durations',
  ];

  /// `wilaya_span` is named in the note for `searchBoost`; this is the
  /// reference that keeps the file honest if the field is ever renamed.
  const List<String> referencedInNotes = ['wilaya_span', 'search_boost'];

  final Set<String> everyKey = {
    ...liveKeys.values.expand((List<String> k) => k),
    ...planKeys,
  };

  group('layer 1 — keys no parser reads', () {
    test('every key the live API sends is read, or allowed on purpose', () {
      final Set<String> read = _keysIn(_lib());
      final List<String> unaccounted = everyKey
          .where(
              (String k) => !read.contains(k) && !deliberatelyUnread.contains(k))
          .toList();

      expect(
        unaccounted,
        isEmpty,
        reason: 'the Worker sends these and no screen reads them. Use the '
            'field, or — if the app genuinely does not need it — add it to '
            '`deliberatelyUnread` in this file with the reason:\n'
            '${unaccounted.join('\n')}',
      );
    });

    test('an allowed key is one nothing reads', () {
      // Otherwise a name sits in the list "just in case" and the list stops
      // being evidence of anything.
      final Set<String> wrong =
          deliberatelyUnread.intersection(_keysIn(_lib()));
      expect(
        wrong,
        isEmpty,
        reason: 'these are allow-listed as unread, but lib/ does read them. A '
            'key that is read belongs in the coverage question, not the '
            'exemption:\n${wrong.join('\n')}',
      );
    });

    test('the allow-list names keys the live API actually sends', () {
      // A name left behind by a Worker rename would let this file go green
      // for the wrong reason, so the list is checked against the captured
      // payload instead of trusted.
      final Set<String> stale = deliberatelyUnread.difference(everyKey);
      expect(
        stale,
        isEmpty,
        reason: 'these are allow-listed but the captured payload no longer has '
            'them — a Worker rename retired them, so delete the line:\n'
            '${stale.join('\n')}',
      );
    });

    test('the allow-list is not a place to park a dump', () {
      // It is only worth something while staying small is cheap. Six of the
      // fifty-nine unique keys is the measured floor; a tenth of the payload
      // means the sweep has stopped being a sweep.
      expect(
        deliberatelyUnread.length,
        lessThanOrEqualTo(7),
        reason: 'the allow-list has outgrown what this app really ignores. '
            'Re-run the sweep: a key that has become genuinely needed should '
            'be read, not listed.',
      );
    });
  });

  group('layer 2 — read into a model, named on no screen', () {
    test('the captured keys resolve to fields this app really declares', () {
      // A rename on either side would otherwise make layer 2 silently cover
      // nothing, which is worse than not having it.
      final String all = _lib();
      for (final String field in renderedNowhere.keys) {
        expect(
          RegExp('\\b$field\\b').hasMatch(all),
          isTrue,
          reason: '`$field` is listed in `renderedNowhere` but appears nowhere '
              'in lib/ — the field was renamed; delete the line.',
        );
      }
    });

    test('a field listed as invisible is invisible, not moved', () {
      final String ui = _reachableFromScreens();
      for (final MapEntry<String, String> e in renderedNowhere.entries) {
        expect(
          _namesField(ui, e.key, _writes),
          isFalse,
          reason: '`${e.key}` is listed as reaching no screen, but a file '
              'reachable from a screen or widget names it. It is live — take '
              'the name out of `renderedNowhere` and print it.',
        );
      }
    });

    test('the reason is a sentence, not a shrug', () {
      for (final MapEntry<String, String> e in renderedNowhere.entries) {
        expect(
          e.value.trim().length,
          greaterThan(40),
          reason: '`${e.key}` is listed without a reason worth reading. A bare '
              'word is indistinguishable from a placeholder.',
        );
      }
    });

    test('the field behind every captured key is either read or listed', () {
      // The automatic half of layer 2. A NEW key the server starts sending,
      // parsed into a model and printed nowhere, fails here with its field
      // name — the exact shape of wilaya_span, caught by a test rather than by
      // somebody remembering to grep.
      final Map<String, String> parsed = _keyToField();
      final String ui = _reachableFromScreens();
      final List<String> escaped = <String>[];

      for (final String key in everyKey) {
        final String? field = parsed[key];
        if (field == null) continue; // layer 1 owns this one
        if (renderedNowhere.containsKey(field)) continue;
        if (_namesField(ui, field, _writes)) continue;
        escaped.add('$key -> $field');
      }

      expect(
        escaped,
        isEmpty,
        reason: 'the Worker sends these, the parser keeps them, and no file '
            'reachable from a screen names them. Print the field, or add it '
            'to `renderedNowhere` with the reason:\n${escaped.join('\n')}',
      );
    });

    test('a note that names a field names a real one', () {
      for (final String key in referencedInNotes) {
        final String? field = _keyToField()[key];
        expect(field, isNotNull,
            reason: '`$key` is cited in a note but no model parses it');
        expect(_declaredIn(_lib(), field!), isTrue,
            reason: '`$key` is parsed into `$field` but no declaration of '
                '`$field` survives in lib/ — the field was renamed or dropped.');
      }
    });
  });
}

/// Whether any line of [source] *uses* [field] — a `.field` read or a
/// `field:` argument.
///
/// A declaration is not a use. The model that declares the field is itself
/// reachable from a screen, so searching its own body would match
/// `final String nameFr;` and call a dead field live.
bool _namesField(String source, String field, Set<String> writes) {
  for (final String line in const LineSplitter().convert(source)) {
    if (_declaresField(line, field)) continue;
    if (writes.contains(line.trim())) continue;
    if (RegExp('[.]\\s*$field\\b').hasMatch(line)) return true;
    if (RegExp('\\b$field\\s*:').hasMatch(line)) return true;
    // A bare identifier — `autoRenew == false`. `bool get isPrepaid =>
    // autoRenew == false;` is the only place `autoRenew` is read anywhere,
    // and neither `.field` nor `field:` sees it, so the detector called a
    // field that the subscription screen really does print dead. Guarded
    // above against the three shapes that merely name it: the declaration,
    // the `this.` forwarding, and the `fromJson` write.
    if (RegExp('(?<![.\\w])$field(?![\\w])').hasMatch(line)) return true;
  }
  return false;
}

/// Whether [line] *declares or forwards* [field] rather than reading it.
///
/// Three shapes declare and none of them is a use:
///  * `final String nameFr;` — the field itself;
///  * `required this.nameFr,` — a named constructor parameter, which reads
///    as `nameFr: nameFr` to the detector below and so reads as a *use* of
///    `nameFr` on its own line. Left unguarded it called a dead field live
///    and failed the run for the wrong reason;
///  * `this.nameFr,` — the forwarding shorthand for the same thing.
///
/// [source]-level [RegExp] is not enough for the middle one: the
/// declaration and the use are the same token on the same line, so the line
/// is skipped whole.
bool _declaresField(String line, String field) {
  return RegExp('^\\s*(?:required\\s+)?(?:final|late|const)\\s+[\\w<>,\\?\\s\\.]+?'
          '\\s+$field\\b')
      .hasMatch(line) ||
      RegExp('^\\s*(?:required\\s+)?this\\.$field\\b').hasMatch(line);
}

/// Whether [source] declares [field] at all — used by the test that a cited
/// note names a real field, which is a question about existence, not use.
bool _declaredIn(String source, String field) {
  for (final String line in const LineSplitter().convert(source)) {
    if (_declaresField(line, field)) return true;
  }
  return false;
}

/// Every `'key': value` in a file that subscripts that same key — the parse
/// line itself, not any other assignment.
final RegExp _parseLine = RegExp(
  '^\\s*([A-Za-z_]\\w*)\\s*:\\s*.*?\\[\\s*$eitherQuote(\\w+)$eitherQuote\\s*\\]',
  multiLine: true,
);

/// Single and double quote, as literal characters.
///
/// Neither Dart string delimiter can hold the other quote unescaped, and a
/// quote inside a regex character class *ends* that class — so both are built
/// by character code, once, and interpolated where a literal is unreadable.
final String sq = String.fromCharCode(39);
final String dq = String.fromCharCode(34);
final String eitherQuote = '[$sq$dq]';

/// Every line in `lib/` that *writes* a payload value into a field, trimmed.
///
/// `Plan.fromJson` closes with `nameFr: '${json['name_fr'] ?? ''}',`, and a
/// detector that counts `field:` as a use reads that line as the field being
/// live. It is the opposite: it is the field being filled in for the first
/// time, by the one file guaranteed to name every field it declares. A
/// `wilaya_span` that lands on such a line and nowhere else is exactly the
/// defect layer 2 exists to catch, so its own constructor must not be allowed
/// to manufacture the read that dismisses it.
///
/// The rule is stated in words and implemented as words — a line assigns a
/// field name *and* subscripts a json map on the same line — because a
/// regular expression for a regular expression is what this file already lost a
/// cycle to. Matching the tail of the line with a character class missed
/// `'${…}''}',` for the one field under test and quietly covered nothing.
Set<String> get _writes {
  final RegExp assigns = RegExp('^\\s*[A-Za-z_]\\w*\\s*:');
  final RegExp readsPayload = RegExp('\\bjson\\s*\\[');
  return <String>{
    for (final String line in const LineSplitter().convert(_lib()))
      if (assigns.hasMatch(line) && readsPayload.hasMatch(line)) line.trim(),
  };
}

/// key -> the field a model stores it in, taken from the parse lines only.
Map<String, String> _keyToField() {
  final Map<String, String> map = <String, String>{};
  for (final Match m in _parseLine.allMatches(_lib())) {
    final String field = m.group(1)!;
    final String key = m.group(2)!;
    if (field == 'json' || field == 'raw') continue;
    // First writer wins, matching the order the files are read in.
    map.putIfAbsent(key, () => field);
  }
  return map;
}

/// Every string key `lib/` subscripts, whatever the receiver is called.
Set<String> _keysIn(String source) => RegExp(
      '\\[$eitherQuote(\\w+)$eitherQuote\\]',
    ).allMatches(source).map((Match m) => m.group(1)!).toSet();

String _lib() => _dir(<String>['lib']);

/// Every file a screen or a widget can reach, imports followed transitively.
///
/// The closure is the point: a field printed by a helper in `data/` counts as
/// live, because the screen imports the helper. Only a field that no file on
/// this list names at all is reported, which is a claim about reaching no
/// screen — never a claim about reaching one.
String _reachableFromScreens() {
  final List<String> roots = <String>['lib/src/screens', 'lib/src/widgets'];
  final Map<String, List<String>> imports = <String, List<String>>{};
  for (final String file in _dartFiles(roots)) {
    imports[file] = RegExp("import\\s+$sq([^$sq]+)$sq")
        .allMatches(_read(file))
        .map((Match m) => m.group(1)!)
        .toList();
  }
  final Set<String> seen = <String>{..._dartFiles(roots)};
  final List<String> stack = seen.toList();
  while (stack.isNotEmpty) {
    final String current = stack.removeLast();
    for (final String rel in imports[current] ?? const <String>[]) {
      final String? resolved = _resolve(current, rel);
      if (resolved == null) continue;
      if (seen.add(resolved)) stack.add(resolved);
    }
  }
  final StringBuffer buffer = StringBuffer();
  for (final String file in seen) {
    buffer.writeln(_read(file));
  }
  return buffer.toString();
}

/// The imported path, normalised and confirmed to exist, or null.
String? _resolve(String from, String relative) {
  final int slash = from.lastIndexOf('/');
  final String base = slash < 0 ? '' : from.substring(0, slash + 1);
  final String joined = '$base$relative';
  // Normalise `..` and `.` by hand so the test needs no package:path import.
  final List<String> parts = <String>[];
  for (final String part in joined.split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  final String path = parts.join('/');
  // A `Directory` is never a file, so existence is asked of the `File` the
  // import names. Asking a directory whether a file exists answers no, and
  // the closure silently lost six live fields the first time round.
  return File(path).existsSync() ? path : null;
}

List<String> _dartFiles(List<String> roots) {
  final List<String> out = <String>[];
  for (final String root in roots) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        out.add(entity.path);
      }
    }
  }
  return out;
}

String _read(String path) => File(path).readAsStringSync();

String _dir(List<String> roots) {
  expect(Directory('lib').existsSync(), isTrue,
      reason: 'run from the package root — flutter test does');
  final StringBuffer buffer = StringBuffer();
  for (final String file in _dartFiles(roots)) {
    buffer.writeln(_read(file));
  }
  return buffer.toString();
}
