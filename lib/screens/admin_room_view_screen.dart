import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../config/theme.dart';
import '../core/perf/perf_probe.dart';
import '../models/message_model.dart';
import '../providers/riverpod/admin_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../screens/room_chat/widgets/room_message_bubble.dart';
import '../utils.dart';
import '../widgets/profile_avatar.dart';

/// Admin: monitor SATU grup (private room) — info + anggota + isi chat.
///
/// - Info room dari `roomInfo` (bawa dari list; fallback kosong).
/// - Anggota: `fetchRoomMembers` (JOIN profiles) — live via realtime
///   `room_members`.
/// - Pesan: `roomMessagesFor(roomId)` (per-room, bukan buffer bersama) —
///   live via realtime `messages` filter `room_id` + poll 5 dtk fallback.
/// - Media dirender NYATA (foto/voice/video/view-once) lewat
///   [RoomMessageBubble] (widget sama dgn room chat user). Foto biasa:
///   RPC mengosongkan `image_data` → lazy via `fetchRoomMessageImage`.
class AdminRoomViewScreen extends ConsumerStatefulWidget {
  final String roomId;
  final Map<String, dynamic> roomInfo;

  const AdminRoomViewScreen({
    super.key,
    required this.roomId,
    this.roomInfo = const {},
  });

  @override
  ConsumerState<AdminRoomViewScreen> createState() =>
      _AdminRoomViewScreenState();
}

