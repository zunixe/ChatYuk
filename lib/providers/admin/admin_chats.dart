part of '../admin_provider.dart';

/// Hasil merge pesan monitor: daftar gabungan + apakah ada perubahan.
/// Murni & testable (tanpa I/O/cache).
class AdminChatMerge {
  final List<Map<String, dynamic>> merged;
  final bool changed;
  const AdminChatMerge(this.merged, this.changed);
}

/// Sidik satu baris pesan monitor: id + field yang bisa berubah lewat poll
/// (isi, tipe, media, hapus, edit). Dipakai mendeteksi pesan BARU maupun
/// pesan LAMA yang berubah (dihapus/diedit) — dulu merge hanya menyisipkan
/// id baru sehingga pesan yang dihapus terjebak tampil konten lama selamanya
/// (teks tak berubah saat soft-delete, hanya flag is_deleted).
String adminChatRowSig(Map<String, dynamic> m) =>
    '${m['id']}|${m['text']}|${m['type']}|${m['is_deleted']}|${m['edited']}|'
    '${m['image_data']}|${m['image_path']}|${m['voice_path']}';

/// Gabung `latest` (DESC terbaru dulu) ke `current` (DESC): sisipkan id baru
/// di depan (urutan DESC dipertahankan), TIMPA baris dikenal yang sidiknya
/// berubah (hapus/edit).
@visibleForTesting
AdminChatMerge mergeAdminChatMessages(
  List<Map<String, dynamic>> current,
  List<Map<String, dynamic>> latest,
) {
  final sigById = <String, String>{};
  for (final m in current) {
    sigById['${m['id']}'] = adminChatRowSig(m);
  }
  final merged = List<Map<String, dynamic>>.from(current);
  final fresh = <Map<String, dynamic>>[];
  var changed = false;
  for (final m in latest) {
    final id = '${m['id']}';
    final prev = sigById[id];
    if (prev == null) {
      fresh.add(m);
      changed = true;
    } else if (prev != adminChatRowSig(m)) {
      final idx = merged.indexWhere((e) => '${e['id']}' == id);
      if (idx >= 0) merged[idx] = m;
      changed = true;
    }
  }
  // latest sudah DESC → sisipkan berurutan di depan (tak dibalik).
  for (var i = fresh.length - 1; i >= 0; i--) {
    merged.insert(0, fresh[i]);
  }
  return AdminChatMerge(merged, changed);
}

