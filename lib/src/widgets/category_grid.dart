import 'package:flutter/material.dart';

import '../data/taxonomy.dart';

/// Horizontal scrollable strip of service categories — big tiles,
/// emoji + Arabic label, tap target comfortably large for low-literacy users.
class CategoryGrid extends StatelessWidget {
  final void Function(String slug)? onTap;

  const CategoryGrid({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: Taxonomy.categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = Taxonomy.categories[i];
          return _Tile(
            icon: c.icon,
            label: c.name,
            onTap: onTap == null ? null : () => onTap!(c.slug),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;

  const _Tile({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8E7E3)),
    );
    final tile = Container(
      width: 88,
      decoration: b,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, height: 1.2),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: tile);
  }
}