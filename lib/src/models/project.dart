import '../core/format/money.dart';

/// Lifecycle of a posted project. Mirrors `ProjectStatus`.
///
/// The Dart names are camelCase and the wire names are snake_case, and the
/// only thing that translates between them is [wire] — the same arrangement
/// [UrgencyLevel] uses, for the same reason, after the identical bug cost a
/// 500 on every deadline-bearing project.
///
/// Found on production 30 Sep 2026. `Repository.myProjects` and
/// `_browseProjectsPage` both sent `status.name`, so the «قيد التنفيذ» tab
/// asked for `inProgress` against a project the server had as `in_progress`:
///
///   GET /api/mobile/my/projects?status=inProgress  -> 200, 0 rows
///   GET /api/mobile/my/projects?status=in_progress -> 200, 1 row
///
/// **A 200 with no rows, which is why nothing anywhere reported an error.**
/// The filter is not a write — nothing is refused, no toast fires, no retry
/// banner appears — so the only symptom is a successful read of zero. The
/// empty state then said «لا مشاريع في هذه الحالة» ("no projects in this
/// state") about a project that was in that state, on the tab a client opens
/// to see the renovation he is currently paying for.
///
/// Three of the four tabs were accidentally right: `open`, `completed` and
/// `cancelled` are single words in both languages. Only the tab that names a
/// two-word state was wrong, which is why this survived in a shipped app with
/// five status tabs and a full test suite.
///
/// It was also invisible on purpose. `StatusPill.project` was widened to
/// accept *both* spellings — it strips `_` and lowercases, so `in_progress`
/// and `inProgress` both reach the same branch — which is a display helper
/// made tolerant of the very mismatch that had to be fixed at the source. The
/// pill drew «قيد التنفيذ» correctly from a value the server had never sent.
enum ProjectStatus {
  open,
  inProgress,
  completed,
  cancelled;

  /// The only string this status may be sent as.
  ///
  /// `name` is wrong for two of the four values. Anything that puts a status
  /// on the wire reads this instead — the read path via [fromWire], the
  /// filter path via the query parameter, so write and read cannot drift.
  String get wire {
    switch (this) {
      case ProjectStatus.open:
        return 'open';
      case ProjectStatus.inProgress:
        return 'in_progress';
      case ProjectStatus.completed:
        return 'completed';
      case ProjectStatus.cancelled:
        return 'cancelled';
    }
  }

  /// The inverse of [wire]. Anything unrecognised — including null — is read
  /// as [open], the column's own default, so an unknown value can never crash
  /// a feed.
  ///
  /// The camelCase Dart name is deliberately *not* accepted. It was the bug:
  /// tolerating it on the way in is what let a mismatched write look correct
  /// in the one place it was displayed. A row still carrying `inProgress`
  /// reads as [open] here, which is a claim the server will eventually correct
  /// in its own snake_case, and it is the safer of the two answers.
  static ProjectStatus fromWire(String? v) {
    switch (v) {
      case 'in_progress':
        return ProjectStatus.inProgress;
      case 'completed':
        return ProjectStatus.completed;
      case 'cancelled':
        return ProjectStatus.cancelled;
      default:
        return ProjectStatus.open;
    }
  }
}

/// How urgent the client's project is. Mirrors `UrgencyLevel`.
enum UrgencyLevel {
  flexible,
  withinWeek,
  withinMonth,
  urgent;

  /// The only string this level may be sent as.
  ///
  /// The Dart names are camelCase and the `projects.urgency` column is
  /// snake_case with a CHECK constraint listing the four snake values, so
  /// `POST /api/mobile/projects` has to send this, never `name`. It did send
  /// `name`, which meant the two commonest answers — «خلال أسبوع» and
  /// «خلال شهر» — violated the constraint and came back as a bare 500 the
  /// screen could only render as "خدمة غير متاحة، أعد المحاولة".
  /// Measured against the live API (13 Sep): `withinWeek` and `withinMonth`
  /// → 500, `within_week`, `within_month`, `urgent`, `flexible` → 201.
  String get wire {
    switch (this) {
      case UrgencyLevel.flexible:
        return 'flexible';
      case UrgencyLevel.withinWeek:
        return 'within_week';
      case UrgencyLevel.withinMonth:
        return 'within_month';
      case UrgencyLevel.urgent:
        return 'urgent';
    }
  }

