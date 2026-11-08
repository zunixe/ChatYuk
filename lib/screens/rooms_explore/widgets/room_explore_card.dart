import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import '../../../config/theme.dart';
import '../../../models/room_model.dart';
import '../../../models/room_session_model.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../utils.dart';
import '../../../widgets/room_icon.dart';
import '../../../config/strings.dart';

/// Kartu room ala gambar: ikon | nama + preview + member•online |
/// waktu/Live + badge unread. Live HANYA grup (isLive dari server).
/// Room v2: sesi terjadwal menampilkan badge jam + tombol "Ingatkan";
/// sesi live menampilkan judul + host + jumlah penonton (menang dari preview).
class RoomExploreCard extends ConsumerWidget {
  final RoomModel room;
  final VoidCallback onTap;
  final RoomSessionInfo? session;
  final VoidCallback? onToggleReminder;
  const RoomExploreCard({
    super.key,
    required this.room,
    required this.onTap,
    this.session,
    this.onToggleReminder,
  });

  String _preview(S s) {
    if (room.lastText.isNotEmpty) {
      final body = switch (room.lastType) {
        'image' => s.msgPhoto,
        'voice' => s.msgVoice,
        'gift' => '🎁',
        'coin' => '🪙',
        'location' => '📍 ${s.msgLocation}',
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
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
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
                      if (session != null && session!.isLive) ...[
                        Text(
                          '${s.exploreLive} · ${session!.title}',
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${s.sessionHostBy(session!.hostName)} · '
                          '${s.sessionViewers(formatCompactCount(session!.peakViewers, isId: s.isId))}',
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else if (session != null) ...[
                        Text(
                          '⏰ ${formatSessionStart(session!.startsAt, isId: s.isId)} — ${session!.title}',
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.sessionHostBy(session!.hostName),
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else
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
                    if ((session?.isLive ?? false) || room.isLive)
                      Text(
                        s.exploreLive,
                        style: AppText.caption.copyWith(
                          color: AppTheme.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else if (session != null && onToggleReminder != null)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: onToggleReminder,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                session!.reminded
                                    ? Icons.notifications_active_rounded
                                    : Icons.notifications_none_rounded,
                                size: 14,
                                color: session!.reminded
                                    ? AppTheme.primary
                                    : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                session!.reminded
                                    ? s.sessionReminded
                                    : s.sessionRemind,
                                style: AppText.caption.copyWith(
                                  color: session!.reminded
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
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
