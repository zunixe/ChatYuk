import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../models/room_model.dart';
import '../../../providers/locale_provider.dart';
import '../../../utils.dart';
import '../../../widgets/room_icon.dart';

/// Kartu room ala gambar: ikon | nama + preview + member•online |
/// waktu/Live + badge unread. Live HANYA grup (isLive dari server).
class RoomExploreCard extends StatelessWidget {
  final RoomModel room;
  final VoidCallback onTap;
  const RoomExploreCard({super.key, required this.room, required this.onTap});

  String _preview(S s) {
    if (room.lastText.isNotEmpty) {
      final body = switch (room.lastType) {
        'image' => s.msgPhoto,
        'voice' => s.msgVoice,
        'gift' => '🎁',
        'coin' => '🪙',
        _ => room.lastText.replaceAll('\n', ' '),
      };
      final sender = room.lastSenderName.isNotEmpty
          ? '${room.lastSenderName}: '
          : '';
      return '$sender$body';
    }
    if (room.description.isNotEmpty) return room.description;
    return s.roomDesc(room.category);
  }

  String _unreadLabel(int n) {
    if (n > 99) return '99+';
    if (n > 20) return '$n+';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final title =
        room.name.isNotEmpty ? room.name : s.roomName(room.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RoomIcon(
                  category: room.category,
                  emoji: room.icon,
                  roomId: room.id,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _preview(s),
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.roomMembersOnline(
                          formatCompactCount(
                            room.memberCount,
                            isId: s.isId,
                          ),
                          formatCompactCount(
                            room.onlineCount,
                            isId: s.isId,
                          ),
                        ),
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (room.isLive)
                      Text(
                        s.exploreLive,
                        style: AppText.caption.copyWith(
                          color: AppTheme.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else if (room.lastAt != null)
                      Text(
                        formatExploreTime(room.lastAt!, isId: s.isId),
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    if (room.unread > 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.female,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _unreadLabel(room.unread),
                          style: AppText.micro.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