class _AdminRoomViewScreenState extends ConsumerState<AdminRoomViewScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  RealtimeChannel? _channel;
  SupabaseClient? _channelClient;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final admin =
        ProviderScope.containerOf(context, listen: false).read(adminProvider);
    Future.microtask(() {
      admin.fetchRoomMembers(widget.roomId, force: true);
      admin.fetchRoomMessages(widget.roomId);
    });
    _subscribeRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  // Stop polling saat app di-background (sama seperti admin_chat_view_screen):
  // tanpa ini timer 5 dtk terus menembak RPC selama background → saat resume
  // RPC bertumpuk dengan rangkaian resume → terasa ngelag.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      _pollTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      unawaited(_poll());
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    // Buang channel SEPENUHNYA (bukan hanya unsubscribe) — cegah bocor socket
    // saat buka-tutup grup berulang (pola admin_chat_view_screen).
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      final sb = _channelClient;
      if (sb != null) {
        unawaited(sb.removeChannel(ch));
      } else {
        unawaited(ch.unsubscribe());
      }
    }
    _channelClient = null;
    super.dispose();
  }

  void _subscribeRealtime() {
    final sb = ProviderScope.containerOf(context, listen: false)
        .read(adminProvider)
        .realtimeClient;
    _channelClient = sb;
    _channel = sb.channel('admin-room-${widget.roomId.hashCode}');
    // Filter room_id — hanya perubahan GRUP INI yang memicu _poll.
    final msgFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'room_id',
      value: widget.roomId,
    );
    for (final ev in [
      PostgresChangeEvent.insert,
      PostgresChangeEvent.update,
      PostgresChangeEvent.delete,
    ]) {
      _channel!.onPostgresChanges(
        event: ev,
        schema: 'public',
        table: 'messages',
        filter: msgFilter,
        callback: (_) => _poll(),
      );
    }
    // Anggota berubah (join/keluar) → segarkan daftar anggota.
    final memFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'room_id',
      value: widget.roomId,
    );
    for (final ev in [
      PostgresChangeEvent.insert,
      PostgresChangeEvent.delete,
    ]) {
      _channel!.onPostgresChanges(
        event: ev,
        schema: 'public',
        table: 'room_members',
        filter: memFilter,
        callback: (_) {
          final admin = ProviderScope.containerOf(context, listen: false)
              .read(adminProvider);
          unawaited(admin.fetchRoomMembers(widget.roomId, force: true));
          if (mounted) setState(() {});
        },
      );
    }
    _channel!.subscribe((status, err) {
      if (err != null) debugPrint('[ADMIN] room-monitor realtime error: $err');
    });
  }

  Future<void> _poll() async {
    if (!mounted || _polling) return;
    _polling = true;
    try {
      final admin =
          ProviderScope.containerOf(context, listen: false).read(adminProvider);
      await admin.refreshRoomMessages(widget.roomId);
    } finally {
      _polling = false;
    }
  }

  Future<void> _confirmDeleteRoom(S s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.adminRoomDeleteTitle),
        content: Text(s.adminRoomDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.adminRoomDelete,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(adminProvider)
          .deleteRoom(widget.roomId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(s.adminRoomDeleted)));
      nav.pop();
    } catch (e) {
      dlog('[ADMIN] deleteRoom error: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(s.adminRoomDeleteFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    // Rebuild saat domain rooms berubah (pesan/anggota baru).
    ref.watch(adminProvider.select((p) => p.revRooms));
    PerfProbe.buildCount('AdminRoomView');

    final admin = ref.read(adminProvider);
    final info = widget.roomInfo;
    final members = admin.roomMembersFor(widget.roomId);
    final rawMsgs = admin.roomMessagesFor(widget.roomId);
    final msgs = rawMsgs.map(_toModel).toList();
    final hasMore = admin.roomMessagesHasMoreFor(widget.roomId);
    final deletedIds = <String>{
      for (final m in msgs)
        if (m.isDeleted) m.id,
    };

    final name = '${info['name'] ?? ''}'.trim();
    final owner = '${info['owner_name'] ?? ''}'.trim();
    final country = '${info['country'] ?? ''}'.trim();
    final category = '${info['category'] ?? ''}'.trim();
    final hasPass = info['has_password'] == true;
    final expiresAt = info['expires_at'] != null
        ? DateTime.tryParse('${info['expires_at']}')
        : null;
    final expired = expiresAt != null && expiresAt.isBefore(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? s.adminRoomMonitor : name),
        actions: [
          IconButton(
            tooltip: s.adminRoomDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDeleteRoom(s),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Info grup ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            color: AppTheme.bgCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _pill('${s.adminRoomOwner}: ${owner.isEmpty ? '—' : owner}'),
                    if (country.isNotEmpty) _pill(country),
                    if (category.isNotEmpty) _pill(category),
                    if (hasPass)
                      _pill('🔒 ${s.adminRoomLocked}', color: AppTheme.primary),
                    _pill(
                      expired ? s.adminRoomExpired : s.adminRoomActive,
                      color: expired ? AppTheme.danger : AppTheme.online,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${members.length} ${s.adminRoomMembers} · '
                  '${msgs.length}${hasMore ? '+' : ''} ${s.adminRoomMessages}',
                  style: AppText.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),

          // ── Anggota (horizontal) ──
          Container(
            height: 74,
            alignment: Alignment.centerLeft,
            color: AppTheme.bgCard,
            child: members.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      s.adminRoomLoadingMembers,
                      style: AppText.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: members.length,
                    itemBuilder: (_, i) => _memberChip(s, members[i]),
                  ),
          ),
          const Divider(height: 1),

          // ── Pesan (terbaru di bawah ala chat) ──
          Expanded(
            child: msgs.isEmpty
                ? Center(
                    child: Text(
                      s.adminRoomEmptyChat,
                      style: AppText.body
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: msgs.length + (hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= msgs.length) {
                        // Trigger load-more (scroll ke atas).
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            admin.fetchMoreRoomMessages(widget.roomId);
                          }
                        });
                        return const Padding(
                          padding: EdgeInsets.all(14),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final m = msgs[i];
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Flexible(
                            child: RoomMessageBubble(
                              msg: m,
                              isMe: false, // admin = pengamat → semua kiri
                              color: Color(
                                userColorPalette[
                                    colorHashForUid(m.senderId) %
                                        userColorPalette.length],
                              ),
                              roomId: widget.roomId,
                              onTapUser: () {},
                              deletedIds: deletedIds,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? AppTheme.textSecondary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppText.micro.copyWith(
          color: color ?? AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _memberChip(S s, Map<String, dynamic> mem) {
    final uid = '${mem['user_id'] ?? ''}';
    final nick = '${mem['nickname'] ?? 'Anon'}';
    final isOwner = mem['is_owner'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ProfileAvatar(uid: uid, name: nick, size: 40, borderRadius: 20),
              if (isOwner)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star, size: 9,
                        color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 52,
            child: Text(
              nick,
              style: AppText.micro,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Map baris RPC → MessageModel (pola admin_chat_view: voice→voice_path,
  /// foto→image_data/image_path — supaya bubble media bisa render path).
  MessageModel _toModel(Map<String, dynamic> r) {
    final type = '${r['type'] ?? 'text'}';
    final imageData = '${r['image_data'] ?? ''}';
    final imagePath = '${r['image_path'] ?? ''}';
    final voicePath = '${r['voice_path'] ?? ''}';
    return MessageModel(
      id: '${r['id']}',
      senderId: '${r['sender_id'] ?? ''}',
      senderName: '${r['sender_name'] ?? 'Anon'}',
      senderGender: '${r['sender_gender'] ?? 'other'}',
      isRegistered: false,
      text: '${r['text'] ?? ''}',
      type: type,
      imageData: type == 'voice'
          ? voicePath
          : (imageData.isNotEmpty ? imageData : imagePath),
      isDeleted: r['is_deleted'] == true,
      edited: r['edited'] == true,
      durationMs: r['duration_ms'] is int
          ? r['duration_ms'] as int
          : int.tryParse('${r['duration_ms'] ?? ''}'),
      timestamp: parseDate(r['created_at']),
      repliedToId: r['replied_to_id'] is String ? r['replied_to_id'] : null,
      repliedToText: r['replied_to_text'],
      repliedToSenderName: r['replied_to_sender_name'],
    );
  }
}
