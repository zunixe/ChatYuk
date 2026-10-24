part of '../private_chat_screen.dart';


mixin _PcChat2Mx on _PrivateChatBase {
void _onSearchChanged(String v) {
    setState(() {
      _searchQuery = v;
      _matchIndex = 0;
      _searchJumpTries = 0;
    });
    // Ketik = lompat ke cocok terbaru HANYA bila sudah ter-render
    // (tanpa jambak scroll untuk yang jauh — user pakai panah).
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToMatch(0));
  }
/// Pindah ke hasil berikut/sebelumnya (dir +1 = lebih lama, -1 = lebih
  /// baru), bungkus melingkar ala WhatsApp.
  void _gotoMatch(int dir) {
    if (_matchIds.isEmpty) return;
    setState(() {
      _matchIndex = (_matchIndex + dir) % _matchIds.length;
      if (_matchIndex < 0) _matchIndex += _matchIds.length;
      _searchJumpTries = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToMatch(dir),
    );
  }
@override
  String get chatId => widget.chatId;
@override
  chatRiverpod.ChatNotifier get chatProvider => ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier);
@override
  void chatFocusComposer() => _inputFocus.requestFocus();
@override
  void chatScrollToBottom() => _scrollToBottom();
@override
  String chatDeletedLabel(S s) => s.messageDeleted;
/// Kirim pembaruan koordinat lokasi live tiap 30 detik sampai kedaluwarsa.
  /// Berhenti otomatis saat waktu habis; update gagal diabaikan (best-effort).
  void _startLiveLocationUpdates(String messageId, ChatLocation initial) {
    _liveTimer?.cancel();
    final lp = ProviderScope.containerOf(context, listen: false).read(locationProvider);
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (t) async {
      final exp = initial.expiresAt;
      if (exp == null || DateTime.now().toUtc().isAfter(exp)) {
        t.cancel();
        return;
      }
      // P1b (baterai 2026-10-11): JANGAN nyalakan GPS + update DB saat app
      // di background/layar mati (boros baterai; lokasi terakhir tetap
      // tersimpan). Resume di foreground → update berikutnya menyusul.
      if (!AppForeground.now) return;
      final pos = await lp.precisePosition();
      if (pos == null) return;
      if (!mounted) return;
      final updated = initial.copyWith(lat: pos.$1, lng: pos.$2);
      await ProviderScope.containerOf(context, listen: false)
          .read(chatRiverpod.chatProvider.notifier)
          .updateLocationMessage(messageId, updated.encode());
    });
  }
  // Caption & balasan untuk view-once dari picker (kirim langsung tanpa
  // preview) — dulu teks yang diketik diabaikan.
  @override
  String get photoComposerText => sendMsgCtrl.text;
@override
  void photoOnSent(String kind) {
    _maybeNewChatBonus();
    _schedulePendingConfirmFallback();
  }
@override
  String? get pendingVideoPath => _pendingVideoPath;
/// Kontrak ChatSendMixin: video pending (router tombol kirim).
  @override
  String? get sendPendingVideoPath => _pendingVideoPath;
@override
  void videoSetOnce(bool value) {
    setState(() => _pendingVideoOnce = value);
  }
@override
  void videoSetPreview({
    required String path,
    required String posterBase64,
    required int durationMs,
  }) {
    setState(() {
      _pendingVideoPath = path;
      _pendingVideoPoster = posterBase64;
      _pendingVideoMs = durationMs;
      _pendingVideoOnce = false; // default: video biasa
      // Video bukan foto: buang preview foto + timer view-once. Lokasi juga
      // (hanya satu preview yang boleh tampil).
      _pendingPhotoBase64 = null;
      _pendingLocation = null;
      _viewTimerSecs = null;
      _inputFocus.requestFocus();
    });
    _scrollToBottom();
  }
@override
  List<Mention> sendMentionCandidates() => _mentionCandidates;
void _autoLoadMissingImages(List<MessageModel> msgs) {
    final now = DateTime.now();
    for (final m in msgs) {
      if (m.type != 'image') continue;
      // Sudah pernah dipindai → lewati (anti scan ulang O(N) tiap emit).
      if (!_imgScannedIds.add(m.id)) continue;
      if (m.imageData.isNotEmpty || m.isDeleted) continue;
      if (_imgInFlight.contains(m.id) || _imgQueued.contains(m.id)) continue;
      final last = _imgLastAttempt[m.id];
      if (last != null && now.difference(last) < const Duration(seconds: 10)) {
        continue;
      }
      _imgLastAttempt[m.id] = now;
      _imgQueue.add(m.id);
      _imgQueued.add(m.id);
    }
    // Bound map penanda (cegah tumbuh seumur sesi).
    if (_imgScannedIds.length > 2000) {
      _imgScannedIds.removeAll(_imgScannedIds.take(500).toList());
    }
    if (_imgLastAttempt.length > 2000) {
      _imgLastAttempt.remove(_imgLastAttempt.keys.first);
    }
    _drainImageQueue();
  }
