import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../models/room_model.dart';
import '../core/nav_guard.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/room_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import 'room_chat_screen.dart';
import 'room_members_sheet.dart';
import '../widgets/person_avatar.dart';
import '../widgets/message/photo_prefetch.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Daftar private room milik/diikuti + buat room baru (QR join).
/// Fitur fase 1 — hanya admin build (gate di titik navigasi).
class PrivateRoomsScreen extends ConsumerStatefulWidget {
  const PrivateRoomsScreen({super.key});

  @override
  ConsumerState<PrivateRoomsScreen> createState() => _PrivateRoomsScreenState();
}

class _PrivateRoomsScreenState extends ConsumerState<PrivateRoomsScreen> {
  RoomNotifier get _prv => ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier);
  List<Map<String, dynamic>> _myRooms = [];
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
    // Fallback poll JARANG (60s): realtime private rooms (RoomProvider)
    // adalah jalur utama — poll 10s cuma buang RPC selama screen terbuka.
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = _prv.prvUid;
      if (uid == null) return;
      // Batch: 1 RPC ganti N+1 fetchRoomById
      try {
        final res = await _prv.listMyRooms();
        if (!mounted) return;
        setState(() {
          _myRooms = res;
          _loading = false;
        });
        return;
      } catch (_) {
        // fallback ke jalur lama
      }
      final rows = await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchMyMemberships(uid);
      final ids = rows.where((rid) => rid.startsWith('pr_')).toList();
      // Batch 1 query ganti N+1 fetchRoomById per room.
      final all = await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchRoomsByIds(ids);
      if (!mounted) return;
      setState(() {
        _myRooms = all;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.privateRoomsTitle, style: AppText.title),
        actions: [
          IconButton(
            tooltip: s.privateRoomsScanQr,
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _openScanner(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create-private-room',
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          s.createPrivateRoomTitle,
          style: AppText.label.copyWith(color: Colors.white),
        ),
        onPressed: () => _openCreate(context),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _myRooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.meeting_room_outlined,
                        size: 56,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        s.privateRoomsEmpty,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                    itemCount: _myRooms.length,
                    itemBuilder: (_, i) => _RoomTile(
                      room: _myRooms[i],
                      s: s,
                      onOpen: (ctx) => _openRoom(ctx, _myRooms[i]),
                    ),
                  ),
                ),
    );
  }

  Future<void> _openRoom(BuildContext context, Map<String, dynamic> room) async {
    final navKey = navKeyRoom('${room['id']}');
    if (!tryClaimNav(navKey)) return;
    try {
      await PhotoPrefetch.precacheAll(context, 'room_${room['id']}')
          .timeout(const Duration(milliseconds: 450));
    } catch (_) {}
    if (!mounted) {
      releaseNav(navKey);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RoomChatScreen(room: RoomModel.fromMap('${room['id']}', room)),
      ),
    ).then((_) => releaseNav(navKey));
    unawaited(_load());
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreatePrivateRoomScreen()),
    );
  }

  void _openScanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
  }
}

// ── Tile room ──

class _RoomTile extends StatelessWidget {
  final Map<String, dynamic> room;
  final S s;
  final Future<void> Function(BuildContext) onOpen;
  const _RoomTile({required this.room, required this.s, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final liveUid = '${room['live_uid'] ?? ''}';
    final isLive = liveUid.isNotEmpty;
    final amOwner = '${room['owner_id'] ?? ''}' ==
        ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).uid;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isLive
              ? AppTheme.danger.withValues(alpha: 0.6)
              : AppTheme.divider,
        ),
      ),
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor:
                  AppTheme.primary.withValues(alpha: 0.15),
              child: Text(
                '${room['icon'] ?? '🔒'}',
                style: const TextStyle(fontSize: AppGlyph.sm),
              ),
            ),
            if (isLive)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.bgCard, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          '${room['name'] ?? '?'}',
          style: AppText.bodyStrong,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (((room['member_count'] ?? 0) as num) > 0)
              '${room['member_count']} ${s.adminDeviceCount}',
            if (amOwner) s.privateRoomsYouAreOwner,
            if (isLive) s.privateRoomsLive,
          ].where((e) => e.isNotEmpty).join(' · '),
          style: AppText.caption.copyWith(
            color: isLive ? AppTheme.danger : AppTheme.textSecondary,
            fontWeight: isLive ? FontWeight.w700 : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => onOpen(context),
      ),
    );
  }
}

// ── Create room + QR share ──

class CreatePrivateRoomScreen extends ConsumerStatefulWidget {
  const CreatePrivateRoomScreen({super.key});

  @override
  ConsumerState<CreatePrivateRoomScreen> createState() =>
      _CreatePrivateRoomScreenState();
}

