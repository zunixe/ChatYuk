import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../models/room_model.dart';
import '../providers/room_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import 'room_chat_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  static const _prefKey = 'lobby_country';

  @override
  void initState() {
    super.initState();
    _initCountry();
  }

  Future<void> _initCountry() async {
    final auth = context.read<AuthProvider>();
    final profileCountry = auth.profile?.country ?? 'Indonesia';
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    final target = (saved != null && allCountries.contains(saved)) ? saved : profileCountry;
    if (!mounted) return;
    await context.read<RoomProvider>().setCountry(target);
    // Muat harga room (dual pricing) dari server.
    context.read<PointsProvider>().refreshRoomPricing();
  }

  Future<void> _onCountryChanged(String country) async {
    await context.read<RoomProvider>().setCountry(country);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, country);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final roomProvider = context.watch<RoomProvider>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.bgScreen,
        appBar: AppBar(
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primaryDark, AppTheme.primary, AppTheme.accent],
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ChatYuk', style: AppText.title.copyWith(color: Colors.white)),
              Text(s.titleRooms, style: AppText.bodySmall.copyWith(color: Colors.white70)),
            ],
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: s.tabGlobalRoom),
              Tab(text: s.tabPrivateRoom),
            ],
          ),
        ),
        body: Column(
          children: [
            // Pilih negara (berlaku untuk kedua tab)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.public, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: roomProvider.country,
                          isExpanded: true,
                          isDense: true,
                          menuMaxHeight: 400,
                          hint: Text(s.lobbyCountryHint, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                          style: AppText.body.copyWith(fontWeight: FontWeight.w500),
                          items: [
                            for (final c in allCountries)
                              DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis, maxLines: 1, style: AppText.body)),
                          ],
                          onChanged: (v) { if (v != null) _onCountryChanged(v); },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _GlobalRoomsTab(rooms: roomProvider.rooms),
                  _PrivateRoomsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalRoomsTab extends StatelessWidget {
  final List<RoomModel> rooms;
  const _GlobalRoomsTab({required this.rooms});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    if (rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏠', style: TextStyle(fontSize: AppGlyph.xl)),
            const SizedBox(height: 12),
            Text(s.noRooms, style: AppText.bodyStrong.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rooms.length,
      itemBuilder: (_, i) => _RoomCard(room: rooms[i]),
    );
  }
}

class _PrivateRoomsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final roomProvider = context.watch<RoomProvider>();
    final rooms = roomProvider.privateRooms;
    return Stack(
      children: [
        if (rooms.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🔒', style: TextStyle(fontSize: AppGlyph.xl)),
                const SizedBox(height: 12),
                Text(s.noPrivateRooms, style: AppText.bodyStrong.copyWith(color: AppTheme.textSecondary)),
                const SizedBox(height: 4),
                Text(s.noPrivateRoomsHint, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
              ],
            ),
          )
        else
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: rooms.length,
            itemBuilder: (_, i) => _PrivateRoomCard(room: rooms[i]),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _showCreateRoomDialog(context),
            backgroundColor: AppTheme.primary,
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text(s.btnCreateRoom, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

const _roomIconChoices = ['🔒', '💬', '🎉', '🎮', '🎵', '💘', '🔥', '⭐', '🌙', '👑', '☕', '🌸'];

Future<void> _showCreateRoomDialog(BuildContext context) async {
  final s = context.read<LocaleProvider>().s;
  final points = context.read<PointsProvider>();
  final auth = context.read<AuthProvider>();
  final isAdmin = auth.userEmail == 'zunixe@gmail.com';
  final nameCtrl = TextEditingController();
  final pwCtrl = TextEditingController();
  String icon = '🔒';

  await points.refreshRoomPricing();

  // Room private (berbayar) butuh email terverifikasi. Anon tetap bisa
  // memakai tier bonus (beli lewat koin bonus), tapi tetap harus registered
  // + verified untuk fitur berbayar penuh.
  if (!isAdmin && points.enabled && !auth.canUsePaid && !auth.isAnonymous) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
    }
    return;
  }

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) {
        final hasPw = pwCtrl.text.trim().isNotEmpty;
        final paidCost = hasPw ? points.roomCreatePwPaid : points.roomCreatePaid;
        final bonusCost = paidCost * points.bonusMultiplier;
        return AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(s.createRoomTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  maxLength: 30,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: s.roomNameLabel,
                    hintText: s.roomNameHint,
                    labelStyle: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 8),
                Text(s.roomIconLabel, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: _roomIconChoices.map((e) => GestureDetector(
                    onTap: () => setInner(() => icon = e),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: icon == e ? AppTheme.primary.withValues(alpha: 0.25) : AppTheme.bgScreen,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: icon == e ? AppTheme.primary : Colors.transparent, width: 1.5),
                      ),
                      child: Center(child: Text(e, style: const TextStyle(fontSize: AppGlyph.sm))),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pwCtrl,
                  onChanged: (_) => setInner(() {}),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: s.roomPasswordOpt,
                    hintText: s.roomPasswordHint,
                    labelStyle: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                // Biaya + saldo koin — sembunyikan saat sistem poin OFF (room gratis diam-diam)
                if (points.enabled && !isAdmin)
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.paidOrBonus(paidCost, bonusCost),
                            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ),
                      Text('${s.labelYourCoins}: ${points.points}',
                          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.btnCancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.length < 3 || name.length > 30) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(s.errRoomNameLen)));
                  return;
                }
                if (points.enabled && !isAdmin && points.points < paidCost && points.points < bonusCost) {
                  Navigator.pop(ctx);
                  points.showOutOfPointsDialog(context, s.isId);
                  return;
                }
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final res = await context.read<RoomProvider>().createPrivateRoom(
                    name: name, icon: icon, password: hasPw ? pwCtrl.text.trim() : null);
                  if (res['points'] != null) points.setPoints((res['points'] as num).toInt());
                  if (ctx.mounted) Navigator.pop(ctx);
                  messenger.showSnackBar(SnackBar(content: Text(s.roomCreated)));
                } catch (e) {
                  final msg = e.toString();
                  final show = msg.contains('Room limit') ? s.errRoomLimit
                    : msg.contains('Not enough') ? s.errCoinInsufficient
                    : msg.contains('Invalid room name') ? s.errRoomNameLen
                    : s.errSendCoin;
                  messenger.showSnackBar(SnackBar(content: Text(show)));
                }
              },
              child: Text(s.btnCreateRoom, style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    ),
  );
}