void _drainImageQueue() {
    while (_imgInFlight.length < _maxImageFetches && _imgQueue.isNotEmpty) {
      final id = _imgQueue.removeAt(0);
      _imgQueued.remove(id);
      if (!_imgInFlight.add(id)) continue;
      _fetchImageQueued(id);
    }
  }
/// Derivasikan `(items, deletedIds)` di-cache berbasis IDENTITAS list
  /// pesan sumber ([msgsSrc], dari stream — referensinya stabil antar rebuild
  /// parent) + jumlah `_pending` + locale + hari. [all] dipakai untuk hasil.
  (List<ChatItem>, Set<String>) _deriveItems(
    S s,
    List<MessageModel> msgsSrc,
    List<MessageModel> all, {
    required DateTime day,
  }) {
    final locale = s.isId ? 'id' : 'en';
    // A1: kunci cache = REVISI isi pesan (bukan `identical(msgsSrc)`).
    // Stream emit list BARU tiap event → `identical` selalu false → dulu
    // recompute O(N) tiap emit (makin banyak pesan = makin lag). Revisi naik
    // HANYA saat isi berubah → derive dilewati saat rebuild non-isi
    // (ngetik/status/reaksi).
    if (_cacheItemsRevision == _msgsRevision &&
        _cacheItemsPendingLen == _pending.length &&
        _cacheItemsLocale == locale &&
        _cacheItemsDay == day) {
      return (_cachedItems, _cachedDeletedIds);
    }
    final deletedIds = <String>{
      for (final m in all)
        if (m.isDeleted) m.id,
    };
    final items = <ChatItem>[];
    String? prevDateKey;
    // ALBUM: gabungkan foto berurutan dengan albumId sama (satu batch kirim)
    // jadi SATU bubble grid. Buffer kecil — album maks 10 foto.
    final albumBuf = <MessageModel>[];
    String? albumKey;

    void flushAlbum() {
      if (albumBuf.isEmpty) return;
      if (albumBuf.length == 1) {
        items.add(ChatItem.message(albumBuf.first));
      } else {
        items.add(ChatItem.album(List.of(albumBuf)));
      }
      albumBuf.clear();
      albumKey = null;
    }

    for (final m in all) {
      final local = m.timestamp.toLocal();
      final dateKey = '${local.year}-${local.month}-${local.day}';
      if (prevDateKey != dateKey) {
        // Album tidak boleh melintasi batas hari (chip tanggal di tengah).
        flushAlbum();
        items.add(ChatItem.date(dateChipLabel(m.timestamp, s)));
      }
      prevDateKey = dateKey;

      final aid = m.albumId;
      final isAlbumPhoto =
          aid != null && aid.isNotEmpty && m.type == 'image' && !m.isDeleted;
      if (isAlbumPhoto) {
        if (albumKey != null && albumKey != aid) flushAlbum();
        albumKey = aid;
        albumBuf.add(m);
        continue;
      }
      flushAlbum();
      items.add(ChatItem.message(m));
    }
    flushAlbum();
    _cacheItemsRevision = _msgsRevision;
    _cacheItemsPendingLen = _pending.length;
    _cacheItemsLocale = locale;
    _cacheItemsDay = day;
    _cachedItems = items;
    _cachedDeletedIds = deletedIds;
    return (items, deletedIds);
  }
  void _scheduleRebuild() {
    if (!mounted) return;
    // P1c (2026-10-11): KOALESENSI WINDOW ~80ms (dulu per-frame). Saat buka
    // chat ada gelombang ~6 sumber rebuild (reactions/starred/status/typing/
    // profil/chatInfo) tersebar di 220-500ms → dulu 1 setState PER FRAME
    // (rebuild penuh ListView+bubble). Sekarang di-kuantum 80ms: burst dalam
    // 1 window = 1 setState. Timer 220/280ms TETAP terpisah (tak digabung).
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    Timer(const Duration(milliseconds: 80), () {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }
bool get _showCallOverlay {
    final prov = ProviderScope.containerOf(context, listen: false).read(callProvider.notifier);
    final sess = prov.activeSession;
    return sess != null &&
        prov.activeMode == CallMode.chat &&
        sess.remoteUid == widget.otherUid &&
        !_callExpanded;
  }
void _subscribeTyping() {
    _typingSub?.cancel();
    dlog('[TYPING] screen subscribing for ${widget.chatId}');
    _typingSub = ProviderScope.containerOf(context, listen: false)
        .read(chatRiverpod.chatProvider.notifier)
        .getTypingPulseStream(widget.chatId)
        .listen((event) {
          final kind = event.$1;
          final ts = event.$2;
          // Pulse basi: dikirim SEBELUM/SESAAT SETELAH balasan terakhir
          // dibuat (race delivery: pulse terkirim duluan tapi tiba belakangan)
          // → abaikan. Toleransi +1 detik; typing asli berikutnya (burst /
          // balasan baru, ≥2 detik kemudian) tetap menyalakan bubble.
          final lastMsg = _lastPartnerMsgTime;
          if (lastMsg != null &&
              ts < lastMsg.millisecondsSinceEpoch + 1000) {
            dlog('[TYPING] skipped stale pulse');
            return;
          }
          dlog('[TYPING] stream got kind=$kind -> bubble on');
          if (!mounted) return;
          // Tidak setState: hanya notifier typing (rebuild terbatas).
          _typingState.value = kind == 'recording' ? 2 : 1;
          _typingClearTimer?.cancel();
          _typingClearTimer = Timer(const Duration(seconds: 3), () {
            if (!mounted) return;
            _typingState.value = 0;
          });
        }, onError: (e) {
          // OFFLINE: stream typing error → jangan tak tertangkap.
          dlog('[NAV] typing stream error private-chat: $e');
        });
  }
void _sendTypingSignal() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds < 2500) return;
    _lastTypingSent = now;
    ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier).sendTyping(widget.chatId);
  }
