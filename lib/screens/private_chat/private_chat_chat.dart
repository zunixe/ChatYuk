part of '../private_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _PcChatMx on _PrivateChatBase {
@override
  TextEditingController get chatMsgCtrl => _msgCtrl;
@override
  set sendPendingLocation(ChatLocation? v) => _pendingLocation = v;
@override
  void photoClearComposerText() {
    sendClearComposer();
    if (mounted) setState(() => sendReplyingTo = null);
  }
@override
  bool get videoOnceSelected => _pendingVideoOnce;
/// Dibaca composer untuk menampilkan pratinjau video (thumbnail base64).
  String? get pendingVideoPosterB64 => _pendingVideoPoster;
  // ── Kontrak ChatSendMixin ──
  @override
  TextEditingController get sendMsgCtrl => _msgCtrl;
@override
  set sendIsSending(bool v) => _isSending = v;
@override
  set sendReplyingTo(MessageModel? v) => replyingTo = v;
@override
  String? get sendPendingPhotoBase64 => _pendingPhotoBase64;
@override
  void sendCancelEdit() => cancelEdit();
@override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    // Ukuran font chat berubah (slider) → rebuild bubble & composer langsung.
    ChatTextScale.notifier.addListener(_onFontScaleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) activeChatId.value = widget.chatId;
    });
    // Lazy load centang-2: baca last-read tersimpan dari disk DULU supaya
    // pesan yang sudah dibaca langsung centang 2 — tanpa menunggu network.
    // Network tetap sumber kebenaran dan me-refresh diam-diam bila berubah.
    // JALUR CEPAT (sinkron): snapshot list chat di MEMORI (sudah di-preload
    // saat bootstrap) — `lastReadAt` langsung terisi sebelum frame pertama
    // dirender, jadi centang-2 tidak menunggu satu hop async apa pun.
    _primeReadFromCache();
    // Fallback: kv `read:` (bila snapshot memori belum ada) — async.
    _loadCachedRead();
    // Prime bintang SINKRON: baca id pesan berbintang dari MEMORI sebelum
    // frame pertama → bintang tampil instan, tanpa "di-load dulu" (anti-glich).
    // Stream realtime + fallback async menimpa sesudahnya.
    _primeStarredFromCache();
    // (listener call via ref.listen di build — lihat bawah).
    // Buka keyboard → tutup baris menu attach (mirip WhatsApp).
    // + PENTING (HP memori ketat): saat user mulai mengetik, buang bitmap
    //   foto/video full-res dari RAM cache (bukan yang tampil di list) supaya
    //   working-set ngetik kecil → halaman tak ter-swap → tak ada "freeze lalu
    //   kedelte semua" saat page ter-swap di-fault balik. Pesan/list tetap
    //   (MessageCache tak disentuh) → buka chat tetap instan.
    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus) {
        if (_showAttachRow) setState(() => _showAttachRow = false);
        try {
          PhotoCache.instance.trimMemCache();
        } catch (_) {}
        try {
          PostPhotoCache.instance.trimMemCache();
        } catch (_) {}
        // Buang bytes foto (bukan thumb yang tampil) dari RAM saat mulai
        // mengetik → working-set kecil → halaman tak ter-swap → anti freeze.
        try {
          decodedImageCache.clear();
        } catch (_) {}
      }
    });
    // Anti-screenshot dikontrol setting admin global (ScreenSecureService).
    // Privasi view_once tetap terjaga via enterViewOnce/exitViewOnce.

    final chat = ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier);
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);

    // Prime sinkron supaya akun terhapus langsung tampil banner di frame
    // pertama — tanpa kedip composer "Ketik pesan..." dulu menunggu stream.
    _otherDeleted = widget.initialOtherDeleted;
    if (!_otherDeleted && auth.uid != null) {
      final snap = chat.lastPrivateChatsSnapshot(auth.uid!);
      if (snap != null) {
        for (final c in snap) {
          if (c.chatId == widget.chatId && c.otherDeleted) {
            _otherDeleted = true;
            break;
          }
        }
      }
    }

    // Scroll ke atas → load pesan lama (pagination)
    _scrollCtrl.addListener(_onScrollToLoadOlder);
    // T1b/T1c: kerja berat (channel realtime+RPC) ditunda ke post-frame agar
    // animasi transisi bebas I/O. Frame pertama dari snapshot+peekMessages.
    _chatInfoStream = chat.getMyPrivateChats(auth.uid ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startMessagesStream();
    });

    // Dedupe _pending: hapus satu per satu saat server konfirmasi — aman utk double-send text sama
    _msgsSub = _msgsStreamCtrl.stream.listen((msgs) {
      _scheduleWarmPrefetch(msgs); // hangatkan voice + poster video (post-frame).
      // Auto-load foto deferred (di luar window) — HANYA saat daftar pesan
      // berubah (emit stream), BUKAN dari build(). Dulu dipanggil di itemBuilder
      // → tiap rebuild (mis. tiap kirim TEKS) memicu fetchImage → `_emit()`
      // stream baru → bubble FOTO di atasnya re-mount/re-decode = "foto ngedip
      // saat kirim pesan teks" (insiden 2026-10-11).
      _autoLoadMissingImages(msgs);
      // Pesan BARU dari lawan yang masuk sementara chat terbuka → tandai baca
      // agar last_read_at lawan maju → centang 2 (read) pengirim langsung terisi.
      // Tanpa ini, centang 2 baru muncul setelah keluar-masuk chat.
      final myUid = auth.uid;
      if (myUid != null) {
        final latestIncoming = msgs
            .where((m) => m.senderId != myUid && m.timestamp.isAfter(_openedAt))
            .map((m) => m.timestamp)
            .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
        if (latestIncoming != null &&
            (_lastIncomingSeen == null ||
                latestIncoming.isAfter(_lastIncomingSeen!))) {
          _lastIncomingSeen = latestIncoming;
          chat.markAsRead(widget.chatId, myUid);
        }
      }
      if (_pending.isEmpty || !mounted) return;
      final mySenderIds = _pending.map((p) => p.senderId).toSet();
      var changed = false;
      // A2 (2026-10-11): SATU pass atas `msgs` (dulu 6 loop penuh terpisah).
      // Semantik SAMA — tiap jenis diklasifikasi via switch, aksi per-jenis
      // dijalankan inline. Bounded N≤100, tapi dari 6×O(N) → 1×O(N)/emit.
      for (final m in msgs) {
        if (!mySenderIds.contains(m.senderId)) continue;
        switch (m.type) {
          case 'call':
            if (m.timestamp.isAfter(_openedAt)) {
              final idx = _pending.indexWhere((p) => p.type == 'call');
              if (idx != -1) {
                _pending.removeAt(idx);
                changed = true;
              }
            }
            break;
          case 'image':
          case 'view_once':
          case 'view_once_expired':
            if (m.timestamp.isAfter(_openedAt) &&
                _confirmedPhotoIds.add(m.id)) {
              _trimConfirmed(_confirmedPhotoIds);
              final idx = _pending.indexWhere(
                (p) =>
                    p.type == 'image' ||
                    p.type == 'view_once' ||
                    p.type == 'view_once_expired',
              );
              if (idx != -1) {
                _pending.removeAt(idx);
                changed = true;
              }
            }
            break;
          case 'voice':
            if (m.timestamp.isAfter(_openedAt) &&
                _confirmedVoiceIds.add(m.id)) {
              _trimConfirmed(_confirmedVoiceIds);
              final idx = _pending.indexWhere((p) => p.type == 'voice');
              if (idx != -1) {
                _pending.removeAt(idx);
                changed = true;
              }
            }
            break;
          case 'video':
          case 'video_once':
          case 'video_once_expired':
            if (m.timestamp.isAfter(_openedAt) &&
                _confirmedVideoIds.add(m.id)) {
              _trimConfirmed(_confirmedVideoIds);
              final idx = _pending.indexWhere(
                (p) =>
                    p.type == 'video' ||
                    p.type == 'video_once' ||
                    p.type == 'video_once_expired',
              );
              if (idx != -1) {
                _pending.removeAt(idx);
                changed = true;
              }
            }
            break;
          default:
            // Teks: cocokkan via consumeConfirmedText (recency + sekali pakai
            // + FIFO). JANGAN cocokkan mentah via isi.
            {
              final idx = consumeConfirmedText(
                server: m,
                openedAt: _openedAt,
                consumedIds: _confirmedTextIds,
                pendings: _pending,
              );
              _trimConfirmed(_confirmedTextIds);
              if (idx != -1) {
                _queuedIds.remove(_pending[idx].id);
                _pending.removeAt(idx);
                changed = true;
              }
            }
        }
      }
      if (changed && mounted) setState(() {});
    }, onError: (e) {
      // OFFLINE: stream pesan bisa error (realtime putus). TANPA onError,
      // error tak tertangkap ini merusak frame/dispatcher → back mati.
      debugPrint('[NAV] msgs stream error private-chat: $e');
    });

    // Subscription non-kritis ditunda ke post-frame supaya frame pertama
    // (list pesan) tidak tertahan — ala WhatsApp: pesan tampil dulu,
    // status/typing/centang-2 menyusul di frame berikutnya.
    _wasBlocked = ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier).isBlocked(widget.otherUid);
    _chatInfoSub = _chatInfoStream.listen((chats) {
      final info = chats.cast<chatRiverpod.PrivateChatInfo?>().firstWhere(
        (c) => c?.chatId == widget.chatId,
        orElse: () => null,
      );
      // Lawan sudah menghapus akunnya → tandai + buang centang-2 "hantu".
      // Tanpa ini, lastReadAt lama yang tersimpan di cache membuat pesan
      // kita tetap terlihat centang-2 padahal tidak ada perangkat lawan
      // yang pernah menerimanya.
      final gone = info?.otherDeleted ?? false;
      if (gone != _otherDeleted) {
        _otherDeleted = gone;
        if (gone) _otherLastRead = null;
        _scheduleRebuild();
      }
      if (gone) return;
      final read = info?.lastReadAt[widget.otherUid];
      // Monoton maju: yang sudah centang-2 tidak boleh balik centang-1
      // walau network/disk menyusul dengan nilai null atau lebih tua.
      final merged = ReadReceipt.merge(_otherLastRead, read);
      if (read != null && merged != _otherLastRead) {
        _otherLastRead = merged;
        _scheduleRebuild();
        // Persist untuk cold start berikutnya.
        if (merged != null) _persistRead(merged);
      }
    }, onError: (e) {
      // OFFLINE: chat-info stream error → jangan biarkan tak tertangkap.
      debugPrint('[NAV] chatInfo stream error private-chat: $e');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // markAsRead: RPC tanpa render → aman dijalankan langsung (centang-2
      // lawan cepat maju). Bukan beban frame.
      if (auth.uid != null) chat.markAsRead(widget.chatId, auth.uid!);
      // ── Sisa pekerjaan (reaksi, starred, status, typing, profil) TIDAK
      // dijalankan di frame pertama: dulu semuanya nembak bersamaan TEPAT
      // saat animasi buka private chat mulai → 7 tugas (disk+setState+RPC)
      // bersaing dengan transisi = jank "pas mau kebuka". Ditunda ~220ms
      // (di atas durasi transisi 150ms) supaya frame animasi bersih; fitur
      // (badge reaksi) menyusul sekejap setelah chat tampil.
      _openWorkTimer = Timer(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        _openWorkTimer = null;
        // Cache dulu (tampil instan), stream menimpa sesudahnya.
        ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).loadCachedReactions(widget.chatId).then((
          cached,
        ) {
          if (!mounted || cached.isEmpty || reactions.isNotEmpty) return;
          reactions = cached;
          _scheduleRebuild();
        });
        _reactionsSub = ProviderScope.containerOf(context, listen: false).read(messageReactionProvider)
            .watchReactions(widget.chatId)
            .listen((m) {
          reactions = m;
          _scheduleRebuild();
          ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).saveCachedReactions(widget.chatId, m);
        }, onError: (e) {
          debugPrint('[NAV] reactions stream error: $e');
        });
        _starredSub = ProviderScope.containerOf(context, listen: false).read(messageReactionProvider)
            .watchStarred(widget.chatId)
            .listen((m) {
          starredIds = m;
          _scheduleRebuild();
          ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).saveCachedStarred(
            widget.chatId,
            m,
          );
        }, onError: (e) {
          debugPrint('[NAV] starred stream error: $e');
        });
        // Fallback async: bila prime sinkron (initState) belum terisi (cache
        // memori kosong di sesi ini), muat dari disk. Jangan timpa bila
        // `starredIds` sudah terisi (stream/prime lebih akurat). Dulu TANPA
        // cache → tiap buka chat bintang "di-load dulu" menunggu round-trip.
        ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).loadCachedStarred(
          widget.chatId,
        ).then((cached) {
          if (!mounted || cached.isEmpty || starredIds.isNotEmpty) return;
          starredIds = cached;
          _scheduleRebuild();
        });
        // ── Yang MEMBUAT channel realtime + RPC profil dipisah ke tahap
        // kedua (~500ms) — pembuatan channel Supabase (handshake join) &
        // getOtherProfile bisa "ketahan" tepat saat transisi buka chat baru
        // selesai sempurna. Reaksi cache (di atas, murah) tetap 220ms.
        _channelWorkTimer = Timer(const Duration(milliseconds: 280), () {
          if (!mounted) return;
          _channelWorkTimer = null;
          // Subscribe status realtime lawan bicara
          if (!_wasBlocked) {
            _subscribeStatus();
            _subscribeTyping();
          }
          final otherId = widget.otherUid;
          ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).getOtherProfile(otherId).then((p) {
            if (!mounted || p == null) return;
            _otherCity = p.city.trim();
            _otherCountry = p.country.trim();
            _otherRegistered = p.isRegistered;
            _otherAgeLive = p.age;
            _otherGenderLive = p.gender;
            _scheduleRebuild();
          });
        });
      });
    });
    // Antrean offline: koneksi pulih → kirim otomatis; muat sisa antrean
    // sesi lalu (app sempat ditutup saat offline).
    // CATATAN: `ref.listen` TIDAK boleh di initState (harus di build) —
    // lihat build(): ref.listen(connectivityProvider) dipasang di sana.
    _connOnline = ref.read(connectivityProvider);
    loadQueuedForChat();
  }
void _sendRecordingSignal() {
    ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier).sendTyping(widget.chatId, kind: 'recording');
  }
  // ── Antrean offline: implementasi BERSAMA di ChatOutboxMixin ──
  bool get outboxIsOnline => _connOnline;
@override
  Set<String> get outboxQueuedIds => _queuedIds;
}
