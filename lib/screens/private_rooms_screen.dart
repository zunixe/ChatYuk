import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../models/room_model.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/private_room_service.dart';
import '../services/room_service.dart';
import 'room_chat_screen.dart';

/// Daftar private room milik/diikuti + buat room baru (QR join).
/// Fitur fase 1 — hanya admin build (gate di titik navigasi).
class PrivateRoomsScreen extends StatefulWidget {
  const PrivateRoomsScreen({super.key});

  @override
  State<PrivateRoomsScreen> createState() => _PrivateRoomsScreenState();
}

class _PrivateRoomsScreenState extends State<PrivateRoomsScreen> {
  final _prv = PrivateRoomService.instance;
  List<Map<String, dynamic>> _myRooms = [];
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = _prv.uid;
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
      final rows = await RoomService().fetchMyMemberships(uid);
      final all = <Map<String, dynamic>>[];
      for (final rid in rows) {
        if (!rid.startsWith('pr_')) continue;
        try {
          final row = await RoomService().fetchRoomById(rid);
          if (row != null) all.add(Map<String, dynamic>.from(row));
        } catch (_) {}
      }
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
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;

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
          s.createRoomTitle,
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RoomChatScreen(room: RoomModel.fromMap('${room['id']}', room)),
      ),
    );
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
        Provider.of<AuthProvider>(context, listen: false).uid;

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
                style: const TextStyle(fontSize: 18),
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

class CreatePrivateRoomScreen extends StatefulWidget {
  const CreatePrivateRoomScreen({super.key});

  @override
  State<CreatePrivateRoomScreen> createState() =>
      _CreatePrivateRoomScreenState();
}

class _CreatePrivateRoomScreenState extends State<CreatePrivateRoomScreen> {
  final _nameCtrl = TextEditingController();
  String _icon = '🔒';
  bool _creating = false;
  String? _createdId;
  String? _joinToken;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 3 || mounted == false) return;
    setState(() => _creating = true);
    try {
      final myCountry =
          context.read<AuthProvider>().profile?.country ?? 'Indonesia';
      final res = await RoomService().createPrivateRoom(
        name: name,
        icon: _icon,
        country: myCountry,
      );
      if (!mounted) return;
      setState(() {
        _createdId = '${res['id'] ?? ''}';
        _joinToken = '${res['join_token'] ?? ''}';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _rotateToken() async {
    if (_createdId == null) return;
    await PrivateRoomService.instance.rotateToken(_createdId!);
    // Refresh token dari server.
    try {
      final row = await RoomService().fetchRoomById(_createdId!);
      if (mounted && row != null) {
        setState(() => _joinToken = '${row['join_token'] ?? ''}');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.createRoomTitle, style: AppText.title),
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
                          label: Text(ic, style: const TextStyle(fontSize: 20)),
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
                      label: Text(s.btnCreateRoom),
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
          FilledButton.icon(
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(s.privateRoomsEnterRoom),
            onPressed: () async {
              // Buka chat room mode private.
              final room = await RoomService().fetchRoomById(_createdId!);
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

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
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
      final row = await RoomService().fetchRoomById(roomId);
      final serverToken = '${row?['join_token'] ?? ''}';
      if (serverToken.isEmpty || token != serverToken) {
        if (mounted) {
          setState(() => _error = 'QR tidak valid / sudah di-rotate');
        }
        return;
      }
      // Rotasi otomatis setelah dipakai — QR sekali pakai per share.
      await PrivateRoomService.instance.rotateToken(roomId);

      final res =
          await RoomService().joinPrivateRoom(roomId);
      final pending = res['pending'] == true;
      if (!mounted) return;
      final s = context.read<LocaleProvider>().s;
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
    final s = context.watch<LocaleProvider>().s;
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
            bottom: 48,
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