  /// The inverse of [wire]. Anything unrecognised is read as [flexible] — the
  /// column's own default — so an unknown value can never crash a feed.
  static UrgencyLevel fromWire(String? v) {
    switch (v) {
      case 'within_week':
        return UrgencyLevel.withinWeek;
      case 'within_month':
        return UrgencyLevel.withinMonth;
      case 'urgent':
        return UrgencyLevel.urgent;
      default:
        return UrgencyLevel.flexible;
    }
  }
}

/// A client-posted project. Mirrors `Project` from finili types.
class Project {
  final String id;
  final int customerId;
  final String title;
  final String? description;
  final String category;

  /// Every trade this job covers, primary first.
  ///
  /// The founder's ask, verbatim: «make sure the job seeker to be able to choose
  /// multiple niches … Like عام وهيكل، ترميم وتجديد، تشطيب عام وتسليم مفتاح — all
  /// in once». `category` stays the primary trade (older rows, and every filter
  /// built before this, use it); this is the full list.
  final List<String> categories;

  /// The trades to show, primary first and never empty — a project posted
  /// before multi-trade existed only has [category].
  List<String> get allCategories {
    if (categories.isEmpty) return [category];
    if (categories.contains(category)) return categories;
    return [category, ...categories];
  }

  final List<String> images;
  final String wilaya;
  final String? commune;
  final int? budgetMin;
  final int? budgetMax;
  final UrgencyLevel urgency;
  final ProjectStatus status;
  final int? selectedWorkerId;

  const Project({
    required this.id,
    required this.customerId,
    required this.title,
    this.description,
    required this.category,
    this.categories = const [],
    required this.images,
    required this.wilaya,
    this.commune,
    this.budgetMin,
    this.budgetMax,
    required this.urgency,
    required this.status,
    this.selectedWorkerId,
  });

  /// The budget as the feed and the project page read it, in whole dinars.
  ///
  /// **A stored `0` is an absent answer, not a price.** This getter had five
  /// arms — both null, min only, max only, equal ends, a real band — and a
  /// zero fitted none of them, so it fell through to the band and printed
  ///
  ///     «من 0 إلى 50000 دج»
  ///
  /// on `project_card.dart` and `project_detail_screen.dart`: the card a
  /// contractor scrolls to pick a job, and the page he reads before quoting.
  ///
  /// The zero is reachable from **this app's own form**, which is what makes it
  /// a defect rather than server state. `DzNumber.tryParse` takes a `min`
  /// bound and the budget fields pass none, so typing `0` parses to the
  /// integer `0`; the form's `_budgetError` refuses only `min > max`, and zero
  /// is not greater than anything, so the project publishes with a budget
  /// floor of nothing. `Money.amountOnly(0)` then prints `0` instead of
  /// dropping it, because a real `0` and a nonsense `0` are the same `0` by
  /// the time it is a string.
  ///
  /// What it says to a man reading it is the damage. «من 0 دج» is not "no
  /// budget given" — it is a claim that this renovation is available from
  /// nothing, and it is indistinguishable on screen from the project's own
  /// «بدون ميزانية محددة», which is the honest rendering of a customer who
  /// left both boxes empty. Two different facts, one of them a price. A budget
  /// of zero dinars is not a budget, and the row that says so is the same
  /// silence the empty project already gets.
  ///
  /// The rule is the one `worker_stats_copy.dart` and `price_range_copy.dart`
  /// already keep — a stored `0` is a default standing in for an answer — so
  /// the zero is folded into null **before** the arms are chosen, rather than
  /// being given a sixth arm. That is the whole difference: one column, one
  /// rule, and no caller of this getter can reach the band arm with a zero in
  /// it.
  ///
  /// The **negative** half is not handled here on purpose. `DzNumber`'s digit
  /// fold strips the sign, so a budget this app can publish is never negative;
  /// a negative row is server state, and this getter has nothing to say about
  /// one that the form cannot create.
  String get budgetLabel {
    final min = budgetMin != null && budgetMin! > 0 ? budgetMin : null;
    final max = budgetMax != null && budgetMax! > 0 ? budgetMax : null;
    if (min == null && max == null) return 'بدون ميزانية محددة';
    if (max == null) return 'من ${Money.dzd(min!)}';
    if (min == null) return 'حتى ${Money.dzd(max)}';
    if (min == max) return Money.dzd(min);
    return 'من ${Money.amountOnly(min)} إلى ${Money.dzd(max)}';
  }

