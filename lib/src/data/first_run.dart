import '../models/chat.dart';
import '../models/project.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  Client first-run decision
/// ─────────────────────────────────────────────────────────────────────────
///
/// A project owner used to land on the marketplace with no explanation of what
/// to do first: a search bar, a grid of trades and two empty strips. A
/// contractor in the same situation gets a checklist that names his next step
/// (see `_GettingStarted` in `worker_home_screen.dart`). This is the rule that
/// decides whether the client gets the equivalent.
///
/// A renovation starts with one of two acts — publishing a project, or opening
/// a conversation with a contractor — so the guide belongs on screen only while
/// the app can prove the client has done neither.
bool clientNeedsFirstRunGuide({
  required bool projectsLoaded,
  required bool conversationsLoaded,
  required int projectCount,
  required int conversationCount,
}) {
  // A strip that failed to load is not evidence of a new account. A card that
  // keeps telling a client who already posted two projects to "post your first
  // project" reads as a broken app, so an unknown answer means no guide.
  if (!projectsLoaded || !conversationsLoaded) return false;
  return projectCount == 0 && conversationCount == 0;
}

/// The same rule applied to two possibly-failed loads, so call sites stop
/// repeating the null handling.
bool clientNeedsFirstRunGuideFor({
  required List<Project>? projects,
  required List<Conversation>? conversations,
}) =>
    clientNeedsFirstRunGuide(
      projectsLoaded: projects != null,
      conversationsLoaded: conversations != null,
      projectCount: projects?.length ?? 0,
      conversationCount: conversations?.length ?? 0,
    );
