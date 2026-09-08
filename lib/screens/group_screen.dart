import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../core/admin_gate.dart';
import '../models/room_model.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/room_provider.dart';
import '../services/private_room_service.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../widgets/room_icon.dart';
import 'room_chat_screen.dart';

/// Tab "Grup": list grup private milikku + FAB buat grup.
/// Dipindah dari lobby_screen (dulu tab Private di dalam Room).
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  /// Akses statis untuk memuat-ulang list dari dialog buat grup.
  static final GlobalKey<_GroupListState> _listKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return _GroupList(key: _listKey);
  }
}

class _GroupList extends StatefulWidget {
  const _GroupList({super.key});
  @override
  State<_GroupList> createState() => _GroupListState();
}

class _GroupListState extends State<_GroupList> {
  List<RoomModel> _rooms = [];
  bool _loading = true;

  /// Muat-ulang dari luar (dialog buat grup) — key statis di GroupScreen.
  static void reloadCurrent(BuildContext context) {
    final st = context.findAncestorStateOfType<_GroupListState>();
    st?._load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }
  /// List grup MILIKKU dari RPC list_my_groups (member-only,
  /// tanpa filter negara). Grup expired disembunyikan kecuali milik
  /// sendiri (owner bisa perpanjang).
  Future<void> _load() async {
    try {
      final myUid = PrivateRoomService.instance.uid ?? '';
      final rows = await PrivateRoomService.instance.listMyRooms();
      final rooms = <RoomModel>[];
      for (final r in rows) {
        final m = RoomModel.fromMap('${r['id'] ?? ''}', r);
        final expired =
            m.expiresAt != null && m.expiresAt!.isBefore(DateTime.now());
        if (expired && m.ownerId != myUid) continue;
        rooms.add(m);
      }
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppTheme.primary,
          ),
        ),
      );
    }
    return Stack(
      children: [
        if (_rooms.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🔒', style: TextStyle(fontSize: AppGlyph.xl)),
                SizedBox(height: 12),
                Text(
                  s.noGroups,
                  style: AppText.bodyStrong.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  s.noGroupsHint,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: _rooms.length,
            itemBuilder: (_, i) => _GroupCard(room: _rooms[i]),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => showCreateGroupDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryDark,
                      AppTheme.primary,
                      AppTheme.accent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      s.btnCreateGroup,
                      style: AppText.bodyStrong.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _roomIconChoices = [
  '🔒',
  '💬',
  '🎉',
  '🎮',
  '🎵',
  '💘',
  '🔥',
  '⭐',
  '🌙',
  '👑',
  '☕',
  '🌸',
];

/// Dialog buat grup — publik: dipakai FAB tab Grup DAN menu ⋮ chat list.
Future<void> showCreateGroupDialog(BuildContext context) async {
  final s = context.read<LocaleProvider>().s;
  final points = context.read<PointsProvider>();
  final auth = context.read<AuthProvider>();
  // Admin privilege hanya ada di build admin (flavor-gate) —
  // bukan lagi cek email runtime.
  final isAdmin = AdminGate.enabled;
  // Gate ANON: bikin grup khusus terdaftar (server juga menolak).
  // Sesi dummy (admin jadi anon) diizinkan — server bypass dummy.
  if (auth.isAnonymous && !auth.dummySessionActive) {
    showAnonPromptDialog(context);
    return;
  }
  final nameCtrl = TextEditingController();
  final pwCtrl = TextEditingController();
  String icon = '🔒';

  await points.refreshRoomPricing();

  // Room private (berbayar) butuh email terverifikasi. Anon tetap bisa
  // memakai tier bonus (beli lewat koin bonus), tapi tetap harus registered
  // + verified untuk fitur berbayar penuh.
  if (!isAdmin && points.enabled && !auth.canUsePaid && !auth.isAnonymous) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
    }
    return;
  }

  bool usePw = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) {
        final paidCost =
            usePw ? points.roomCreatePwPaid : points.roomCreatePaid;
        final bonusCost = paidCost * points.bonusMultiplier;
        return Dialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryDark,
                            AppTheme.primary,
                            AppTheme.accent,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.group_add_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.createGroupTitle, style: AppText.title),
                          const SizedBox(height: 2),
                          Text(
                            s.createGroupSubtitle,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(s.groupNameLabel, style: AppText.label),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  maxLength: 30,
                  style: AppText.body.copyWith(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: s.groupNameHint,
                    prefixIcon: const Icon(Icons.edit_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 14),
                Text(s.roomIconLabel, style: AppText.label),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _roomIconChoices
                      .map(
                        (e) => GestureDetector(
                          onTap: () => setInner(() => icon = e),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: icon == e
                                  ? AppTheme.primary.withValues(alpha: 0.15)
                                  : AppTheme.bgScreen,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: icon == e
                                    ? AppTheme.primary
                                    : AppTheme.textSecondary.withValues(
                                        alpha: 0.25,
                                      ),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                e,
                                style: TextStyle(fontSize: AppGlyph.sm),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                Text(s.groupAccessLabel, style: AppText.label),
                const SizedBox(height: 6),
                _AccessCard(
                  selected: !usePw,
                  icon: Icons.all_inclusive_rounded,
                  color: AppTheme.online,
                  title: s.groupNoPwTitle,
                  desc: s.groupNoPwDesc,
                  onTap: () => setInner(() => usePw = false),
                ),
                const SizedBox(height: 8),
                _AccessCard(
                  selected: usePw,
                  icon: Icons.lock_rounded,
                  color: AppTheme.primary,
                  title: s.groupPwTitle,
                  desc: s.groupPwDesc,
                  onTap: () => setInner(() => usePw = true),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: usePw
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextField(
                            controller: pwCtrl,
                            obscureText: true,
                            onChanged: (_) => setInner(() {}),
                            style: AppText.body.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: s.roomPasswordHint,
                              prefixIcon:
                                  const Icon(Icons.key_rounded, size: 18),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // Biaya + saldo koin — sembunyikan saat sistem poin OFF (room gratis diam-diam)
                if (points.enabled && !isAdmin) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          '🪙',
                          style: TextStyle(fontSize: AppGlyph.sm),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.paidOrBonus(paidCost, bonusCost),
                            style: AppText.bodyStrong.copyWith(
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        Text(
                          '${points.points}',
                          style: AppText.bodyStrong.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final name = nameCtrl.text.trim();
                      if (name.length < 3 || name.length > 30) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(s.errRoomNameLen)),
                        );
                        return;
                      }
                      if (usePw && pwCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(s.errPasswordRequired)),
                        );
                        return;
                      }
                      if (points.enabled &&
                          !isAdmin &&
                          points.points < paidCost &&
                          points.points < bonusCost) {
                        Navigator.pop(ctx);
                        points.showOutOfPointsDialog(context, s.isId);
                        return;
                      }
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final res = await context
                            .read<RoomProvider>()
                            .createPrivateRoom(
                              name: name,
                              icon: icon,
                              password: usePw ? pwCtrl.text.trim() : null,
                            );
                        if (res['points'] != null) {
                          points.setPoints((res['points'] as num).toInt());
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        messenger.showSnackBar(
                          SnackBar(content: Text(s.groupCreated)),
                        );
                        if (context.mounted) {
                          // List milikku berubah (grup baru) — muat ulang.
                          _GroupListState.reloadCurrent(context);
                        }
                      } catch (e) {
                        final msg = e.toString();
                        final show = msg.contains('Room limit')
                            ? s.errGroupLimit
                            : msg.contains('REGISTERED_ONLY')
                            ? s.msgVerifyToUsePaid
                            : msg.contains('Not enough')
                            ? s.errCoinInsufficient
                            : msg.contains('Invalid room name')
                            ? s.errRoomNameLen
                            : s.errSendCoin;
                        messenger.showSnackBar(SnackBar(content: Text(show)));
                      }
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryDark,
                            AppTheme.primary,
                            AppTheme.accent,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        s.btnCreateGroup,
                        style: AppText.button.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(s.btnCancel),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _GroupCard extends StatelessWidget {
  final RoomModel room;
  const _GroupCard({required this.room});

  int get _daysLeft {
    if (room.expiresAt == null) return 0;
    return room.expiresAt!.difference(DateTime.now()).inDays;
  }

  Future<void> _enter(BuildContext context) async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final roomProvider = context.read<RoomProvider>();
    final points = context.read<PointsProvider>();
    final isMember =
        roomProvider.memberRoomIds.contains(room.id) ||
        room.ownerId == auth.uid;
    if (isMember) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)),
      );
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
      final res = await roomProvider.joinPrivateRoom(
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
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)),
          );
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
    final s = context.read<LocaleProvider>().s;
    final roomProvider = context.read<RoomProvider>();
    final points = context.read<PointsProvider>();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _SheetIcon(
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
              leading: const _SheetIcon(
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
        final res = await roomProvider.extendRoom(room.id);
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
        await roomProvider.deleteRoom(room.id);
        messenger.showSnackBar(SnackBar(content: Text(s.roomDeleted)));
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final s = context.read<LocaleProvider>().s;
    final roomProvider = context.read<RoomProvider>();
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
      await roomProvider.deleteRoom(room.id);
      messenger.showSnackBar(SnackBar(content: Text(s.roomDeleted)));
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final roomProvider = context.watch<RoomProvider>();
    final isOwner = room.ownerId == auth.uid;
    // Admin privilege hanya ada di build admin (flavor-gate) —
    // bukan lagi cek email runtime.
    final isAdmin = AdminGate.enabled;
    final canManage = isOwner || isAdmin;
    final isMember = roomProvider.memberRoomIds.contains(room.id) || isOwner;
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
                        context.read<PointsProvider>().enabled) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${context.read<PointsProvider>().roomJoinPaid} 🪙',
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
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
      ),
      child: card,
    );
  }
}

/// Kartu pilihan akses grup: tanpa password (permanen) vs password (7 hari).
/// Terpilih = border + tint warna aksen + radio terisi.
class _AccessCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
  final VoidCallback onTap;
  const _AccessCard({
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
            color: selected
                ? color.withValues(alpha: 0.10)
                : AppTheme.bgScreen,
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
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
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
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 14)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetIcon extends StatelessWidget {  final IconData icon;
  final Color color;
  const _SheetIcon({required this.icon, required this.color});

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
