part of 'chat_service.dart';

/// Domain **private-chatlist** — list chat 1:1, read, pin/mute/archive,
/// hide, block. Dipisah dari `chat_service_private.dart` (Fase 8).
mixin ChatServicePrivateChatListMx on ChatBase {
  // Throttle markAsRead per chat — chat aktif dengan banyak pesan masuk
  // memanggil ini tiap pesan; cukup sekali per ~2.5s (read state jarang
  // berubah & RPC-nya berat di jaringan). Emit lokal tetap jalan.
  //
  // STATIS (lintas instance): ChatService dibuat BEBERAPA kali (chatProvider,
  // roomProvider, onlineUsersProvider, + main_notifications) sehingga map
  // per-instance membuat throttle TIDAK terbagi → RPC mark_chat_read bocor
  // beruntun (terukur 4–8×/sesi walau window 2500ms). Satu map global = satu
  // kebijakan throttle untuk chatId yang sama, apa pun instance-nya.
  // (map throttle lihat top-level `_markReadLastAt` di bawah mixin)

  /// Tandai chat dibaca.
  ///
  /// PENTING (2026-10-18, terukur): update LOKAL dilakukan SINKRON lebih dulu
  /// (UI centang-2 instan), RPC dikirim di BELAKANG tanpa di-await. Dulu
  /// fungsi ini `await` RPC `mark_chat_read` (terukur 161ms) sehingga
  /// pemanggil — jalur buka chat — ikut menunggu sebelum layar dianggap
  /// siap. Penanda dibaca tidak perlu memblokir apa pun: kalau RPC gagal,
  /// percobaan berikutnya (throttle 1s) akan mengulang.
  Future<void> markAsRead(String chatId, String uid) async {
    // 1) UI dulu: snapshot lokal + centang-2 langsung terlihat.
    _applyLocalRead(uid, chatId);
    // 2) Throttle: cegah burst RPC (buka-tutup chat berulang).
    final now = DateTime.now();
    final last = _markReadLastAt[chatId];
    // 1000ms (dulu 2500ms): batas ini menentukan seberapa cepat LAWAN
    // melihat centang-2 setelah kita membuka chat. 2.5s terasa "lama
    // update centangnya". 1s cukup meredam burst pesan tapi responsif.
    if (last != null && now.difference(last).inMilliseconds < 1000) return;
    _markReadLastAt[chatId] = now;
    // 3) RPC di latar — JANGAN ditunggu pemanggil.
    unawaited(() async {
      try {
        await measuredRpc(
          _sb,
          'mark_chat_read',
          params: {'p_chat_id': chatId, 'p_uid': uid},
        );
        // Event realtime dari RPC ini menyusul & menyinkronkan snapshot.
      } catch (e) {
        dlog('[DEBUG-READ] RPC FAIL chat=$chatId uid=$uid err=$e');
      }
    }());
  }

  /// Tandai dibaca atas nama peserta dari monitor admin. Pakai RPC khusus
  /// (SECURITY DEFINER + guard admin) karena akun admin bukan participant,
  /// sehingga mark_chat_read biasa (RLS participants) tidak mengubah apa-apa.
  Future<void> markAsReadAdmin(String chatId, String uid) async {
    try {
      await measuredRpc(_sb, 
        'admin_mark_chat_read',
        params: {'p_chat_id': chatId, 'p_uid': uid},
      );
      _applyLocalRead(uid, chatId);
    } catch (e) {
      dlog('[DEBUG-READ-ADMIN] RPC FAIL chat=$chatId uid=$uid err=$e');
    }
  }

  @visibleForTesting
  void debugScheduleChatListSave(String myUid) => _scheduleChatListSave(myUid);

  @visibleForTesting
  int get debugPendingChatListSaves =>
      _chatListSaveTimers.values.where((t) => t.isActive).length;

  void _scheduleChatListSave(String myUid) {
    _chatListSaveTimers[myUid]?.cancel();
    _chatListSaveTimers[myUid] = Timer(const Duration(seconds: 2), () {
      final rows = _privateChatsLast[myUid];
      if (rows == null || rows.isEmpty) return;
      MessageCache.instance
          .saveRawList(myUid, rows.map((c) => c.toMap()).toList());
    });
  }

  /// Emit list chat ke UI dengan DEBOUNCE ~180ms — menggabungkan burst event
  /// realtime (markAsRead saat buka chat, centang baca, pesan baru) jadi SATU
  /// emission. Snapshot `_privateChatsLast` sudah update instan di pemanggil;
  /// fungsi ini hanya menunda `controller.add` supaya rebuild list tidak
  /// mendarat di tengah animasi back (penyebab "kadang ngelag" saat balik
  /// dari private chat). Selalu emit NILAI TERBARU saat timer habis (bukan
  /// yang lama), jadi tidak ada update yang hilang.
  void _emitChatListDebounced(String myUid) {
    final controller = _privateChatsStreams[myUid];
    if (controller == null || controller.isClosed) return;
    _chatListEmitPending.add(myUid);
    _chatListEmitDebounce[myUid]?.cancel();
    _chatListEmitDebounce[myUid] = Timer(
      const Duration(milliseconds: 180),
      () {
        _chatListEmitDebounce.remove(myUid);
        _chatListEmitPending.remove(myUid);
        if (controller.isClosed) return;
        final latest = _privateChatsLast[myUid] ?? const [];
        controller.add(latest);
      },
    );
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
    // Emit ter-debounce: read-receipt lokal digabung dgn event realtime
    // menyusul → satu emission, tidak bentrok dgn animasi back.
    _emitChatListDebounced(myUid);
  }

  /// Refetch list ter-debounce (500ms) — dipakai saat event realtime
  /// gagal diparse / channel error. Tanpa ini satu event gagal = chat itu
  /// stale sampai user pindah halaman.
  void _scheduleChatListReload(String myUid) {
    final controller = _privateChatsStreams[myUid];
    if (controller == null || controller.isClosed) return;
    _chatListReloadDebounce[myUid]?.cancel();
    _chatListReloadDebounce[myUid] = Timer(
      const Duration(milliseconds: 500),
      () {
        _chatListReloadDebounce.remove(myUid);
        final c = _privateChatsStreams[myUid];
        if (c != null && !c.isClosed) _refreshChatStreams(myUid);
      },
    );
  }

  void _cancelChatListReload(String myUid) {
    _chatListReloadDebounce.remove(myUid)?.cancel();
  }

  /// Terapkan row private_chats dari payload realtime ke snapshot lokal —
  /// tanpa query tambahan. Row dikirim lengkap oleh Supabase Realtime.
  /// TOTAL: payload tak terduga tidak boleh melempar (melempar di dalam
  /// callback realtime = update hilang diam-diam) — fallback refetch.
  void _applyChatEvent(String myUid, Map<String, dynamic> row) {
    late final PrivateChatInfo chat;
    try {
      chat = _rowToPrivateChat(row, myUid: myUid);
    } catch (_) {
      _scheduleChatListReload(myUid);
      return;
    }
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
    // Emit ter-debounce: burst event realtime → satu emission ke UI.
    _emitChatListDebounced(myUid);
    // Pesan baru dari lawan → prefetch fotonya di background (best-effort).
    // Saat chat dibuka, foto sudah di PhotoCache → bubble langsung tampil.
    _prefetchLatestPhoto(myUid, chat);
  }

  // ── Prefetch foto pesan baru (background, ringan) ─────────────────────────
  // Pemicu: event realtime list chat (tanpa query tambahan per event).
  // Batasan hemat kuota/baterai: hanya 1 pesan terbaru per chat, hanya foto
  // biasa (bukan view-once/video/voice), maks 3 download paralel, dedupe per
  // messageId, dan tidak pernah melempar (jangan rusak stream list).
  final Map<String, DateTime> _prefetchSeenAt = {};
  final Set<String> _prefetchedPhotoIds = {};
  int _prefetchInflight = 0;

  void _prefetchLatestPhoto(String myUid, PrivateChatInfo chat) {
    try {
      if (!shouldPrefetchChatPhoto(
        lastSenderId: chat.lastSenderId,
        myUid: myUid,
        lastMessageAt: chat.lastMessageAt,
        seenAt: _prefetchSeenAt[chat.chatId],
      )) {
        return;
      }
      _prefetchSeenAt[chat.chatId] = chat.lastMessageAt;
      if (_prefetchInflight >= 3) return;
      _prefetchInflight++;
      unawaited(
        _fetchAndCachePhoto(chat.chatId).whenComplete(
          () => _prefetchInflight--,
        ),
      );
    } catch (e) { dlog('[CHAT-LIST]: $e'); }
  }

  Future<void> _fetchAndCachePhoto(String chatId) async {
    try {
      final rows = await _sb
          .from('private_messages')
          .select('id,type,image_data,image_path')
          .eq('chat_id', chatId)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return;
      final r = rows.first;
      if (r['type'] != 'image') return;
      final data = (r['image_data'] as String? ?? '').isNotEmpty
          ? (r['image_data'] as String? ?? '')
          : (r['image_path'] as String? ?? '');
      if (data.isEmpty || !StoragePhotoService.instance.isPath(data)) return;
      final id = '${r['id']}';
      if (id.isEmpty || _prefetchedPhotoIds.contains(id)) return;
      if (_prefetchedPhotoIds.length >= 200) _prefetchedPhotoIds.clear();
      _prefetchedPhotoIds.add(id);
      final b64 = await StoragePhotoService.instance.download(data);
      if (b64 == null || b64.isEmpty) return;
      await PhotoCache.instance.save('private_$chatId', id, b64);
    } catch (e) { dlog('[CHAT-LIST]: $e'); }
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
    // Delete chat admin → emit ter-debounce (konsisten dgn _applyChatEvent).
    _emitChatListDebounced(myUid);
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
    // Timer save 2 dtk WAJIB batal sebelum wipe cache (logout) — kalau
    // tidak, list chat akun lama ditulis ulang ke disk setelah dihapus.
    for (final t in _chatListSaveTimers.values) {
      t.cancel();
    }
    _chatListSaveTimers.clear();
    for (final t in _chatListReloadDebounce.values) {
      t.cancel();
    }
    _chatListReloadDebounce.clear();
    _privateChatsLast.clear();
    _privateChatsHidden.clear();
    for (final t in _chatListEmitDebounce.values) {
      t.cancel();
    }
    _chatListEmitDebounce.clear();
    _chatListEmitPending.clear();
    for (final c in _privateChatsStreams.values) {
      if (!c.isClosed) c.close();
    }
    _privateChatsStreams.clear();
  }

  /// Fetch rows private_chats untuk user — dipakai getMyPrivateChats dan
  /// refresh saat stream cached di-subscribe ulang.
  Future<List<PrivateChatInfo>> _fetchPrivateChatRows(String myUid) async {
    // ── Kolom EKSPLISIT (dulu `select()` = semua kolom) ──
    // `hidden_by` IKUT diambil di query yang SAMA lalu disaring di klien.
    //
    // Kenapa berubah (2026-10-18, terukur di HP): dulu chat tersembunyi
    // diambil lewat query KEDUA (`getHiddenChats`) yang berjalan paralel.
    // Walau paralel, request itu menambah satu round-trip penuh ke Supabase
    // dan terukur 1947ms saat app baru bangun dari idle — LEBIH LAMBAT dari
    // query utama (1734ms). Karena `Future.wait` menunggu SEMUA, daftar chat
    // tertahan sampai request tersembunyi selesai. Query-nya sendiri hanya
    // 1.4ms di server (1450 baris) — jadi biayanya murni jaringan.
    // Sekarang cukup SATU round-trip: `hidden_by` (uuid[]) ikut di select.
    const cols =
        'chat_id,participants,participant_names,participant_genders,'
        'participant_locations,participant_ages,participant_registered,'
        'last_message,last_message_at,last_sender_id,message_count,'
        'unread_counts,last_read_at,pinned_by,pinned_at,muted_by,archived_by,'
        'deleted_participants,hidden_by';
    // LIMIT BERTAHAP (2026-10-22). Dulu selalu 200 baris (~186 KB @932 B/baris
    // terukur di live: 1350 baris total, 932 B rata-rata) padahal daftar
    // memaginasi di klien (`take(page*20)`) dan p50 user hanya punya 2 chat.
    // Paginasi klien memotong data yang SUDAH ada di memori — jadi limit
    // server harus >= jumlah chat user; kalau tidak, chat ke-51+ hilang.
    // Solusi: minta 50 dulu; kalau hasilnya penuh 50, tarik halaman berikutnya
    // (maks 4 halaman = 200, sama seperti batas lama) agar user "berat"
    // (live: maks 212 chat) tetap utuh. Realtime menjaga baris tetap fresh.
    Future<List<dynamic>> fetchPage(int from, int to) => PerfProbe.timed(
      from == 0 ? 'chat.listFetch' : 'chat.listFetchMore',
      () => _sb
          .from('private_chats')
          .select(cols)
          .contains('participants', [myUid])
          .order('last_message_at', ascending: false)
          .range(from, to),
    );
    const pageSize = 50;
    final rows = <dynamic>[];
    for (var page = 0; page < 4; page++) {
      final from = page * pageSize;
      final batch = await fetchPage(from, from + pageSize - 1);
      rows.addAll(batch);
      if (batch.length < pageSize) break;
    }
    // Saring chat yang disembunyikan user ini — di klien, tanpa round-trip.
    final hiddenSet = <String>{};
    for (final r in rows) {
      final hb = (r as Map)['hidden_by'];
      if (hb is List && hb.any((e) => '$e' == myUid)) {
        hiddenSet.add('${r['chat_id']}');
      }
    }
    _privateChatsHidden[myUid] = hiddenSet;
    // [PERF] parse 50 baris → PrivateChatInfo (sinkron). Kandidat blokir UI
    // saat kembali ke daftar — diukur supaya tak menebak.
    final list = PerfProbe.measure('chat.parseRows', () {
      final l = rows
          .where((row) => !hiddenSet.contains((row as Map)['chat_id']))
          .map((r) => _rowToPrivateChat(Map<String, dynamic>.from(r as Map), myUid: myUid))
          .where((c) => c.messageCount > 0)
          .toList();
      listSort(l, myUid);
      return l;
    });
    return list;
  }

  void listSort(List<PrivateChatInfo> l, String myUid) =>
      l.sort((a, b) => ChatService._comparePinned(a, b, myUid));

  PrivateChatInfo _rowToPrivateChat(Map<String, dynamic> row, {String? myUid}) {
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
      // Penanda dari SERVER: peserta yang sudah menghapus akun. Diisi saat
      // akun dihapus (helper mark_chats_user_deleted) — baris chat sengaja
      // dipertahankan supaya lawan tahu alasannya.
      deletedOtherUid: _deletedOtherFromRow(d, myUid),
    );
  }

  /// Ambil uid lawan (bukan diri sendiri) yang ada di `deleted_participants`.
  static String _deletedOtherFromRow(Map<String, dynamic> d, String? myUid) {
    final raw = d['deletedParticipants'];
    if (raw is! List || raw.isEmpty) return '';
    final me = myUid ?? '';
    for (final e in raw) {
      final uid = '$e';
      if (uid.isNotEmpty && uid != me) return uid;
    }
    return '';
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
    await measuredRpc(_sb, 'pin_private_chat', params: {'p_chat_id': chatId, 'p_pin': pin});
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
    await measuredRpc(_sb, 'mute_private_chat', params: {'p_chat_id': chatId, 'p_mute': mute});
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
    await measuredRpc(_sb, 'archive_private_chat', params: {'p_chat_id': chatId, 'p_archive': archive});
  }

  /// Snapshot terakhir list private chat — dipakai initialData StreamBuilder
  /// supaya tab Pesan tidak spinner saat di-mount ulang (broadcast stream
  /// tidak me-replay event yang di-add sebelum subscriber terpasang).
  ///
  /// FALLBACK SINKRON dari cache mentah (2026-10-18): setelah app idle lama /
  /// proses di-recreate, `_privateChatsLast` bisa kosong padahal disk masih
  /// menyimpan snapshot. `MessageCache.peekRawList` membaca MEMORI tanpa
  /// await → daftar chat langsung tampil dari cache, sementara fetch jaringan
  /// menyusul di belakang. Tanpa ini user melihat layar kosong ~2 detik.
  List<PrivateChatInfo>? lastPrivateChatsSnapshot(String myUid) {
    final hot = _privateChatsLast[myUid];
    if (hot != null && hot.isNotEmpty) return hot;
    final raw = MessageCache.instance.peekRawList(myUid);
    if (raw.isEmpty) return hot;
    try {
      final list = raw
          .map((r) => PrivateChatInfo.fromMap(Map<String, dynamic>.from(r)))
          .where((c) => c.messageCount > 0)
          .toList();
      if (list.isEmpty) return hot;
      listSort(list, myUid);
      // Simpan juga ke memori panas agar panggilan berikutnya instan.
      _privateChatsLast[myUid] = list;
      return list;
    } catch (_) {
      return hot;
    }
  }

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
        // Refetch penuh = data paling baru → batalkan emission ter-debounce
        // yang tertunda supaya tidak ada emission dobel sesudah ini.
        _chatListEmitDebounce.remove(myUid)?.cancel();
        _chatListEmitPending.remove(myUid);
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
        // _applyChatEvent total (tak melempar); delete aman-null.
        if (controller.isClosed) return;
        _lastChatListEventAt[myUid] = DateTime.now();
        if (payload.eventType == PostgresChangeEvent.delete) {
          final chatId = payload.oldRecord['chat_id']?.toString();
          if (chatId != null && chatId.isNotEmpty) {
            _removeLocalChat(myUid, chatId);
          }
        } else {
          _applyChatEvent(myUid, payload.newRecord);
        }
      },
    );
    channel.subscribe((status, _) {
      // Channel mati (error/timeout/closed) = tidak ada event lagi;
      // refetch supaya list tidak stale selamanya.
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        _scheduleChatListReload(myUid);
      }
    });

    // Fallback polling ala stream pesan: kalau realtime diam >25 dtk
    // (channel mati diam-diam tanpa status error), refetch kalau snapshot
    // juga sudah tua (>30 dtk). Saat realtime sehat = nol fetch ekstra.
    final pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (controller.isClosed) return;
      // BATERAI (P3): JANGAN poll saat app di-background (lebih ketat dari
      // gate-tab P1c di bawah). Dulu timer hidup walau layar mati.
      if (!AppForeground.now) return;
      // P1c: JANGAN poll saat tab list/Pesan tidak visible (tab lain
      // ter-mount di IndexedStack → timer tetap hidup walau non-aktif).
      // Realtime channel tetap jalan; poll hanya jaring-pengaman saat aktif.
      final t = visibleMainTab.value;
      if (t != 1 && t != 0) return;
      final lastEvent = _lastChatListEventAt[myUid];
      final lastReload = _lastChatReloadAt[myUid];
      final now = DateTime.now();
      final silent = lastEvent == null ||
          now.difference(lastEvent).inSeconds > 25;
      final stale = lastReload == null ||
          now.difference(lastReload).inSeconds > 30;
      if (silent && stale) _refreshChatStreams(myUid);
    });

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
            if (cutoff == null || msgAt == null || !msgAt.isAfter(cutoff)) {
              return;
            }
          }
          await unhideChat(myUid, chatId);
          // Row private_chats berubah → channel di atas yang apply ke list.
        } catch (e) {
          dlog('[ChatService] autoUnhideOnMessage error: $e');
        }
      },
    );
    msgChannel.subscribe((status, err) {
      if (err != null) dlog('[Chat] chatlist msg realtime error: $err');
    });

    // PERF: defer reload pertama ~250ms supaya frame boot bersih. List sudah
    // tampil dari cache disk (di atas) → tak perlu nunggu RPC. RPC network
    // (`listFetch` — 1 RTT; chat tersembunyi disaring di klien dari kolom
    // `hidden_by`, lihat §57 PERFORMANCE.md) tetap jalan, sekadar tidak
    // menyerobot frame pertama. Dedupe in-flight tetap berlaku.
    Timer(const Duration(milliseconds: 250), reload);

    controller.onCancel = () {
      _chatReloaders[myUid]?.remove(reload);
      if (_chatReloaders[myUid]?.isEmpty == true) _chatReloaders.remove(myUid);
      pollTimer.cancel();
      _cancelChatListReload(myUid);
      _sb.removeChannel(channel);
      _sb.removeChannel(msgChannel);
      final cached = _privateChatsStreams[myUid];
      if (cached == controller) {
        _privateChatsStreams.remove(myUid);
        _privateChatsLast.remove(myUid);
        _privateChatsHidden.remove(myUid);
        _lastChatReloadAt.remove(myUid);
        _lastChatListEventAt.remove(myUid);
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


  /// Query chat tersembunyi TERPISAH.
  ///
  /// PERF (2026-10-18, §57): **TIDAK dipakai lagi** oleh `_fetchPrivateChatRows`
  /// — kolom `hidden_by` kini ikut di-select pada query utama lalu disaring di
  /// klien, memangkas satu round-trip (terukur 1947 ms saat app bangun dari
  /// idle). Dipertahankan karena masih diekspos `chatProvider.getHiddenChats`
  /// untuk pemakaian lain di masa depan; jangan dipakai lagi di jalur daftar
  /// chat tanpa mengukur dampaknya.
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

  /// Insert ignore-duplicates (`ON CONFLICT DO NOTHING`). Dulu upsert biasa
  /// (`DO UPDATE`) → butuh policy UPDATE yang TIDAK ada di `blocks` → blokir
  /// ulang user yang barisnya sudah ada ditolak RLS.
  Future<void> blockUser(String myUid, String blockedUid) async {
    await _sb.from('blocks').upsert({
      'blocker_id': myUid,
      'blocked_id': blockedUid,
    }, onConflict: 'blocker_id,blocked_id', ignoreDuplicates: true);
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

  /// Status blokir DUA ARAH dengan satu lawan bicara.
  ///
  /// RLS `blocks` hanya mengizinkan SELECT baris milik sendiri, jadi klien
  /// TIDAK bisa tahu bila dirinya diblokir orang lain → dulu user mengetik,
  /// bubble tampil optimistis, lalu INSERT ditolak trigger
  /// (`enforce_chat_block`, 'blocked'/P0001) dan pesan hilang tanpa sebab.
  /// RPC `chat_block_state` hanya mengembalikan boolean (tanpa identitas),
  /// jadi privasi tetap: kita tahu "tidak bisa kirim", bukan "siapa memblokir".
  Future<({bool iBlockedOther, bool otherBlockedMe, bool canSend})>
  getChatBlockState(String otherUid) async {
    try {
      final res = await _sb.rpc(
        'chat_block_state',
        params: {'p_other': otherUid},
      );
      final m = res is Map ? Map<String, dynamic>.from(res) : const {};
      final iBlocked = m['i_blocked_other'] == true;
      final otherBlocked = m['other_blocked_me'] == true;
      return (
        iBlockedOther: iBlocked,
        otherBlockedMe: otherBlocked,
        canSend: m['can_send'] == true && !iBlocked && !otherBlocked,
      );
    } catch (e) {
      // Gagal RPC (offline dsb) → jangan blokir user dari mengirim; server
      // tetap penjaga terakhir lewat trigger.
      dlog('[Chat] getChatBlockState error: $e');
      return (iBlockedOther: false, otherBlockedMe: false, canSend: true);
    }
  }
}

// ── Throttle markAsRead: GLOBAL (lintas instance ChatService) ──
// ChatService dibuat beberapa kali (chatProvider/roomProvider/online/notif) →
// map per-instance tak terbagi → RPC mark_chat_read bocor (terukur 4-8x).
// Top-level (bukan static mixin) supaya bisa diakses kelas + test.
final Map<String, DateTime> _markReadLastAt = {};

@visibleForTesting
void resetMarkReadThrottleForTest() => _markReadLastAt.clear();

@visibleForTesting
bool isMarkReadThrottledForTest(String chatId, {int windowMs = 1000}) {
  final last = _markReadLastAt[chatId];
  if (last == null) return false;
  return DateTime.now().difference(last).inMilliseconds < windowMs;
}
