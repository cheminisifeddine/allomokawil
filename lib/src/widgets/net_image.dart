import 'package:flutter/material.dart';

/// A network photo decoded at the size it is actually drawn at.
///
/// `Image.network` without `cacheWidth` hands the file to the codec whole: a
/// photo this API serves comes back 1024x1024, the codec expands it to 4 MB of
/// ARGB, and the image cache keeps those 4 MB alive per distinct URL for as
/// long as the screen lives. A project thumbnail drawn 76x76 was still costing
/// 4 MB, and a contractor's 3-wide portfolio grid costs 12 MB for tiles closer
/// to 110 px than to 1024 — on the cheap 2 GB phones this market actually runs
/// on, that is the difference between scrolling the gallery and being OOM-killed
/// back to the home screen.
///
/// The decode is sized from the box the image really occupies, so it cannot
/// drift out of step with the layout the way a hardcoded pixel number would:
/// an explicit [width] wins, otherwise the laid-out size is read off the
/// constraints. A photo the user opened to see in full passes neither and is
/// decoded at full resolution, which is the only case where that is correct.
///
/// Failure is unchanged: [errorBuilder] still gets every error and a broken
/// URL still renders the caller's own fallback.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.semanticLabel,
    this.fit = BoxFit.cover,
    this.excludeFromSemantics = false,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String url;

  /// Drawn size, in logical pixels, when the caller knows it up front.
  final double? width;
  final double? height;
  final String? semanticLabel;
  final BoxFit fit;
  final bool excludeFromSemantics;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  /// The smallest decode we will ever ask for.
  ///
  /// Under this a second codec pass costs more than the pixels save, and a 46 px
  /// avatar fetched at 46 px on a 3x screen would just be an upscaled blur.
  static const int minDecodePx = 160;

  /// The physical-pixel decode width for a photo drawn [logical] logical
  /// pixels wide, or null when the caller did not size the image and the full
  /// resolution is what was asked for.
  ///
  /// `cacheWidth` counts physical pixels, so the honest number is the drawn
  /// size times the device pixel ratio — capped at the photo's own width,
  /// because asking a codec for more pixels than the file has is wasted work.
  /// Pure, so the arithmetic is testable without pumping a widget.
  static int? decodeWidth({
    required double? logical,
    required double pixelRatio,
    int? sourceWidth,
    int floorPx = minDecodePx,
  }) {
    if (logical == null || !logical.isFinite || logical <= 0) return null;
    final wanted = logical * (pixelRatio.isFinite && pixelRatio > 0 ? pixelRatio : 1.0);
    if (!wanted.isFinite) return null;
    var px = wanted.ceil();
    if (px < floorPx) px = floorPx;
    if (sourceWidth != null && sourceWidth > 0 && px > sourceWidth) {
      px = sourceWidth;
    }
    return px;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final explicit = decodeWidth(logical: width, pixelRatio: dpr);
    Image networkImage(int? cacheWidth) => Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          semanticLabel: semanticLabel,
          excludeFromSemantics: excludeFromSemantics,
          cacheWidth: cacheWidth,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        );
    if (explicit != null) return networkImage(explicit);
    // No size given: read the box the layout actually produced, and only if it
    // is bounded. Unbounded means "as wide as it likes" (a fullscreen viewer),
    // where downscaling the source would be the bug, not the fix.
    return LayoutBuilder(
      builder: (context, constraints) {
        final measured = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : (constraints.hasBoundedHeight ? constraints.maxHeight : null);
        return networkImage(decodeWidth(logical: measured, pixelRatio: dpr));
      },
    );
  }
}
