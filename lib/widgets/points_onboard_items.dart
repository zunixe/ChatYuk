import 'package:flutter/material.dart';

import '../config/gifts.dart';
import '../config/strings.dart';
import '../config/theme.dart';

/// Isi popup onboarding YukCoin, dipisah per gender.
/// Male = apa yang DIBAYAR + bonus selamat datang; female = cara MENDAPAT.
/// Female TIDAK dapat bonus selamat datang (server `credit_welcome_bonus`
/// → `female_no_bonus`) dan tidak bisa kirim gift → baris itu tidak tampil.
class PointsOnboardItems extends StatelessWidget {
  final S s;
  final bool isFemale;
  final int callAudio;
  final int callVideo;
  final int matchFee;
  final int withdrawMin;

  const PointsOnboardItems({
    super.key,
    required this.s,
    required this.isFemale,
    required this.callAudio,
    required this.callVideo,
    required this.matchFee,
    required this.withdrawMin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isFemale) ...[
          _item('💰', s.pointsOnboardFemaleSub, highlight: true),
          _item('', s.pointsOnboardFemaleCall),
          _item('', s.pointsOnboardFemaleGift),
          _item('', s.pointsOnboardFemaleMatch),
          _item('', s.pointsOnboardFemaleCallOut),
          _item('', s.pointsOnboardFemaleAllFree),
          _item('', s.pointsOnboardFemaleWithdraw(withdrawMin)),
        ] else ...[
          _item('🪙', s.pointsOnboardMaleSub, highlight: true),
          _item('', s.pointsOnboardMaleCall(callAudio, callVideo)),
          _item('', s.pointsOnboardMaleMatch(matchFee)),
          _item(
            '',
            s.pointsOnboardMaleGift(
              kGiftCatalog.first.coins,
              kGiftCatalog.last.coins,
            ),
          ),
          _item('', s.pointsOnboardMaleFree),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('🎉', style: TextStyle(fontSize: AppGlyph.sm)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.pointsOnboardMaleWelcome,
                  style: AppText.bodySmall.copyWith(color: Colors.amber),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _item(String emoji, String text, {bool highlight = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF2ECC71).withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? const Color(0xFF2ECC71).withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Text(emoji, style: TextStyle(fontSize: AppGlyph.md)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: (highlight ? AppText.bodyStrong : AppText.body).copyWith(
                color: highlight ? Colors.white : Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
