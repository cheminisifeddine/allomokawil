import 'package:flutter/material.dart';

import '../core/text/monogram.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/motion.dart';
import '../data/project_status_copy.dart';
import '../data/quote_status_copy.dart';
import '../data/review_count.dart';
import '../data/star_row_shape.dart';
import '../data/taxonomy.dart';
import '../models/enums.dart' show QuoteStatus;
import '../models/project.dart' show ProjectStatus;
import 'a11y.dart';
import 'motion.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  Shared UI kit for Allo Mokawil.
///
///  HARD RULE for this whole kit: no widget may leave a `color` unset and hope
///  to inherit it. The old specialty tiles did exactly that inside a Material 3
///  `ChoiceChip` and rendered white-on-white. Every text style below names its
///  colour. Keep it that way.
/// ─────────────────────────────────────────────────────────────────────────

/// Circular icon on a soft wash — the visual anchor of every card/tile.
class IconBubble extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color wash;
  final double size;

  const IconBubble({
    super.key,
    required this.icon,
    this.tint = AppTheme.navy,
    this.wash = AppTheme.lineSoft,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}

/// The app's basic building block — one shape for every card, built from the
/// single recipe in [AppTheme.cardDecorationOf] so no screen can invent its own
/// radius, border, shadow or inner padding. Pinned by `card_recipe_test.dart`.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = AppTheme.cardPad,
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = AppTheme.cardRadius,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: AppTheme.cardDecorationOf(
        fill: color,
        border: borderColor,
        radius: radius,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

/// Arabic section heading with an optional trailing action ("عرض الكل").
class SectionTitle extends StatelessWidget {
  final String text;
  final String? actionText;
  final VoidCallback? onAction;
  final IconData? icon;

  const SectionTitle(
    this.text, {
    super.key,
    this.actionText,
    this.onAction,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The action is 56 dp tall, so the band grows 11 dp over the plain one:
      // 8 + 56 + 4 = 68 against 8 + 25 = 33 before.
      //
      // **The horizontal `2` was an optical guess from the design overhaul and
      // it never had a caller that asked for it.** It has 25 call sites across
      // eight screens, and every one of them already owns the left edge: four
      // wrap this widget in their own `Padding(horizontal: 16)` / `gutter`, and
      // the other 21 sit inside a list that carries `pagePad` or `s16`. So the
      // heading sat 2 dp inside the band that introduces it on **all 25**, and
      // the three customer-home titles — the only ones measured, because
      // `customer_home_column_test.dart` reads the *band* rather than the text —
      // were the only three anybody had ever looked at. It is now `0`.
      //
      // **The vertical `10` is now `s8`, and it was defended by a false claim.**
      // Two earlier ticks left it counted and recorded on the grounds that it
      // is "the arithmetic that keeps a 56 dp tap target inside a 70 dp band
      // (`10 + 56 + 4`)" — restated in `card_recipe_test.dart` and in
      // `section_title_edge_test.dart`, where a case *asserts* the band at
      // `tapMin + 14` and cites this sentence as the reason.
      //
      // Measured, because that sentence is inverted: the 56 dp is
      // `SizedBox(height: AppTheme.tapMin)`, **not** the padding. Zeroing this
      // padding to `0` still gives a 70 -> 56 dp band with the action
      // measuring exactly 56.0 dp, and `tap_target_test.dart` — the a11y tick
      // the comment cites as its authority — passes green with the padding
      // gone. The padding never held the tap target; it only added a band
      // around a height the child already guaranteed. The `SizedBox` is what
      // makes the action 56 dp at either `10` or `8`, so the value was free.
      //
      // What `10` actually bought was a rhythm no other section in the app
      // draws: 10 dp above the heading and 4 dp below it, so the band is glued
      // to the content it introduces and floats away from the content it
      // follows. `s8` is the ladder step above the `4` and is one line above
      // what it was — 2 dp on 25 headings, the cost of removing an invented
      // rule. The `4` below is untouched: it is on the ladder and it is the gap
      // to the content the heading introduces.
      //
      // `section_title_edge_test.dart` now asserts the **action's** height and
      // that it holds independently of this padding, which is the property the
      // old comment claimed and the one that was never checked.
      padding: const EdgeInsets.fromLTRB(0, AppTheme.s8, 0, AppTheme.s4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: AppTheme.navy),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: AppTheme.h2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionText != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: AppTheme.tapMin,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(actionText!,
                          style: AppTheme.label.copyWith(
                              fontSize: AppTheme.fsMeta, color: AppTheme.info)),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 12, color: AppTheme.info),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The single big amber call-to-action, with an inline loading state.
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    // Busy is not the same as dead. Both pass a null callback, so the button
    // style cannot tell them apart — but they must not *look* alike.
    //
    // This computed `enabled = onPressed != null && !loading` and let the
    // spinner fall through to the style's `disabledBackgroundColor`, so every
    // busy button in the app painted grey: the same fill as a button the user
    // cannot press. The one moment a screen is waiting on the network is the
    // one moment the app looks like it has refused to act.
    //
    // Caught by measuring the pixels of the previous tick's own screenshot:
    // the committing «قبول العرض» button was 99.6 % `e8e8ec` — identical to
    // the two dead sibling buttons around it — while idle it is 100 % accent.
    // A busy fill is supplied explicitly, which keeps the amber promise the
    // rest of the app makes about its primary action.
    final busy = loading;
    final enabled = onPressed != null && !busy;
    final btn = ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: AppTheme.navy,
        // The disabled palette is kept for a button with no callback *and*
        // nothing in flight; a busy one keeps the accent.
        disabledBackgroundColor:
            busy ? AppTheme.accent : AppTheme.line,
        disabledForegroundColor:
            busy ? AppTheme.navy : AppTheme.textMuted,
        elevation: 0,
        minimumSize: const Size.fromHeight(AppTheme.tapMin),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rMd)),
      ),
      child: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.6, color: AppTheme.navy),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 21, color: AppTheme.navy),
                  const SizedBox(width: 9),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: AppTheme.button,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
    // Both shared buttons answer a press with the same 3% shrink, so a screen
    // that mixes them still moves as one thing.
    final pressable = Pressable(enabled: enabled, child: btn);
    return expanded
        ? SizedBox(width: double.infinity, child: pressable)
        : pressable;
  }
}

