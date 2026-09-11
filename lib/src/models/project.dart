/// Lifecycle of a posted project. Mirrors `ProjectStatus`.
enum ProjectStatus { open, inProgress, completed, cancelled }

/// How urgent the client's project is. Mirrors `UrgencyLevel`.
enum UrgencyLevel { flexible, withinWeek, withinMonth, urgent }

/// A client-posted project. Mirrors `Project` from finili types.
class Project {
  final String id;
  final int customerId;
  final String title;
  final String? description;
  final String category;
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
    if (budgetMax == null) return 'من ${budgetMin!} دج';
    if (budgetMin == null) return 'حتى ${budgetMax!} دج';
    return '$budgetMin - $budgetMax دج';
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

  static UrgencyLevel _urgen(String? v) {
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