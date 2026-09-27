import 'package:flutter/material.dart';
import '../../../config/strings.dart';
import '../../../config/theme.dart';

/// Header saldo YukCoin: satu angka besar + tombol top-up (Play only).
class YukcoinHeader extends StatelessWidget {
  final S s;
  final int total;
  final bool showTopup;

  const YukcoinHeader({
    super.key,
    required this.s,
    required this.total,
    this.showTopup = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primary.withValues(alpha: 0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.monetization_on_outlined,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                s.yukcoinMyBalance,
                style: AppText.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$total',
            style: AppText.display.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            s.yukcoinTitle,
            style: AppText.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          if (showTopup) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  // Fase top-up Google Play: tombol disiapkan, aksi menyusul.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.yukcoinTopupSoon)),
                  );
                },
                icon: const Icon(Icons.add_circle_outline, size: 20),
                label: Text(s.yukcoinTopup),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