/// Misi "chat orang baru": bonus hanya diberikan saat user BENAR-BENAR
  /// mengirim pesan pertama ke lawan bicara (bukan pas membuka chat kosong).
  /// RPC new_chat_bonus tetap punya guard sendiri (sekali per user + limit
  /// harian), jadi aman dipanggil dari semua jalur kirim.
  void _maybeNewChatBonus() {
    if (_newChatBonusClaimed) return;
    _newChatBonusClaimed = true;
    ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).newChatBonus(widget.otherUid);
  }
/// Kandidat mention private 1:1 — hanya lawan bicara. `@all` tidak pernah.
  List<Mention> get _mentionCandidates => widget.otherUid.isEmpty
      ? const []
      : [Mention(uid: widget.otherUid, name: widget.otherName)];
@override
  String get outboxChatId => widget.chatId;
@override
  bool get outboxIsFlushing => _flushingOutbox;
@override
  Future<void> outboxSendEntry(OutboxEntry e, String imageData) async {
    // Kirim ulang video dari outbox: unggah poster juga (kalau disimpan) agar
    // penerima tetap dapat thumbnail — dulu upload video saja → kotak hitam.
    final scope = ProviderScope.containerOf(context, listen: false);
    var posterPath = '';
    if (e.videoPosterB64.isNotEmpty &&
        (e.type == 'video' || e.type == 'video_once' || e.type == 'video_once_expired')) {
      try {
        posterPath = await scope
                .read(storageProvider)
                .uploadChatVideoPoster(
                  chatId: photoUploadChatId,
                  bytes: base64Decode(e.videoPosterB64),
                ) ??
            '';
      } catch (_) {}
    }
    await scope.read(chatRiverpod.chatProvider.notifier).sendPrivateMessage(
      chatId: widget.chatId,
      senderId: e.senderId,
      senderName: e.senderName,
      senderGender: e.senderGender,
      text: e.text,
      type: e.type,
      imageData: imageData,
      durationMs: e.durationMs,
      repliedToId: e.repliedToId,
      repliedToText: e.repliedToText,
      repliedToSenderName: e.repliedToSenderName,
      repliedToMeta: e.repliedToMeta,
      isForwarded: e.isForwarded,
      mentions: e.mentions,
      videoPoster: posterPath,
    );
  }
@override
  void outboxOnSent() {
    _maybeNewChatBonus();
    _schedulePendingConfirmFallback();
  }
Future<void> _sendCoins(int amount) async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final chat = ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier);
    final points = ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await chat.sendCoins(widget.chatId, widget.otherUid, amount);
      if (res['ok'] == true) {
        if (res['points'] != null)
          points.setPoints((res['points'] as num).toInt());
        _maybeNewChatBonus();
        if (mounted) points.showPointsToast(context, s.coinSentToast(amount));
        _scrollToBottom();
      }
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('Not enough paid') || msg.contains('Not enough')
          ? s.errCoinInsufficient
          : msg.contains('registered')
          ? s.errCoinRegisterOnly
          : s.errSendCoin;
      showChatSnackVia(messenger, mounted ? context : messenger.context, show);
    }
  }
