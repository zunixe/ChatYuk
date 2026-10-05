import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';
import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../providers/riverpod/points_provider.dart';

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
    final pp = ref.watch(
      pointsProvider.select(
        (p) => (
          callAudio: p.callAudioCostPerMin,
          callVideo: p.callVideoCostPerMin,
          filterGender: p.filterGenderCost,
          nearby: p.nearbyCost,
          undo: p.costUndoMessage,
          edit: p.costEditMessage,
          extraSlot: p.costExtraPhotoSlot,
          ghostDaily: p.costGhostModeDaily,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(s.yukcoinHowToEarn),
        _card(
          children: [
            _row(Icons.add_circle_outline, s.yukcoinEarnTopup, ''),
            _row(Icons.card_giftcard, s.yukcoinEarnWelcome, ''),
            _row(Icons.call_received, s.yukcoinEarnCallIncome, ''),
          ],
        ),
        _sectionTitle(s.yukcoinHowToSpend),
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
              Icons.person_outline,
              s.yukcoinFeatureFilterGender,
              '${pp.filterGender}',
              trailing: s.yukcoinPerDay,
            ),
            _row(
              Icons.explore_outlined,
              s.yukcoinFeatureNearby,
              '${pp.nearby}',
              trailing: s.yukcoinPerDay,
            ),
          ],
        ),
        if (v2Active) ...[
          _sectionTitle(s.yukcoinHowToSpend),
          _card(
            children: [
              _row(
                Icons.undo,
                s.yukcoinFeatureUndo,
                '${pp.undo}',
                trailing: s.yukcoinPerUse,
              ),
              _row(
                Icons.edit_outlined,
                s.yukcoinFeatureEdit,
                '${pp.edit}',
                trailing: s.yukcoinPerUse,
              ),
              _row(
                Icons.photo_library_outlined,
                s.yukcoinFeatureExtraPhoto,
                '${pp.extraSlot}',
                trailing: s.yukcoinOnce,
              ),
              _row(
                Icons.visibility_off_outlined,
                s.yukcoinFeatureGhost,
                '${pp.ghostDaily}',
                trailing: ghostActive ? s.ghostModeActive : s.yukcoinPerDay,
              ),
            ],
          ),
        ],
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
    child: Column(children: children),
  );

  Widget _row(IconData icon, String label, String value, {String? trailing}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppText.body)),
            Text(
              value,
              style: AppText.bodyStrong.copyWith(color: AppTheme.primary),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              Text(
                trailing,
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      );
}
