import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/motion.dart';
import 'ui.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  Skeleton kit — the shape of the content, shown while it loads.
///
///  A grey circle in the middle of an empty page reads as "broken" to a
///  first-time user; a card-sized grey block where the card will land reads as
///  "arriving", which is the truth. Every recipe here mirrors the real geometry
///  of the screen it stands in for — same paddings, same radii, same card
///  recipe — so the content replaces the skeleton without a layout jump.
///
///  One [Shimmer] wraps a whole screen of blocks: the sweep costs a single
///  animation controller per screen, not one per box.
/// ─────────────────────────────────────────────────────────────────────────

/// Kill switch for the sweep.
///
/// A perpetual animation means `pumpAndSettle` never returns, so a widget test
/// that wants a settled tree turns this off instead of fighting the clock.
class SkeletonMotion {
  SkeletonMotion._();

  static bool enabled = true;
}

/// The two greys of the kit. The base is deliberately a step darker than
/// [AppTheme.lineSoft] so the white sweep travelling over it is visible.
class SkeletonTone {
  SkeletonTone._();

  static const Color base = Color(0xFFE5E2DB);
  static const Color highlight = Color(0x8CFFFFFF);
}

/// Sweeps a soft highlight across every skeleton block beneath it.
class Shimmer extends StatefulWidget {
  final Widget child;

  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: AppMotion.shimmer,
  );

  @override
  void initState() {
    super.initState();
    _sweep.repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Excluded from the semantics tree: a screen reader should hear the page
    // arrive, not "grey box, grey box, grey box".
    final tree = ExcludeSemantics(child: widget.child);

    // Honour the OS "reduce motion" setting — for those users the blocks stay
    // still rather than pulsing behind their eyes.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!SkeletonMotion.enabled || reduceMotion) return tree;

    return AnimatedBuilder(
      animation: _sweep,
      child: tree,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment(-1.8 + 3.6 * _sweep.value, 0),
          end: Alignment(-0.8 + 3.6 * _sweep.value, 0),
          colors: const [
            Color(0x00FFFFFF),
            SkeletonTone.highlight,
            Color(0x00FFFFFF),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
        child: child,
      ),
    );
  }
}

/// Text-line sized block. Everything in the kit is built from these.
class SkeletonBar extends StatelessWidget {
  final double height;
  final double width;
  final double radius;

  const SkeletonBar({
    super.key,
    this.height = 12,
    this.width = double.infinity,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) => SkeletonBox(
        height: height,
        width: width,
        radius: radius,
        color: SkeletonTone.base,
      );
}

/// A white bordered card of stacked bars — the block that stands in for any
/// [AppCard] whose content is text.
class SkeletonCard extends StatelessWidget {
  final int rows;

  const SkeletonCard({super.key, this.rows = 3});

