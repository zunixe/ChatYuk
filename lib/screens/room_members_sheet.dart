import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/room_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/avatar_provider.dart';
import '../providers/riverpod/social_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../widgets/sheet_drag_handle.dart';
import '../widgets/person_avatar.dart';
import '../config/theme.dart';

/// Bottom sheet anggota private room: role, kick, jadikan admin,
/// izinkan broadcast, dan antrean approval (untuk admin).
class RoomMembersSheet extends ConsumerStatefulWidget {
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
  ConsumerState<RoomMembersSheet> createState() => _RoomMembersSheetState();
}

class _RoomMembersSheetState extends ConsumerState<RoomMembersSheet> {
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
    s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).listMembers(widget.roomId);
      final pending = canModerate
          ? await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier)
              .listJoinRequests(widget.roomId)
              .then((rows) => rows) // RPC guard admin di server
          : <Map<String, dynamic>>[];
      final room = await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchRoomById(widget.roomId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _pending = pending;
        _liveUid = room?['live_uid']?.toString();
        _loading = false;
      });
      // Prefetch avatar semua anggota (1 query) — cegah N fetch serial saat
      // list dirender (foto muncul cepat, bukan satu-satu lambat).
      final uids = members
          .map((m) => '${m['user_id'] ?? ''}')
          .where((u) => u.isNotEmpty)
          .toList();
      if (uids.isNotEmpty && mounted) {
        ProviderScope.containerOf(context, listen: false).read(avatarProvider).prefetch(uids);
      }
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
        SnackBar(content: Text(ProviderScope.containerOf(context, listen: false).read(localeProvider).s.errGeneric), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _resetPw(bool remove) async {
    setState(() => _pwSaving = true);
    try {
      await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).resetRoomPassword(widget.roomId, remove ? null : _pwCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgPasswordReset)));
      _pwCtrl.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ProviderScope.containerOf(context, listen: false).read(localeProvider).s.errGeneric)));
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
            child: Text(s.btnOk),
          ),
        ],
      ),
    );
  }


  /// Picker invite: daftar orang yang pernah chat (teman/bukan),
  /// di luar member aktif. Tap → invite langsung jadi member.
  Future<void> _showInvitePicker(BuildContext context) async {
    final memberIds =
        _members.map((m) => '${m['user_id'] ?? ''}').toSet();
    await showGroupInvitePicker(
      context: context,
      roomId: widget.roomId,
      excludeUids: memberIds,
      onInvited: () async {
        await _load();
        widget.onChanged();
      },
    );
  }

  Future<void> _showQrDialog(BuildContext context) async {    final row = await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchRoomById(widget.roomId);
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
    final s = ref.watch(localeProvider).s;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        // Root DI-BERI BACKGROUND SOLID: pemanggil (GroupInfoScreen) membuka
        // via showModalBottomSheet(backgroundColor: transparent) + Draggable
        // → tanpa ini seluruh card sheet TRANSPARAN (konten tembus ke belakang).
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    '${s.privateRoomsMembersTitle} (${_members.length})',
                    style: AppText.title,
                  ),
                  const Spacer(),
                  if (canModerate)
                    IconButton(
                      tooltip: s.roomInviteTitle,
                      icon: const Icon(Icons.person_add_alt_rounded),
                      onPressed: () => _showInvitePicker(context),
                    ),
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
              // Lazy: antrean + password kecil via SliverToBoxAdapter,
              // daftar anggota (bisa ratusan) via SliverList.builder.
              child: CustomScrollView(
                controller: scrollCtrl,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                  ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).approveJoin(
                                      widget.roomId, '${p['user_id']}')),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.cancel_rounded,
                                  color: AppTheme.danger, size: 20),
                              onPressed: () => _act(() =>
                                  ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).rejectJoin(
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
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _pwSaving ? null : () => _resetPw(false),
                          child: Text(s.btnResetPassword),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                        ),
                        onPressed: _pwSaving ? null : () => _resetPw(true),
                        child: Text(s.btnRemovePassword),
                      ),
                    ]),
                    const Divider(height: 24),
                  ],
                        ],
                      ),
                    ),
                  ),
                  // Daftar anggota LAZY via SliverList (pengganti for eager).
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.builder(
                      itemCount: _members.length,
                      itemBuilder: (_, i) {
                        final m = _members[i];
                        return ListTile(
                      dense: true,
                      // PersonAvatar = standar yang sama persis dengan
                      // Pengguna Online (foto + latar tint + ring gender).
                      leading: PersonAvatar(
                        uid: '${m['user_id'] ?? ''}',
                        name: '${m['nickname'] ?? '?'}',
                        gender: '${m['gender'] ?? ''}',
                        size: 32,
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
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  Widget? _memberActions(Map<String, dynamic> m) {
    final uid = '${m['user_id'] ?? ''}';
    final myUid = ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).prvUid;
    final role = '${m['role'] ?? 'member'}';

    if (uid == myUid || uid.isEmpty) return null;
    if (!canModerate && widget.myRole != 'owner') return null;

    final items = <PopupMenuEntry<String>>[];
    // Warna teks EKSPLISIT (textPrimary) — dulu Text() polos → di theme app
    // teks menu jatuh ke default pucat/nyaris transparan.
    Widget mi(String t) =>
        Text(t, style: AppText.body.copyWith(color: AppTheme.textPrimary));
    // Promote member→admin: owner & admin. Demote admin→member: owner saja
    // (server selaras kick: admin tak bisa demote/kick admin).
    if ((widget.myRole == 'owner' || widget.myRole == 'admin') &&
        role == 'member') {
      items.add(PopupMenuItem(value: 'promote', child: mi(s.roomActionPromote)));
    }
    if (widget.myRole == 'owner' && role == 'admin') {
      items.add(PopupMenuItem(value: 'promote', child: mi(s.roomActionDemote)));
    }
    if (!(role == 'owner' || (role == 'admin' && widget.myRole == 'admin'))) {
      items.add(PopupMenuItem(value: 'kick', child: mi(s.roomActionKick)));
    }
    items.add(PopupMenuItem(
      value: 'broadcast',
      child: mi((uid == _liveUid || '${m['broadcast_granted']}' == 'true')
          ? s.roomActionRevokeBroadcast
          : s.roomActionBroadcast),
    ));

    return PopupMenuButton<String>(
      color: AppTheme.bgCard,
      onSelected: (v) {
        switch (v) {
          case 'promote':
            _act(() => ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).setRole(
                widget.roomId, uid, role == 'admin' ? 'member' : 'admin'));
            break;
          case 'kick':
            _confirm(
              s.roomKickConfirmTitle,
              s.roomKickConfirmBody,
              () => ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).kick(widget.roomId, uid),
            );
            break;
          case 'broadcast':
            final isCurrentlyGranted = uid == _liveUid || '${m['broadcast_granted']}' == 'true';
            _act(() async {
              if (isCurrentlyGranted) {
                await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).revokeBroadcast(widget.roomId, uid);
              } else {
                await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).grantBroadcast(widget.roomId, uid);
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

/// Picker invite grup reusable (dipakai members sheet + menu ⋮ + buat grup).
///
/// Fitur:
///  - SEARCH nama (client-side, atas orang yang sudah dimuat).
///  - Dua SECTION: "Teman" (uid ∈ [socialProvider].state.friends) lalu
///    "Lainnya".
///  - MULTI-INVITE: tap = invite, baris ditandai ✓ "Sudah diundang", picker
///    TETAP TERBUKA (undang beberapa sebelum tutup).
///  - [onInvited] dipanggil tiap sukses (pemanggil bisa lacak/menyegarkan).
Future<void> showGroupInvitePicker({
  required BuildContext context,
  required String roomId,
  required Set<String> excludeUids,
  required VoidCallback onInvited,
  void Function(String uid, String name, String gender)? onInvitedOne,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _GroupInvitePickerSheet(
      roomId: roomId,
      excludeUids: excludeUids,
      onInvited: onInvited,
      onInvitedOne: onInvitedOne,
    ),
  );
}

class _GroupInvitePickerSheet extends ConsumerStatefulWidget {
  final String roomId;
  final Set<String> excludeUids;
  final VoidCallback onInvited;
  final void Function(String uid, String name, String gender)? onInvitedOne;
  const _GroupInvitePickerSheet({
    required this.roomId,
    required this.excludeUids,
    required this.onInvited,
    this.onInvitedOne,
  });

  @override
  ConsumerState<_GroupInvitePickerSheet> createState() =>
      _GroupInvitePickerSheetState();
}

class _GroupInvitePickerSheetState
    extends ConsumerState<_GroupInvitePickerSheet> {
  final _searchCtrl = TextEditingController();
  final Set<String> _invited = {};
  final Map<String, String> _genderByUid = {};
  String _query = '';

  String _genderOf(String uid) => _genderByUid[uid] ?? '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _invite(String uid, String name, S s) async {
    if (_invited.contains(uid)) return;
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(roomProvider.notifier)
          .invite(widget.roomId, uid);
      if (!mounted) return;
      setState(() => _invited.add(uid));
      widget.onInvited();
      widget.onInvitedOne?.call(uid, name, _genderOf(uid));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name — ${s.roomInvitedOk}')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('Room full')
          ? s.roomInviteFull
          : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final myUid =
        ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).prvUid;
    final friends =
        ref.watch(socialProvider.select((st) => st.friends));
    final seed = (myUid != null && myUid.isNotEmpty)
        ? ProviderScope.containerOf(context, listen: false)
            .read(chatProvider.notifier)
            .lastPrivateChatsSnapshot(myUid)
        : null;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.roomInviteTitle,
                        style: AppText.title
                            .copyWith(color: AppTheme.textPrimary)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Search.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                style: AppText.body,
                decoration: InputDecoration(
                  hintText: s.roomInviteSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.bgInput,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<PrivateChatInfo>>(
                stream: myUid != null && myUid.isNotEmpty
                    ? ProviderScope.containerOf(context, listen: false)
                        .read(chatProvider.notifier)
                        .getMyPrivateChats(myUid)
                    : const Stream.empty(),
                initialData: seed,
                builder: (_, snap) {
                  final seen = <String>{};
                  final all = <Map<String, String>>[];
                  for (final c in (snap.data ?? const <PrivateChatInfo>[])) {
                    for (final p in c.participants) {
                      if (p.isEmpty ||
                          p == myUid ||
                          !seen.add(p) ||
                          widget.excludeUids.contains(p)) {
                        continue;
                      }
                      all.add({
                        'uid': p,
                        'name': c.participantNames[p] ?? '?',
                        'gender': c.participantGenders[p] ?? '',
                      });
                      _genderByUid[p] = c.participantGenders[p] ?? '';
                    }
                  }
                  // Filter search.
                  final people = _query.isEmpty
                      ? all
                      : all
                          .where((e) =>
                              (e['name'] ?? '').toLowerCase().contains(_query))
                          .toList();
                  if (people.isEmpty) {
                    return Center(
                      child: Text(s.noResults,
                          style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary)),
                    );
                  }
                  // Pisah: teman dulu, lalu lainnya.
                  final friendList =
                      people.where((e) => friends.contains(e['uid'])).toList();
                  final otherList =
                      people.where((e) => !friends.contains(e['uid'])).toList();

                  final rows = <Widget>[];
                  if (friendList.isNotEmpty) {
                    rows.add(_sectionHeader(s.roomInviteFriends));
                    rows.addAll(friendList.map((e) => _tile(s, e)));
                  }
                  if (otherList.isNotEmpty) {
                    rows.add(_sectionHeader(s.roomInviteOthers));
                    rows.addAll(otherList.map((e) => _tile(s, e)));
                  }
                  // ListView.builder = lazy (batas awal viewport + scroll).
                  return ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) => rows[i],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(
          label,
          style: AppText.bodySmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _tile(S s, Map<String, String> e) {
    final uid = e['uid']!;
    final name = e['name'] ?? '?';
    final done = _invited.contains(uid);
    return ListTile(
      dense: true,
      leading: PersonAvatar(uid: uid, name: name, gender: e['gender'] ?? '', size: 32),
      title: Text(name, style: AppText.bodySmall),
      trailing: done
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    size: 18, color: AppTheme.online),
                const SizedBox(width: 4),
                Text(s.roomInviteAlready,
                    style: AppText.micro
                        .copyWith(color: AppTheme.textSecondary)),
              ],
            )
          : const Icon(Icons.person_add_alt_rounded,
              size: 18, color: AppTheme.primary),
      onTap: done ? null : () => _invite(uid, name, s),
    );
  }
}
