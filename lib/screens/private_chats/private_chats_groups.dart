part of '../private_chats_screen.dart';

// Baris GRUP daftar Pesan + helper teks (_chatSubtitle/_formatTime) dan
// pembuka grup. Dipisah dari private_chats_build.dart agar file itu < 1000
// baris (REVIEW_2026-10-24 ARCH-01/R-11). Perilaku tidak berubah.

mixin _PcGroupsMx on _PcBase {
  /// Tap AVATAR kartu → zoom foto (pola sama menu "Pengguna Online"), BUKAN
  /// buka chat/profil. Foto diambil dari cache avatar (RAM→disk, sinkron);
  /// bila kosong → dialog lingkaran inisial.
  void _showAvatarZoomFor(
    String uid,
    String name,
    String gender,
  ) {
    final b64 = ProviderScope.containerOf(context, listen: false)
        .read(avatarProvider)
        .cachedSyncIncludeDisk(uid) ??
        '';
    showAvatarZoomDialog(
      context,
      b64: b64,
      bgColor: PersonAvatar.colorFor(gender),
      initial: name.isNotEmpty ? name[0].toUpperCase() : '?',
    );
  }

  String _chatSubtitle(PrivateChatInfo chat, String myUid, S s) {
    final otherUid = chat.participants.firstWhere(
      (p) => p != myUid,
      orElse: () => '',
    );
    final gender = chat.participantGenders[otherUid] ?? '';
    final age = chat.participantAges[otherUid] ?? 0;
    final loc = chat.participantLocations[otherUid] ?? '';
    final genderLabel = gender == 'male'
        ? s.genderMale
        : gender == 'female'
        ? s.genderFemale
        : '';
    final genderAgePart = genderLabel.isNotEmpty
        ? '$genderLabel${age > 0 ? ' $age' : ''}'
        : (age > 0 ? '$age' : '');
    final parts = [
      if (genderAgePart.isNotEmpty) genderAgePart,
      if (loc.isNotEmpty) loc,
    ];
    if (parts.isEmpty) return '';
    return parts.join(' · ');
  }

  String _formatTime(DateTime dt, S s) {
    return formatRelativeTime(dt, isId: s.isId);
  }

  /// Baris GRUP di daftar Pesan (ikon, nama, preview, waktu, badge unread).
  /// Baris GRUP di daftar Pesan. Geser KANAN = sematkan/lepas sematan,
  /// geser KIRI = hapus (pemilik) atau keluar (anggota) — pola sama seperti
  /// baris chat private.
  Widget _groupRow(RoomModel g, S s) {
    final unread = g.unread;
    final isPinned = GroupPinStore.isPinned(g.id);
    final preview = g.lastText.isNotEmpty
        ? (g.lastSenderName.isNotEmpty
            ? '${g.lastSenderName}: ${g.lastText}'
            : g.lastText)
        : s.tabGroups;
    final timeStr = g.lastAt == null ? '' : formatBubbleTime(g.lastAt!);
    return Dismissible(
      key: ValueKey('group_${g.id}'),
      direction: DismissDirection.horizontal,
      background: _groupSwipeBg(
        alignLeft: true,
        icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
        label: isPinned ? s.btnUnpin : s.btnPin,
        color: AppTheme.primary,
      ),
      secondaryBackground: _groupSwipeBg(
        alignLeft: false,
        icon: Icons.delete_outline,
        label: s.btnDelete,
        color: AppTheme.danger,
      ),
      confirmDismiss: (direction) async => _onGroupSwipe(g, s, direction),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openGroup(g),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // PEMBEDA: grup = kotak membulat (chat personal = lingkaran).
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.bgInput,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      g.icon.isEmpty ? '\u{1F465}' : g.icon,
                      style: TextStyle(fontSize: AppGlyph.md),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                g.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.bodyStrong,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _groupBadge(g, s),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: AppText.micro.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      if (isPinned)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.push_pin,
                            size: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unread',
                            style: AppText.micro.copyWith(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pill kecil penanda GRUP (`Grup` / `Grup · 12`) — pembeda eksplisit dari
  /// chat personal.
  Widget _groupBadge(RoomModel g, S s) {
    final label = g.memberCount > 0
        ? s.groupMemberCountLabel(g.memberCount)
        : s.tabGroups;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(
          alpha: AppTheme.isDark ? 0.20 : 0.10,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppText.label.copyWith(color: AppTheme.primary),
      ),
    );
  }

  /// Latar aksi geser baris grup (sama tampilan dengan baris chat private).
  Widget _groupSwipeBg({
    required bool alignLeft,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: EdgeInsets.only(left: alignLeft ? 20 : 0, right: alignLeft ? 0 : 20),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(label, style: AppText.caption.copyWith(color: Colors.white)),
        ],
      ),
    );
  }

  /// Aksi geser baris grup. Kembalian `true` = biarkan baris ter-dismiss
  /// (dipakai saat hapus/keluar sudah sukses → daftar di-reload).
  Future<bool> _onGroupSwipe(
    RoomModel g,
    S s,
    DismissDirection direction,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // Geser KANAN → sematkan / lepas sematan (lokal, tanpa network).
    if (direction == DismissDirection.startToEnd) {
      final nowPinned = GroupPinStore.toggle(g.id);
      if (mounted) setState(() {});
      messenger.showSnackBar(
        SnackBar(content: Text(nowPinned ? s.msgPinned : s.msgUnpinned)),
      );
      return false;
    }
    // Geser KIRI → hapus grup (pemilik) atau keluar (anggota).
    final myUid = ref.read(authProvider).uid ?? '';
    final isOwner = g.ownerId.isNotEmpty && g.ownerId == myUid;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isOwner ? s.btnDeleteGroup : s.btnLeaveGroup),
        content: Text(isOwner ? s.deleteGroupConfirm : s.leaveGroupConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isOwner ? s.btnDeleteGroup : s.btnLeaveGroup,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      final rooms = ref.read(roomProvider.notifier);
      if (isOwner) {
        await rooms.deleteRoom(g.id);
      } else {
        await rooms.leavePrivate(g.id);
        await rooms.loadMyGroups(refresh: true);
      }
      GroupPinStore.remove(g.id);
      if (mounted) setState(() {});
      messenger.showSnackBar(
        SnackBar(content: Text(isOwner ? s.groupDeleted : s.groupLeft)),
      );
      return false;
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.errGroupAction)));
      return false;
    }
  }

  void _openGroup(RoomModel g) {
    final navKey = navKeyRoom(g.id);
    if (!tryClaimNav(navKey)) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RoomChatScreen(room: g)))
        .then((_) => releaseNav(navKey));
  }
}