  @override
  Widget build(BuildContext context) {
    const widths = <double>[double.infinity, 210, 150, 180, 120];
    return Container(
      padding: AppTheme.cardPadRows,
      decoration: AppTheme.cardDecoration,
      child: Column(
        children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppTheme.lineSoft),
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: SkeletonTone.base,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SkeletonBar(
                      width: widths[i % widths.length],
                      height: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Thumbnail-plus-text cards: the contractor directory and the project feeds.
class SkeletonCardList extends StatelessWidget {
  final int count;
  final double thumb;

  const SkeletonCardList({super.key, this.count = 4, this.thumb = 62});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        itemCount: count,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: AppTheme.cardPad,
          decoration: AppTheme.cardDecoration,
          child: Row(
            children: [
              SkeletonBox(
                height: thumb,
                width: thumb,
                radius: AppTheme.rSm,
                color: SkeletonTone.base,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBar(width: 158, height: 15),
                    SizedBox(height: 10),
                    SkeletonBar(width: 104, height: 11),
                    SizedBox(height: 10),
                    SkeletonBar(width: 72, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three-column photo grid with a header row — the contractor's gallery.
class SkeletonGrid extends StatelessWidget {
  final int count;

  const SkeletonGrid({super.key, this.count = 9});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            children: [
              const Row(
                children: [
                  SkeletonBar(width: 132, height: 15),
                  Spacer(),
                  SkeletonBar(width: 54, height: 15),
                ],
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (var i = 0; i < count; i++)
                    const SkeletonBox(
                      height: double.infinity,
                      radius: AppTheme.rMd,
                      color: SkeletonTone.base,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Photo banner, title, status pills, then the detail cards.
class SkeletonDetailPage extends StatelessWidget {
  const SkeletonDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: AppTheme.pagePad,
            children: const [
              SkeletonBox(
                height: 196,
                radius: AppTheme.rLg,
                color: SkeletonTone.base,
              ),
              SizedBox(height: 18),
              SkeletonBar(width: 224, height: 20),
              SizedBox(height: 14),
              Row(
                children: [
                  SkeletonBar(width: 96, height: 28, radius: 999),
                  SizedBox(width: 8),
                  SkeletonBar(width: 96, height: 28, radius: 999),
                ],
              ),
              SizedBox(height: 26),
              SkeletonBar(width: 120, height: 14),
              SizedBox(height: 10),
              SkeletonCard(rows: 3),
              SizedBox(height: 24),
              SkeletonBar(width: 144, height: 14),
              SizedBox(height: 10),
              SkeletonCard(rows: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Field-height blocks — profile edit and the verification upload form.
class SkeletonFormPage extends StatelessWidget {
  final int fields;

  const SkeletonFormPage({super.key, this.fields = 3});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              const SkeletonBar(width: 118, height: 14),
              const SizedBox(height: 12),
              for (var i = 0; i < fields; i++) ...[
                const SkeletonBox(
                  height: AppTheme.tapMin,
                  radius: AppTheme.rMd,
                  color: SkeletonTone.base,
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              const SkeletonBar(width: 148, height: 14),
              const SizedBox(height: 12),
              const SkeletonBox(
                height: 108,
                radius: AppTheme.rLg,
                color: SkeletonTone.base,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bubbles on both sides, so the thread reads as a conversation before the
/// messages exist.
class SkeletonChatThread extends StatelessWidget {
  const SkeletonChatThread({super.key});

  @override
  Widget build(BuildContext context) {
    // Varied widths: a wall of equal bars reads as a table, not as speech.
    const widths = <double>[176, 240, 124, 208, 150, 96];
    return Shimmer(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        itemCount: widths.length,
        itemBuilder: (_, i) {
          final mine = i.isOdd;
          return Align(
            alignment:
                mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
            child: Container(
              width: widths[i],
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: mine ? AppTheme.accentWash : AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border: Border.all(color: mine ? AppTheme.accentWash : AppTheme.line),
              ),
              child: SkeletonBar(height: mine ? 13 : 12),
            ),
          );
        },
      ),
    );
  }
}

/// Tall rows with a leading mark and two lines — the commune/wilaya picker.
/// Height matches the real `ListTile` (icon + name + latin name) so the sheet
/// does not jump when the list arrives.
class SkeletonRowList extends StatelessWidget {
  final int count;

  const SkeletonRowList({super.key, this.count = 7});

  @override
  Widget build(BuildContext context) {
    const widths = <double>[150, 188, 132, 170, 206, 142, 178, 122];
    return Shimmer(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
        itemCount: count,
        itemBuilder: (_, i) => SizedBox(
          height: 72,
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: SkeletonTone.base,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBar(width: widths[i % widths.length], height: 14),
                    const SizedBox(height: 9),
                    const SkeletonBar(width: 88, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first paint of the app, while the stored session restores.
///
/// The restore takes a few frames; showing the shape of a home screen means the
/// app never opens on a grey circle — it opens looking like the product.
class AppBootSkeleton extends StatelessWidget {
  const AppBootSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ColoredBox(
        color: AppTheme.bg,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
            children: const [
              Row(
                children: [
                  SkeletonBox(
                    height: 34,
                    width: 34,
                    radius: 999,
                    color: SkeletonTone.base,
                  ),
                  SizedBox(width: 10),
                  SkeletonBar(width: 132, height: 16),
                  Spacer(),
                  SkeletonBox(
                    height: 34,
                    width: 34,
                    radius: 999,
                    color: SkeletonTone.base,
                  ),
                ],
              ),
              SizedBox(height: 26),
              SkeletonBox(
                height: 172,
                radius: AppTheme.rXl,
                color: SkeletonTone.base,
              ),
              SizedBox(height: 22),
              SkeletonBar(width: 152, height: 15),
              SizedBox(height: 12),
              SkeletonCard(rows: 2),
              SizedBox(height: 22),
              SkeletonBar(width: 120, height: 15),
              SizedBox(height: 12),
              SkeletonCard(rows: 2),
            ],
          ),
        ),
      ),
    );
  }
}
