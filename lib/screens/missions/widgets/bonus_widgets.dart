import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Widget halaman Bonus (ala Vava) — grid sign-in 7 hari + baris tugas.
/// Semua ukuran memakai token `AppText`/`AppTextSize` (tanpa fontSize
/// mentah) sesuai AGENTS.md.

/// Reward sign-in per hari siklus — cermin `streak_bonus_amount` server.
const List<int> kStreakRewards = [25, 30, 35, 40, 45, 50, 100];

/// Kartu satu hari di grid sign-in.
/// [state]: 0 = future (biasa), 1 = klaim hari ini (highlight), 2 = claimed.
/// [dayLabel] label hari dari `S` (bilingual — jangan hardcode).
class BonusDayCard extends StatelessWidget {
  final int day;
  final int coins;
  final int state;
  final String dayLabel;
  const BonusDayCard({
    super.key,
    required this.day,
    required this.coins,
    required this.state,
    required this.dayLabel,
  });

  @override
  Widget build(BuildContext context) {
    final active = state == 1;
    final claimed = state == 2;
    return Container(
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF42A5F5), Color(0xFF1976D2)],
              )
            : null,
        color: active ? null : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: active
            ? null
            : Border.all(color: AppTheme.divider.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pill status di atas kartu (ala Vava): centang abu = claimed,
          // centang hijau = hari ini.
          Container(
            width: 34,
            height: 16,
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.onlineDark
                  : claimed
                  ? AppTheme.divider
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: claimed || active
                ? const Icon(Icons.check_rounded,
                    size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 3),
          Text(
            dayLabel,
            style: AppText.caption.copyWith(
              color: active ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Icon(
            Icons.monetization_on_rounded,
            size: 22,
            color: active
                ? Colors.white
                : claimed
                ? AppTheme.divider
                : AppTheme.idle,
          ),
          const SizedBox(height: 2),
          Text(
            '+$coins',
            style: AppText.caption.copyWith(
              color: active
                  ? Colors.white
                  : claimed
                  ? AppTheme.divider
                  : AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris tugas (Beginner/Daily) gaya Vava: judul + progres + reward + aksi.
/// [claimLabel] dari `S` (bilingual — jangan hardcode).
class BonusTaskRow extends StatelessWidget {
  final String title;
  final String progressLabel;
  final int rewardCoins;
  final bool claimed;
  final bool locked;
  final String claimLabel;
  final VoidCallback? onClaim;
  const BonusTaskRow({
    super.key,
    required this.title,
    required this.progressLabel,
    required this.rewardCoins,
    required this.claimed,
    required this.claimLabel,
    this.locked = false,
    this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final canClaim = onClaim != null && !claimed && !locked;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (progressLabel.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        progressLabel,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      size: 15,
                      color: AppTheme.idle,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '+$rewardCoins',
                      style: AppText.caption.copyWith(
                        color: claimed
                            ? AppTheme.divider
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (claimed)
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.onlineDark.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.check_rounded,
                size: 17,
                color: AppTheme.onlineDark,
              ),
            )
          else if (canClaim)
            FilledButton(
              onPressed: onClaim,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(72, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(
                claimLabel,
                style: AppText.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                locked ? Icons.lock_outline : Icons.arrow_forward_rounded,
                size: 15,
                color: AppTheme.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
