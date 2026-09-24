import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Card putih standar untuk section admin.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: child,
    );
  }
}

/// Kartu section sheet AI: judul + badge + deskripsi + isi.
class AiSectionCard extends StatelessWidget {
  final String title;
  final String? badge;
  final bool badgeOn;
  final String? desc;
  final Widget child;
  const AiSectionCard({
    super.key,
    required this.title,
    this.badge,
    this.badgeOn = false,
    this.desc,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: AppText.bodyStrong),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeOn
                        ? AppTheme.primary
                        : AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge!,
                    style: AppText.label.copyWith(
                      color: badgeOn ? Colors.white : AppTheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          if (desc != null) ...[
            const SizedBox(height: 4),
            Text(
              desc!,
              style:
                  AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// Sub-blok di dalam section Lanjutan: label kecil + isi.
class AiSubBlock extends StatelessWidget {
  final String label;
  final Widget child;
  const AiSubBlock({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
