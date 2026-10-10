part of '../admin_chat_view_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _AcDataMx on _AdminBase {
  bool _applyMessages() {
    if (!mounted) return false;
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
    return _applyRawMessages(admin.chatMessagesFor(widget.chatId));
  }

  /// Pasang daftar pesan mentah (dari cache prefetch monitor / provider) ke
  /// layar. Dipakai jalur SINKRON supaya frame pertama langsung terisi.
  ///
  /// MERGE by id — bukan replace. Alasannya:
  ///  - poll/realtime hanya membawa puluhan pesan terbaru (limit 15/40);
  ///    replace akan MEMANGKAS riwayat yang sudah dimuat via scroll.
  ///  - dua sumber (provider map vs SQLite view) bisa punya window beda.
  /// Hasil selalu: union(incoming, existing) urut terbaru dulu.
  ///
  /// Return true bila _msgs berubah (pemanggil menyimpan ke cache).
  /// Perbandingan mencakup isDeleted/edited/type — teks TAK BERUBAH saat
  /// soft-delete (hanya flag), jadi banding id+teks saja membuat penanda
  /// hapus tak pernah muncul.
  bool _applyRawMessages(List<Map<String, dynamic>> raw) {
    if (!mounted || raw.isEmpty) return false;
    final incoming = _mapMessages(raw);
    if (incoming.isEmpty) {
      _ensureLeftUid();
      return false;
    }
    // Union by id: incoming menang untuk id yang sama (data lebih segar).
    final byId = <String, MessageModel>{};
    for (final m in incoming) {
      byId[m.id] = m;
    }
    for (final m in _msgs) {
      byId.putIfAbsent(m.id, () => m);
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    // Pertahankan imageData yang sudah di-load (jangan hilang setelah merge).
    final oldImg = <String, String>{};
    for (final m in _msgs) {
      if (m.imageData.isNotEmpty) oldImg[m.id] = m.imageData;
    }
    for (var i = 0; i < list.length; i++) {
      final kept = oldImg[list[i].id];
      if (kept != null && kept.isNotEmpty && list[i].imageData.isEmpty) {
        list[i] = list[i].copyWith(imageData: kept);
      }
    }
    // Anti-rebuild: isi identik → tak perlu setState. Bandingkan juga
    // isDeleted/edited/type (bukan cuma id+teks) supaya penanda hapus/edit
    // yang masuk tetap memicu rebuild. imageData SENGAJA dikecualikan:
    // foto yang sudah di-load (thumb) vs datang '' dari server — ikut
    // dibandingkan malah menghapus foto yang tampil tiap poll.
    if (list.length == _msgs.length) {
      var same = true;
      for (var i = 0; i < list.length; i++) {
        final a = list[i];
        final b = _msgs[i];
        if (a.id != b.id ||
            a.text != b.text ||
            a.isDeleted != b.isDeleted ||
            a.edited != b.edited ||
            a.type != b.type) {
          same = false;
          break;
        }
      }
      if (same) {
        _ensureLeftUid();
        return false;
      }
    }
    final senderSet = <String>{};
    for (final m in list) {
      if (m.senderId.isNotEmpty) senderSet.add(m.senderId);
    }
    final senders = senderSet.toList();
    setState(() {
      _msgs = list;
      _invalidateItems();
      // Sisi kiri STABIL: hanya diisi bila masih kosong. Menimpa tiap poll
      // dengan hasil hitung-ulang (yang bisa null/kosong saat data sesaat
      // kosong) membuat SEMUA bubble pindah ke kanan.
      if (_leftUid == null || _leftUid!.isEmpty) {
        final computed = _computeLeftUid(senders);
        if (computed != null && computed.isNotEmpty) _leftUid = computed;
      }
      _error = false;
    });
    _loadPhotos();
    // Hangatkan cache file voice terbaru (sekali per buka chat) supaya tap
    // play instan seperti foto.
    unawaited(VoicePrefetch.warmChat(widget.chatId, list));
    return true;
  }

  // ── Voice: VoiceBubble cache disk sendiri (play pertama download
  // sekali, sesi berikutnya dari lokal). imageData = voice_path.

  /// Sisi kiri = peserta pertama sesuai urutan judul (mis. judul
  /// "A & B" → bubble A di kiri, B di kanan). Konsisten, tidak tergantung
  /// siapa yang terakhir kirim pesan.
  ///
  /// FIX (gejala "lawan kadang muncul kadang ilang"): fallback WAJIB
  /// deterministik. Dulu cadangan terakhir `senders.first` = pengirim pesan
  /// Delegasi tipis ke [computeMonitorLeftUid] (fungsi murni, terkunci test).
  /// JANGAN menaruh logika di sini — dulu tiap lawan mengirim pesan,
  /// `_leftUid` berubah → SEMUA bubble berpindah sisi.
  String? _computeLeftUid(List<String> senders) => computeMonitorLeftUid(
    participantOrder: widget.participantOrder,
    chatId: widget.chatId,
    senders: senders,
  );

  /// Samakan last-read dari server (dasar centang-2 per pesan).
  /// Dipanggil tiap fetch + poll 5 detik supaya live mengikuti.
  Future<void> _refreshRead() async {
    try {
      final raw = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(adminProvider).fetchChatLastRead(widget.chatId);
      if (!mounted) return;
      final map = <String, DateTime>{};
      raw.forEach((k, v) {
        final t = DateTime.tryParse(v);
        if (t != null) map[k] = t;
      });
      setState(() => _lastRead = map);
    } catch (_) {}
  }

  /// Lawan bicara pengirim di chat 1:1 (uid satunya). Null bila tak jelas
  /// (bukan format uid1_uid2) → pesan fallback centang-1.
  String? _recipientOf(String senderId) {
    final parts = widget.chatId.split('_');
    if (parts.length != 2) return null;
    if (senderId == parts[0]) return parts[1];
    if (senderId == parts[1]) return parts[0];
    return null;
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  /// [force] = true memaksa load ulang dari server (pull-to-refresh).
  /// Tanpa [force], kalau pesan sudah ada di cache lokal (memori/SQLite),
  /// layar TIDAK menembak server — pesan lama dari lokal, yang baru lewat
  /// poll/realtime. Inilah yang bikin buka ulang chat terasa instan.
  Future<void> _fetch({bool force = false}) async {
    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
    // 0) SINKRON dari cache pesan monitor (hasil prefetch tap) — paling
    //    cepat, tanpa await: frame pertama langsung terisi seperti private
    //    chat. Dulu jalur ini tak ada (hanya cache stream `private_<id>`
    //    yang beda dari yang dipakai monitor) → selalu spinner → RPC.
    final adminMem = admin.peekChatMessages(widget.chatId);
    if (adminMem.isNotEmpty && _msgs.isEmpty) {
      _applyRawMessages(adminMem);
    }
    // 1) SINKRON dari memori stream (bila chat pernah dibuka sebagai user).
    final mem = MessageCache.instance.peekMessages(_chatKey);
    if (mem != null && mem.isNotEmpty && _msgs.isEmpty) {
      final senders = <String>{};
      for (final m in mem) {
        if (m.senderId.isNotEmpty) senders.add(m.senderId);
      }
      setState(() {
        _msgs = mem;
        _invalidateItems();
        _leftUid ??= _computeLeftUid(senders.toList());
      });
      _loadPhotos();
    }
    // 2) DISK cache MONITOR (`admin_chatmsg_<id>`) — kunci SAMA dengan
    //    prefetchChatMessages saat tap daftar. Dulu di sini memakai
    //    `cacheKeyFor(chatId)` (kunci cache USER) → SELALU KOSONG, sehingga
    //    buka-pertama jatuh ke RPC penuh (tunggu ~1 dtk) dan baru cepat di
    //    buka berikutnya (data sudah di memori). Sekarang jalur disk monitor
    //    dibaca lebih dulu → buka pertama sudah terisi.
    try {
      final raw = await MessageCache.instance.loadRawList(
        AdminBase.adminChatMsgKey(widget.chatId),
      );
      if (mounted && raw.isNotEmpty && _msgs.isEmpty) {
        if (_applyRawMessages(raw)) {
          _hasMore = admin.chatMessagesHasMoreFor(widget.chatId);
        }
      }
    } catch (_) {}
    // 2b) SQLite (cache lokal versi USER) — pelengkap bila monitor belum ada.
    try {
      final cached = await MessageCache.instance.loadMessages(_chatKey);
      if (mounted && cached.isNotEmpty && _msgs.isEmpty) {
        final senders = <String>{};
        for (final m in cached) {
          if (m.senderId.isNotEmpty) senders.add(m.senderId);
        }
        setState(() {
          _msgs = cached;
          _invalidateItems();
          _leftUid ??= _computeLeftUid(senders.toList());
        });
        _loadPhotos();
      }
    } catch (_) {}
    // SQLite sudah dicek → boleh tentukan kosong/isi (hindari empty-state blink).
    if (mounted && !_firstResolved) setState(() => _firstResolved = true);
    // PERSISTEN: sudah ada pesan lokal & tidak dipaksa → cukup. Pesan BARU
    // ditangani poll 5 dtk + realtime (tidak menembak server di sini).
    if (!force && _msgs.isNotEmpty) {
      _hasMore = admin.chatMessagesHasMoreFor(widget.chatId);
      unawaited(_refreshRead());
      return;
    }
    try {
      final ok = await admin.fetchChatMessages(widget.chatId, force: force);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _error = true;
        });
        return;
      }
      _applyMessages();
      unawaited(_refreshRead());
      _hasMore = admin.chatMessagesHasMoreFor(widget.chatId);
      // Simpan ke cache untuk buka berikutnya (instant).
      if (_msgs.isNotEmpty) {
        unawaited(MessageCache.instance.saveMessages(_chatKey, _msgs));
      }
      dlog(
        '[ADMIN-TIME] _fetch selesai msgs=${_msgs.length} hasMore=$_hasMore force=$force',
      );
    } catch (e) {
      if (!mounted) return;
      dlog('[ADMIN] chat view load error: $e');
      setState(() {
        _error = true;
      });
    }
  }

  Future<void> _poll() async {
    // Tumpukan poll saat jaringan lambat = RPC bertubi + rebuild
    // beruntun. Satu poll jalan dalam satu waktu.
    if (_polling) return;
    _polling = true;
    try {
      final admin = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(adminProvider);
      // Poll hanya butuh pesan BARU (15 cukup) — bukan 1 halaman penuh.
      await admin.refreshChatMessages(widget.chatId, limit: 15);
      if (!mounted) return;
      // Berubah (baru/dihapus/diedit) → simpan ke cache lokal supaya
      // buka-ulang langsung benar tanpa menunggu poll berikutnya.
      if (_applyMessages()) {
        if (_msgs.isNotEmpty) {
          unawaited(MessageCache.instance.saveMessages(_chatKey, _msgs));
        }
      }
      _hasMore = admin.chatMessagesHasMoreFor(widget.chatId);
      // last-read jarang berubah — cek tiap ~15 dtk, bukan tiap 5 dtk.
      if (++_pollCount % 3 == 0) unawaited(_refreshRead());
    } finally {
      _polling = false;
    }
  }

  List<MessageModel> _mapMessages(List<Map<String, dynamic>> raw) {
    return raw.map(_toMessageModel).where((m) => m.id.isNotEmpty).toList();
  }

  // ── Photo Loading (lazy, background) ─────────────────────────────────────

  /// Dua lapis supaya tidak spinner lama:
  /// 1) Thumbnail lokal (file chat di HP ini) dibaca SEKALIGUS via
  ///    `loadMany` (1 isolate) — bukan satu-satu seperti dulu.
  /// 2) Sisanya (belum pernah dibuka di HP ini) baru unduh per foto.
  Future<void> _loadPhotos() async {
    bool isPhoto(MessageModel m) =>
        m.type == 'image' ||
        m.type == 'view_once' ||
        m.type == 'view_once_expired';
    // CATATAN: video TIDAK lewat jalur thumbnail ini. Path video diisi dari
    // RPC (image_path) → ChatVideoBubble mengunduh & memutar sendiri.
    if (!_thumbBatchRunning) {
      _thumbBatchRunning = true;
      try {
        final ids = <String>[];
        for (final m in _msgs) {
          if (isPhoto(m) &&
              m.imageData.isEmpty &&
              !_photoLoading.contains(m.id)) {
            ids.add(m.id);
          }
        }
        if (ids.isNotEmpty && mounted) {
          final thumbs = await PhotoCache.instance.loadMany(_chatKey, ids);
          if (mounted) {
            var changed = false;
            for (final id in ids) {
              final t = thumbs[id];
              if (t == null || t.isEmpty) continue;
              final idx = _msgIndexById[id] ?? -1;
              if (idx >= 0 && _msgs[idx].imageData.isEmpty) {
                _msgs[idx] = _msgs[idx].copyWith(imageData: t);
                changed = true;
              }
            }
            if (changed) setState(() {});
          }
        }
      } catch (_) {
      } finally {
        _thumbBatchRunning = false;
      }
    }
    if (!mounted) return;
    // _msgs datang DESC (terbaru dulu) → pra-muat HANYA [_photoAutoLoadMax]
    // foto terbaru. Sisa foto dimuat saat bubble-nya tampil (via _retryImage
    // saat deferred) — buka chat banyak foto jadi mulus.
    var scheduled = 0;
    final now = DateTime.now();
    for (final m in _msgs) {
      if (scheduled >= _photoAutoLoadMax) break;
      if (!isPhoto(m) || m.imageData.isNotEmpty || m.isDeleted) continue;
      if (_photoLoading.contains(m.id) || _photoQueued.contains(m.id)) {
        continue;
      }
      final last = _photoLastAttempt[m.id];
      if (last != null && now.difference(last) < const Duration(seconds: 10)) {
        continue;
      }
      _photoLastAttempt[m.id] = now;
      _photoQueue.add(m.id);
      _photoQueued.add(m.id);
      scheduled++;
    }
    _drainPhotoQueue();
  }

  /// Jalankan antrean foto maksimal [_maxPhotoLoads] bersamaan.
  /// Selesai satu (sukses/gagal) → lanjutkan berikutnya.
  void _drainPhotoQueue() {
    if (!mounted) return;
    while (_photoActive < _maxPhotoLoads && _photoQueue.isNotEmpty) {
      final id = _photoQueue.removeAt(0);
      _photoQueued.remove(id);
      final idx = _msgIndexById[id] ?? -1;
      if (idx < 0) continue;
      final m = _msgs[idx];
      if (m.imageData.isNotEmpty || m.isDeleted) continue;
      final target = m;
      _photoActive++;
      _loadOnePhoto(target).whenComplete(() {
        _photoActive--;
        _drainPhotoQueue();
      });
    }
  }

  /// Sesi HP harus akun admin asli (bukan sesi dummy hasil swap) —
  /// kalau tidak, RPC foto melempar 'Unauthorized' dan foto tak pernah
  /// tampil. Cek di client supaya pesannya jelas.
  bool _isAdminSession() =>
      AdminGate.isRealAdmin(SupabaseConfig.client.auth.currentUser?.email);

  /// Return true bila foto berhasil tampil. Gagal (mis. sesi dummy,
  /// offline) → false supaya pemanggil bisa memberi tahu user, bukan diam.
  Future<bool> _loadOnePhoto(MessageModel msg) async {
    if (!mounted) return false;
    _photoLoading.add(msg.id);
    var loaded = false;
    try {
      var data = '';
      // Coba PhotoCache dulu (thumbnail yang sudah ada di device ini)
      try {
        data = await PhotoCache.instance.load(_chatKey, msg.id) ?? '';
      } catch (_) {}
      // Kalau belum ada di cache, fetch dari server via admin RPC
      if (data.isEmpty) {
        final msgId = int.tryParse(msg.id);
        if (msgId != null && mounted) {
          final admin = ProviderScope.containerOf(
            context,
            listen: false,
          ).read(adminProvider);
          var raw = await admin
              .fetchMessageImage(msgId)
              .timeout(const Duration(seconds: 15));
          // image_data berupa PATH storage (foto baru) → download dari bucket.
          if (raw.isNotEmpty &&
              mounted &&
              ProviderScope.containerOf(
                context,
                listen: false,
              ).read(storageProvider).isPath(raw)) {
            raw =
                await ProviderScope.containerOf(context, listen: false)
                    .read(storageProvider)
                    .download(raw)
                    .timeout(const Duration(seconds: 15)) ??
                '';
          }
          data = raw;
          if (data.isNotEmpty) {
            try {
              await PhotoCache.instance.save(_chatKey, msg.id, data);
            } catch (_) {}
          }
        }
      }
      // Decode + buat thumbnail dari full-res
      if (data.isNotEmpty) {
        var thumb = '';
        try {
          thumb = await PhotoCache.instance.loadThumb(_chatKey, msg.id) ?? '';
        } catch (_) {}
        if (thumb.isEmpty) {
          try {
            thumb = await NativeImage.processAdminThumb(data) ?? '';
          } catch (_) {}
        }
        if (thumb.isEmpty) thumb = '';
        if (!mounted) return false;
        final idx = _msgIndexById[msg.id] ?? -1;
        if (idx >= 0) {
          // Gunakan thumbnail kalau ada, fallback ke full-res
          final imgData = thumb.isNotEmpty ? thumb : data;
          if (_msgs[idx].imageData.isEmpty || _msgs[idx].imageData != imgData) {
            _msgs[idx] = _msgs[idx].copyWith(imageData: imgData);
            // Batch: TIDAK setState per foto (dulu tiap foto = rebuild seluruh
            // list → blink/jank). Jadwalkan satu rebuild per frame.
            _schedulePhotoSetState();
          }
          loaded = _msgs[idx].imageData.isNotEmpty;
        }
      }
    } catch (_) {
      // Gagal (timeout/network/RPC) → biarkan placeholder; tap/auto-load
      // berikutnya bisa coba lagi (id SELALU dibuang di finally).
    } finally {
      _photoLoading.remove(msg.id);
    }
    return loaded;
  }

  void _schedulePhotoSetState() {
    if (!mounted) return;
    // Coalesce 400ms: foto selesai berselang detik (network), bukan dalam
    // frame yang sama — post-frame saja berarti 1 rebuild PER FOTO (12 foto
    // = 12x rebuild 40 bubble). Timer ini menggabungkannya jadi sedikit.
    if (_photoSetStateTimer?.isActive ?? false) return;
    _photoSetStateTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _retryImage(String msgId) async {
    final msg = _msgs.where((m) => m.id == msgId).firstOrNull;
    if (msg == null || !mounted) return;
    final ok = await _loadOnePhoto(msg);
    // Gagal tampil JANGAN diam: beri tahu sebabnya. Sesi dummy = RPC
    // ditolak server; kalau tidak, berarti koneksi/kuota.
    if (!ok && mounted) {
      final s = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(localeProvider).s;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _isAdminSession() ? s.adminPhotoLoadFail : s.dummyNeedAdmin,
            ),
          ),
        );
    }
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeRealtime() {
    // Lewat provider (bukan Supabase.instance langsung) supaya test bisa
    // menyuntik client mock — perilaku produksi identik.
    final sb = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider).realtimeClient;
    _channelClient = sb;
    _channel = sb.channel('admin-${widget.chatId.hashCode}');
    // FILTER chat_id — tanpa ini SETIAP pesan di seluruh app memicu _poll
    // (fetch+setState) → blink/berat. Hanya perubahan chat INI yang reaksi.
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'chat_id',
      value: widget.chatId,
    );
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'private_messages',
      filter: filter,
      callback: (_) => _poll(),
    );
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'private_messages',
      filter: filter,
      callback: (_) => _poll(),
    );
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'private_messages',
      filter: filter,
      callback: (_) => _poll(),
    );
    _channel!.subscribe((status, err) {
      // Realtime error (mis. offline) → catat; timer _pollTimer 5 dtk tetap
      // jadi fallback sehingga monitor tidak mati diam-diam.
      if (err != null) debugPrint('[ADMIN] chat-monitor realtime error: $err');
    });
  }

  // ── Mapping ───────────────────────────────────────────────────────────────

  MessageModel _toMessageModel(Map<String, dynamic> m) {
    return MessageModel(
      id: '${m['id']}',
      senderId: '${m['sender_id'] ?? ''}',
      senderName: '${m['sender_name'] ?? 'Anon'}',
      senderGender: '${m['sender_gender'] ?? 'other'}',
      isRegistered: false,
      text: '${m['text'] ?? ''}',
      type: '${m['type'] ?? 'text'}',
      // Voice: RPC kirim voice_path → disimpan di imageData (dipakai
      // VoiceBubble dengan disk cache-nya sendiri).
      // Foto/video: pakai `image_data` bila ada (view-once), kalau kosong
      // fallback ke `image_path` (path storage) — supaya admin BISA melihat
      // foto biasa & video di monitor (dulu kosong → tak tampil).
      imageData: m['type'] == 'voice'
          ? '${m['voice_path'] ?? ''}'
          : (('${m['image_data'] ?? ''}').isNotEmpty
                ? '${m['image_data']}'
                : '${m['image_path'] ?? ''}'),
      isDeleted: m['is_deleted'] == true,
      edited: m['edited'] == true,
      durationMs: m['duration_ms'] is int
          ? m['duration_ms'] as int
          : int.tryParse('${m['duration_ms'] ?? ''}'),
      timestamp: parseDate(m['created_at']),
      repliedToId: m['replied_to_id'] is String ? m['replied_to_id'] : null,
      repliedToText: m['replied_to_text'],
      repliedToSenderName: m['replied_to_sender_name'],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Dua avatar peserta DITUMPANG-TINDIH (bukan satu di kiri & satu di kanan)
  /// — gaya sama dengan kartu di daftar monitor agar header rapi. Tap salah
  /// satu avatar → buka PROFIL-nya (UserInfoScreen, sama seperti tap avatar
  /// di private chat) — bukan zoom foto.
  Widget _headerAvatarPair() {
    final uids = widget.participantOrder
        .where((u) => u.isNotEmpty)
        .take(2)
        .toList();
    if (uids.isEmpty) return const SizedBox.shrink();
    const size = 34.0;
    const overlap = 12.0;

    Widget avatarOf(String uid, int i, {required bool withRing}) {
      final name = widget.participantNames[uid] ?? '';
      return Container(
        // Ring pemisah HANYA saat avatar tumpang-tindih (2 peserta) supaya
        // batas antar-avatar terlihat rapi. Avatar TUNGGAL tampil polos
        // (tanpa border) — persis gaya daftar "Pengguna Online".
        decoration: withRing
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.headerGradient.colors.first,
                  width: 2,
                ),
              )
            : null,
        child: GestureDetector(
          onTap: () => _openProfile(uid, name),
          // Gaya SAMA PERSIS dengan daftar "Pengguna Online": lingkaran latar
          // + ring warna gender untuk yang tanpa foto.
          child: GenderAvatar(
            uid: uid,
            name: name,
            gender: widget.participantGenders[uid] ?? '',
            size: size,
          ),
        ),
      );
    }

    if (uids.length == 1) return avatarOf(uids[0], 0, withRing: false);
    return SizedBox(
      width: size * 2 - overlap,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < 2; i++)
            Positioned(
              left: i * (size - overlap),
              child: avatarOf(uids[i], i, withRing: true),
            ),
        ],
      ),
    );
  }

  /// Tap avatar header → profil peserta (sama seperti private chat).
  void _openProfile(String uid, String name) {
    if (uid.isEmpty || !mounted) return;
    final navKey = navKeyUser(uid);
    if (!tryClaimNav(navKey)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInfoScreen(userId: uid, fallbackName: name),
      ),
    ).then((_) => releaseNav(navKey));
  }

  /// Tahan bubble pesan → salin teks (sama seperti "salin" di private chat).
  /// Monitor read-only: langsung salin + toast, tanpa mode seleksi.
  Future<void> _copyMessage(MessageModel msg) async {
    if (msg.text.isEmpty || !mounted) return;
    await Clipboard.setData(ClipboardData(text: msg.text));
    if (!mounted) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.msgMessageCopied)));
  }
}
