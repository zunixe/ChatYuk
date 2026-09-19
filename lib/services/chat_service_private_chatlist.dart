part of 'chat_service.dart';

/// Domain **private-chatlist** — list chat 1:1, read, pin/mute/archive,
/// hide, block. Dipisah dari `chat_service_private.dart` (Fase 8).
mixin ChatServicePrivateChatListMx on ChatBase {
  Future<void> markAsRead(String chatId, String uid) async {
    try {
      await _sb.rpc(
        'mark_chat_read',
        params: {'p_chat_id': chatId, 'p_uid': uid},
      );
      // Update snapshot lokal langsung (tanpa refetch 500 row) — event
      // realtime dari RPC ini menyusul dan menyinkronkan via _applyChatEvent.
      _applyLocalRead(uid, chatId);
    } catch (e) {
      dlog('[DEBUG-READ] RPC FAIL chat=$chatId uid=$uid err=$e');
    }
  }

  /// Tandai dibaca atas nama peserta dari monitor admin. Pakai RPC khusus
  /// (SECURITY DEFINER + guard admin) karena akun admin bukan participant,
  /// sehingga mark_chat_read biasa (RLS participants) tidak mengubah apa-apa.
  Future<void> markAsReadAdmin(String chatId, String uid) async {
    try {
      await _sb.rpc(
        'admin_mark_chat_read',
        params: {'p_chat_id': chatId, 'p_uid': uid},
      );
      _applyLocalRead(uid, chatId);
    } catch (e) {
      dlog('[DEBUG-READ-ADMIN] RPC FAIL chat=$chatId uid=$uid err=$e');
    }
  }

  void _scheduleChatListSave(String myUid) {
    _chatListSaveTimers[myUid]?.cancel();
    _chatListSaveTimers[myUid] = Timer(const Duration(seconds: 2), () {
      final rows = _privateChatsLast[myUid];
      if (rows == null || rows.isEmpty) return;
      MessageCache.instance
          .saveRawList(myUid, rows.map((c) => c.toMap()).toList());
    });
  }

  /// Update unread/lastRead di snapshot lokal list chat — UI instan tanpa
  /// refetch. Snapshot tetap akurat karena realtime mengirim row lengkap.
  void _applyLocalRead(String myUid, String chatId) {
    final last = _privateChatsLast[myUid];
    if (last == null) return;
    final idx = last.indexWhere((c) => c.chatId == chatId);
    if (idx < 0) return;
    final chat = last[idx];
    if ((chat.unreadCounts[myUid] ?? 0) == 0) return;
    final updated = chat.copyWith(
      unreadCounts: {...chat.unreadCounts, myUid: 0},
      lastReadAt: {...chat.lastReadAt, myUid: DateTime.now()},
    );
    final list = List.of(last)..[idx] = updated;
    _privateChatsLast[myUid] = list;
    _lastChatReloadAt[myUid] = DateTime.now();
    _scheduleChatListSave(myUid);
    final controller = _privateChatsStreams[myUid];
    if (controller != null && !controller.isClosed) controller.add(list);
  }

  /// Terapkan row private_chats dari payload realtime ke snapshot lokal —
  /// tanpa query tambahan. Row dikirim lengkap oleh Supabase Realtime.
  void _applyChatEvent(String myUid, Map<String, dynamic> row) {
    final chat = _rowToPrivateChat(row);
    final hiddenBy = List<String>.from(
      (row['hidden_by'] as List<dynamic>?) ?? [],
    );
    if (hiddenBy.contains(myUid)) {
      _privateChatsHidden.putIfAbsent(myUid, () => {}).add(chat.chatId);
      _removeLocalChat(myUid, chat.chatId);
      return;
    }
    _privateChatsHidden[myUid]?.remove(chat.chatId);
    if (chat.messageCount <= 0) {
      _removeLocalChat(myUid, chat.chatId);
      return;
    }
    final last = _privateChatsLast[myUid] ?? [];
    final idx = last.indexWhere((c) => c.chatId == chat.chatId);
    final List<PrivateChatInfo> list;
    if (idx >= 0) {
      list = List.of(last)..[idx] = chat;
    } else {
      list = [chat, ...last];
    }
    // Jaga urutan: pinned dulu (by pinnedAt), baru lastMessageAt
    list.sort((a, b) => ChatService._comparePinned(a, b, myUid));
    _privateChatsLast[myUid] = list;
    _lastChatReloadAt[myUid] = DateTime.now();
    _scheduleChatListSave(myUid);
    final controller = _privateChatsStreams[myUid];
    if (controller != null && !controller.isClosed) controller.add(list);
  }

  void _removeLocalChat(String myUid, String chatId) {
    // Hard delete (mis. admin hapus chat di monitor) harus ikut menguap
    // dari disk user — kalau tidak, pesan lama bangkit lagi dari cache
    // saat buka offline. Fire-and-forget: jangan tahan stream list.
    final cacheKey = 'private_$chatId';
    MessageCache.instance.saveMessages(cacheKey, []).catchError((_) {});
    PhotoCache.instance.clearChat(cacheKey).catchError((_) {});
    final last = _privateChatsLast[myUid];
    if (last == null) return;
    final idx = last.indexWhere((c) => c.chatId == chatId);
    if (idx < 0) return;
    final list = List.of(last)..removeAt(idx);
    _privateChatsLast[myUid] = list;
    _lastChatReloadAt[myUid] = DateTime.now();
    _scheduleChatListSave(myUid);
    final controller = _privateChatsStreams[myUid];
    if (controller != null && !controller.isClosed) controller.add(list);
  }

  void _refreshChatStreams(String myUid) {
    final callbacks = _chatReloaders[myUid];
    if (callbacks == null) return;
    for (final cb in List.of(callbacks)) {
      cb();
    }
  }

  /// Refresh paksa list private chat (dipanggil saat screen list di-mount
  /// ulang — broadcast stream tidak menyimpan data terakhir, jadi tanpa ini
  /// StreamBuilder bisa stuck spinner setelah tab di-switch).
  void refreshMyPrivateChats(String myUid) => _refreshChatStreams(myUid);

  void clearCachedStreams() {
    _chatReloaders.clear();
    for (final c in _privateChatsStreams.values) {
      if (!c.isClosed) c.close();
    }
    _privateChatsStreams.clear();
  }

  /// Fetch rows private_chats untuk user — dipakai getMyPrivateChats dan
  /// refresh saat stream cached di-subscribe ulang.
  Future<List<PrivateChatInfo>> _fetchPrivateChatRows(String myUid) async {
    // ── Kolom EKSPLISIT (dulu `select()` = semua kolom) ──
    // `hidden_by`/`hidden_at` TIDAK diambil di sini: chat tersembunyi
    // disaring lewat `getHiddenChats` (query terpisah, sudah ada) sehingga
    // kolom itu tidak pernah dibaca dari hasil fetch. Membuangnya memangkas
    // payload per baris × 50 baris — jalur ini terukur 505-788ms.
    const cols =
        'chat_id,participants,participant_names,participant_genders,'
        'participant_locations,participant_ages,participant_registered,'
        'last_message,last_message_at,last_sender_id,message_count,'
        'unread_counts,last_read_at,pinned_by,pinned_at,muted_by,archived_by';
    // Fetch rows + daftar hidden PARALEL: dulu berurutan (fetch → await
    // hidden), jadi jalur kritis menanggung 2 RTT. Keduanya tidak saling
    // bergantung → satu RTT.
    final results = await Future.wait([
      PerfProbe.timed(
        'chat.listFetch',
        () => _sb
            .from('private_chats')
            .select(cols)
            .contains('participants', [myUid])
            .order('last_message_at', ascending: false)
            .limit(50),
      ),
      PerfProbe.timed('chat.hiddenFetch', () => getHiddenChats(myUid)),
    ]);
    final rows = results[0] as List<dynamic>;
    final hiddenSet = results[1] as Set<String>;
    _privateChatsHidden[myUid] = hiddenSet;
    final list = rows
        .where((row) => !hiddenSet.contains((row as Map)['chat_id']))
        .map((r) => _rowToPrivateChat(Map<String, dynamic>.from(r as Map)))
        .where((c) => c.messageCount > 0)
        .toList();
    list.sort((a, b) => ChatService._comparePinned(a, b, myUid));
    return list;
  }

  PrivateChatInfo _rowToPrivateChat(Map<String, dynamic> row) {
    final d = snakeToCamel(row);
    return PrivateChatInfo(
      chatId: d['chatId'] ?? '',
      participants: List<String>.from(d['participants'] ?? []),
      participantNames: Map<String, String>.from(d['participantNames'] ?? {}),
      participantGenders: Map<String, String>.from(
        d['participantGenders'] ?? {},
      ),
      participantLocations: Map<String, String>.from(
        d['participantLocations'] ?? {},
      ),
      participantAges: (d['participantAges'] as Map<dynamic, dynamic>? ?? {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      participantRegistered:
          (d['participantRegistered'] as Map<dynamic, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k.toString(), v == true),
          ),
      lastMessage: d['lastMessage'] ?? '',
      lastMessageAt: parseDate(d['lastMessageAt']),
      lastSenderId: '${d['lastSenderId'] ?? ''}',
      messageCount: (d['messageCount'] as num?)?.toInt() ?? 0,
      unreadCounts: (d['unreadCounts'] as Map<dynamic, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      ),
      lastReadAt: (d['lastReadAt'] as Map<dynamic, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k.toString(), parseDate(v)),
      ),
      pinnedBy: List<String>.from(d['pinnedBy'] ?? const []),
      pinnedAt: (d['pinnedAt'] as Map<dynamic, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k.toString(), parseDate(v)),
      ),
      mutedBy: List<String>.from(d['mutedBy'] ?? const []),
      archivedBy: List<String>.from(d['archivedBy'] ?? const []),
    );
  }

  Future<void> pinPrivateChat(String chatId, bool pin, {String? myUidParam}) async {
    // Optimistic update biar UI langsung pindah ke atas tanpa tunggu network
    final myUid = myUidParam ?? _sb.auth.currentUser?.id;
    if (myUid != null) {
      final last = _privateChatsLast[myUid];
      if (last != null) {
        final idx = last.indexWhere((c) => c.chatId == chatId);
        if (idx >= 0) {
          final old = last[idx];
          final newPinnedBy = pin
              ? (old.pinnedBy.contains(myUid) ? old.pinnedBy : [...old.pinnedBy, myUid])
              : old.pinnedBy.where((id) => id != myUid).toList();
          final newPinnedAt = Map<String, DateTime>.from(old.pinnedAt);
          if (pin) {
            newPinnedAt[myUid] = DateTime.now();
          } else {
            newPinnedAt.remove(myUid);
          }
          final updated = old.copyWith(pinnedBy: newPinnedBy, pinnedAt: newPinnedAt);
          final list = List<PrivateChatInfo>.from(last)..[idx] = updated;
          list.sort((a, b) => ChatService._comparePinned(a, b, myUid));
          _privateChatsLast[myUid] = list;
          _privateChatsStreams[myUid]?.add(List.unmodifiable(list));
          _scheduleChatListSave(myUid);
        }
      }
    }
    await _sb.rpc('pin_private_chat', params: {'p_chat_id': chatId, 'p_pin': pin});
  }

  /// Mute/unmute notifikasi chat — pola sama seperti pin: optimistic
  /// update cache + cermin lokal (dipakai gate notif di main.dart) + RPC.
  /// RPC butuh migrasi 20260909000000_mute_archive_chats.sql.
  Future<void> mutePrivateChat(String chatId, bool mute, {String? myUidParam}) async {
    final myUid = myUidParam ?? _sb.auth.currentUser?.id;
    if (myUid != null) {
      final last = _privateChatsLast[myUid];
      if (last != null) {
        final idx = last.indexWhere((c) => c.chatId == chatId);
        if (idx >= 0) {
          final old = last[idx];
          final next = mute
              ? (old.mutedBy.contains(myUid) ? old.mutedBy : [...old.mutedBy, myUid])
              : old.mutedBy.where((id) => id != myUid).toList();
          final list = List<PrivateChatInfo>.from(last)..[idx] = old.copyWith(mutedBy: next);
          _privateChatsLast[myUid] = list;
          _privateChatsStreams[myUid]?.add(List.unmodifiable(list));
          _scheduleChatListSave(myUid);
        }
      }
    }
    await NotificationPrefsService.setChatMuted(chatId, mute);
    await _sb.rpc('mute_private_chat', params: {'p_chat_id': chatId, 'p_mute': mute});
  }

  /// Archive/unarchive chat — optimistic update + RPC.
  /// Chat terarsip difilter di layar (tidak di service) agar daftar
  /// arsip bisa ditampilkan dari cache yang sama.
  Future<void> archivePrivateChat(String chatId, bool archive, {String? myUidParam}) async {
    final myUid = myUidParam ?? _sb.auth.currentUser?.id;
    if (myUid != null) {
      final last = _privateChatsLast[myUid];
      if (last != null) {
        final idx = last.indexWhere((c) => c.chatId == chatId);
        if (idx >= 0) {
          final old = last[idx];
          final next = archive
              ? (old.archivedBy.contains(myUid) ? old.archivedBy : [...old.archivedBy, myUid])
              : old.archivedBy.where((id) => id != myUid).toList();
          final list = List<PrivateChatInfo>.from(last)..[idx] = old.copyWith(archivedBy: next);
          _privateChatsLast[myUid] = list;
          _privateChatsStreams[myUid]?.add(List.unmodifiable(list));
          _scheduleChatListSave(myUid);
        }
      }
    }
    await _sb.rpc('archive_private_chat', params: {'p_chat_id': chatId, 'p_archive': archive});
  }

  /// Snapshot terakhir list private chat — dipakai initialData StreamBuilder
  /// supaya tab Pesan tidak spinner saat di-mount ulang (broadcast stream
  /// tidak me-replay event yang di-add sebelum subscriber terpasang).
  List<PrivateChatInfo>? lastPrivateChatsSnapshot(String myUid) =>
      _privateChatsLast[myUid];

  Stream<List<PrivateChatInfo>> getMyPrivateChats(String myUid) {
    // Cache: kembali stream yang sudah ada agar channel Supabase
    // tidak dilipatgandakan tiap subscribe/didChange berikutnya.
    final existing = _privateChatsStreams[myUid];
    if (existing != null && !existing.isClosed) {
      // Subscriber baru (mis. balik ke sub-tab Pesan setelah buka Room):
      // broadcast stream tidak me-replay event lama, jadi kirim snapshot
      // terakhir dulu supaya list langsung tampil tanpa spinner.
      final last = _privateChatsLast[myUid];
      if (last != null) existing.add(last);
      // Snapshot sudah dijaga fresh oleh realtime (payload row lengkap) —
      // refetch 500 row cuma perlu kalau snapshot sudah lama / belum ada.
      final lastReload = _lastChatReloadAt[myUid];
      if (lastReload == null ||
          DateTime.now().difference(lastReload) > const Duration(seconds: 30)) {
        _refreshChatStreams(myUid);
      }
      return existing.stream;
    }

    final controller = StreamController<List<PrivateChatInfo>>.broadcast();
    _privateChatsStreams[myUid] = controller;

    Future<void> doReload() async {
      try {
        // Pengukuran `chat.listFetch` ada DI DALAM _fetchPrivateChatRows
        // (query + pembacaan hidden sudah paralel di sana).
        final rows = await _fetchPrivateChatRows(myUid);
        _privateChatsLast[myUid] = rows;
        _lastChatReloadAt[myUid] = DateTime.now();
        dlog(
          '[getMyPrivateChats] fetched ${rows.length} chats for $myUid',
        );
        if (!controller.isClosed) controller.add(rows);
        if (rows.isNotEmpty) {
          MessageCache.instance
              .saveRawList(myUid, rows.map((c) => c.toMap()).toList());
        }
      } catch (e) {
        dlog('[getMyPrivateChats] fetch error for $myUid: $e');
      }
    }

    Future<void> reload() async {
      // ── DEDUPE IN-FLIGHT (fix fetch beruntun) ──
      // getMyPrivateChats dipanggil 4 layar (nav app, list Pesan, layar chat,
      // sheet anggota room) + layar pengguna online. Tiap panggilan pertama
      // membuat channel + reload. Tanpa dedupe, semuanya menembak
      // `private_chats` BERSAMAAN → terukur 8 fetch beruntun 300-760ms
      // (padahal 1 fetch cukup) + 8× beban DB.
      // Sekarang: kalau fetch uid ini sedang jalan, panggilan lain menunggu
      // future yang SAMA, bukan memulai query baru.
      final running = _chatListFetchInFlight[myUid];
      if (running != null) return running;
      final fut = doReload();
      _chatListFetchInFlight[myUid] = fut;
      try {
        await fut;
      } finally {
        _chatListFetchInFlight.remove(myUid);
      }
    }

    _chatReloaders.putIfAbsent(myUid, () => []).add(reload);

    // Cold start (app baru dibuka): tampilkan list dari cache disk DULU
    // tanpa spinner — fetch server menyusul dan mengkoreksi.
    MessageCache.instance.loadRawList(myUid).then((cachedRows) {
      if (cachedRows.isEmpty) return;
      final cached =
          cachedRows.map(PrivateChatInfo.fromMap).toList()
            ..sort((a, b) => ChatService._comparePinned(a, b, myUid));
      if (_privateChatsLast[myUid] != null &&
          _privateChatsLast[myUid]!.isNotEmpty) {
        return; // sudah ada data lebih baru — jangan timpa
      }
      _privateChatsLast[myUid] = cached;
      if (!controller.isClosed) controller.add(cached);
    });

    // Nama channel harus UNIK per instance — getMyPrivateChats bisa disubscribe
    // dari 2 screen sekaligus (list chat + layar chat); nama sama = join gagal,
    // event realtime tidak pernah sampai (centang baca jadi tidak update).
    final instanceId = DateTime.now().microsecondsSinceEpoch;
    final channel = _sb.channel('private-chats-$myUid-$instanceId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'private_chats',
      callback: (payload) {
        // Update snapshot langsung dari payload (row lengkap) — tanpa
        // refetch 500 row untuk setiap centang baca / pesan baru.
        if (controller.isClosed) return;
        if (payload.eventType == PostgresChangeEvent.delete) {
          final chatId = payload.oldRecord['chat_id'] as String?;
          if (chatId != null) _removeLocalChat(myUid, chatId);
        } else {
          _applyChatEvent(myUid, payload.newRecord);
        }
      },
    );
    channel.subscribe();

    // Pesan BARU masuk untuk chat yang aku hapus (hidden) → chat muncul lagi
    // di list, tapi hanya pesan setelah cutoff yang akan tampil isinya.
    // Chat yang tidak hidden tidak perlu dicek — row private_chats sudah
    // di-update trigger dan dikirim channel di atas (tanpa query tambahan).
    final msgChannel = _sb.channel('private-chats-msg-$myUid-$instanceId');
    msgChannel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'private_messages',
      callback: (payload) async {
        final chatId = payload.newRecord['chat_id'] as String?;
        if (chatId == null || controller.isClosed) return;
        if (!(_privateChatsHidden[myUid]?.contains(chatId) ?? false)) return;
        try {
          final row = await _sb
              .from('private_chats')
              .select('hidden_by,hidden_at')
              .eq('chat_id', chatId)
              .maybeSingle();
          if (row == null) return;
          final hidden = List<String>.from(
            (row['hidden_by'] as List<dynamic>?) ?? [],
          );
          if (!hidden.contains(myUid)) return;
          final hm = (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {};
          final cutoffStr = hm[myUid];
          final msgStr = payload.newRecord['created_at'] as String?;
          if (cutoffStr != null && msgStr != null) {
            final cutoff = DateTime.tryParse('$cutoffStr');
            final msgAt = DateTime.tryParse(msgStr);
            if (cutoff == null || msgAt == null || !msgAt.isAfter(cutoff))
              return;
          }
          await unhideChat(myUid, chatId);
          // Row private_chats berubah → channel di atas yang apply ke list.
        } catch (e) {
          dlog('[ChatService] autoUnhideOnMessage error: $e');
        }
      },
    );
    msgChannel.subscribe();

    reload();

    controller.onCancel = () {
      _chatReloaders[myUid]?.remove(reload);
      if (_chatReloaders[myUid]?.isEmpty == true) _chatReloaders.remove(myUid);
      _sb.removeChannel(channel);
      _sb.removeChannel(msgChannel);
      final cached = _privateChatsStreams[myUid];
      if (cached == controller) {
        _privateChatsStreams.remove(myUid);
        _privateChatsLast.remove(myUid);
        _privateChatsHidden.remove(myUid);
        _lastChatReloadAt.remove(myUid);
      }
    };

    return controller.stream;
  }

  Future<void> hideChat(String myUid, String chatId) async {
    final row = await _sb
        .from('private_chats')
        .select('hidden_by,hidden_at')
        .eq('chat_id', chatId)
        .maybeSingle();
    if (row == null) return;
    final hidden = List<String>.from(
      (row['hidden_by'] as List<dynamic>?) ?? [],
    );
    final hiddenAt = Map<String, dynamic>.from(
      (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {},
    );
    if (!hidden.contains(myUid)) hidden.add(myUid);
    // Cutoff selalu di-refresh — pesan sebelum waktu delete terbaru
    // tetap tidak tampil walau chat sudah pernah muncul lagi sebelumnya.
    hiddenAt[myUid] = DateTime.now().toUtc().toIso8601String();
    await _sb
        .from('private_chats')
        .update({'hidden_by': hidden, 'hidden_at': hiddenAt})
        .eq('chat_id', chatId);
  }


  Future<Set<String>> getHiddenChats(String myUid) async {
    try {
      final rows = await _sb.from('private_chats').select('chat_id').contains(
        'hidden_by',
        [myUid],
      );
      return rows.map((r) => r['chat_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> blockUser(String myUid, String blockedUid) async {
    await _sb.from('blocks').upsert({
      'blocker_id': myUid,
      'blocked_id': blockedUid,
    }, onConflict: 'blocker_id,blocked_id');
  }

  Future<void> unblockUser(String myUid, String blockedUid) async {
    await _sb
        .from('blocks')
        .delete()
        .eq('blocker_id', myUid)
        .eq('blocked_id', blockedUid);
  }

  Future<void> reportUser({
    required String reporterId,
    required String reportedId,
    required String reason,
  }) async {
    await _sb.from('reports').insert({
      'reporter_id': reporterId,
      'reported_id': reportedId,
      'reason': reason,
    });
  }

  Future<bool> isUserBlocked(String myUid, String otherUid) async {
    final res = await _sb
        .from('blocks')
        .select('blocker_id')
        .eq('blocker_id', myUid)
        .eq('blocked_id', otherUid)
        .maybeSingle();
    return res != null;
  }

  Future<List<String>> getBlockedUids(String myUid) async {
    final res = await _sb
        .from('blocks')
        .select('blocked_id')
        .eq('blocker_id', myUid);
    return res.map((r) => '${r['blocked_id']}').toList();
  }
}
