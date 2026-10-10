import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/admin_gate.dart';
import '../../core/nav_guard.dart';
import '../../models/room_model.dart';
import '../../providers/riverpod/auth_provider.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../providers/riverpod/points_provider.dart';
import '../../providers/riverpod/room_provider.dart';
import '../../widgets/room_icon.dart';
import '../room_chat_screen.dart';

class GroupCard extends ConsumerWidget {
  final RoomModel room;
  const GroupCard({required this.room});

  int get _daysLeft {
    if (room.expiresAt == null) return 0;
    return room.expiresAt!.difference(DateTime.now()).inDays;
  }

  Future<void> _enter(BuildContext context) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final rooms = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(roomProvider.notifier);
    final points = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier);
    final isMember =
        rooms.memberRoomIds.contains(room.id) || room.ownerId == auth.uid;
    if (isMember) {
      final navKey = navKeyRoom(room.id);
      if (!tryClaimNav(navKey)) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)),
      ).then((_) => releaseNav(navKey));
      return;
    }

    // Join room berbayar butuh email terverifikasi (kecuali anon pakai bonus).
    if (points.enabled && !auth.canUsePaid && !auth.isAnonymous) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
      return;
    }

    final joinPaid = points.roomJoinPaid;
    final joinBonus = joinPaid * points.bonusMultiplier;

    // Belum member → dialog konfirmasi (+ password bila perlu)
    final pwCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.joinRoomTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${room.icon} ${room.name}', style: AppText.bodyStrong),
            SizedBox(height: 8),
            // Biaya join + saldo koin — sembunyikan saat sistem poin OFF (gratis diam-diam)
            if (points.enabled) ...[
              Text(
                s.paidOrBonus(joinPaid, joinBonus),
                style: AppText.body.copyWith(color: AppTheme.primary),
              ),
              Text(
                '${s.labelYourCoins}: ${points.points}',
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            if (room.hasPassword) ...[
              SizedBox(height: 12),
              TextField(
                controller: pwCtrl,
                obscureText: true,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: s.enterPassword,
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnJoin, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (points.enabled &&
        points.points < joinPaid &&
        points.points < joinBonus) {
      if (context.mounted) points.showOutOfPointsDialog(context, s.isId);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await rooms.joinPrivateRoom(
        room.id,
        password: room.hasPassword ? pwCtrl.text.trim() : null,
      );
      if (res['ok'] == true) {
        if (res['points'] != null)
          points.setPoints((res['points'] as num).toInt());
        final charged = (res['charged'] as num?)?.toInt() ?? 0;
        if (charged > 0 && context.mounted)
          points.showPointsToast(context, s.coinSentToast(charged));
        if (context.mounted) {
          final navKey = navKeyRoom(room.id);
          if (tryClaimNav(navKey)) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)),
            ).then((_) => releaseNav(navKey));
          }
        }
      }
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('Wrong password')
          ? s.errWrongPassword
          : msg.contains('Not enough')
          ? s.errCoinInsufficient
          : s.errSendCoin;
      messenger.showSnackBar(SnackBar(content: Text(show)));
    }
  }

  Future<void> _ownerMenu(BuildContext context) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final rooms = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(roomProvider.notifier);
    final points = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: GroupSheetIcon(
                icon: Icons.more_time_rounded,
                color: AppTheme.primary,
              ),
              title: Text(
                s.btnExtendRoom,
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, 'extend'),
            ),
            ListTile(
              leading: const GroupSheetIcon(
                icon: Icons.delete_outline_rounded,
                color: AppTheme.danger,
              ),
              title: Text(
                s.btnDeleteRoom,
                style: const TextStyle(color: AppTheme.danger),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (action == 'extend') {
      final extendPaid = points.roomExtendPaid;
      final extendBonus = extendPaid * points.bonusMultiplier;
      if (points.enabled &&
          points.points < extendPaid &&
          points.points < extendBonus) {
        points.showOutOfPointsDialog(context, s.isId);
        return;
      }
      try {
        final res = await rooms.extendRoom(room.id);
        if (res['points'] != null)
          points.setPoints((res['points'] as num).toInt());
        messenger.showSnackBar(SnackBar(content: Text(s.roomExtended)));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(s.errSendCoin)));
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(s.btnDeleteRoom),
          content: Text(s.deleteRoomConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.btnCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                s.btnDeleteRoom,
                style: const TextStyle(color: AppTheme.danger),
              ),
            ),
          ],
        ),
      );
      if (ok == true) {
        await rooms.deleteRoom(room.id);
        messenger.showSnackBar(SnackBar(content: Text(s.roomDeleted)));
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final rooms = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(roomProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.btnDeleteRoom),
        content: Text(s.deleteRoomConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.btnDeleteRoom,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await rooms.deleteRoom(room.id);
      messenger.showSnackBar(SnackBar(content: Text(s.roomDeleted)));
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    // PERF: dulu `watch<RoomProvider>()` penuh di SETIAP kartu → semua kartu
    // rebuild tiap provider notify (counts/presence/membership sering).
    // Kartu hanya butuh SATU boolean: apakah aku anggota grup ini.
    final isOwner = room.ownerId == auth.uid;
    // Admin privilege hanya ada di build admin (flavor-gate) —
    // bukan lagi cek email runtime.
    final isAdmin = AdminGate.enabled;
    final canManage = isOwner || isAdmin;
    final isMember =
        ref.watch(
          roomProvider.select((rp) => rp.memberRoomIds.contains(room.id)),
        ) ||
        isOwner;
    final days = _daysLeft;

    final card = Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _enter(context),
          onLongPress: canManage ? () => _ownerMenu(context) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                RoomIcon(category: room.category, emoji: room.icon),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              room.name,
                              style: AppText.titleEmphasis,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (room.hasPassword) ...[
                            SizedBox(width: 4),
                            Icon(
                              Icons.lock_rounded,
                              size: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 2),
                      Text(
                        '${s.roomByOwner} ${room.ownerName} · ${days <= 0 ? s.roomExpiresToday : s.roomExpiresIn(days)}',
                        style: AppText.bodySmall.copyWith(
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.online.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppTheme.online,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${room.onlineCount}',
                            style: AppText.caption.copyWith(
                              color: AppTheme.online,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isMember &&
                        ProviderScope.containerOf(
                          context,
                          listen: false,
                        ).read(pointsProvider.notifier).enabled) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).roomJoinPaid} 🪙',
                        style: AppText.caption.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
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

    // Owner (atau admin) bisa hapus room dengan geser ke kiri (swipe).
    if (!canManage) return card;
    return Dismissible(
      key: ValueKey('room-${room.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.danger,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
      child: card,
    );
  }
}

/// Kartu pilihan akses grup: tanpa password (permanen) vs password (7 hari).
/// Terpilih = border + tint warna aksen + radio terisi.
class GroupAccessCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final VoidCallback onTap;
  const GroupAccessCard({
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.10) : AppTheme.bgScreen,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color
                  : AppTheme.textSecondary.withValues(alpha: 0.25),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: AppText.caption.copyWith(
                        color: selected ? color : AppTheme.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? color : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? color
                        : AppTheme.textSecondary.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GroupSheetIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const GroupSheetIcon({required this.icon, required this.color});

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