/// Outlined, quieter action that sits next to [PrimaryButton].
class SecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expanded;

  const SecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final btn = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.navy,
        minimumSize: const Size.fromHeight(AppTheme.tapMin),
        side: const BorderSide(
            color: AppTheme.controlLine, width: AppTheme.hairline),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rMd)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppTheme.navy),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(label,
                style: AppTheme.button.copyWith(fontSize: AppTheme.fsLead),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    final pressable = Pressable(enabled: onPressed != null, child: btn);
    return expanded
        ? SizedBox(width: double.infinity, child: pressable)
        : pressable;
  }
}

/// Compact icon + name pill — replaces bare emoji strings in list rows.
class CategoryBadge extends StatelessWidget {
  final String slug;
  final String? label;

  const CategoryBadge({super.key, required this.slug, this.label});

  @override
  Widget build(BuildContext context) {
    final tint = Taxonomy.categoryTint(slug);
    final wash = Taxonomy.categoryWash(slug);
    return Container(
      padding: AppTheme.pillPad,
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Taxonomy.categoryIcon(slug), size: 14, color: tint),
          const SizedBox(width: AppTheme.pillGap),
          // Flexible + ellipsis: a bare Text takes its intrinsic width inside a
          // Row, which pushed long Arabic category names past the card edge.
          Flexible(
            child: Text(
              label ?? Taxonomy.categoryName(slug),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.label.copyWith(fontSize: AppTheme.fsCaption, color: tint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable tile used by every picker (specialty, urgency, filters).
/// This is what was rendering white-on-white before: now every colour here is
/// written down, so it is impossible for the label to vanish.
class SelectableTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color tint;
  final Color wash;
  final double height;

  const SelectableTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
    this.tint = AppTheme.navy,
    this.wash = AppTheme.lineSoft,
    this.height = 104,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: A11y.button(
        selected: selected,
        enabled: onTap != null,
        child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: height,
          // The horizontal inset was `6` — off the 4 dp ladder, and the reason
          // the selected tile is the only one that ever ellipsizes a label.
          // Two grids of three columns at a 320 dp page leave the *selected*
          // tile 72.00 dp of label room (88.00 tile, less 2x4 padding, less the
          // 2 dp border the user is looking at), and the longest label in the
          // taxonomy needs 72.06 dp to stay on two lines. It missed by 0.06 dp,
          // so «بلاط وسيراميك ورخام» drew as «بلاط وسيراميك…» on exactly the
          // tile the user had just tapped. `s4` is the ladder step that clears
          // it: 76.00 dp, 3.94 dp of headroom.
          //
          // Measured off the engine, not inferred: see
          // `test/tile_label_fit_test.dart`, which lays every label out in a
          // real `TextPainter` at 392/360/320 in both tile states.
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.s4, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentWash : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: selected ? AppTheme.navy : AppTheme.line,
              width:
                  selected ? AppTheme.hairlineSelected : AppTheme.hairlineResting,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.navy : wash,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: 19, color: selected ? AppTheme.onNavy : tint),
              ),
              const SizedBox(height: 6),
              // Flexible, not a fixed box: a two-line Arabic label must be able
              // to shrink instead of overflowing the tile.
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // Explicit colour — this is the bug fix.
                  //
                  // The size is [fsBadge] (11), and it was `fsCaption` (12.5)
                  // until this slice. `git log -L` on this line is the whole
                  // story: the tile drew a bare `fontSize: 12` until the type
                  // ladder landed (`f589ae0`), which snapped it *up* to the
                  // nearest step. Nothing asked whether the tile still fitted
                  // its own label, and the numbers here are the fit, not the
                  // type: a 3-column grid on a 320 dp page gives the tile
                  // 78.00 dp of label room (88.00 tile, less 2 x s4, less the
                  // 1 dp border) and 76.00 when selected, because the selected
                  // border is 2 dp. «تشطيب عام وتسليم مفتاح», «سباكة وترصيص
                  // صحي» and «بلاط وسيراميك ورخام» need **78.40 / 80.57 /
                  // 81.88 dp** for two lines at 12.5 — so those three names
                  // ellipsized on *every*
                  // 320 dp phone, in both tile states, on both screens that
                  // show this grid (publish and profile edit), and only there:
                  // at 392 and 360 every label fits, which is why the goldens
                  // are clean and nobody saw it.
                  //
                  // 11 needs 72.06 dp, and its twin agrees: the horizontal
                  // strip tile in `category_grid.dart` draws the same trade
                  // names at the same [fsBadge] — so after this the two ways
                  // the app asks a user to pick a trade answer in one size.
                  //
                  // **A step below (`fsBadge` is the ladder floor) is not the
                  // fix and was not taken.** Letting a third line was the other
                  // way out, and at the width that matters it does not even
                  // work: 3 lines at 12.5 need **46.88 dp** and the 320 dp tile
                  // has **31.65 dp** of vertical room (95.65 tile, less 2x10
                  // padding, less the 2 dp border, less the 36 dp glyph, less
                  // the 6 dp gap). It clears at 392 (57.74 dp available) and
                  // not at 320, so it would trade this defect for a narrower
                  // one on the cheapest phone the app supports.
                  style: AppTheme.label.copyWith(
                    fontSize: AppTheme.fsBadge,
                    height: 1.25,
                    color: selected ? AppTheme.navy : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}

/// Coloured status badge for project/quote states.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color wash;
  final IconData? icon;

  /// Draw a 1 px outline around the pill. `null` = none, which is what every
  /// caller that shows a pill *beside* other pills wants: two pills on one row
  /// are separated by their wash, and an outline on both reads as a table.
  ///
  /// This is how [StatusPill] absorbed the hand-rolled verdict pill on the
  /// verification screen (`_PartsStatusCard._part`, deleted 9 Oct). That copy
  /// drew `symmetric(horizontal: 10, vertical: 5)`, icon 13 and a 5 dp gap
  /// beside a real [StatusPill] on **the same `ListView`**, so a worker
  /// scrolled between two pills that agreed on radius and font and disagreed
  /// by 1 dp of inset and 1 dp of gap. What it also had that this one did not
  /// was a **border** — the outline is what told «لم تُرسل» apart from the two
  /// washes behind it, so it could not simply be dropped. Rather than keep two
  /// pills, the border became an option on this one. `null` by default, so
  /// every existing caller paints exactly the same pixels as before.
  final Color? border;

  const StatusPill({
    super.key,
    required this.label,
    this.color = AppTheme.info,
    this.wash = AppTheme.infoWash,
    this.icon,
    this.border,
  });

  /// The pill on a project card and on the project page.
  ///
  /// Takes the parsed [ProjectStatus], not a string, and that signature is the
  /// fix: this factory used to take a bare `String` and switch on it, so
  /// nothing checked what a caller passed. Both callers passed
  /// `status.wire` (`'in_progress'`) while the switch keyed on
  /// `'inprogress'` — the Dart enum name — so the arm was unreachable and
  /// **no project in this app has ever been drawn as «قيد التنفيذ»**. Every
  /// running job drew «مفتوح»: the claim that other contractors may still
  /// bid on it.
  ///
  /// See `data/project_status_copy.dart`, which owns the words; this factory
  /// owns only the colour, and it reads the label from there so the filter
  /// tabs in `projects_screen.dart` and this pill cannot name one state two
  /// ways. `ProjectStatus.fromWire` is the single parser, so a string the
  /// server never sends is read as `open` before it reaches a widget that was
  /// only asked to draw a pill.
  factory StatusPill.project(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.inProgress:
        return StatusPill(
            label: projectStatusAr(ProjectStatus.inProgress),
            color: AppTheme.info,
            wash: AppTheme.infoWash,
            icon: Icons.play_circle_fill_rounded);
      case ProjectStatus.completed:
        return StatusPill(
            label: projectStatusAr(ProjectStatus.completed),
            color: AppTheme.success,
            wash: AppTheme.successWash,
            icon: Icons.check_circle_rounded);
      case ProjectStatus.cancelled:
        return StatusPill(
            label: projectStatusAr(ProjectStatus.cancelled),
            color: AppTheme.danger,
            wash: AppTheme.dangerWash,
            icon: Icons.cancel_rounded);
      case ProjectStatus.open:
        return StatusPill(
            label: projectStatusAr(ProjectStatus.open),
            color: AppTheme.accentDeep,
            wash: AppTheme.accentWash,
            icon: Icons.bolt_rounded);
    }
  }

  /// A sibling of [StatusPill.project] rather than a private widget inside the
  /// quote card, for the same reason that factory is public: the word, the
  /// colour and the icon are one decision, and a second copy of it on another
  /// card is how a marketplace ends up answering «did I win this?» in two
  /// colours.
  ///
  /// A [QuoteStatus.pending] bid carries **no stamp at all** — not a grey
  /// «قيد الانتظار». The common case is a bid the owner can still act on, and a
  /// stamp on every card trains the eye to stop reading them; the absence is
  /// what means "live", exactly as it does on the card.
  factory StatusPill.quote(QuoteStatus status) {
    switch (status) {
      case QuoteStatus.accepted:
        return StatusPill(
            label: quoteStatusAr(QuoteStatus.accepted),
            color: AppTheme.success,
            wash: AppTheme.successWash,
            icon: Icons.check_circle_rounded);
      case QuoteStatus.rejected:
        return StatusPill(
            label: quoteStatusAr(QuoteStatus.rejected),
            color: AppTheme.textSecondary,
            wash: AppTheme.lineSoft,
            icon: Icons.cancel_outlined);
      case QuoteStatus.pending:
        // Unreachable through the card, which gates on `isDecided`. Handled
        // anyway because a `switch` on an enum that adds a fourth value must
        // not throw inside somebody's widget build.
        final label = quoteStatusAr(QuoteStatus.pending);
        return StatusPill(
            label: label.isEmpty ? 'قيد الانتظار' : label,
            color: AppTheme.info,
            wash: AppTheme.infoWash,
            icon: Icons.hourglass_empty_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppTheme.pillPad,
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            // Was a literal `5` where both sibling pills use `6`. These three
            // draw side by side on the worker's filter strip and the project
            // page, so the status pill sat 1 dp tighter to its own icon than
            // the trade badge beside it. `AppTheme.pillGap` is the one number.
            const SizedBox(width: AppTheme.pillGap),
          ],
          Text(label,
              style: AppTheme.label.copyWith(fontSize: AppTheme.fsCaption, color: color)),
        ],
      ),
    );
  }
}

