import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Kartu skeleton placeholder untuk list user (dipakai saat loading).
/// Dipakai di OnlineUsersScreen & skeleton loading screen auth.
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 64});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.divider,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 14,
                width: 120,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 11,
                width: 180,
                decoration: BoxDecoration(
                  color: AppTheme.divider.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// ListView berisi beberapa SkeletonCard — placeholder list saat loading.
/// Taxan dipakai semua screen (online users, chat list, timeline, rooms).
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsets padding;
  const SkeletonList({super.key, this.count = 6, this.padding = const EdgeInsets.fromLTRB(10, 8, 10, 12)});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: count,
      itemBuilder: (_, __) => const SkeletonCard(),
    );
  }
}
