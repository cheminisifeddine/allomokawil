/// A row that can say it must not be drawn.
///
/// **Why this file exists.** `Repository._rows` drops a row it cannot parse and
/// records the loss, because a contractor with a drifted column must not be the
/// reason a customer opening the app sees an empty market. That contract was
/// testable only while the models *threw* — the drop mechanism had no way to
/// notice a row that parsed cleanly and was still undrawable.
///
/// Making the parsers tolerant took that away: a row with no `id` stopped
/// throwing and started arriving as `id: 0`, which is drawn as a real card
/// whose profile link is `/api/mobile/workers/0`. That is a card a customer
/// can tap and that can only fail, which is the exact thing the drop was for.
///
/// So tolerance and the drop are separate concerns, and this interface is the
/// seam. A model **reads** its payload — no cast, no exception for a shape it
/// did not expect — and then declares whether what it read is a row a screen
/// can draw. `_rows` honours the answer: a row that says no is dropped and
/// counted, and the existing record names it.
library;

/// Implemented by models whose rows can be **not drawable** after a successful
/// parse — typically because the row's identity (`id`) was absent or
/// unreadable.
///
/// A model that does not implement this is assumed renderable: the interface is
/// opt-in precisely so a row that is genuinely incomplete in some other way
/// keeps whatever its own screen says about it.
abstract class RenderableRow {
  /// False when this value is a parsed row the app must not draw.
  ///
  /// Implementations must not throw. `_rows` calls this on every row it read,
  /// so a throw here would be the very failure the interface exists to
  /// prevent.
  bool get isRenderable;
}
