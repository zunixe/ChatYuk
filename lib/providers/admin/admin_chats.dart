part of '../admin_provider.dart';

/// Monitor chat + call aktif + pesan kontak + pesan per-chat + cache.
mixin AdminChatsMx on AdminBase {
  // ── Admin Chat Monitor ──
  static const int chatPageSize = 50;
  // 40 (dulu 100): buka chat ringan — 100 pesan + view_once base64 berat
  // di-serialize sekaligus bikin lambat. Sisanya dimuat saat scroll ke atas.
  static const int messagePageSize = 40;

  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _chatMessages = [];
  List<String> _adminUids = [];
  bool _chatsLoading = false;
  bool _chatsHasMore = true;
  int _chatsTotal = 0;
  bool _chatsFetchingMore = false;
  AdminErrKind? _chatsError;

  List<Map<String, dynamic>> get chats => _chats;
  List<Map<String, dynamic>> get chatMessages => _chatMessages;
  List<String> get adminUids => _adminUids;
  bool get chatsLoading => _chatsLoading;
  bool get chatsHasMore => _chatsHasMore;
  int get chatsTotal => _chatsTotal;
  AdminErrKind? get chatsError => _chatsError;

  Future<void> fetchChats() async {
    _chatsLoading = true;
    _chatsError = null;
    if (!_disposed) notifyListeners();
    // Data kosong (cold start / tab baru) → tampilkan cache disk dulu.
    if (_chats.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(AdminBase.kAdminChatsKey);
        if (cached.isNotEmpty && _chats.isEmpty) {
          _chats = cached;
          _chatsTotal = cached.length;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final res = await _service.listChats(limit: chatPageSize, offset: 0);
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
    if (!_disposed) notifyListeners();
  }

  /// Muat halaman berikutnya (infinite scroll list chat).
  Future<void> fetchMoreChats() async {
    if (_chatsFetchingMore || !_chatsHasMore || _chatsLoading) return;
    _chatsFetchingMore = true;
    try {
      final res = await _service.listChats(
        limit: chatPageSize,
        offset: _chats.length,
      );
      final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _chatsTotal = (res['total'] as num?)?.toInt() ?? _chatsTotal;
      _chats = [..._chats, ...more];
      _chatsHasMore = _chats.length < _chatsTotal;
      _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .toList();
    } catch (e) {
      dlog('[ADMIN] fetchMoreChats error: $e');
    }
    _chatsFetchingMore = false;
    if (!_disposed) notifyListeners();
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
    if (!_disposed) notifyListeners();
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
    try {
      // Sweep zombie hanya tiap panggilan ke-12 (fallback ~12 menit pada
      // polling 60 dtk) — realtime UPDATE sudah memicu refresh instan.
      if (_sweepCounter++ % 12 == 0) {
        try {
          await _service.sweepStaleCalls();
        } catch (_) {}
      }
      _activeCalls = await _service.getActiveCalls();
      _detectNewCalls(_activeCalls);
    } catch (e) {
      dlog('[ADMIN] fetchActiveCalls error: $e');
    }
    _activeCallsLoading = false;
    if (!_disposed) notifyListeners();
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
    ch.subscribe();
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
  int get contactTotal => _contactTotal;
  AdminErrKind? get contactError => _contactError;

  Future<void> fetchContactMessages() async {
    _contactLoading = true;
    _contactError = null;
    if (!_disposed) notifyListeners();
    // Cold start / tab baru → cache disk dulu (tahan offline).
    if (_contactMessages.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(
          AdminBase.kAdminContactKey,
        );
        if (cached.isNotEmpty && _contactMessages.isEmpty) {
          _contactMessages = cached;
          _contactTotal = cached.length;
          if (!_disposed) notifyListeners();
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
    if (!_disposed) notifyListeners();
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
    if (!_disposed) notifyListeners();
  }

  Future<void> setContactRead(String id, {bool read = true}) async {
    try {
      await _service.setContactRead(id, read: read);
      final i = _contactMessages.indexWhere((m) => m['id'] == id);
      if (i >= 0) {
        _contactMessages[i] = {..._contactMessages[i], 'is_read': read};
        if (!_disposed) notifyListeners();
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
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[ADMIN] deleteContactMessage error: $e');
    }
  }

  bool _chatMessagesHasMore = true;
  bool _chatMessagesFetchingMore = false;
  bool get chatMessagesHasMore => _chatMessagesHasMore;

  Future<bool> fetchChatMessages(String chatId) async {
    // JANGAN kosongkan list dulu — biar pesan lama tetap tampil selama fetch
    // (anti-blink: dulu _chatMessages=[] → layar kosong → isi ulang, ikut
    // terulang tiap poll 5s).
    _chatMessagesHasMore = true;
    // Chat berbeda → muat cache disk chat itu dulu (tahan offline).
    if (_chatMsgCacheFor != chatId) {
      _chatMsgCacheFor = chatId;
      _chatMessages = const [];
      try {
        final cached = await MessageCache.instance.loadRawList(
          AdminBase.adminChatMsgKey(chatId),
        );
        if (cached.isNotEmpty && _chatMsgCacheFor == chatId) {
          _chatMessages = cached;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final fresh = await _service.getChatMessages(
        chatId,
        limit: messagePageSize,
        offset: 0,
      );
      if (fresh.isNotEmpty) {
        _chatMessages = fresh;
        MessageCache.instance.saveRawList(AdminBase.adminChatMsgKey(chatId), fresh);
      }
      _chatMessagesHasMore = fresh.length >= messagePageSize;
      return true;
    } catch (e) {
      // Data lama (memori/disk) dipertahankan — layar tetap ada isinya.
      dlog('[ADMIN] fetchChatMessages error: $e');
      return false;
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  /// Chat yang sedang ditampilkan di monitor (untuk tahu kapan cache disk
  /// perlu dimuat ulang saat pindah chat).
  String? _chatMsgCacheFor;

  /// Muat pesan lebih lama (pagination, dipanggil saat scroll ke atas).
  Future<void> fetchMoreChatMessages(String chatId) async {
    if (_chatMessagesFetchingMore || !_chatMessagesHasMore) return;
    _chatMessagesFetchingMore = true;
    try {
      final older = await _service.getChatMessages(
        chatId,
        limit: messagePageSize,
        offset: _chatMessages.length,
      );
      _chatMessages = [..._chatMessages, ...older];
      _chatMessagesHasMore = older.length >= messagePageSize;
    } catch (e) {
      dlog('[ADMIN] fetchMoreChatMessages error: $e');
    }
    _chatMessagesFetchingMore = false;
    if (!_disposed) notifyListeners();
  }

  /// Refresh pesan terbaru tanpa reset pagination — merge dengan yang sudah
  /// dimuat supaya scroll history tidak hilang saat ada pesan baru masuk.
  Future<void> refreshChatMessages(String chatId) async {
    try {
      final latest = await _service.getChatMessages(
        chatId,
        limit: messagePageSize,
        offset: 0,
      );
      final knownIds = _chatMessages.map((m) => '${m['id']}').toSet();
      final merged = List<Map<String, dynamic>>.from(_chatMessages);
      // Pesan baru (belum ada) ditambahkan di depan (terbaru duluan).
      for (final m in latest) {
        if (!knownIds.contains('${m['id']}')) {
          merged.insert(0, m);
        }
      }
      _chatMessages = merged;
    } catch (e) {
      dlog('[ADMIN] refreshChatMessages error: $e');
    }
    if (!_disposed) notifyListeners();
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

  void clearChatMessages() {
    _chatMessages = [];
    _chatMessagesHasMore = true;
    _chatMessagesFetchingMore = false;
    if (!_disposed) notifyListeners();
  }
}
