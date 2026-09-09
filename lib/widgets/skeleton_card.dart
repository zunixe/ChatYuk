import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Kartu skeleton placeholder untuk list user (dipakai saat loading).
/// Dipakai di OnlineUsersScreen & skeleton loading screen auth.
///
/// TANPA background kotak — dulu pakai bgCard (putih di light mode /
/// abu di dark mode) yang terlihat sebagai "kotak putih/abu menutupi
/// list". Sekarang hanya bentuk placeholder (lingkaran + garis) dengan
/// tint primary tipis, menyatu dengan bgScreen → nol kotak.
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 64});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
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
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 11,
                width: 180,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 11,
              width: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
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

/// Skeleton bentuk POST timeline (bukan baris user): header avatar+nama,
/// 2 baris caption, kotak foto, baris aksi. Bahasa visual sama dengan
/// SkeletonCard (tanpa background kotak, tint primary tipis di bgScreen).
class PostSkeletonCard extends StatelessWidget {
  const PostSkeletonCard({super.key});

  Widget _bar(double w, double h, double r, double alpha) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(r),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(120, 14, 6, 0.10),
                  const SizedBox(height: 6),
                  _bar(80, 11, 6, 0.08),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _bar(double.infinity, 14, 6, 0.10),
          const SizedBox(height: 6),
          _bar(220, 11, 6, 0.08),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _bar(64, 16, 8, 0.08),
            const SizedBox(width: 16),
            _bar(64, 16, 8, 0.08),
            const SizedBox(width: 16),
            _bar(64, 16, 8, 0.08),
          ]),
        ],
      ),
    );
  }
}

/// ListView berisi beberapa PostSkeletonCard — placeholder feed timeline.
class PostSkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsets padding;
  const PostSkeletonList(
      {super.key,
      this.count = 3,
      this.padding = const EdgeInsets.only(top: 4, bottom: 88)});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: count,
      itemBuilder: (_, __) => const PostSkeletonCard(),
    );
  }
}
