import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/worker.dart';
import 'rating_stars.dart';

/// Horizontal contractor card (top-rated strip on customer home).
class WorkerCard extends StatelessWidget {
  final WorkerProfile worker;
  final VoidCallback? onTap;

  const WorkerCard({super.key, required this.worker, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E7E3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFFE0E5F0),
              backgroundImage:
                  worker.avatarUrl != null ? NetworkImage(worker.avatarUrl!) : null,
              child: worker.avatarUrl == null
                  ? Text(worker.fullName.isEmpty
                      ? '؟'
                      : worker.fullName.characters.first)
                  : null,
            ),
            const SizedBox(height: 10),
            Text(worker.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              worker.specialties.isEmpty
                  ? 'عمال'
                  : worker.specialties.first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                RatingStars(rating: worker.avgRating, size: 14),
                const SizedBox(width: 4),
                Text('(${worker.totalReviews})',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6E6E73))),
              ],
            ),
            if (worker.verificationStatus == VerificationStatus.verified) ...[
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.verified, size: 14, color: Color(0xFF2E7D32)),
                  SizedBox(width: 4),
                  Text('موثّق',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}