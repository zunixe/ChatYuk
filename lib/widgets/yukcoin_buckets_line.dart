import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../utils.dart' show formatPoints;

/// Rincian saldo YukCoin per jenis — dulu kartu hanya menampilkan total,
/// sehingga user mengira koin bonus bisa dipakai untuk semua fitur.
///  * Bonus      → fee match & 30 detik pertama call.
///  * Isi ulang  → semua fitur berbayar.
///  * Penghasilan (hanya bila ada) → bisa ditarik (female).
/// Widget murni (tanpa provider) — dipakai header & dites tanpa ProviderScope.
class YukcoinBucketsText extends StatelessWidget {
  final S s;
  final int bonus;
  final int topup;
  final int earned;
  final bool showHint;
  final Color onColor;

  const YukcoinBucketsText({
    super.key,
    required this.s,
    required this.bonus,
    required this.topup,
    required this.earned,
    this.showHint = true,
    this.onColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final parts = [
      '${s.walletBonus} ${formatPoints(bonus)}',
      '${s.walletPaid} ${formatPoints(topup)}',
      if (earned > 0) '${s.walletEarned} ${formatPoints(earned)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          parts.join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.caption.copyWith(color: onColor.withValues(alpha: 0.9)),
        ),
        if (showHint) ...[
          const SizedBox(height: 2),
          Text(
            s.walletBucketsHint,
            style: AppText.caption.copyWith(color: onColor.withValues(alpha: 0.75)),
          ),
        ],
      ],
    );
  }
}

/// Versi yang membaca saldo dari [pointsProvider] (kartu profil).
class YukcoinBucketsLine extends ConsumerWidget {
  final bool showHint;
  const YukcoinBucketsLine({super.key, this.showHint = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(
      pointsProvider.select(
        (p) => (bonus: p.bonusBalance, topup: p.topupBalance, earned: p.earnedBalance),
      ),
    );
    return YukcoinBucketsText(
      s: ref.watch(localeProvider).s,
      bonus: b.bonus,
      topup: b.topup,
      earned: b.earned,
      showHint: showHint,
    );
  }
}