  /// Reads the payload instead of casting it, for the reason `chat.dart` and
  /// `notification.dart` carry in their own file headers: `repository._rows`
  /// turns a model `TypeError` into an `ApiException` and **drops the row**, so
  /// one unexpected column costs a card and not a field.
  ///
  /// On this model that is the worst of the four outcomes the family has found.
  /// A lost chat row is a message missing from a thread that still reads as a
  /// thread; a lost notification is never drawn at all; a lost project is **a
  /// job the customer cannot open and a contractor cannot quote** — and browsing
  /// is the first thing either of them does with the app. The feed renders as
  /// «لا توجد مشاريع» over a market that has work in it, and the founder's
  /// screen shows him no projects rather than an error he could report.
  ///
  /// **This file was the one with three casts that could not fail quietly.**
  /// `customer_id`, `title` and `category` were `as int` / `as String`, not the
  /// `as String?` the audit flagged, so there was no null to tolerate: any
  /// shape but the exact one threw, and one row took the page with it.
  ///
  /// The rules are the ones the two shipped files already keep, and they are
  /// not applied uniformly on purpose — each field gets the fallback its
  /// **caller** already knows how to render:
  ///
  ///   * **`title` is the one field a string may not become a placeholder.** It
  ///     is drawn verbatim on the card (`project_card.dart:31`) and the detail
  ///     page (`project_detail_screen.dart:389`), and the same string seeds the
  ///     edit form (`project_new_screen.dart:118`). A fabricated «مشروع بدون
  ///     عنوان» would be *written back to the server* the next time its owner
  ///     saves an edit — the app inventing a title and then persisting it as
  ///     the customer's own. So an unreadable title is empty, and the honest
  ///     rendering of an empty title is a card with no headline, which is
  ///     visibly unfinished rather than confidently wrong.
  ///   * **`category` does get a placeholder**, because it has one: every
  ///     reader already routes an unknown slug to `Taxonomy`'s own fallback —
  ///     `categoryName` answers «خدمات عامة» and `canonical` never leaks a raw
  ///     English slug into the Arabic UI. `''` is already on that path
  ///     (`canonical` returns it unchanged), so the badge draws the same grey
  ///     handyman it draws for a slug this build has never heard of. Nothing
  ///     invents a trade.
  ///   * **`id` stays a key** — flattened by its own text, never interpolated
  ///     into «null», because it is the argument to `/api/mobile/projects/$id`
  ///     and `push()` with it.
  ///   * **Copy is never flattened.** A number is not a sentence somebody
  ///     wrote, and both readers already answer «there is nothing here»: the
  ///     description's own section is skipped when it is null, and the title is
  ///     drawn as it came.
  ///   * **A budget stays nullable.** `budgetLabel` folds a stored `0` into null
  ///     before it chooses a band, and `project_new_screen` writes
  ///     `budgetMin?.toString() ?? ''` — so an unreadable floor must be
  ///     *absent*, never `0`, or the edit form would show a zero budget the
  ///     customer never typed.
  factory Project.fromJson(Map<String, dynamic> json) {
    List<String> imgs = const [];
    final raw = json['images'];
    if (raw is List) imgs = raw.map((e) => e.toString()).toList();
    return Project(
      // A key, not copy: whatever the server sent is flattened by its own
      // text, and an absent one is '' rather than the word «null» — which is
      // what `.toString()` already did, so this is the same answer for a new
      // reason. `push()` with it either way is still a dead link, but a dead
      // link beats a page that shows nothing.
      id: _wireText(json['id']),
      // Read, not cast: `as int` threw on `'30'` — a string from SQLite, the
      // shape `_asInt` in `data/repository.dart` documents in its own comment
      // — and `customer_id` is what the «مراسلة صاحب المشروع» button sends to
      // the chat screen (`project_detail_screen.dart:466`). A lost id there is
      // a conversation opened against nobody.
      customerId: _int(json['customer_id']),
      // Copy, never flattened, and never invented — see the note above.
      title: _text(json['title']) ?? '',
      // Copy. The detail page guards this section with `!= null`
      // (`project_detail_screen.dart:399`), so an absent description is a
      // section that is not drawn, which is the existing honest answer.
      description: _text(json['description']),
      // A key with a fallback already in the table — see the class note.
      category: _wireText(json['category']),
      categories: json['categories'] is List
          ? (json['categories'] as List).map((e) => e.toString()).toList()
          : const [],
      images: imgs,
      // A **code**, not a name: `Taxonomy.wilayaNameOrNull` returns null for a
      // blank or unknown one and the card then draws no location row at all
      // (`project_card.dart:18,59`), which is the fix the 26 Sep
      // «project without a wilaya is published in الجزائر» bug produced. An
      // unreadable code must therefore be blank and stay blank — flattening a
      // number here would name a wilaya nobody stated, which is the exact lie
      // that getter was written to stop.
      wilaya: _wireText(json['wilaya']),
      // Copy the edit form seeds a field with (`project_new_screen.dart:119`).
      commune: _text(json['commune']),
      // `as num?` threw on a SQLite string and read `''` as 0 on a null — see
      // the budget note above.
      budgetMin: _nullableInt(json['budget_min']),
      budgetMax: _nullableInt(json['budget_max']),
      urgency: _urgen(_wireText(json['urgency'])),
      status: _status(_wireText(json['status'])),
      // Read rather than cast, and still nullable: `project_commit_outcome`
      // compares `fresh.selectedWorkerId == workerId` to decide whether a
      // contractor's pick is confirmed, so a drifted `'7'` must arrive as 7 —
      // and a genuinely absent one must stay null, or every project would
      // claim a worker nobody was chosen.
      selectedWorkerId: _nullableInt(json['selected_worker_id']),
    );
  }