class _PrivateRoomCard extends StatelessWidget {
  final RoomModel room;
  const _PrivateRoomCard({required this.room});

  int get _daysLeft {
    if (room.expiresAt == null) return 0;
    return room.expiresAt!.difference(DateTime.now()).inDays;
  }

  Future<void> _enter(BuildContext context) async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final roomProvider = context.read<RoomProvider>();
    final points = context.read<PointsProvider>();
    final isMember = roomProvider.memberRoomIds.contains(room.id) || room.ownerId == auth.uid;
    if (isMember) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)));
      return;
    }

    // Join room berbayar butuh email terverifikasi (kecuali anon pakai bonus).
    if (points.enabled && !auth.canUsePaid && !auth.isAnonymous) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
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
            const SizedBox(height: 8),
            // Biaya join + saldo koin — sembunyikan saat sistem poin OFF (gratis diam-diam)
            if (points.enabled) ...[
              Text(s.paidOrBonus(joinPaid, joinBonus), style: AppText.body.copyWith(color: AppTheme.primary)),
              Text('${s.labelYourCoins}: ${points.points}', style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
            ],
            if (room.hasPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: pwCtrl,
                obscureText: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: s.enterPassword,
                  labelStyle: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnJoin, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (points.enabled && points.points < joinPaid && points.points < joinBonus) {
      if (context.mounted) points.showOutOfPointsDialog(context, s.isId);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await roomProvider.joinPrivateRoom(room.id,
        password: room.hasPassword ? pwCtrl.text.trim() : null);
      if (res['ok'] == true) {
        if (res['points'] != null) points.setPoints((res['points'] as num).toInt());
        final charged = (res['charged'] as num?)?.toInt() ?? 0;
        if (charged > 0 && context.mounted) points.showPointsToast(context, s.coinSentToast(charged));
        if (context.mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)));
        }
      }
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('Wrong password') ? s.errWrongPassword
        : msg.contains('Not enough') ? s.errCoinInsufficient
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
              leading: const Icon(Icons.more_time, color: AppTheme.primary),
              title: Text(s.btnExtendRoom, style: const TextStyle(color: AppTheme.textPrimary)),
              onTap: () => Navigator.pop(ctx, 'extend'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: Text(s.btnDeleteRoom, style: const TextStyle(color: AppTheme.danger)),
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
      if (points.enabled && points.points < extendPaid && points.points < extendBonus) {
        points.showOutOfPointsDialog(context, s.isId);
        return;
      }
      try {
        final res = await roomProvider.extendRoom(room.id);
        if (res['points'] != null) points.setPoints((res['points'] as num).toInt());
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.btnDeleteRoom, style: const TextStyle(color: AppTheme.danger))),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.btnDeleteRoom, style: const TextStyle(color: AppTheme.danger))),
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
    final isAdmin = auth.userEmail == 'zunixe@gmail.com';
    final canManage = isOwner || isAdmin;
    final isMember = roomProvider.memberRoomIds.contains(room.id) || isOwner;
    final days = _daysLeft;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _enter(context),
          onLongPress: canManage ? () => _ownerMenu(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: Text(room.icon, style: const TextStyle(fontSize: AppGlyph.md))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(room.name, style: AppText.titleEmphasis, overflow: TextOverflow.ellipsis)),
                          if (room.hasPassword) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.lock, size: 13, color: AppTheme.textSecondary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${s.roomByOwner} ${room.ownerName} · ${days <= 0 ? s.roomExpiresToday : s.roomExpiresIn(days)}',
                        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.online.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppTheme.online, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('${room.onlineCount}', style: AppText.caption.copyWith(color: AppTheme.online, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    if (!isMember && context.read<PointsProvider>().enabled) ...[
                      const SizedBox(height: 4),
                      Text('${context.read<PointsProvider>().roomJoinPaid} 🪙',
                          style: AppText.caption.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w700)),
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
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      child: card,
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomModel room;
  const _RoomCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(room.icon, style: const TextStyle(fontSize: AppGlyph.md)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.roomName(room.category), style: AppText.titleEmphasis),
                    const SizedBox(height: 2),
                    Text(s.roomDesc(room.category), style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.online.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppTheme.online, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('${room.onlineCount} ${s.roomOnlineCount}', style: AppText.caption.copyWith(color: AppTheme.online, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
