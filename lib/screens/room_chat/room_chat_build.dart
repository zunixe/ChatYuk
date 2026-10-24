part of '../room_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _RcBuildMx on _RoomChatBase {
  Widget _buildMessageList(S s, AuthNotifier auth) {
    return Expanded(
      child: Stack(
        children: [
          StreamBuilder<List<MessageModel>>(
            stream: _msgsStream,
            // FRAME PERTAMA LANGSUNG: data awal dari cache memori
            // (sinkron) → pesan "nempel" sejak frame pertama (ala
            // WhatsApp), bukan layar kosong lalu muncul. Pola sama
            // seperti private chat.
            initialData:
                MessageCache.instance.peekMessages(
                  'room_${widget.room.id}',
                ) ??
                const <MessageModel>[],
            builder: (_, snap) {
              final s = ProviderScope.containerOf(
                context,
                listen: false,
              ).read(localeProvider).s;
              // Persisten anti-glitch bawah: saat stream belum emit /
              // blip kosong, tampilkan batch terakhir (_lastMsgs diisi
              // listener tiap emisi) — list tidak kedip hilang.
              final raw = snap.data;
              final msgs =
                  (raw == null || raw.isEmpty) && _lastMsgs.isNotEmpty
                  ? _lastMsgs
                  : (raw ?? []);
              // Bubble optimistik milik sendiri (centang-1) selalu tampil
              // di ujung list — walau offline, walau stream belum emit.
              // `_pending` biasanya kosong: jangan alokasi list gabungan
              // tiap build kalau tidak perlu (identitas `msgs` stabil dari
              // stream → `_deriveItems` tetap cache-hit).
              final all = _pending.isEmpty ? msgs : [...msgs, ..._pending];
              if (all.isEmpty) {
                // Room baru/kosong — tampilkan layar kosong saja,
                // tanpa ikon/teks "mulai percakapan".
                return const SizedBox.shrink();
              }
              if (msgs.length > _lastMsgCount && _isNearBottom) {
                _lastMsgCount = msgs.length;
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _scrollToBottom(),
                );
              } else {
                _lastMsgCount = msgs.length;
              }
              // Selipkan chip tanggal (Hari ini/Kemarin/tanggal) di antara grup hari,
              // pola WhatsApp — item list berisi pesan + separator tanggal.
              // PRIVASI: kumpulan id pesan terhapus — quote reply yang
              // menunjuk pesan ini dirender "Pesan dihapus", bukan isinya.
              // Derivasi di-CACHE (lihat `_deriveItems`): rebuild parent
              // (reaksi/starred/typing/menu) tidak lagi menghitung O(N).
              final now = DateTime.now();
              final (items, deletedIds) = _deriveItems(
                s,
                msgs,
                all,
                day: DateTime(now.year, now.month, now.day),
              );
              // Anti-kedip: key→index agar ListView MEMINDAHKAN bubble yang
              // sama saat index bergeser (bukan membuat ulang). Sama private.
              final keyIndex = <String, int>{};
              for (var i = 0; i < items.length; i++) {
                final it = items[items.length - 1 - i];
                if (it.isAlbum) {
                  keyIndex['album_${it.album.first.id}'] = i;
                } else if (it.msg != null) {
                  keyIndex['m_${it.msg!.id}'] = i;
                }
              }
              return ListView.builder(
                controller: _scrollCtrl,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                findChildIndexCallback: (key) =>
                    key is ValueKey<String> ? keyIndex[key.value] : null,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[items.length - 1 - i];
                  if (item.dateLabel != null)
                    return DateChip(label: item.dateLabel!);
                  // ALBUM: satu bubble grid (bukan N bubble).
                  if (item.isAlbum) {
                    final ph = item.album;
                    return RepaintBoundary(
                      key: ValueKey('album_${ph.first.id}'),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: ph.first.senderId == auth.uid
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: PhotoAlbumBubble(
                            photos: ph,
                            chatKey: 'room_${widget.room.id}',
                            timeStr: formatBubbleTime(ph.last.timestamp),
                            showChecks: false,
                            isMe: ph.first.senderId == auth.uid,
                            cardColor: ph.first.senderId == auth.uid
                                ? AppTheme.primary.withValues(alpha: 0.25)
                                : AppTheme.bgInput,
                          ),
                        ),
                      ),
                    );
                  }
                  final m = item.msg!;
                  final isMe = m.senderId == auth.uid;
                  final mkey = _msgKeys.putIfAbsent(
                    m.id,
                    () => GlobalKey(),
                  );
                  final selected = selectedIds.contains(m.id);
                  final reacts = reactions[m.id];
                  final starred = starredIds.contains(m.id);
                  // RepaintBoundary per baris: satu bubble berubah
                  // (reaksi/star/centang/highlight) tidak merepaint seluruh
                  // list panjang. Pola sama seperti kartu list lain.
                  return RepaintBoundary(
                    key: ValueKey('m_${m.id}'),
                    child: Container(
                      // Tanpa wash biru selebar baris (sama private chat —
                      // hanya border bubble). Wash tersisa hanya untuk flash
                      // sesaat saat lompat ke pesan (_highlightId).
                      color: _highlightId == m.id
                          ? AppTheme.primary.withValues(alpha: 0.22)
                          : Colors.transparent,
                      child: CompositedTransformTarget(
                        link: linkFor(m.id),
                        // AppGestureDetector: tahan 600ms (longPressBubble) —
                        // sama seperti bubble private chat: hindari toolbar
                        // muncul tak sengaja saat scroll.
                        child: AppGestureDetector(
                          onLongPressStart: (d) =>
                              onMessageLongPress(d, m, linkFor(m.id)),
                          onTap: inSelection ? () => toggleSelect(m) : null,
                          longPressDuration: AppTiming.longPressBubble,
                          child: SwipeToReply(
                            // Geser kanan = balas (grup & room). Pesan sendiri
                            // dikecualikan agar tidak bentrok swipe-back sistem.
                            enabled:
                                !inSelection &&
                                m.senderId != auth.uid &&
                                !m.isDeleted,
                            onReply: () => replyMessage(m),
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (m.isForwarded)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 4,
                                      right: 4,
                                      bottom: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.forward,
                                          size: 14,
                                          color: AppTheme.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          s.msgForwardedLabel,
                                          style: AppText.caption.copyWith(
                                            color: AppTheme.textSecondary,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      // Border seleksi digambar DI DALAM bubble
                                      // (sama seperti private chat) — dulu di
                                      // Container pembungkus sehingga border
                                      // memanjang sampai ujung layar.
                                      child: RoomMessageBubble(
                                        key: mkey,
                                        msg: m,
                                        isMe: isMe,
                                        isPending: m.id.startsWith(
                                          'pending-',
                                        ),
                                        isQueued: _queuedIds.contains(m.id),
                                        isSelected: selected,
                                        // Link preview hanya auto-fetch untuk 25
                                        // pesan terbaru; sisanya tap-to-load.
                                        autoLinkPreview: i < 25,
                                        codeMaxLines: i < 25 ? null : 40,
                                        color: Color(
                                          userColorPalette[colorHashForUid(
                                                m.senderId,
                                              ) %
                                              userColorPalette.length],
                                        ),
                                        roomId: widget.room.id,
                                        onTapUser: () =>
                                            _onTapUser(m, auth),
                                        deletedIds: deletedIds,
                                        highlightMentionAll:
                                            isPrivateRoom && canModerate,
                                      ),
                                    ),
                                    if (starred)
                                      Positioned(
                                        top: -6,
                                        right: isMe ? 0 : null,
                                        left: isMe ? null : 0,
                                        child: const Icon(
                                          Icons.star,
                                          size: 14,
                                          color: Color(0xFFFFB300),
                                        ),
                                      ),
                                    if (reacts != null && reacts.isNotEmpty)
                                      Positioned(
                                        bottom: -10,
                                        left: isMe ? null : 8,
                                        right: isMe ? 8 : null,
                                        child: ReactionBadge(
                                          counts: reacts,
                                          isMe: isMe,
                                          onTap: inSelection
                                              ? null
                                              : () => openReactionDetail(m),
                                        ),
                                      ),
                                  ],
                                ),
                                if (reacts != null && reacts.isNotEmpty)
                                  const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // Banner approval mengambang — hanya setelah role dicek,
          // tidak menggeser list pesan saat muncul.
          if (isPrivateRoom && _roleChecked && _myRole == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    Colors.orange.withValues(alpha: 0.12),
                    AppTheme.bgCard,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_top_rounded,
                      color: Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.privateRoomNeedApproval,
                        style: AppText.bodySmall.copyWith(
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildRoomAppBar(BuildContext context, S s) {
    // Tombol aksi RAPAT (tanpa padding bawaan IconButton 48px) — kamera &
    // anggota berdempet tanpa jeda.
    Widget tightIcon({
      required String tooltip,
      required Widget icon,
      required VoidCallback? onPressed,
    }) => IconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      // Jeda tipis antar ikon: 0 terlalu dempet, 48 (default) terlalu jauh.
      padding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 38),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
    return AppBar(
      // Nama grup RATA KIRI (Android default bisa ikut centerTitle theme).
      centerTitle: false,
      title: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Text(widget.room.icon, style: TextStyle(fontSize: AppGlyph.sm)),
          SizedBox(width: 8),
          // Nama room panjang (mis. "Testing Broadcast ...") tidak boleh
          // menabrak tombol aksi → elipsis.
          Flexible(child: Text(widget.room.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      actions: [
        if (isPrivateRoom) ...[
          // Hand-raise utk member biasa; Start broadcast utk yang live_uid == saya (di-grant)
          if (_broadcastReady &&
              _liveUid == null &&
              !canModerate &&
              !isGrantedBroadcast)
            IconButton(
              tooltip: s.roomActionHandRaise,
              icon: const Icon(Icons.pan_tool_rounded),
              onPressed: _raiseHand,
            ),
          if (((_broadcastReady &&
                      _liveUid == _auth.uid &&
                      !iAmBroadcasting) ||
                  (_broadcastReady &&
                      _liveUid == null &&
                      isGrantedBroadcast &&
                      !iAmBroadcasting)) ||
              _broadcastStarting)
            // KOMPAK: ikon saja (tooltip = teks lengkap) — dulu pill
            // ikon+teks "Mulai Broadcast" berdesakan dengan nama room di
            // app bar. Teks lengkap tetap ada di banner dalam body.
            _broadcastStarting
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : tightIcon(
                    tooltip: s.privateRoomsStartBroadcast,
                    icon: const Icon(
                      Icons.videocam_rounded,
                      color: AppTheme.primary,
                    ),
                    onPressed: _onStartBroadcastTap,
                  ),
          if (iAmBroadcasting)
            IconButton(
              tooltip: s.privateRoomsStopBroadcast,
              icon: Icon(Icons.cancel_rounded, color: AppTheme.danger),
              onPressed: () async {
                await ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(roomProvider.notifier).stopBroadcast(widget.room.id);
                await _broadcastSession?.stop();
                if (mounted)
                  setState(() {
                    _broadcastSession = null;
                  });
              },
            ),
          tightIcon(
            tooltip: s.privateRoomsMembersTitle,
            icon: Badge(
              isLabelVisible: canModerate && _pendingCount > 0,
              label: Text('$_pendingCount'),
              child: const Icon(Icons.group_outlined),
            ),
            onPressed: _openMembersSheet,
          ),
          PopupMenuButton<String>(
            tooltip: s.menuMore,
            icon: const Icon(Icons.more_vert),
            // Menu menempel di bawah ikon titik-3 (bukan di tengah layar).
            position: PopupMenuPosition.under,
            offset: const Offset(-8, 4),
            onSelected: _onGroupMenu,
            itemBuilder: (_) => [
              if (canModerate)
                PopupMenuItem(
                  value: 'add',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_add_alt_rounded, size: 20),
                    title: Text(s.menuAddMembers),
                  ),
                ),
              PopupMenuItem(
                value: 'info',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline_rounded, size: 20),
                  title: Text(s.menuGroupInfo),
                ),
              ),
              PopupMenuItem(
                value: 'media',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.photo_library_outlined, size: 20),
                  title: Text(s.menuGroupMedia),
                ),
              ),
              PopupMenuItem(
                value: 'search',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.search_rounded, size: 20),
                  title: Text(s.menuSearchMessages),
                ),
              ),
              PopupMenuItem(
                value: 'mute',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _muted
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_outlined,
                    size: 20,
                  ),
                  title: Text(_muted ? s.menuUnmuteNotif : s.menuMuteNotif),
                ),
              ),
              PopupMenuItem(
                value: 'more',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.more_horiz_rounded, size: 20),
                  title: Text(s.menuMore),
                ),
              ),
            ],
          ),
        ] else ...[
          // Mic voice stage (global room): status sesuai sesi.
          VoiceMicButton(
            session: _voiceSession,
            joining: _voiceJoining,
            onTap: _onMicTap,
            onLongPress: _onMicLongPress,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: RoomHeaderToggle(
              showUsers: _showUsers,
              onTap: () => setState(() => _showUsers = !_showUsers),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _onTapUser(MessageModel msg, AuthNotifier auth) async {
    if (msg.senderId == auth.uid) return;
    if (_sheetOpen) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final deletedUsers = container.read(deletedUsersProvider.notifier);
    if (container.read(deletedUsersProvider).contains(msg.senderId)) {
      showChatSnack(context, container.read(localeProvider).s.msgAccountDeleted);
      return;
    }
    // Kasus tap-cepat: bubble lama belum pernah dibangun oleh
    // DeletedUserBuilder → cek & tunggu hasil batch sebelum lanjut.
    // Dulu langsung buka sheet → snack generik "User tidak ditemukan".
    container.read(deletedUsersProvider.notifier).ensureChecked(msg.senderId);
    if (await deletedUsers.checkedDeletedNow(msg.senderId)) {
      if (!mounted) return;
      showChatSnack(context, container.read(localeProvider).s.msgAccountDeleted);
      return;
    }
    if (!mounted) return;
    if (container.read(chatRiverpod.chatProvider.notifier).isBlocked(msg.senderId)) {
      final s = container.read(localeProvider).s;
      showChatSnack(context, s.msgBlocked);
      return;
    }
    _sheetOpen = true;
    showRoomUserActionSheet(
      context,
      msg: msg,
      auth: auth,
      onSheetClosed: () => _sheetOpen = false,
      onReport: _showReportDialog,
    );
  }

  void _showReportDialog(String reportedId, String reportedName) {
    showReportUserDialog(
      context,
      reportedId: reportedId,
      reportedName: reportedName,
    );
  }
}