  /// Reading and writing urgency are the same table, so they cannot drift:
  /// `UrgencyLevel.fromWire` is the inverse of `UrgencyLevel.wire`, and the
  /// publish path uses the same getter.
  static UrgencyLevel _urgen(String? v) => UrgencyLevel.fromWire(v);

  /// Reading a status is [ProjectStatus.fromWire] and nothing else, so the
  /// table above has exactly one copy of it.
  static ProjectStatus _status(String? v) => ProjectStatus.fromWire(v);
}
// ---- reading the payload, not casting it -----------------------------------
//
// The same four readers `chat.dart` and `notification.dart` keep, and
// deliberately the same code: three files that each grew their own version of
// "how do we read a column" is how they drift apart, and the drift would be
// invisible — a tolerant field in one model and a throwing one in the next is
// the same defect the audit found three times. Each stays private to its file,
// so a model cannot quietly borrow another model's leniency.

/// An integer column, tolerant of the two shapes D1 really answers with.
///
/// `_asInt` in `data/repository.dart` names them: a number from a JSON body, a
/// string from SQLite. 0 when neither — and 0 on `customer_id` opens a chat
/// against user 0, which is a visibly dead thread rather than a lost screen.
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// An integer that stays null when the field is absent or unreadable, so the
/// caller must choose a default instead of inheriting one by accident.
///
/// Both budgets and the selected worker use this. A 0 where a budget was
/// expected is not "no money": `budgetLabel` treats a stored 0 as an absent
/// answer, and the edit form prints `?.toString() ?? ''`, so a fabricated 0
/// would round-trip a zero budget the customer never typed.
int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// A wire value as text, for a **key** column: a project id, a wilaya code, a
/// trade slug, a status or urgency name.
///
/// Interpolation prints the literal «null» for an absent key, and «null» is a
/// code the routing rule, the wilaya table and the category table have never
/// heard of — so every one of them lands on its own fallback, which is what an
/// absent key gets anyway. Flattening a real number is right here and only
/// here: these are identifiers, not sentences.
String _wireText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

/// Copy, trimmed, or null when absent/empty/not a string.
///
/// No flattening: a number is not a sentence somebody wrote, and both callers
/// here already have the honest answer for «there is nothing here» — the
/// description section is simply not drawn, and the title is drawn as it came.
String? _text(Object? value) {
  if (value is! String) return null;
  final v = value.trim();
  return v.isEmpty ? null : v;
}
