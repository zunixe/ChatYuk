import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/locale_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/room_service.dart';
import '../services/private_room_service.dart';

/// Bottom sheet anggota private room: role, kick, jadikan admin,
/// izinkan broadcast, dan antrean approval (untuk admin).
class RoomMembersSheet extends StatefulWidget {
  const RoomMembersSheet({
    super.key,
    required this.roomId,
    required this.myRole,
    required this.onChanged,
  });

  final String roomId;
  final String myRole; // owner | admin | member
  final VoidCallback onChanged;

  @override
  State<RoomMembersSheet> createState() => _RoomMembersSheetState();
}

class _RoomMembersSheetState extends State<RoomMembersSheet> {
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  final _pwCtrl = TextEditingController();
  bool _pwSaving = false;
  String? _liveUid;

  late final S s;
  bool get canModerate =>
      widget.myRole == 'owner' || widget.myRole == 'admin';

  @override
  void initState() {
    super.initState();
    s = context.read<LocaleProvider>().s;
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await PrivateRoomService.instance.listMembers(widget.roomId);
      final pending = canModerate
          ? await PrivateRoomService.instance
              .listJoinRequests(widget.roomId)
              .then((rows) => rows) // RPC guard admin di server
          : <Map<String, dynamic>>[];
      final room = await RoomService().fetchRoomById(widget.roomId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _pending = pending;
        _liveUid = room?['live_uid']?.toString();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() fn) async {
    try {
      await fn();
      await _load();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _resetPw(bool remove) async {
    setState(() => _pwSaving = true);
    try {
      await RoomService().resetRoomPassword(widget.roomId, remove ? null : _pwCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgPasswordReset)));
      _pwCtrl.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _pwSaving = false);
    }
  }

  void _confirm(String title, String body, Future<void> Function() fn) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _act(fn);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }


  Future<void> _showQrDialog(BuildContext context) async {
    final row = await RoomService().fetchRoomById(widget.roomId);
    final token = '${row?['join_token'] ?? ''}';
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
                data:
                    'chatyuk://room/join?id=${widget.roomId}&t=$token',
                size: 210),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(s.privateRoomsCopyLink),
              onPressed: () {
                Clipboard.setData(ClipboardData(
                    text:
                        'chatyuk://room/join?id=${widget.roomId}&t=$token'));
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    '${s.privateRoomsMembersTitle} (${_members.length})',
                    style: AppText.title,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: s.privateRoomsShowQr,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    onPressed: () => _showQrDialog(context),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  // Antrean approval (hanya owner/admin).
                  if (canModerate) ...[
                    Text(
                      s.privateRoomsPendingQueue,
                      style: AppText.label.copyWith(color: AppTheme.accent),
                    ),
                    const SizedBox(height: 6),
                    for (final p in _pending)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.bgInput.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_top_rounded,
                                size: 16, color: AppTheme.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${p['nickname'] ?? '?'}',
                                style: AppText.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.check_circle_rounded,
                                  color: Colors.green, size: 20),
                              onPressed: () => _act(() =>
                                  PrivateRoomService.instance.approveJoin(
                                      widget.roomId, '${p['user_id']}')),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.cancel_rounded,
                                  color: AppTheme.danger, size: 20),
                              onPressed: () => _act(() =>
                                  PrivateRoomService.instance.rejectJoin(
                                      widget.roomId, '${p['user_id']}')),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 24),
                  ],
                  if (widget.myRole == 'owner') ...[
                    Text(s.resetPasswordTitle, style: AppText.label.copyWith(color: AppTheme.primary)),
                    const SizedBox(height: 6),
                    TextField(controller: _pwCtrl, obscureText: true, decoration: InputDecoration(hintText: s.resetPasswordHint, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8))),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: FilledButton(onPressed: _pwSaving ? null : () => _resetPw(false), child: Text(s.btnResetPassword))),
                      const SizedBox(width: 8),
                      TextButton(onPressed: _pwSaving ? null : () => _resetPw(true), child: Text(s.btnRemovePassword)),
                    ]),
                    const Divider(height: 24),
                  ],
                  // Member list.
                  for (final m in _members) ...[
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.15),
                        child: Text(
                          ('${m['nickname'] ?? '?'}')
                                  .isNotEmpty
                              ? '${m['nickname']}'[0].toUpperCase()
                              : '?',
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        '${m['nickname'] ?? '?'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                       subtitle: Row(
                        children: [
                          Text(
                            switch (m['role']) {
                              'owner' => s.roomRoleOwner,
                              'admin' => s.roomRoleAdmin,
                              _ => s.roomRoleMember,
                            },
                            style: AppText.micro.copyWith(
                              color: (m['role'] == 'owner' ||
                                      m['role'] == 'admin')
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if ('${m['user_id']}' == _liveUid || '${m['broadcast_granted']}' == 'true')
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: ('${m['user_id']}' == _liveUid
                                          ? Colors.red
                                          : AppTheme.primary)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    '${m['user_id']}' == _liveUid
                                        ? Icons.live_tv_rounded
                                        : Icons.videocam_rounded,
                                    size: 10,
                                    color: '${m['user_id']}' == _liveUid ? Colors.red : AppTheme.primary,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '${m['user_id']}' == _liveUid
                                        ? s.privateRoomsLiveNow
                                        : s.roomActionBroadcast,
                                    style: AppText.micro.copyWith(
                                        color: '${m['user_id']}' == _liveUid
                                            ? Colors.red
                                            : AppTheme.primary,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      trailing: _memberActions(m),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget? _memberActions(Map<String, dynamic> m) {
    final uid = '${m['user_id'] ?? ''}';
    final myUid = PrivateRoomService.instance.uid;
    final role = '${m['role'] ?? 'member'}';

    if (uid == myUid || uid.isEmpty) return null;
    if (!canModerate && widget.myRole != 'owner') return null;

    final items = <PopupMenuEntry<String>>[];
    if (widget.myRole == 'owner' && role != 'owner') {
      items.add(PopupMenuItem(
        value: 'promote',
        child: Text(role == 'admin'
            ? s.roomActionDemote
            : s.roomActionPromote),
      ));
    }
    if (!(role == 'owner' || (role == 'admin' && widget.myRole == 'admin'))) {
      items.add(PopupMenuItem(value: 'kick', child: Text(s.roomActionKick)));
    }
    items.add(PopupMenuItem(
      value: 'broadcast',
      child: Text(
          (uid == _liveUid || '${m['broadcast_granted']}' == 'true')
              ? s.roomActionRevokeBroadcast
              : s.roomActionBroadcast),
    ));

    return PopupMenuButton<String>(
      onSelected: (v) {
        switch (v) {
          case 'promote':
            _act(() => PrivateRoomService.instance.setRole(
                widget.roomId, uid, role == 'admin' ? 'member' : 'admin'));
            break;
          case 'kick':
            _confirm(
              s.roomKickConfirmTitle,
              s.roomKickConfirmBody,
              () => PrivateRoomService.instance.kick(widget.roomId, uid),
            );
            break;
          case 'broadcast':
            final isCurrentlyGranted = uid == _liveUid || '${m['broadcast_granted']}' == 'true';
            _act(() async {
              if (isCurrentlyGranted) {
                await PrivateRoomService.instance.revokeBroadcast(widget.roomId, uid);
              } else {
                await PrivateRoomService.instance.grantBroadcast(widget.roomId, uid);
              }
            });
            break;
        }
      },
      itemBuilder: (_) => items,
      icon: Icon(Icons.more_vert, size: 18, color: AppTheme.textSecondary),
    );
  }
}