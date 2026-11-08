import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme.dart';
import '../../../config/gifts.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/points_provider.dart';
import '../../../providers/riverpod/match_pricing_provider.dart';
import '../../../config/strings.dart';

/// Section "Cara dapat" & "Cara pakai YukCoin". Harga diambil dari provider
/// (default sesuai migration; sumber kebenaran tetap server).
class YukcoinHowTo extends ConsumerWidget {
  final S s;
  final bool v2Active;
  final bool ghostActive;

  const YukcoinHowTo({
    super.key,
    required this.s,
    this.v2Active = false,
    this.ghostActive = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // PERF: `select` record field harga (value-type) — dulu `watch` penuh →
    // widget rebuild tiap PointsProvider notify (saldo/pricing sering).
    // Hanya harga call/video yang ditampilkan (fitur lain gratis).
    final mp = ref.matchPricing;
    final pp = ref.watch(
      pointsProvider.select(
        (p) => (
          callAudio: p.callAudioCostPerMin,
          callVideo: p.callVideoCostPerMin,
        ),
      ),
    );
    // Female tidak top-up dan tidak pernah ditagih: yang relevan untuknya
    // hanya "Cara dapat" (income). Male melihat keduanya + harga.
    final gender = ref.watch(authProvider.select((a) => a.profile?.gender));
    // Gender belum termuat → jangan tebak (bisa salah tampilkan versi male).
    if (gender != 'male' && gender != 'female') return const SizedBox.shrink();
    final isFemale = gender == 'female';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(s.yukcoinHowToEarn),
        _card(
          children: [
            if (isFemale) ...[
              _row(
                Icons.call_outlined,
                s.yukcoinEarnCallAudio,
                '',
                note: s.yukcoinEarnCallNote,
              ),
              _row(
                Icons.videocam_outlined,
                s.yukcoinEarnCallVideo,
                '',
                note: s.yukcoinEarnCallNote,
              ),
              _row(
                Icons.people_outline,
                s.yukcoinEarnMatch,
                '',
                note: s.yukcoinEarnMatchNote,
              ),
              _row(
                Icons.card_giftcard,
                s.yukcoinEarnGift,
                '',
                note: s.yukcoinGiftNote,
              ),
              _row(
                Icons.flag_outlined,
                s.yukcoinEarnMission,
                '',
                note: s.yukcoinEarnMissionNote,
              ),
              _row(
                Icons.account_balance_wallet_outlined,
                s.yukcoinCashOut,
                '',
                note: s.yukcoinCashOutNote,
              ),
              _row(
                Icons.auto_awesome_outlined,
                s.yukcoinFemaleAllFree,
                '',
                note: s.yukcoinFemaleAllFreeNote,
              ),
            ] else ...[
              // Top-up hanya untuk male (female menerima koin, bukan beli).
              _row(Icons.add_circle_outline, s.yukcoinEarnTopup, ''),
              _row(Icons.card_giftcard, s.yukcoinEarnWelcome, ''),
              _row(
                Icons.event_available_outlined,
                s.yukcoinEarnLogin,
                '',
                note: s.yukcoinEarnLoginNote,
              ),
              _row(
                Icons.redeem,
                s.yukcoinEarnGift,
                '',
                note: s.yukcoinGiftNote,
              ),
            ],
          ],
        ),
        if (!isFemale) _sectionTitle(s.yukcoinHowToSpend),
        if (!isFemale)
          _card(
            children: [
              _row(
                Icons.call_outlined,
                s.yukcoinFeatureCallAudio,
                '${pp.callAudio}',
                trailing: s.yukcoinPerMin,
              ),
              _row(
                Icons.videocam_outlined,
                s.yukcoinFeatureCallVideo,
                '${pp.callVideo}',
                trailing: s.yukcoinPerMin,
              ),
              _row(
                Icons.people_outline,
                s.yukcoinFeatureMatch,
                '${mp.searchCoins}',
                trailing: s.yukcoinPerMatch,
                note: '${s.yukcoinMatchNote} ${s.yukcoinMatchPerMinNote(pp.callVideo, mp.freeSeconds, mp.connectCoins)}',
              ),
              _row(
                Icons.card_giftcard,
                s.yukcoinFeatureGift,
                '${kGiftCatalog.first.coins}–${kGiftCatalog.last.coins}',
                trailing: s.yukcoinPerGift,
                note: s.yukcoinGiftNote,
              ),
              // Filter gender & cari orang sekitar GRATIS (2026-10-31).
            ],
          ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      text,
      style: AppText.label.copyWith(color: AppTheme.textSecondary),
    ),
  );

  Widget _card({required List<Widget> children}) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.divider),
    ),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: 0.5, indent: 46, color: AppTheme.divider),
          children[i],
        ],
      ],
    ),
  );

  Widget _row(
    IconData icon,
    String label,
    String value, {
    String? trailing,
    String? note,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: AppTheme.textSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.body),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(
                  note,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (value.isNotEmpty) ...[
          const SizedBox(width: 12),
          // Angka di atas, satuan di bawah — rata kanan supaya sejajar.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: AppText.bodyStrong.copyWith(color: AppTheme.primary),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}