/// Monitor chat + call aktif + pesan kontak + pesan per-chat + cache.
mixin AdminChatsMx on AdminBase {
  // ── Admin Chat Monitor ──
  static const int chatPageSize = 50;
  // 40 (dulu 100): buka chat ringan — 100 pesan + view_once base64 berat
  // di-serialize sekaligus bikin lambat. Sisanya dimuat saat scroll ke atas.
  static const int messagePageSize = 40;

  List<Map<String, dynamic>> _chats = [];
  List<String> _adminUids = [];
  bool _chatsLoading = false;
  bool _chatsHasMore = true;
  int _chatsTotal = 0;
  bool _chatsFetchingMore = false;
  AdminErrKind? _chatsError;

  List<Map<String, dynamic>> get chats => _chats;
  /// DEPRECATED: buffer pesan bersama sudah dihapus (penyebab "pesan kecampur
  /// antar-chat"). Gunakan [chatMessagesFor] dengan chatId eksplisit.
  List<Map<String, dynamic>> get chatMessages => const [];
  List<String> get adminUids => _adminUids;
  bool get chatsLoading => _chatsLoading;
  bool get chatsHasMore => _chatsHasMore;
  /// True HANYA saat halaman berikutnya sedang dimuat — dipakai UI untuk
  /// spinner footer (jangan pakai `chatsHasMore`: itu "masih ada halaman",
  /// bukan "sedang memuat" → spinner muter terus saat idle).
  bool get chatsFetchingMore => _chatsFetchingMore;
  AdminErrKind? get chatsError => _chatsError;

  Future<void> fetchChats() async {
    _chatsLoading = true;
    _chatsError = null;
    _notifyChats();
    // Data kosong (cold start / tab baru) → tampilkan cache disk dulu.
    if (_chats.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(AdminBase.kAdminChatsKey);
        if (cached.isNotEmpty && _chats.isEmpty) {
          _chats = cached;
          _chatsTotal = cached.length;
          _notifyChats();
        }
      } catch (_) {}
    }
    try {
      // Pertahankan kedalaman yang SUDAH dimuat (mis. kategori yang chat-nya
      // di halaman >1). Dulu selalu minta page-0 (50) → refresh memangkas
      // daftar → kategori "kosong" lagi → pindai ulang = blink berulang.
      final want = _chats.length > chatPageSize ? _chats.length : chatPageSize;
      final res = await _service.listChats(limit: want, offset: 0);
      final fresh = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      // Jangan timpa data baik dengan hasil kosong (bisa karena server
      // mengembalikan kosong sesaat) — kecuali memang belum ada data.
      if (fresh.isNotEmpty || _chats.isEmpty) {
        _chats = fresh;
        _chatsTotal = (res['total'] as num?)?.toInt() ?? 0;
        _chatsHasMore = _chats.length < _chatsTotal;
      }
      _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .toList();
      if (_chats.isNotEmpty) {
        MessageCache.instance.saveRawList(AdminBase.kAdminChatsKey, _chats);
      }
    } catch (e) {
      // Data lama dipertahankan → banner "data terakhir" di UI.
      _chatsError = classifyAdminError(e);
      dlog('[ADMIN] fetchChats error: $e');
    }
    _chatsLoading = false;
    _notifyChats();
  }

  /// Muat halaman berikutnya (infinite scroll list chat).
  /// Return true bila berhasil (halaman termuat) — dipakai auto-load
  /// kategori untuk berhenti saat jaringan gagal (cegah "muter-muter").
  Future<bool> fetchMoreChats() async {
    if (_chatsFetchingMore || !_chatsHasMore || _chatsLoading) return false;
    _chatsFetchingMore = true;
    _notifyChats(); // footer spinner muncul saat mulai
    var ok = false;
    try {
      final res = await _service.listChats(
        limit: chatPageSize,
        offset: _chats.length,
      );
      final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _chatsTotal = (res['total'] as num?)?.toInt() ?? _chatsTotal;
      // Kembar & halaman kosong → hentikan (jangan ulang offset sama).
      if (more.isEmpty) {
        _chatsHasMore = false;
      } else {
        _chats = [..._chats, ...more];
        _chatsHasMore = _chats.length < _chatsTotal;
      }
      _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .toList();
      ok = true;
    } catch (e) {
      dlog('[ADMIN] fetchMoreChats error: $e');
    }
    _chatsFetchingMore = false;
    _notifyChats();
    return ok;
  }

  /// Pastikan SEMUA [wantedChatIds] ada di `chats` — SATU RPC besar dulu
  /// (limit [bulkLimit]), baru paginasi kecil bila masih kurang.
  ///
  /// Alasan: filter kategori butuh chat yang bisa ada di rank ratusan; dulu
  /// memuat 50-an per panggilan → 8–12 round-trip berturut = footer spinner
  /// "muter" lama. Satu panggilan besar jauh lebih cepat (server sort ~60ms
  /// untuk berapa pun limit-nya — biaya ada di sort, bukan jumlah baris).
  Future<void> ensureChatsContain(
    Set<String> wantedChatIds, {
    int bulkLimit = 400,
  }) async {
    if (wantedChatIds.isEmpty) return;
    bool allPresent() {
      final have = _chats.map((c) => '${c['chat_id']}').toSet();
      for (final id in wantedChatIds) {
        if (!have.contains(id)) return false;
      }
      return true;
    }

    if (allPresent()) return;

    // Satu RPC besar (bila daftar sekarang masih lebih kecil dari bulkLimit).
    if (_chats.length < bulkLimit && !_chatsFetchingMore && !_chatsLoading) {
      _chatsFetchingMore = true;
      _notifyChats();
      try {
        final res = await _service.listChats(limit: bulkLimit, offset: 0);
        final fresh = List<Map<String, dynamic>>.from(res['items'] ?? const []);
        if (fresh.length >= _chats.length) {
          _chats = fresh;
          _chatsTotal = (res['total'] as num?)?.toInt() ?? _chatsTotal;
          _chatsHasMore = _chats.length < _chatsTotal;
          _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
              .map((e) => '$e')
              .toList();
        }
      } catch (e) {
        dlog('[ADMIN] ensureChatsContain bulk error: $e');
      }
      _chatsFetchingMore = false;
      _notifyChats();
    }

    if (allPresent()) return;
    // Sisa (di luar bulkLimit) → paginasi kecil sampai ketemu / habis.
    var pages = 0;
    while (pages < 12) {
      if (allPresent()) break;
      if (!_chatsHasMore || _chatsFetchingMore || _chatsLoading) break;
      final before = _chats.length;
      final ok = await fetchMoreChats();
      pages++;
      if (!ok || _chats.length == before) break;
    }
  }

  /// Refresh daftar chat tanpa loading spinner (untuk polling berkala).
  /// MERGE dengan list existing: server bisa return subset (race/filter),
  /// jangan memangkas balik → gejala "kadang muncul kadang ilang".
  Future<void> refreshChats() async {
    try {
      final want = _chats.length > chatPageSize ? _chats.length : chatPageSize;
      final res = await _service.listChats(limit: want, offset: 0);
      final fresh =
          List<Map<String, dynamic>>.from(res['items'] ?? const []);
      final merged = List<Map<String, dynamic>>.from(_chats);
      // Update existing / add new
      for (final f in fresh) {
        final id = '${f['chat_id']}';
        final idx = merged.indexWhere((c) => '${c['chat_id']}' == id);
        if (idx >= 0) {
          merged[idx] = f;
        } else {
          merged.insert(0, f); // terbaru di depan
        }
      }
      // JANGAN hapus item yang tidak ada di fresh (bisa filter/race).
      // Hanya jika server return LEBIH BANYAK → refresh total/hasMore.
      if (fresh.length > _chats.length) {
        _chatsTotal = (res['total'] as num?)?.toInt() ?? _chatsTotal;
        _chatsHasMore = merged.length < _chatsTotal;
      }
      _chats = merged;
      _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .toList();
    } catch (e) {
      dlog('[ADMIN] refreshChats error: $e');
    }
    _notifyChats();
  }

  // ── Call aktif (badge monitor + pantau call) ──
  List<ActiveCallInfo> _activeCalls = [];
  bool _activeCallsLoading = false;
  RealtimeChannel? _callChannel;
  Timer? _callRealtimeDebounce;
  int _sweepCounter = 0;

  List<ActiveCallInfo> get activeCalls => _activeCalls;
  bool get activeCallsLoading => _activeCallsLoading;

  /// Peta chatId → call aktif, untuk badge di kartu list monitor.
  Map<String, ActiveCallInfo> get activeCallsByChat => {
    for (final c in _activeCalls) c.chatId: c,
  };

  Future<void> fetchActiveCalls() async {
    ensureCallRealtime();
    if (_activeCallsLoading) return;
    _activeCallsLoading = true;
    var changed = true;
    try {
      // Sweep zombie hanya tiap panggilan ke-12 (fallback ~12 menit pada
      // polling 60 dtk) — realtime UPDATE sudah memicu refresh instan.
      if (_sweepCounter++ % 12 == 0) {
        try {
          await _service.sweepStaleCalls();
        } catch (_) {}
      }
      final fresh = await _service.getActiveCalls();
      changed = _activeCallsSig(fresh) != _activeCallsSig(_activeCalls);
      _activeCalls = fresh;
      _detectNewCalls(_activeCalls);
    } catch (e) {
      dlog('[ADMIN] fetchActiveCalls error: $e');
    }
    _activeCallsLoading = false;
    // Poll tiap 5–10 dtk: diam bila daftar sama supaya daftar monitor di
    // belakang layar tidak rebuild terus.
    if (changed) _notifyCalls();
  }

  /// Sidik daftar call aktif (id+status+chat) untuk deteksi perubahan.
  String _activeCallsSig(List<ActiveCallInfo> calls) {
    final parts = calls.map((c) => '${c.id}:${c.status}:${c.chatId}').toList()
      ..sort();
    return parts.join(',');
  }

  /// Notifikasi video call baru di monitor chat.
  void _detectNewCalls(List<ActiveCallInfo> calls) {
    for (final c in calls) {
      if (_seenCallIds.contains(c.id)) continue;
      _seenCallIds.add(c.id);
      if (!_notifArmed) continue;
      if (c.status == 'ringing' || c.status == 'answered') {
        _emit('Video call: ${c.callerName} ↔ ${c.calleeName}');
      }
    }
  }

  /// Realtime: dengarkan tabel calls — INSERT/UPDATE apapun langsung
  /// menyegarkan daftar call aktif tanpa menunggu polling.
  void ensureCallRealtime() {
    if (_callChannel != null || _disposed) return;
    final ch = _sb.channel('admin-calls-monitor');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'calls',
      callback: (_) => _debouncedRefreshActiveCalls(),
    );
    ch.subscribe((status, err) {
      if (err != null) dlog('[ADMIN] calls realtime error: $err');
    });
    _callChannel = ch;
  }

  void _debouncedRefreshActiveCalls() {
    _callRealtimeDebounce?.cancel();
    _callRealtimeDebounce = Timer(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      fetchActiveCalls();
    });
  }

  // ── Pesan Kontak (Hubungi Kami) ──
  List<Map<String, dynamic>> _contactMessages = [];
  bool _contactLoading = false;
  bool _contactHasMore = true;
  bool _contactFetchingMore = false;
  int _contactTotal = 0;
  AdminErrKind? _contactError;

  List<Map<String, dynamic>> get contactMessages => _contactMessages;
  bool get contactLoading => _contactLoading;
  bool get contactHasMore => _contactHasMore;
  AdminErrKind? get contactError => _contactError;

  Future<void> fetchContactMessages() async {
    _contactLoading = true;
    _contactError = null;
    _notifyContact();
    // Cold start / tab baru → cache disk dulu (tahan offline).
    if (_contactMessages.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(
          AdminBase.kAdminContactKey,
        );
        if (cached.isNotEmpty && _contactMessages.isEmpty) {
          _contactMessages = cached;
          _contactTotal = cached.length;
          _notifyContact();
        }
      } catch (_) {}
    }
    try {
      final res = await _service.listContactMessages(
        limit: chatPageSize,
        offset: 0,
      );
      final fresh = List<Map<String, dynamic>>.from(
        res['items'] ?? const [],
      );
      if (fresh.isNotEmpty || _contactMessages.isEmpty) {
        _contactMessages = fresh;
        _contactTotal = (res['total'] as num?)?.toInt() ?? 0;
        _contactHasMore = _contactMessages.length < _contactTotal;
      }
      if (_contactMessages.isNotEmpty) {
        MessageCache.instance.saveRawList(AdminBase.kAdminContactKey, _contactMessages);
      }
    } catch (e) {
      _contactError = classifyAdminError(e);
      dlog('[ADMIN] fetchContactMessages error: $e');
    }
    _contactLoading = false;
    _notifyContact();
  }

  /// Muat halaman berikutnya (infinite scroll list pesan kontak).
  Future<void> fetchMoreContactMessages() async {
    if (_contactFetchingMore || !_contactHasMore || _contactLoading) return;
    _contactFetchingMore = true;
    try {
      final res = await _service.listContactMessages(
        limit: chatPageSize,
        offset: _contactMessages.length,
      );
      final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _contactTotal = (res['total'] as num?)?.toInt() ?? _contactTotal;
      _contactMessages = [..._contactMessages, ...more];
      _contactHasMore = _contactMessages.length < _contactTotal;
    } catch (e) {
      dlog('[ADMIN] fetchMoreContactMessages error: $e');
    }
    _contactFetchingMore = false;
    _notifyContact();
  }

  Future<void> setContactRead(String id, {bool read = true}) async {
    try {
      await _service.setContactRead(id, read: read);
      final i = _contactMessages.indexWhere((m) => m['id'] == id);
      if (i >= 0) {
        _contactMessages[i] = {..._contactMessages[i], 'is_read': read};
        _notifyContact();
      }
    } catch (e) {
      dlog('[ADMIN] setContactRead error: $e');
    }
  }

  Future<void> deleteContactMessage(String id) async {
    try {
      await _service.deleteContactMessage(id);
      _contactMessages.removeWhere((m) => m['id'] == id);
      if (_contactTotal > 0) _contactTotal--;
      _notifyContact();
    } catch (e) {
      dlog('[ADMIN] deleteContactMessage error: $e');
    }
  }

  bool _chatMessagesFetchingMore = false;

  /// hasMore PER-CHAT. Dulu satu flag global: saat dua layar monitor hidup
  /// (mis. buka dari list lalu dari lembar detail user), pagination layar atas
  /// mengubah status layar bawah → halaman salah / tak pernah berhenti.
  final Map<String, bool> _chatMsgHasMore = {};
  bool chatMessagesHasMoreFor(String chatId) => _chatMsgHasMore[chatId] ?? true;

  /// Kompat lama (dipakai test/legacy): hasMore default true.
  bool get chatMessagesHasMore => true;

  /// Mem-cache per-chat (buka-tutup-buka instan): provider sebelumnya hanya
  /// menyimpan SATU chat terakhir (`_chatMessages`), sehingga pindah chat
  /// A→B→A selalu baca ulang disk. LRU 20 chat.
  final Map<String, List<Map<String, dynamic>>> _chatMsgMem = {};
  static const int _chatMsgMemMax = 20;

  void _chatMsgMemPut(String chatId, List<Map<String, dynamic>> rows) {
    _chatMsgMem.remove(chatId);
    _chatMsgMem[chatId] = List<Map<String, dynamic>>.from(rows);
    while (_chatMsgMem.length > _chatMsgMemMax) {
      _chatMsgMem.remove(_chatMsgMem.keys.first);
    }
  }

  /// Baca SINKRON cache memori pesan satu chat (tanpa await). Dipakai layar
  /// monitor agar frame pertama langsung terisi setelah prefetch tap.
  List<Map<String, dynamic>> peekChatMessages(String chatId) =>
      _chatMsgMem[chatId] ?? const [];

  final Set<String> _chatMsgPrefetching = {};

  /// Panaskan cache pesan monitor saat kartu di-tap (sebelum layar mount).
  /// Inilah yang membuat buka chat instan seperti private chat — sebelumnya
  /// tap hanya `preloadMessages` (cache stream `private_<chatId>`), padahal
  /// monitor membaca `_chatMsgMem`/disk `admin_chatmsg_<chatId>` → selalu
  /// RPC server saat buka pertama.
  /// Dedupe in-flight per chatId; tidak menyentuh `_chatMessages` (chat yang
  /// sedang tampil) — hanya mengisi map per-chat.
  /// Panaskan cache pesan monitor untuk [chatId].
  ///
  /// PENTING (menyamai chat USER): pemanggil di daftar chat bisa MENUNGGU
  /// (`await`) sebelum push layar, supaya saat AdminChatViewScreen mount,
  /// `peekChatMessages` PASTI hit → frame pertama langsung terisi (tanpa jeda
  /// "kosong dulu" lalu isi). Chat user sudah begini sejak awal
  /// (`prefetchPrivateChat` di-await) — itulah sebabnya chat user terasa
  /// instan sementara monitor admin tidak.
  ///
  /// Aman dipanggil berkali-kali: kalau sudah ada di memori / sedang berjalan,
  /// kembalikan future yang sama (tak menembak RPC dobel).
  Future<void> prefetchChatMessages(String chatId) {
    if (chatId.isEmpty) return Future<void>.value();
    if ((_chatMsgMem[chatId]?.isNotEmpty ?? false)) return Future<void>.value();
    final running = _chatMsgPrefetchFutures[chatId];
    if (running != null) return running;
    if (!_chatMsgPrefetching.add(chatId)) {
      // Sudah ada yang jalan (jalur lama) — tunggu lewat map bila ada.
      return _chatMsgPrefetchFutures[chatId] ?? Future<void>.value();
    }
    final fut = () async {
      try {
        final disk = await MessageCache.instance.loadRawList(
          AdminBase.adminChatMsgKey(chatId),
        );
        if (disk.isNotEmpty) {
          _chatMsgMemPut(chatId, disk);
          // Set hasMore agar footer spinner tidak "muter" saat layar membaca
          // cache ini (dulu tak di-set → default true → spinner selamanya).
          _chatMsgHasMore[chatId] = disk.length >= messagePageSize;
          return;
        }
        final fresh = await _service.getChatMessages(
          chatId,
          limit: messagePageSize,
          offset: 0,
        );
        if (fresh.isNotEmpty) {
          _chatMsgMemPut(chatId, fresh);
          _chatMsgHasMore[chatId] = fresh.length >= messagePageSize;
          MessageCache.instance.saveRawList(
            AdminBase.adminChatMsgKey(chatId),
            fresh,
          );
        }
      } catch (e) {
        dlog('[ADMIN] prefetchChatMessages $chatId error: $e');
      } finally {
        _chatMsgPrefetching.remove(chatId);
        _chatMsgPrefetchFutures.remove(chatId);
      }
    }();
    _chatMsgPrefetchFutures[chatId] = fut;
    return fut;
  }

  final Map<String, Future<void>> _chatMsgPrefetchFutures = {};

  /// Pesan satu chat dari sumber per-chat (`_chatMsgMem` → `_chatMessages`
  /// untuk kompat; WAJIB memakai ini bila ada >1 layar monitor).
  List<Map<String, dynamic>> chatMessagesFor(String chatId) =>
      _chatMsgMem[chatId] ?? const [];

  Future<bool> fetchChatMessages(String chatId, {bool force = false}) async {
    // PENTING (insiden "pesan kecampur & semua ke kanan"): dulu state pesan
    // SATU buffer global (`_chatMessages`). Saat dua layar monitor hidup
    // (buka dari list lalu dari lembar detail user), layar bawah membaca
    // buffer yang ditulis layar atas → pesan chat lain muncul di layar ini
    // dan sender-nya tak cocok `_leftUid` → SEMUA bubble pindah ke kanan.
    // Sekarang SEMUA operasi memakai map per-chat `_chatMsgMem` (sumber
    // tunggal); tidak ada lagi buffer bersama.
    final memHit = _chatMsgMem[chatId];
    final hasLocal = memHit != null && memHit.isNotEmpty;
    if (!hasLocal) {
      // Belum ada di memori → coba disk (tahan offline), per-chat.
      try {
        final cached = await MessageCache.instance.loadRawList(
          AdminBase.adminChatMsgKey(chatId),
        );
        if (cached.isNotEmpty) _chatMsgMemPut(chatId, cached);
      } catch (_) {}
    }
    final local = _chatMsgMem[chatId];
    // PERSISTEN: sudah ada dari cache & tidak dipaksa → jangan RPC. Pesan
    // baru datang lewat poll/realtime (refreshChatMessages).
    if (!force && local != null && local.isNotEmpty) {
      // WAJIB set hasMore juga di jalur cache — dulu return lebih awal tanpa
      // men-set → default `true` → footer spinner layar MUTER SELAMANYA saat
      // chat dibuka dari cache (kasus paling umum). Cache < 1 halaman =
      // memang sudah habis (tak ada lagi di server untuk dimuat lebih lama).
      if (!_chatMsgHasMore.containsKey(chatId)) {
        _chatMsgHasMore[chatId] = local.length >= messagePageSize;
      }
      _notifyChats();
      return true;
    }
    try {
      final fresh = await _service.getChatMessages(
        chatId,
        limit: messagePageSize,
        offset: 0,
      );
      if (fresh.isNotEmpty) {
        _chatMsgMemPut(chatId, fresh);
        MessageCache.instance.saveRawList(
          AdminBase.adminChatMsgKey(chatId),
          fresh,
        );
      }
      _chatMsgHasMore[chatId] = fresh.length >= messagePageSize;
      return true;
    } catch (e) {
      // Data lama (memori/disk) dipertahankan — layar tetap ada isinya.
      dlog('[ADMIN] fetchChatMessages error: $e');
      return false;
    } finally {
      _notifyChats();
    }
  }

  /// Muat pesan lebih lama (pagination) untuk [chatId]. Per-chat: memakai
  /// panjang list chat ITU, bukan buffer bersama.
  Future<void> fetchMoreChatMessages(String chatId) async {
    if (_chatMessagesFetchingMore) return;
    if (!chatMessagesHasMoreFor(chatId)) return;
    _chatMessagesFetchingMore = true;
    try {
      final current = _chatMsgMem[chatId] ?? const <Map<String, dynamic>>[];
      final older = await _service.getChatMessages(
        chatId,
        limit: messagePageSize,
        offset: current.length,
      );
      if (older.isNotEmpty) {
        // Guard: hanya bila chat ini masih ada di map (tidak di-evict LRU).
        final base = _chatMsgMem[chatId] ?? current;
        final merged = [...base, ...older];
        _chatMsgMemPut(chatId, merged);
        MessageCache.instance.saveRawList(
          AdminBase.adminChatMsgKey(chatId),
          merged,
        );
      }
      _chatMsgHasMore[chatId] = older.length >= messagePageSize;
    } catch (e) {
      dlog('[ADMIN] fetchMoreChatMessages error: $e');
    }
    _chatMessagesFetchingMore = false;
    _notifyChats();
  }

  /// Refresh pesan terbaru chat [chatId] tanpa reset pagination — merge
  /// dengan yang sudah dimuat supaya scroll history tidak hilang. Semua
  /// berbasis map per-chat; hasil basi (chat ini keluar dari map) diabaikan.
  Future<void> refreshChatMessages(String chatId, {int? limit}) async {
    try {
      final latest = await _service.getChatMessages(
        chatId,
        limit: limit ?? messagePageSize,
        offset: 0,
      );
      final current = _chatMsgMem[chatId];
      // Chat belum pernah di-prefetch/fetch di sesi ini → jadikan baseline.
      if (current == null) {
        if (latest.isNotEmpty) {
          _chatMsgMemPut(chatId, latest);
          MessageCache.instance.saveRawList(
            AdminBase.adminChatMsgKey(chatId),
            latest,
          );
          _notifyChats();
        }
        return;
      }
      // Merge murni: id baru disisipkan, baris dikenal yang berubah
      // (dihapus/diedit) ditimpa. Diam bila tak ada perubahan supaya daftar
      // di belakang layar tidak rebuild tiap poll.
      final res = mergeAdminChatMessages(current, latest);
      if (!res.changed) return;
      _chatMsgMemPut(chatId, res.merged);
      MessageCache.instance.saveRawList(
        AdminBase.adminChatMsgKey(chatId),
        res.merged,
      );
      _notifyChats();
    } catch (e) {
      dlog('[ADMIN] refreshChatMessages error: $e');
    }
  }

  /// last_read_at chat (uid → ISO) untuk hitung centang-2 monitor.
  Future<Map<String, String>> fetchChatLastRead(String chatId) async {
    try {
      return await _service.getChatLastRead(chatId);
    } catch (e) {
      dlog('[ADMIN] fetchChatLastRead error: $e');
      return {};
    }
  }

  /// Fetch image_data untuk satu foto (retry / thumb).
  Future<String> fetchMessageImage(int messageId) async {
    try {
      return await _service.getMessageImage(messageId);
    } catch (e) {
      dlog('[ADMIN] fetchMessageImage error: $e');
      return '';
    }
  }

  /// Hapus chat (hard delete server) + (opsional) user.
  /// Cache lokal HP admin untuk chat itu ikut dihapus supaya monitor tidak
  /// menampilkan pesan hantu dari disk. HP peserta dibersihkan lewat
  /// realtime DELETE di ChatService._removeLocalChat. Return true jika sukses.
  Future<bool> deleteChat(String chatId, List<String> deleteUserIds) async {
    try {
      final res = await _service.deleteChat(chatId, deleteUserIds);
      final paths = (res['photo_paths'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList();
      // Cleanup foto di bucket storage (best-effort, tidak blokir).
      for (final p in paths) {
        if (StoragePhotoService.instance.isPath(p)) {
          await StoragePhotoService.instance.delete(p);
        }
      }
      if (res['ok'] == true) {
        _chatMsgMem.remove(chatId);
        final cacheKey = 'private_$chatId';
        try {
          await MessageCache.instance.saveMessages(cacheKey, []);
        } catch (_) {}
        try {
          await PhotoCache.instance.clearChat(cacheKey);
        } catch (_) {}
      }
      return res['ok'] == true;
    } catch (e) {
      dlog('[ADMIN] deleteChat error: $e');
      return false;
    }
  }
}
