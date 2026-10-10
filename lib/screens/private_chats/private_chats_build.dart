part of '../private_chats_screen.dart';

// ignore_for_file: unused_element

mixin _PcBuildMx on _PcBase {
  Widget build(BuildContext context) {
    PerfProbe.buildCount('ChatList');
    ref.watch(themeProvider);
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final s = ref.watch(localeProvider).s;
    final blocked = ref.watch(chatProvider.select((c) => c.blockedUids));
    // PERF (§26): JANGAN select SELURUH daftar online — list itu berubah
    // referensi tiap event presence (heartbeat ~30s) sehingga seluruh
    // ChatList rebuild dan menabrak frame saat pindah tab (terukur 853ms
    // dulu). select HANYA status/nama uid yang benar-benar ada di daftar
    // chat → presence user di luar daftar tidak memicu rebuild.
    final chatOtherUids = _lastChats
        .map(
          (c) =>
              c.participants.firstWhere((p) => p != auth.uid, orElse: () => ''),
        )
        .where((u) => u.isNotEmpty)
        .toSet();
    final onlineRelevant = ref.watch(
      onlineUsersProvider.select((o) {
        final st = <String, String>{};
        final nm = <String, String>{};
        for (final u in o.users) {
          if (!chatOtherUids.contains(u.uid)) continue;
          st[u.uid] = u.status;
          if (u.nickname.isNotEmpty) nm[u.uid] = u.nickname;
        }
        return (status: st, name: nm);
      }),
    );
    if (auth.uid == null) return const SizedBox();

    final effectiveQuery = widget.externalQuery ?? _query;

    // Map uid → status (titik/subtitle) dan uid → nickname live
    // (judul + cari) dari daftar online users. DIPISAH: status tidak
    // boleh dipakai sebagai nama (bug: judul jadi "online"/"idle").
    final statusMap = onlineRelevant.status;
    final liveNameMap = onlineRelevant.name;

    // Recompute hanya kalau input yang memengaruhi hasil berubah (data,
    // query, tab arsip, atau peta nama live). Rebuild lain (tema dsb.)
    // tidak lagi mengurutkan ulang list.
    final queryChanged = effectiveQuery != _lastQueryUsed;
    final liveChanged =
        !_sameStatusMap(statusMap, _statusMap) ||
        !_sameStatusMap(liveNameMap, _nameMap);
    final currentFriends = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(socialProvider.notifier).friends;
    final friendsChanged = !setEquals(currentFriends, _friendSet);
    if (_lastChats.isNotEmpty &&
        (_recomputeDirty || queryChanged || liveChanged || friendsChanged)) {
      _recomputeDirty = false;
      _lastQueryUsed = effectiveQuery;
      _statusMap = Map.of(statusMap);
      _nameMap = Map.of(liveNameMap);
      _friendSet = Set.of(currentFriends);
      _recomputeFiltered(
        myUid: auth.uid ?? '',
        query: effectiveQuery,
        liveNameMap: liveNameMap,
      );
    }

    return PopScope(
      // Back sistem saat seleksi aktif = batal seleksi dulu.
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        debugPrint(
          '[NAV] back veto private-chats selection=${_selected.length}',
        );
        try {
          _clearSelection();
        } catch (e) {
          debugPrint('[NAV] back handler error private-chats: $e');
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgScreen,
        appBar: widget.embedded
            ? null
            : _selectionMode
            ? AppBar(
                leading: IconButton(
                  tooltip: s.btnCancel,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _clearSelection,
                ),
                title: Text(s.selectedCount(_selected.length)),
                actions: _selectionActions(auth.uid!, s),
              )
            : AppBar(title: Text(s.titlePrivateChat)),
        body: Stack(
          children: [
            Column(
              children: [
                // Baris arsip hanya rebuild saat jumlah arsip berubah.
                ValueListenableBuilder<int>(
                  valueListenable: _archivedNotifier,
                  builder: (_, count, __) => count > 0
                      ? _archivedToggle(s, count)
                      : const SizedBox.shrink(),
                ),
                // Filter daftar chat (Semua / Belum dibaca / Anon / Terdaftar).
                // SELALU tampil (termasuk saat seleksi) agar tinggi header
                // KONSTAN → list tidak reflow, kartu yang ditahan tak bergeser.
                // Saat seleksi (embedded), bar seleksi overlay menutupinya.
                if (!_showArchived) _chatFilterBar(s),
                Expanded(
                  child: StreamBuilder<List<PrivateChatInfo>>(
                    stream: _stream,
                    initialData: _initial,
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting &&
                          snap.data == null) {
                        // Loader tema saat stream belum memberi data pertama.
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
                      final chats = (snap.data ?? []).toList();
                      // Data berubah → tandai perlu recompute. Dulu ini memicu
                      // setState() post-frame (build KEDUA di frame pertama tab);
                      // sekarang cukup menandai dirty + recompute di build().
                      if (_lastChats.length != chats.length ||
                          (chats.isNotEmpty && _lastChats != chats)) {
                        _lastChats = chats;
                        _recomputeDirty = true;
                        // JANGAN preload pesan SQLite proaktif di sini. Tiap
                        // preload = query SQLCipher (terukur ~1s untuk query
                        // pertama yang dingin). Dulu `_warmTopChats` memanggil ini
                        // TIAP data list berubah → query menumpuk & SQLCipher
                        // serialize → "buka chat / tutup keyboard ngelag".
                        // Prefetch yang BENAR hanya saat user MEN-TAP chat
                        // (lihat _openChat) — tepat 1 chat yang benar dibuka.
                        // Reset page jika data berubah total
                        if (chats.length != _lastTotal) {
                          _lastTotal = chats.length;
                          _page = 1;
                          _pageNotifier.value = 1;
                        }
                      }
                      // ── RECOMPUTE SINKRON (fix kedip "kosong" 1 frame) ──
                      // Dulu recompute baru jalan di build BERIKUTNYA (lewat blok
                      // `_recomputeDirty` di atas build()). Akibatnya di frame
                      // pertama setelah data tiba, `_listNotifier.value` masih []
                      // → user melihat EmptyStateView ("belum ada chat") kedip
                      // walau data SUDAH ada, baru list muncul frame berikutnya.
                      // `_recomputeFiltered` sinkron & murah (≤50 chat), jadi
                      // jalankan langsung di sini — list tampil di frame yang sama.
                      if (_recomputeDirty) {
                        _recomputeDirty = false;
                        _lastQueryUsed = effectiveQuery;
                        _statusMap = Map.of(statusMap);
                        _nameMap = Map.of(liveNameMap);
                        _recomputeFiltered(
                          myUid: auth.uid ?? '',
                          query: effectiveQuery,
                          liveNameMap: liveNameMap,
                        );
                      }
                      // List terlihat: hanya rebuild bagian ini saat data berganti.
                      final filtered = _listNotifier.value;
                      if (filtered.isEmpty) {
                        final searching = effectiveQuery.isNotEmpty;
                        return EmptyStateView(
                          icon: searching
                              ? Icons.search_off_rounded
                              : Icons.chat_bubble_outline_rounded,
                          title: searching
                              ? s.searchNoResult
                              : s.noPrivateChats,
                          hint: searching ? '' : s.noPrivateChatsHint,
                        );
                      }
                      // Tampilkan semua chat — yang diblokir tetap tampil dengan tanda khusus.
                      // Paginasi lewat notifier: scroll tidak rebuild AppBar dkk.
                      final page = _pageNotifier.value;
                      final paged = filtered.take(page * _pageSize).toList();
                      final hasMore = paged.length < filtered.length;
                      return ListView.builder(
                        controller: _scrollCtrl,
                        padding: EdgeInsets.fromLTRB(
                          10,
                          10,
                          10,
                          MediaQuery.of(context).padding.bottom + 16,
                        ),
                        itemCount: paged.length + (hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= paged.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  color: AppTheme.primary,
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          final chat = paged[i];
                          final otherUid = chat.participants.firstWhere(
                            (p) => p != auth.uid,
                            orElse: () => '',
                          );
                          final otherName =
                              liveNameMap[otherUid] ??
                              chat.participantNames[otherUid] ??
                              'Anon';
                          final otherGender =
                              chat.participantGenders[otherUid] ?? '';
                          final unread = chat.unreadCounts[auth.uid] ?? 0;
                          final isBlocked = blocked.contains(otherUid);

                          final isSelected = _selected.contains(chat.chatId);
                          final isPinned = chat.isPinnedFor(auth.uid ?? '');
                          // RepaintBoundary per kartu — satu kartu berubah
                          // (badge/centang) tidak repaint seluruh list.
                          return RepaintBoundary(
                            // AppGestureDetector: tahan 450ms langsung masuk mode
                            // seleksi (bukan 500ms default Flutter).
                            child: AppGestureDetector(
                              // Tap di lapis LUAR (pola _UserCard menu Online yang
                              // responsif). Dulu tap lewat InkWell di dalam Dismissible
                              // → gesture arena menunggu drag/long-press → lambat.
                              behavior: HitTestBehavior.opaque,
                              onTap: _selectionMode
                                  ? () => _toggleSelect(chat.chatId)
                                  : () => _openChat(chat),
                              // Tahan = mulai seleksi (gaya WhatsApp), ketuk = tambah/kurangi.
                              onLongPress: () {
                                if (!_selectionMode) _toggleSelect(chat.chatId);
                              },
                              child: Dismissible(
                                key: ValueKey(chat.chatId),
                                direction: DismissDirection.horizontal,
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: EdgeInsets.only(left: 20),
                                  margin: EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isPinned
                                            ? Icons.push_pin_outlined
                                            : Icons.push_pin,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        isPinned ? s.btnUnpin : s.btnPin,
                                        style: AppText.caption.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                secondaryBackground: Container(
                                  alignment: Alignment.centerRight,
                                  padding: EdgeInsets.only(right: 20),
                                  margin: EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.danger,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        s.btnDelete,
                                        style: AppText.caption.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                confirmDismiss: (direction) async {
                                  if (direction ==
                                      DismissDirection.startToEnd) {
                                    final myUid = auth.uid;
                                    final ok =
                                        await ProviderScope.containerOf(
                                              context,
                                              listen: false,
                                            )
                                            .read(chatProvider.notifier)
                                            .pinChat(
                                              chat.chatId,
                                              !isPinned,
                                              myUid: myUid,
                                            )
                                            .then((_) => true)
                                            .catchError((_) => false);
                                    if (ok && mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            isPinned
                                                ? s.msgUnpinned
                                                : s.msgPinned,
                                          ),
                                        ),
                                      );
                                    }
                                    return false;
                                  }
                                  return await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: AppTheme.bgCard,
                                          title: Text(
                                            s.btnDeleteChat,
                                            style: TextStyle(
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          content: Text(
                                            s.deleteChatConfirm,
                                            style: TextStyle(
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(false),
                                              child: Text(
                                                ProviderScope.containerOf(
                                                      context,
                                                      listen: false,
                                                    )
                                                    .read(localeProvider)
                                                    .s
                                                    .btnCancel,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(true),
                                              child: Text(
                                                s.btnDeleteChat,
                                                style: const TextStyle(
                                                  color: AppTheme.danger,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ) ??
                                      false;
                                },
                                onDismissed: (_) async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  await _deleteChat(auth.uid!, chat.chatId);
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(s.deleteChatSuccess),
                                      ),
                                    );
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 200),
                                  curve: Curves.easeOutCubic,
                                  margin: EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primary.withValues(
                                            alpha: AppTheme.isDark
                                                ? 0.15
                                                : 0.06,
                                          )
                                        : isBlocked
                                        ? AppTheme.bgCard.withValues(alpha: 0.5)
                                        : AppTheme.bgCard,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.primary.withValues(
                                              alpha: 0.4,
                                            )
                                          : Colors.transparent,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isSelected ? 0.08 : 0.05,
                                        ),
                                        blurRadius: isSelected ? 12 : 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: null,
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            // PersonAvatar — SAMA warna/ring/badge
                                            // dengan menu Online & header chat.
                                            PersonAvatar(
                                              uid: otherUid,
                                              name: otherName,
                                              gender: otherGender,
                                              size: 44,
                                              status: isBlocked
                                                  ? null
                                                  : (statusMap[otherUid] ??
                                                        'offline'),
                                              badge: isBlocked
                                                  ? Container(
                                                      padding: EdgeInsets.all(
                                                        2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.danger,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Icon(
                                                        Icons.block,
                                                        size: 10,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Flexible(
                                                              child: Text(
                                                                otherName,
                                                                style: AppText
                                                                    .bodyStrong
                                                                    .copyWith(
                                                                      color:
                                                                          isBlocked
                                                                          ? AppTheme.textSecondary
                                                                          : AppTheme.textPrimary,
                                                                    ),
                                                              ),
                                                            ),
                                                            if (isPinned) ...[
                                                              SizedBox(
                                                                width: 3,
                                                              ),
                                                              Icon(
                                                                Icons.push_pin,
                                                                size: 14,
                                                                color: AppTheme
                                                                    .primary,
                                                              ),
                                                            ],
                                                            if (chat.participantRegistered[otherUid] ==
                                                                true) ...[
                                                              SizedBox(
                                                                width: 3,
                                                              ),
                                                              VerifiedBadgeForUid(
                                                                uid: otherUid,
                                                                size: 14,
                                                                tooltip: s
                                                                    .phoneVerifiedBadge,
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                      if (isBlocked)
                                                        Container(
                                                          padding:
                                                              EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: AppTheme
                                                                .danger
                                                                .withValues(
                                                                  alpha: 0.15,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  6,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            s.msgBlocked
                                                                .split(',')
                                                                .first,
                                                            style: AppText.micro
                                                                .copyWith(
                                                                  color: AppTheme
                                                                      .danger,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 4),
                                                  // #5: baris preview (centang + unread) punya layer repaint sendiri -
                                                  // badge/centang berubah sering, tanpa ini seluruh kartu ikut repaint.
                                                  RepaintBoundary(
                                                    child: Builder(
                                                      builder: (_) {
                                                        final otherStatus =
                                                            statusMap[otherUid] ??
                                                            'offline';
                                                        // Lawan hapus akun → status
                                                        // tidak relevan; label
                                                        // khusus menggantikannya.
                                                        final isOnline =
                                                            !chat
                                                                .otherDeleted &&
                                                            otherStatus ==
                                                                'online';
                                                        final profile =
                                                            chat.otherDeleted
                                                            ? ''
                                                            : _chatSubtitle(
                                                                chat,
                                                                auth.uid!,
                                                                s,
                                                              );
                                                        final hasMessage = chat
                                                            .lastMessage
                                                            .isNotEmpty;
                                                        final preview =
                                                            hasMessage
                                                            ? (isLocationPayload(
                                                                    chat.lastMessage,
                                                                  )
                                                                  ? '📍 ${locationPreviewLabel(chat.lastMessage, s.msgLocation)}'
                                                                  : chat.lastMessage)
                                                            : s.noMessages;
                                                        final hasUnread =
                                                            unread > 0;
                                                        final myUid =
                                                            auth.uid ?? '';
                                                        final otherRead = chat
                                                            .lastReadAt[otherUid];
                                                        final isLastFromMe =
                                                            hasMessage &&
                                                            chat
                                                                .lastSenderId
                                                                .isNotEmpty &&
                                                            chat.lastSenderId ==
                                                                myUid;
                                                        // Centang-2 diabaikan bila
                                                        // lawan sudah terhapus —
                                                        // lastReadAt lamanya hantu.
                                                        final isLastRead =
                                                            !chat
                                                                .otherDeleted &&
                                                            isLastFromMe &&
                                                            otherRead != null &&
                                                            !chat.lastMessageAt
                                                                .isAfter(
                                                                  otherRead,
                                                                );
                                                        return Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            if (chat
                                                                .otherDeleted) ...[
                                                              Text(
                                                                s.accountDeleted,
                                                                style: AppText
                                                                    .bodySmall
                                                                    .copyWith(
                                                                      color: AppTheme
                                                                          .danger,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                            ] else if (isOnline ||
                                                                profile
                                                                    .isNotEmpty) ...[
                                                              Text(
                                                                isOnline
                                                                    ? s.chatOnlineSubtitle
                                                                    : profile,
                                                                style: AppText.bodySmall.copyWith(
                                                                  color:
                                                                      isOnline
                                                                      ? AppTheme
                                                                            .online
                                                                      : AppTheme
                                                                            .textSecondary,
                                                                  fontWeight:
                                                                      isOnline
                                                                      ? FontWeight
                                                                            .w600
                                                                      : FontWeight
                                                                            .w400,
                                                                ),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                            ],
                                                            Row(
                                                              children: [
                                                                if (isLastFromMe) ...[
                                                                  Icon(
                                                                    Icons
                                                                        .done_all,
                                                                    size: 14,
                                                                    color:
                                                                        isLastRead
                                                                        ? AppTheme
                                                                              .primary
                                                                        : AppTheme
                                                                              .textSecondary,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 4,
                                                                  ),
                                                                ],
                                                                Expanded(
                                                                  child: Text(
                                                                    preview,
                                                                    style: AppText.bodySmall.copyWith(
                                                                      color:
                                                                          hasUnread
                                                                          ? AppTheme.textPrimary
                                                                          : AppTheme.textSecondary,
                                                                      fontWeight:
                                                                          hasUnread
                                                                          ? FontWeight.w600
                                                                          : FontWeight.w400,
                                                                    ),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  // Jumlah follower & teman
                                                  // (gaya IG) — DI BAWAH pesan,
                                                  // hanya bila ada.
                                                  SocialCountsLine(
                                                    uid: otherUid,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (isBlocked)
                                              GestureDetector(
                                                onTap: () async {
                                                  await ProviderScope.containerOf(
                                                        context,
                                                        listen: false,
                                                      )
                                                      .read(
                                                        chatProvider.notifier,
                                                      )
                                                      .unblockUser(
                                                        auth.uid!,
                                                        otherUid,
                                                      );
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          s.unblockSuccess,
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                },
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(
                                                      color: AppTheme.primary,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    s.btnUnblock,
                                                    style: AppText.caption
                                                        .copyWith(
                                                          color:
                                                              AppTheme.primary,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                ),
                                              )
                                            else
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    _formatTime(
                                                      chat.lastMessageAt,
                                                      s,
                                                    ),
                                                    style: AppText.bodySmall
                                                        .copyWith(
                                                          color: AppTheme
                                                              .textSecondary,
                                                        ),
                                                  ),
                                                  // Tanda bisu gaya WA di samping jam.
                                                  if (chat.isMutedFor(
                                                    auth.uid ?? '',
                                                  )) ...[
                                                    const SizedBox(height: 4),
                                                    Icon(
                                                      Icons.notifications_off,
                                                      size: 14,
                                                      color: AppTheme
                                                          .textSecondary,
                                                    ),
                                                  ],
                                                  if (unread > 0) ...[
                                                    const SizedBox(height: 4),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.primary,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        '$unread',
                                                        style: AppText.caption
                                                            .copyWith(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                  if (otherUid.isNotEmpty &&
                                                      chat.participantRegistered[otherUid] ==
                                                          true) ...[
                                                    const SizedBox(height: 6),
                                                    FriendButton(
                                                      otherUid: otherUid,
                                                      name: otherName,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
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
                ),
              ],
            ),
            // Bar seleksi OVERLAY (embedded): mengambang di atas, list TIDAK
            // bergeser → kartu yang ditahan tetap persis di bawah jari (tidak
            // "loncat ke bawah"). Muncul/hilang dgn fade+slide halus (tanpa
            // blink). AnimatedOpacity+SlideTransition murah & tak bikin list
            // re-layout. Filter bar disembunyikan (di atas) supaya tak dobel.
            if (widget.embedded)
              Positioned(
                top: 2,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_selectionMode,
                  child: AnimatedOpacity(
                    opacity: _selectionMode ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: AnimatedSlide(
                      offset: _selectionMode
                          ? Offset.zero
                          : const Offset(0, -0.35),
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: _selectionBar(auth.uid!, s, overlay: true),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
}
