import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Chip filter pill (radius 20) dengan status aktif ber-tint. Dipakai bar
/// filter list Pesan (user) & Terhapus (admin).
class FilterChipPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color color;
  /// Bila diisi, label ditampilkan "label (count)".
  final int? count;

  const FilterChipPill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.color = AppTheme.primary,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final text = count == null ? label : '$label ($count)';
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.18) : AppTheme.bgInput,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.7) : AppTheme.divider,
          ),
        ),
        child: Text(
          text,
          style: AppText.label.copyWith(
            color: active ? color : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
