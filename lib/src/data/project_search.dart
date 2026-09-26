import '../core/text/arabic_search.dart';
import '../models/project.dart';
import 'taxonomy.dart';

/// Text filter for the two project feeds: the client's "مشاريعي" list and the
/// contractor's open-project marketplace.
///
/// Both feeds paginate or load a batch of projects, and neither the API nor
/// SQLite can fold Arabic orthography (see [ArabicSearch]) — so the narrowing
/// happens here, in Dart, on the rows the app already holds. A user who types
/// `دهان` must find `دهـــان شقة` from the very first character, on the phone,
/// without a round trip.
///
/// What counts as a match: the title, the description, the commune, and the
/// human names of **every** trade the job covers and of the wilaya. The trades
/// and wilaya are stored as English slugs / numeric codes, so typing `جبس` or
/// `الجزاير` would otherwise find nothing at all — the exact "this app is
/// foreign" failure the backlog is about.
///
/// The wilaya name is only considered when the project actually carries a
/// wilaya: [Taxonomy.wilayaName] falls back to 'الجزائر' for an unknown code,
/// and that fallback must not make every project match a wilaya search.
bool projectMatchesQuery(Project project, String query) {
  if (ArabicSearch.normalize(query).isEmpty) return true;
  return ArabicSearch.matches(query, [
    project.title,
    project.description,
    project.commune,
    for (final slug in project.allCategories) ...[
      Taxonomy.categoryName(slug),
      slug,
    ],
    project.wilaya.isEmpty ? null : Taxonomy.wilayaName(project.wilaya),
  ]);
}

/// [narrowProjects] with the empty-query shortcut: an empty (or
/// punctuation-only) query returns the list untouched, so a cleared search box
/// restores the full feed.
List<Project> narrowProjects(List<Project> projects, String query) {
  if (ArabicSearch.normalize(query).isEmpty) return projects;
  return projects.where((p) => projectMatchesQuery(p, query)).toList();
}