/// The neutral metadata pill: a 14 dp icon, one short word, the soft grey
/// wash. The project page's place chip, and — since the twenty-first slice —
/// the three fact tags on the browse contractor card.
///
/// **It moved here for a measured reason.** It used to be private to
/// `project_detail_screen.dart` and its doc comment already said what
/// happened next: "Naming it means the next pill is a caller, not a copy." The
/// copy was `worker_card.dart`'s private `_MiniTag`, which spelled the same
/// pill by hand at `symmetric(9, 5)`, icon 13, gap 4 and `fsBadge` — **25.0 dp
/// tall against this pill's 26.0**, measured off real layout at 320/360/392.
/// The two are on the **same screen**: the client home draws the contractor
/// strip and the project cards in one column, so a customer scrolls from a
/// 25 dp tag to a 26 dp status pill and watches the pill change height.
///
/// A pill is judged against the pill it sits next to, which is the argument
/// `pillPad` was written for, and that argument does not care which file the
/// other pill lives in. So the shared one moved to the shared kit rather than
/// a second copy moving in.
///
/// Kept as its own widget rather than folded into [StatusPill]: [StatusPill]
/// takes a colour and a wash and a label and is a *state*, while this is a
/// *fact* with no state — merging them would have made the browse card's
/// "paused" tag read as a status. See `test/worker_card_tag_pill_test.dart`,
/// whose census is the assertion that class of copy cannot survive.
/// The place chip on the project page. Public on purpose: it is the third
/// writer of this pill, and a private widget cannot be rendered by the guard
/// that holds the three of them to one inset (`test/pill_inset_test.dart`).
/// Naming it means the next pill is a caller, not a copy.
class MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const MetaChip({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppTheme.pillPad,
      decoration: BoxDecoration(
        color: AppTheme.lineSoft,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: AppTheme.pillGap),
          Text(text,
              style: AppTheme.caption
                  .copyWith(fontSize: AppTheme.fsCaption, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

/// Star rating row (read-only display).
class RatingStars extends StatelessWidget {
  final double rating;
  final int? count;
  final double size;

  const RatingStars({
    super.key,
    required this.rating,
    this.count,
    this.size = 15,
  });

  @override
  Widget build(BuildContext context) {
    // A count of zero is an absence, not a number: the stars and the score are
    // real here, so printing «(0)» beside them claims the score is nobody's.
    // The label below is built from the same value, so what a screen reader
    // says and what the glass shows cannot drift apart — see
    // [printableReviewCount].
    final shown = count == null ? null : printableReviewCount(count!);
    // One score, pinned once, for every shape on this row. The stars already
    // clamped inside [starIconFor] and the label already clamps inside
    // [A11y.rating]; the printed digits were the third copy, and the only one
    // of the three still showing the caller's raw value — so a 7.5 drew five
    // full stars beside the number 7.5. Same argument as the count below it:
    // the text beside the shapes has to be describing the shapes.
    final pinned = clampRating(rating, count: A11y.scale);
    // Stars are geometry: read out one by one they are five meaningless icons
    // and a bare number. The row is a leaf — the icons are excluded and the
    // score is handed over as the sentence a person would say.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: A11y.rating(rating, count: shown),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(starIconFor(i, rating),
                size: size, color: AppTheme.star),
          const SizedBox(width: 6),
          Text(
            pinned.toStringAsFixed(1),
            style: AppTheme.ratingValue(size),
          ),
          if (shown != null) ...[
            const SizedBox(width: 4),
            Text('($shown)',
                style: AppTheme.ratingCount(size)),
          ],
        ],
      ),
    );
  }
}

