import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../providers/points_provider.dart';

/// Section "Cara dapat" & "Cara pakai YukCoin". Harga diambil dari provider
/// (default sesuai migration; sumber kebenaran tetap server).
class YukcoinHowTo extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final pp = context.watch<PointsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(s.yukcoinHowToEarn),
        _card(
          children: [
            _row(Icons.login, s.yukcoinEarnLogin, '+25'),
            _row(Icons.timer_outlined, s.yukcoinEarnOnline, '+20'),
            _row(Icons.menu_book_outlined, s.yukcoinEarnRoomRead, '+6'),
            _row(Icons.person_add_alt, s.yukcoinEarnNewChat, '+10'),
            _row(Icons.group_add_outlined, s.yukcoinEarnReferral, '+50'),
            _row(Icons.emoji_events_outlined, s.yukcoinEarnQuest, '+150'),
          ],
        ),
        if (v2Active) ...[
          _sectionTitle(s.yukcoinHowToSpend),
          _card(
            children: [
              _row(
                Icons.undo,
                s.yukcoinFeatureUndo,
                '${pp.costUndoMessage}',
                trailing: s.yukcoinPerUse,
              ),
              _row(
                Icons.edit_outlined,
                s.yukcoinFeatureEdit,
                '${pp.costEditMessage}',
                trailing: s.yukcoinPerUse,
              ),
              _row(
                Icons.photo_library_outlined,
                s.yukcoinFeatureExtraPhoto,
                '${pp.costExtraPhotoSlot}',
                trailing: s.yukcoinOnce,
              ),
              _row(
                Icons.visibility_off_outlined,
                s.yukcoinFeatureGhost,
                '${pp.costGhostModeDaily}',
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
