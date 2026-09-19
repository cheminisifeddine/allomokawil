import '../core/format/money.dart';

/// Lifecycle of a posted project. Mirrors `ProjectStatus`.
enum ProjectStatus { open, inProgress, completed, cancelled }

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

  static ProjectStatus _status(String? v) {
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