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
      // The action is 56 dp tall now, so the band only grows 11 dp instead of
      // 25: 10 + 56 + 4 = 70 against 18 + 30.9 + 10 = 58.9 before.
      //
      // **The horizontal `2` was an optical guess from the design overhaul and
      // it never had a caller that asked for it.** It has 25 call sites across
      // eight screens, and every one of them already owns the left edge: four
      // wrap this widget in their own `Padding(horizontal: 16)` / `gutter`, and
      // the other 21 sit inside a list that carries `pagePad` or `s16`. So the
      // heading sat 2 dp inside the band that introduces it on **all 25**, and
      // the three customer-home titles — the only ones measured, because
      // `customer_home_column_test.dart` reads the *band* rather than the text —
      // were the only three anybody had ever looked at.
      //
      // It is now `0`, and that is the whole slice: the heading joins the edge
      // it introduces. **The vertical is untouched on purpose** — `10` is
      // off-grid but it is not decoration, it is the arithmetic that keeps a
      // 56 dp tap target inside a 70 dp band (`10 + 56 + 4`), settled and
      // measured by the a11y tick. Re-griddding it in a slice about the
      // horizontal would move every heading on eight screens to settle a
      // question that is not this tick's, so the two remaining literals are
      // left counted and recorded rather than swept.
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
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
        side: const BorderSide(color: AppTheme.controlLine, width: 1.5),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Taxonomy.categoryIcon(slug), size: 14, color: tint),
          const SizedBox(width: 6),
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentWash : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: selected ? AppTheme.navy : AppTheme.line,
              width: selected ? 2 : 1,
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
                  style: AppTheme.label.copyWith(
                    fontSize: AppTheme.fsCaption,
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

  const StatusPill({
    super.key,
    required this.label,
    this.color = AppTheme.info,
    this.wash = AppTheme.infoWash,
    this.icon,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: AppTheme.label.copyWith(fontSize: AppTheme.fsCaption, color: color)),
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