class _CreatePrivateRoomScreenState extends ConsumerState<CreatePrivateRoomScreen> {
  final _nameCtrl = TextEditingController();
  String _icon = '🔒';
  bool _creating = false;
  String? _createdId;
  String? _joinToken;
  // Orang yang sudah diundang saat pembuatan grup: uid → (nama, gender).
  final Map<String, (String, String)> _invitedNames = {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating) return;
    final name = _nameCtrl.text.trim();
    if (name.length < 3 || mounted == false) return;
    setState(() => _creating = true);
    try {
      final res = await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).createPrivateRoom(
        name: name,
        icon: _icon,
      );
      if (!mounted) return;
      setState(() {
        _createdId = '${res['id'] ?? ''}';
        _joinToken = '${res['join_token'] ?? ''}';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ProviderScope.containerOf(context, listen: false).read(localeProvider).s.errGeneric)),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _rotateToken() async {
    if (_createdId == null) return;
    await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).rotateToken(_createdId!);
    // Refresh token dari server.
    try {
      final row = await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchRoomById(_createdId!);
      if (mounted && row != null) {
        setState(() => _joinToken = '${row['join_token'] ?? ''}');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.createPrivateRoomTitle, style: AppText.title),
      ),
      body: _createdId != null
          ? _qrView(s)
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    maxLength: 30,
                    decoration: InputDecoration(
                      labelText: s.createRoomNameLabel,
                      prefixIcon: Icon(
                        Icons.meeting_room_outlined,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final ic in ['🔒', '🎉', '💬', '🎮', '🎵', '⚽'])
                        ChoiceChip(
                          label: Text(ic, style: const TextStyle(fontSize: AppGlyph.sm)),
                          selected: _icon == ic,
                          onSelected: (_) => setState(() => _icon = ic),
                        ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _creating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: Text(s.btnCreateGroup),
                      onPressed: _creating ? null : _create,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      s.privateRoomsMaxNote,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _qrView(S s) {
    final payload = 'chatyuk://room/join?id=$_createdId&t=$_joinToken';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(data: payload, size: 230),
          ),
          const SizedBox(height: 16),
          Text(
            s.privateRoomsQrHint,
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: Icon(Icons.copy_rounded, size: 16),
            label: Text(s.privateRoomsCopyLink),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: payload));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.adminDeviceCopied)),
              );
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: Icon(Icons.refresh_rounded, size: 16),
            label: Text(s.privateRoomsRotateQr),
            onPressed: () async {
              await _rotateToken();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.privateRoomsRotated)),
                );
              }
            },
          ),
          const SizedBox(height: 24),
          // ── Undang anggota (opsional) sebelum masuk grup ──
          OutlinedButton.icon(
            icon: const Icon(Icons.group_add_outlined, size: 18),
            label: Text(s.privateRoomsInviteMembers),
            onPressed: () async {
              await showGroupInvitePicker(
                context: context,
                roomId: _createdId!,
                excludeUids: _invitedNames.keys.toSet(),
                onInvited: () {},
                onInvitedOne: (uid, name, gender) {
                  if (mounted) setState(() => _invitedNames[uid] = (name, gender));
                },
              );
            },
          ),
          // Chip "Terundang (n)".
          if (_invitedNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              s.privateRoomsInvitedCount(_invitedNames.length),
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final e in _invitedNames.entries)
                  Chip(
                    avatar: PersonAvatar(
                        uid: e.key, name: e.value.$1, gender: e.value.$2, size: 22),
                    label: Text(e.value.$1, style: AppText.micro),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(s.privateRoomsEnterRoom),
            onPressed: () async {
              // Buka chat room mode private.
              final room = await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchRoomById(_createdId!);
              if (!mounted) return;
              if (room != null) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) =>
                        RoomChatScreen(room: RoomModel.fromMap('$_createdId', room)),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── QR Scanner → request join → antrean approval ──

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  MobileScannerController? _ctrl;
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled || cap.barcodes.isEmpty) return;
    final raw = cap.barcodes.first.rawValue ?? '';
    if (!raw.startsWith('chatyuk://room/join')) return;
    _handled = true;
    _processPayload(raw);
  }

  Future<void> _processPayload(String raw) async {
    final uri = Uri.parse(raw);
    final roomId = uri.queryParameters['id'] ?? '';
    var token = uri.queryParameters['t'] ?? '';

    // Validasi token vs rooms.join_token.
    try {
      final row = await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchRoomById(roomId);
      final serverToken = '${row?['join_token'] ?? ''}';
      if (serverToken.isEmpty || token != serverToken) {
        if (mounted) {
          setState(() => _error = 'QR tidak valid / sudah di-rotate');
        }
        return;
      }
      // Rotasi otomatis setelah dipakai — QR sekali pakai per share.
      await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).rotateToken(roomId);

      final res =
          await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).joinPrivateRoom(roomId);
      final pending = res['pending'] == true;
      if (!mounted) return;
      final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(pending ? s.privateRoomsJoinPendingTitle : s.privateRoomsJoinedTitle),
          content: Text(pending
              ? s.privateRoomsJoinPendingBody
              : s.privateRoomsJoinedBody),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); // tutup dialog
                if (!pending) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          RoomChatScreen(room: RoomModel.fromMap(roomId, row ?? {})),
                    ),
                  );
                }
              },
              child: Text(s.btnClose),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _ctrl ??= MobileScannerController();
    final s = ref.watch(localeProvider).s;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(s.privateRoomsScanQr, style: AppText.title.copyWith(color: Colors.white)),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          Positioned(
            // Insets bawah (nav bar) — edge-to-edge Android 15.
            bottom: 48 + MediaQuery.paddingOf(context).bottom,
            left: 24,
            right: 24,
            child: Text(
              _error ?? s.privateRoomsScanHint,
              textAlign: TextAlign.center,
              style: AppText.bodySmall.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}