import 'package:flutter/material.dart';

/// Compact 5-star rating display used across search, profiles & reviews.
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;

  const RatingStars({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final filled = rating.round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: i < filled ? const Color(0xFFE0A458) : const Color(0xFFD5D5D9),
        );
      }),
    );
  }
}