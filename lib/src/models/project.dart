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

  String get budgetLabel {
    if (budgetMin == null && budgetMax == null) return 'بدون ميزانية محددة';
    if (budgetMax == null) return 'من ${Money.dzd(budgetMin!)}';
    if (budgetMin == null) return 'حتى ${Money.dzd(budgetMax!)}';
    if (budgetMin == budgetMax) return Money.dzd(budgetMin!);
    return 'من ${Money.amountOnly(budgetMin!)} إلى ${Money.dzd(budgetMax!)}';
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    List<String> imgs = const [];
    final raw = json['images'];
    if (raw is List) imgs = raw.map((e) => e.toString()).toList();
    return Project(
      id: json['id'].toString(),
      customerId: json['customer_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      category: json['category'] as String,
      categories: json['categories'] is List
          ? (json['categories'] as List).map((e) => e.toString()).toList()
          : const [],
      images: imgs,
      wilaya: (json['wilaya'] as String?) ?? '',
      commune: json['commune'] as String?,
      budgetMin: (json['budget_min'] as num?)?.toInt(),
      budgetMax: (json['budget_max'] as num?)?.toInt(),
      urgency: _urgen(json['urgency'] as String?),
      status: _status(json['status'] as String?),
      selectedWorkerId: (json['selected_worker_id'] as num?)?.toInt(),
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