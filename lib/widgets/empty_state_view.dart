import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Empty state bersama seluruh app — komposisi lingkaran tint + ikon
/// Material (BUKAN emoji, konsisten dengan timeline). Judul + hint +
/// aksi opsional (FilledButton) atau petunjuk "Ketuk +".
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(
                  icon,
                  size: 48,
                  color: AppTheme.primary,
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(title, style: AppText.bodyStrong, textAlign: TextAlign.center),
            SizedBox(height: 6),
            Text(
              hint,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
