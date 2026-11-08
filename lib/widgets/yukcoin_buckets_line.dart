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

  /// true = kotak per jenis koin (kartu YukCoin); false = satu baris ringkas
  /// (kartu profil yang sempit).
  final bool tiles;

  /// false = user tidak bisa top-up (female): bucket `Isi ulang` memang
  /// tidak ada untuknya — `Bonus` & `Penghasilan` tetap tampil.
  final bool canTopup;

  const YukcoinBucketsText({
    super.key,
    required this.s,
    required this.bonus,
    required this.topup,
    required this.earned,
    this.showHint = true,
    this.onColor = Colors.white,
    this.tiles = true,
    this.canTopup = true,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      if (canTopup) (label: s.walletPaid, value: topup),
      // Female (tanpa top-up): Penghasilan = saldo utamanya → selalu tampil;
      // Bonus hampir tak pernah ia punya → hanya bila > 0.
      if (earned > 0 || !canTopup) (label: s.walletEarned, value: earned),
      if (canTopup || bonus > 0) (label: s.walletBonus, value: bonus),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    // Hint menjelaskan mekanik top-up/bonus — tak relevan untuk female.
    final hint = showHint && canTopup
        ? Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.info_outline,
                    size: 14,
                    color: onColor.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.walletBucketsHint,
                    style: AppText.caption.copyWith(
                      color: onColor.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;
    if (!tiles) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wrap: tiap jenis koin utuh, pindah baris bila sempit (tidak "…").
          Wrap(
            spacing: 10,
            children: [
              for (final e in items)
                Text(
                  '${e.label} ${formatPoints(e.value)}',
                  style: AppText.caption.copyWith(
                    color: onColor.withValues(alpha: 0.9),
                  ),
                ),
            ],
          ),
          ?hint,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: onColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: onColor.withValues(alpha: 0.85),
                        ),
                      ),
                      Text(
                        formatPoints(items[i].value),
                        maxLines: 1,
                        style: AppText.bodyStrong.copyWith(color: onColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        ?hint,
      ],
    );
  }
}

/// Versi yang membaca saldo dari [pointsProvider] (kartu profil).
class YukcoinBucketsLine extends ConsumerWidget {
  final bool showHint;

  /// true = kotak per jenis koin; false = satu baris ringkas.
  final bool tiles;

  /// false = user tidak bisa top-up (female) — `Isi ulang` disembunyikan.
  final bool canTopup;

  const YukcoinBucketsLine({
    super.key,
    this.showHint = true,
    this.tiles = false,
    this.canTopup = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(
      pointsProvider.select(
        (p) => (
          bonus: p.bonusBalance,
          topup: p.topupBalance,
          earned: p.earnedBalance,
        ),
      ),
    );
    return YukcoinBucketsText(
      s: ref.watch(localeProvider).s,
      bonus: b.bonus,
      topup: b.topup,
      earned: b.earned,
      showHint: showHint,
      tiles: tiles,
      canTopup: canTopup,
    );
  }
}
