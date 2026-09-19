import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../models/user_model.dart';
import '../../../providers/locale_provider.dart';

class RoomUserChip extends StatelessWidget {
  final UserModel user;
  final String? myUid;
  final Color color;
  const RoomUserChip(
      {super.key, required this.user, this.myUid, required this.color});

  @override
  Widget build(BuildContext context) {
    final isMe = user.uid == myUid;
    final s = context.read<LocaleProvider>().s;
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isMe ? AppTheme.primary : color,
                child: Text(
                  user.initial,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: AppGlyph.avatarInitial(44),
                  ),
                ),
              ),
              if (user.isRegistered)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Icon(
                    Icons.verified,
                    size: 14,
                    color: Color(0xFF4A90E2),
                  ),
                ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            isMe ? s.labelYou : user.nickname,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class RoomHeaderToggle extends StatelessWidget {
  final bool showUsers;
  final VoidCallback onTap;
  const RoomHeaderToggle({required this.showUsers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return Tooltip(
      message: showUsers ? s.roomShowChat : s.roomShowMembers,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: showUsers
                ? AppTheme.primary
                : AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(scale: anim, child: child),
            ),
            child: Icon(
              showUsers ? Icons.forum_rounded : Icons.groups_rounded,
              key: ValueKey(showUsers),
              size: 20,
              color: showUsers ? Colors.white : AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon dalam lingkaran tinted untuk item bottom sheet — konsisten
/// gaya modern, warna membedakan aksi.

class RoomSheetIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const RoomSheetIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}



/// Stage broadcast setengah layar: video broadcaster + kontrol ringkas.