/// Round initial avatar — used where we have no profile photo.
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;

  const InitialAvatar({super.key, required this.name, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final initial = Monogram.of(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppTheme.navy,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTheme.monogram(size),
          fontWeight: FontWeight.w700,
          color: AppTheme.onNavy,
        ),
      ),
    );
  }
}

/// Friendly empty / error state with an icon, message and optional action.
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool danger;

  /// The action button defaults to a retry icon; a state whose action is not a
  /// retry (e.g. "clear the search") passes its own so the button does not lie.
  final IconData actionIcon;

  /// Colour of the title line, for a state whose heading itself is the message.
  ///
  /// [danger] already tints the icon and the disc behind it, which is enough
  /// when there is a body under the title to explain the situation. When the
  /// title *is* the whole message — «تعذّر تحميل العروض» — it is the only text
  /// that changed on the screen, so it is the only text that can carry the
  /// meaning: read in [AppTheme.textPrimary] it sits in the same voice as every
  /// ordinary heading on the page. Null keeps the previous behaviour.
  final Color? titleColor;

  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.danger = false,
    this.actionIcon = Icons.refresh_rounded,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: danger ? AppTheme.dangerWash : AppTheme.lineSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 44,
                  color: danger ? AppTheme.danger : AppTheme.textMuted),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.h2
                  .copyWith(color: titleColor ?? AppTheme.textPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTheme.bodySoft,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              PrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
                icon: actionIcon,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sticky bottom action bar so the primary action is never below the fold.
class StickyCta extends StatelessWidget {
  final Widget child;

  const StickyCta({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      // `18` here is `AppTheme.gutter` and always was — this is a **rename,
      // zero pixels**, not a move. It is worth recording *why* it is not a
      // column question like `SectionTitle`'s: a sticky bar owns the full
      // screen width and has no caller edge to join, so its inset is the page
      // gutter by definition rather than by inheritance. And all four callers
      // already sit on 18 — `project_detail` via `AppTheme.pagePad`,
      // `project_new` via `AppTheme.gutter`, `profile_edit` and
      // `worker_profile` through `fromLTRB(18, …)` — which is why a 2 dp
      // change here would have shown up as the button moving relative to the
      // button above it. Naming it stops the fifth writer from retyping it.
      padding: const EdgeInsets.fromLTRB(
          AppTheme.gutter, AppTheme.s12, AppTheme.gutter, AppTheme.s12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// Label + value row with a leading icon (worker profile, project facts).
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppTheme.navy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.lineSoft,
              borderRadius: BorderRadius.circular(AppTheme.rSm),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTheme.caption),
                const SizedBox(height: 2),
                Text(value,
                    style: AppTheme.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Grey shimmer block used while lists load.
class SkeletonBox extends StatelessWidget {
  final double height;
  final double width;
  final double radius;

  /// Defaults to the old soft grey so existing screens keep their look; the
  /// skeleton kit passes its slightly darker [SkeletonTone.base] so the sweep
  /// highlight is actually visible over it.
  final Color color;

  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius = 8,
    this.color = AppTheme.lineSoft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}


/// One line of copy that **reserves no height when it has nothing to say**.
///
/// Every count in this app is honest about a value it cannot print: a zero, a
/// missing field, a duration the contractor never typed all answer `''` rather
/// than «0 صور» or a gap. That contract is right, and the copy files document
/// it at length. It is the *caller* that has to act on the answer, and that is
/// where the copy audit stopped.
///
/// **The cost is measured, not assumed.** `Text('')` inside a `Column` still
/// builds a line box: the `Text` has a non-zero font size, so the framework
/// sizes a strut to the line height and the empty paragraph occupies
/// **20 px at `fontSize: 14, height: 1.4`**. Probed on this exact device
/// config — two lines measure 40 px, the same two lines with an empty `Text`
/// between them measure 60 px. In a `Row` the same empty `Text` costs nothing,
/// because there is no cross-axis strut to reserve. So the hole is a *vertical*
/// one and only a vertical one, and it is exactly the defect the guarded
/// sentences went to such lengths to remove: the string is whole, the analyzer
/// is happy, the unit test on the copy function passes — and the screen shows a
/// band of nothing where a line of Arabic should be.
///
/// Every site this fixes had its own copy call, its own style and its own
/// `SizedBox` between siblings, and each of them would need the same
/// `if (line.isNotEmpty) ...[SizedBox, Text]` dance spelled out again. The
/// failure this file exists to stop is *a second copy of the thing that lacked
/// the guard* — so the guard is one widget and the empty string decides.
///
/// The widget is deliberately dumb: it does not decide what an empty string
/// means, does not substitute a fallback, and does not warn. Substituting is
/// how a hole gets papered over instead of fixed, and the copy files already own
/// the decision of what is worth saying.
class CopyLine extends StatelessWidget {
  /// The Arabic sentence. An empty string draws nothing at all.
  final String text;

  final TextStyle? style;

  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Key? copyKey;

  /// Gap above this line, in logical pixels.
  ///
  /// Applied **only when the line renders**, which is the whole point: a
  /// `const SizedBox(height: 2)` left as a sibling of a `Text('')` is itself
  /// 2 px of nothing, and the leading gap is the half of this defect that is
  /// easiest to miss because it lives outside the widget that causes it.
  final double gapAbove;

  const CopyLine(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.textDirection,
    this.copyKey,
    this.gapAbove = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      // `only` so a zero gap adds no padding object at all.
      padding: gapAbove > 0 ? EdgeInsets.only(top: gapAbove) : EdgeInsets.zero,
      child: Text(
        text,
        key: copyKey,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        textDirection: textDirection,
      ),
    );
  }
}
