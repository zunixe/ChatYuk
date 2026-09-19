import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Chip aksi di header chat — pill bertint warna primary dengan ikon + label.
///
/// Pola tampilan sama dengan chip "Mulai broadcast" grup, dipakai juga di
/// private chat supaya tombol header konsisten antar layar.
class ChatHeaderActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final Color? color;

  const ChatHeaderActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: loading ? 0.25 : 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, color: c, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppText.label.copyWith(
                color: c.withValues(alpha: loading ? 0.6 : 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