/// Mulai panggilan audio/video ke lawan bicara.
  /// [mode] menentukan fullscreen atau video dalam chat (overlay).
  Future<void> _startCall(
    BuildContext ctx,
    String callType,
    CallMode mode,
  ) async {
    final scope = ProviderScope.containerOf(context, listen: false);
    final s = scope.read(localeProvider).s;
    if (scope.read(callProvider.notifier).inCall) {
      showChatSnack(ctx, s.msgCallInProgress);
      return;
    }
    final messenger = ScaffoldMessenger.of(ctx);
    final auth = scope.read(authProvider.notifier);
    final profile = auth.profile;
    // Gate anon & dummy: hanya boleh call bila toggle admin
    // app_settings.call_anon_enabled ON (server RLS juga menegakkan).
    // User terdaftar (bukan sesi dummy) selalu boleh.
    final registeredCaller =
        (profile?.isRegistered ?? false) && !auth.dummySessionActive;
    if (!registeredCaller && !auth.callAnonEnabled) {
      final ls = scope.read(localeProvider).s;
      showAnonPromptDialog(
        context,
        title: ls.promptCompleteEmailCallTitle,
        message: ls.promptCompleteEmailCallMsg,
        icon: Icons.call_outlined,
      );
      return;
    }
    // Nelp pakai COIN (tanpa gratis). Bila saldo < tarif 1 menit → edukasi +
    // topup, batalkan. Hanya untuk penelepon (isCaller).
    {
      final pp = scope.read(pointsProvider.notifier);
      if (pp.enabled && pp.callBillingPublished) {
        final ok = await pp.ensureEnoughForCall(context, callType, s.isId);
        if (!ok) return;
      }
    }
    // Privasi panggilan penerima: bila menolak, jangan tembak DB sama sekali.
    // Server RLS tetap penjaga akhir (map error di bawah).
    final allowed = await scope
        .read(privacyServiceProvider)
        .canView(widget.otherUid, 'call');
    if (!mounted) return;
    if (!allowed) {
      showChatSnack(context, s.callNotAllowed);
      return;
    }
    // Izin kamera/mikrofon WAJIB sebelum getUserMedia — tanpa ini video call
    // pertama (izin belum ada) langsung gagal senyap (CallPhase.error).
    final perm = await ensureCallPermissions(video: callType == 'video');
    if (perm != CallPermissionResult.granted) {
      if (!mounted) return;
      showCallPermissionDialog(
        context,
        video: callType == 'video',
        permanentlyDenied: perm == CallPermissionResult.permanentlyDenied,
      );
      return;
    }
    try {
      final callId = await scope.read(callProvider.notifier).startCall(
        widget.otherUid,
        callType,
      );
      if (!mounted) return;
      final session = await scope.read(callProvider.notifier).startSession(
        callId: callId,
        remoteUid: widget.otherUid,
        remoteName: widget.otherName,
        callType: callType,
        isCaller: true,
        mode: mode,
        myName: profile?.nickname ?? '',
        myGender: profile?.gender ?? 'other',
        notifBody: callType == 'video'
            ? s.callNotifActiveVideo
            : s.callNotifActiveAudio,
        notifChannel: s.callNotifActiveAudio,
        notifDesc: s.callNotifActiveAudio,
        chatId: widget.chatId,
      );
      // Tarif per menit untuk banner (server kirim ulang tiap tick).
      // Koin OFF (toggle admin) atau billing belum publish → 0 = banner sembunyi.
      final pp0 = scope.read(pointsProvider.notifier);
      session.setBillingPerMinute(
        (pp0.enabled && pp0.callBillingPublished)
            ? pp0.callCostPerMin(callType)
            : 0,
      );
      if (!mounted || !ctx.mounted) return;
      if (mode == CallMode.fullscreen) {
        Navigator.of(ctx).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            settings: const RouteSettings(name: kCallScreenRoute),
            builder: (_) => CallScreen(
              callId: callId,
              remoteUid: widget.otherUid,
              remoteName: widget.otherName,
              callType: callType,
              isCaller: true,
              session: session,
            ),
          ),
        );
      }
      // Mode chat: overlay muncul otomatis dari provider.activeSession.
    } catch (e) {
      // Jangan telan error mentah-mentah: tulis ke logcat (dlog di-strip di
      // release) + petakan ke pesan yang menjelaskan penyebab (RLS/jaringan).
      dlog('[CALL-START] _startCall gagal ($callType): $e');
      final low = e.toString().toLowerCase();
      final denied = low.contains('policy') ||
          low.contains('permission denied') ||
          low.contains('unauthorized') ||
          low.contains('401') ||
          low.contains('403') ||
          low.contains('jwt');
      final offline = low.contains('socketexception') ||
          low.contains('failed host lookup') ||
          low.contains('network is unreachable') ||
          low.contains('connection refused') ||
          low.contains('timeout');
      showChatSnackVia(
        messenger,
        ctx.mounted ? ctx : messenger.context,
        denied
            ? s.msgCallRegisterOnly
            : offline
                ? s.errCallNetwork
                : s.errGeneric,
      );
    }
  }
}
