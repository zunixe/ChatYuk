part of '../private_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _PcMediaMx on _PrivateChatBase {
void _openSearch() {
    setState(() {
      _searching = true;
      _searchCtrl.clear();
      _searchQuery = '';
      _matchIds = const [];
      _matchSet = const {};
      _matchIndex = 0;
    });
    _searchFocus.requestFocus();
  }
void _closeSearch() {
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _searchQuery = '';
      _matchIds = const [];
      _matchSet = const {};
      _matchIndex = 0;
      _searchKeys.clear();
    });
  }
/// Scroll ke cocok aktif. dir=0: hanya bila sudah ter-render (lembut,
  /// untuk saat mengetik). dir!=0: lompat bertahap ke arahnya lalu coba
  /// lagi (maks 5x) sampai ketemu.
  void _scrollToMatch(int dir) {
    if (!mounted || !_searching || _matchIds.isEmpty) return;
    if (_matchIndex < 0 || _matchIndex >= _matchIds.length) return;
    final id = _matchIds[_matchIndex];
    final ctx = _searchKeys[id]?.currentContext;
    if (ctx != null) {
      _searchJumpTries = 0;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.45,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    if (dir == 0 || _searchJumpTries >= 5 || !_scrollCtrl.hasClients) return;
    _searchJumpTries++;
    final pos = _scrollCtrl.position;
    // List reverse: offset 0 = paling baru (bawah). Hasil index naik =
    // makin lama = offset makin besar.
    final target = (pos.pixels + dir * pos.viewportDimension * 0.8)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _scrollCtrl.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToMatch(dir));
  }
  // ── Kontrak ChatSelectionMixin ──
  @override
  String get chatKind => 'private';
@override
  AuthNotifier get chatAuth => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
  // ── YukCoin v2 (berbayar) ──
  @override
  bool get chatYukcoinV2Active => ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).yukcoinV2Active;
@override
  Future<bool> chatChargeYukcoin(String feature, int cost, String ref) async {
    try {
      await ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).spendYukcoin(feature, cost, ref: ref);
      return true;
    } catch (e) {
      dlog('[PRIVATE] chargeYukcoin error: $e');
      return false;
    }
  }
@override
  Map<String, String> get chatReactionKnownNames =>
      {widget.otherUid: widget.otherName};
  // ── Kontrak ChatPhotoSendMixin ──
  @override
  Future<String?> photoDispatch({
    required String imageData,
    required String type,
    required String senderId,
    required String senderName,
    required String senderGender,
    String text = '',
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    int? viewOnceSecs,
    int? videoDurationMs,
  }) async {
    return ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier).sendPrivateMessage(
      chatId: widget.chatId,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      text: text,
      type: type,
      imageData: imageData,
      // Video pakai durasi asli (bukan timer view-once).
      durationMs: videoDurationMs ?? viewOnceSecs,
      repliedToId: repliedToId,
      repliedToText: repliedToText,
      repliedToSenderName: repliedToSenderName,
    );
  }
/// Izinkan → ambil posisi → sheet pilihan (lokasi saat ini / live / tempat
  /// sekitar) → LANGSUNG terkirim ke chat (tanpa preview/caption).
  Future<void> _sendLocation() async {
    setState(() => _showAttachRow = false);
    final picked = await pickChatLocation(
      context,
      messenger: ScaffoldMessenger.of(context),
    );
    if (picked == null || !mounted) return;
    await sendLocationFromPreviewAt(picked);
  }
@override
  ChatLocation? get sendPendingLocation => _pendingLocation;
@override
  int? get photoViewTimerSecs => _viewTimerSecs;
@override
  void photoClearViewTimer() {
    _viewTimerSecs = null;
    if (mounted) setState(() => _pendingPhotoBase64 = null);
  }
@override
  MessageModel? get photoReplyingTo => sendReplyingTo;
@override
  String get photoSeed => widget.otherUid;
@override
  void videoClearPreview() {
    if (!mounted) return;
    setState(() {
      _pendingVideoPath = null;
      _pendingVideoPoster = null;
      _pendingVideoMs = 0;
      _pendingVideoOnce = false;
    });
  }
@override
  bool get sendIsSending => _isSending;
@override
  set sendEditingMessage(MessageModel? v) => editingMessage = v;
@override
  Future<void> sendDispatchText({
    required String text,
    required MessageModel? reply,
    required List<Mention> mentions,
  }) async {
    await ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier).sendPrivateMessage(
      chatId: widget.chatId,
      senderId: ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).uid!,
      senderName: ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).profile!.nickname,
      senderGender: ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).profile!.gender,
      text: text,
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
      mentions: mentions,
    );
  }
/// Prime bintang secara SINKRON: ambil id pesan berbintang dari MEMORI
  /// (tanpa await) sebelum frame pertama — jadi bintang langsung tampil saat
  /// chat dibuka, tidak menunggu satu hop async apa pun (anti-glich).
  /// Stream realtime + fallback `_loadCachedStarredAsync` menimpa sesudahnya.
  void _primeStarredFromCache() {
    try {
      final cached = ProviderScope.containerOf(context, listen: false)
          .read(messageReactionProvider)
          .peekCachedStarred(widget.chatId);
      if (cached.isNotEmpty) starredIds = cached;
    } catch (_) {}
  }
/// Baca last-read tersimpan (kv terenkripsi) — dipanggil di initState agar
  /// centang-2 tampil instan. Hanya mengisi bila lebih baru dari state
  /// (read receipt monoton maju — tidak pernah mundur).
  Future<void> _loadCachedRead() async {
    try {
      final obj = await MessageCache.instance
          .loadRawObj('read:${widget.chatId}');
      final t = ReadReceipt.parse(obj[widget.otherUid]);
      final merged = ReadReceipt.merge(_otherLastRead, t);
      if (t != null && mounted && merged != _otherLastRead) {
        setState(() => _otherLastRead = merged);
      }
    } catch (_) {}
  }
/// Simpan last-read network (fire-and-forget) untuk cold start berikutnya.
  void _persistRead(DateTime t) {
    try {
      MessageCache.instance.saveRawObj('read:${widget.chatId}', {
        widget.otherUid: t.toIso8601String(),
      });
    } catch (_) {}
  }
@override
  void dispose() {
    hideActionBar();
    _reactionsSub?.cancel();
    _starredSub?.cancel();
    ChatTextScale.notifier.removeListener(_onFontScaleChanged);
    _pendingConfirmTimer?.cancel();
    // conn listener dikelola Riverpod (ref.listen) — tak perlu close manual.
    // (ref.listen otomatis berhenti saat widget dispose).
    // Keluar chat TIDAK memutus panggilan — call lanjut berjalan dan notifikasi
    // ongoing "sedang call" tetap tampil. Tap notifikasi → kembali ke chat ini.
    _chatInfoSub?.cancel();
    _msgsSub?.cancel();
    _statusSub?.cancel();
    _typingSub?.cancel();
    _typingClearTimer?.cancel();
    _typingState.dispose();
    _openWorkTimer?.cancel();
    _channelWorkTimer?.cancel();
    _liveTimer?.cancel();
    _imgQueue.clear();
    _imgQueued.clear();
    // Voice recording: hentikan timer + native recorder — tanpa ini keluar
    // screen saat rekam = timer jalan terus + setState after dispose + leak.
    // DEFER: dispose saat tree terkunci (unmount IndexedStack) — penulisan
    // notifier memicu markNeedsBuild pada CallBanner → glitch.
    final chatToClear = widget.chatId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (activeChatId.value == chatToClear) activeChatId.value = null;
    });
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _msgsStreamCtrl.close();
    super.dispose();
  }
/// Matikan bubble typing/recording segera (tanpa menunggu timer 3 detik).
  /// Dipanggil saat pesan baru dari lawan bicara masuk — pesan = bukti
  /// otoritatif bahwa fase mengetik selesai (anti bubble nyangkut).
  void _hideTyping() {
    _typingClearTimer?.cancel();
    if (!mounted) return;
    if (_typingState.value != 0) _typingState.value = 0;
  }
/// Jaring pengaman konfirmasi pending: kalau 3 detik setelah insert sukses
  /// bubble masih belum terkonfirmasi (event Realtime miss / channel drop),
  /// fetch ulang pesan dari server supaya tidak nyangkut sampai polling 30s.
  void _schedulePendingConfirmFallback() {
    _pendingConfirmTimer?.cancel();
    _pendingConfirmTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || _pending.isEmpty) return;
      try {
        await _msgsHandleReload();
      } catch (_) {}
    });
  }
@override
  String get outboxUploadChatId => widget.chatId;
@override
  void outboxScrollToBottom() => _scrollToBottom();
Future<void> voiceFinishRecording(String path, int recordedMs) async {
    final f = File(path);
    final bytes = await f.readAsBytes();
    final chatId = widget.chatId;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final uid = auth.uid; final profile = auth.profile;
    if (uid == null || profile == null) return;
    // Offline: bubble tetap tampil (centang-1) + antre, terkirim otomatis
    // saat koneksi pulih. Voice tidak pakai poin (pointsKind 'none').
    if (!outboxIsOnline) {
      final optimisticOffline = MessageModel(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        isRegistered: profile.isRegistered,
        text: '',
        type: 'voice',
        imageData: base64Encode(bytes),
        timestamp: DateTime.now(),
        durationMs: recordedMs,
      );
      setState(() => _pending.add(optimisticOffline));
      _scrollToBottom();
      try { await f.delete(); } catch (_) {}
      await queueOffline(
        pending: optimisticOffline,
        pointsKind: 'none',
        pointsDeducted: true,
        imagePayload: base64Encode(bytes),
        needsUpload: true,
        uploadKind: 'voice',
        durationMs: recordedMs,
      );
      return;
    }
    final storagePath = await ProviderScope.containerOf(context, listen: false).read(storageProvider).uploadVoice(chatId: chatId, bytes: bytes);
    if (storagePath == null || storagePath.isEmpty) {
      if (!outboxIsOnline) {
        final optimisticOffline = MessageModel(
          id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
          senderId: uid,
          senderName: profile.nickname,
          senderGender: profile.gender,
          isRegistered: profile.isRegistered,
          text: '',
          type: 'voice',
          imageData: base64Encode(bytes),
          timestamp: DateTime.now(),
          durationMs: recordedMs,
        );
        setState(() => _pending.add(optimisticOffline));
        _scrollToBottom();
        try { await f.delete(); } catch (_) {}
        await queueOffline(
          pending: optimisticOffline,
          pointsKind: 'none',
          pointsDeducted: true,
          imagePayload: base64Encode(bytes),
          needsUpload: true,
          uploadKind: 'voice',
          durationMs: recordedMs,
        );
        return;
      }
      if (mounted) showChatSnack(context, ProviderScope.containerOf(context, listen: false).read(localeProvider).s.errVoiceUploadFailed);
      return;
    }
    // Optimistic: tampilkan bubble voice langsung
    final optimistic = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: '',
      type: 'voice',
      imageData: storagePath,
      timestamp: DateTime.now(),
      durationMs: recordedMs,
    );
    setState(() => _pending.add(optimistic));
    _scrollToBottom();
    try {
      await ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier).sendPrivateMessage(chatId: chatId, senderId: uid, senderName: profile.nickname, senderGender: profile.gender, text: '', type: 'voice', imageData: storagePath, durationMs: recordedMs);
      try { await f.delete(); } catch (_) {}
    } catch (e) {
      dlog('[Voice] send error: $e');
      if (OfflineOutbox.isNetworkError(e) || !outboxIsOnline) {
        await queueOffline(
          pending: optimistic,
          pointsKind: 'none',
          pointsDeducted: true,
          imagePayload: storagePath,
          durationMs: recordedMs,
        );
      } else if (mounted) {
        setState(() => _pending.remove(optimistic));
        showChatSnack(context, ProviderScope.containerOf(context, listen: false).read(localeProvider).s.errSendFailed);
      }
    }
  }
Future<void> _sendGift(String giftId, String name, int coins) async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final chat = ProviderScope.containerOf(context, listen: false).read(chatRiverpod.chatProvider.notifier);
    final points = ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await chat.sendGift(widget.chatId, widget.otherUid, giftId);
      if (res['ok'] == true) {
        if (res['points'] != null)
          points.setPoints((res['points'] as num).toInt());
        _maybeNewChatBonus();
        if (mounted) points.showPointsToast(context, s.giftSentToast(name));
        _scrollToBottom();
      }
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('Not enough')
          ? s.giftInsufficient
          : msg.contains('registered')
          ? s.errCoinRegisterOnly
          : s.errSendCoin;
      showChatSnackVia(messenger, context, show);
    }
  }
/// AppBar mode search (ala WhatsApp): tombol kembali + field cari +
  /// penghitung hasil + panah atas/bawah.
  AppBar _buildSearchAppBar() {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final total = _matchIds.length;
    final label = total == 0 ? '0/0' : '${_matchIndex + 1}/$total';
    return AppBar(
      toolbarHeight: 56.0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        tooltip: s.btnCancel,
        onPressed: _closeSearch,
      ),
      title: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        autofocus: true,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: AppText.body.copyWith(color: Colors.white),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          isDense: true,
          hintText: s.chatSearchHint,
          hintStyle: AppText.body.copyWith(color: Colors.white70),
          border: InputBorder.none,
        ),
      ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_searchQuery.trim().isNotEmpty)
              Text(
                label,
                style: AppText.label.copyWith(color: Colors.white),
              ),
            SearchNavButton(
              icon: Icons.keyboard_arrow_up,
              enabled: total > 0,
              onTap: () => _gotoMatch(-1),
            ),
            SearchNavButton(
              icon: Icons.keyboard_arrow_down,
              enabled: total > 0,
              onTap: () => _gotoMatch(1),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ],
    );
  }
void _showReportDialog() {
    showReportUserDialog(
      context,
      reportedId: widget.otherUid,
      reportedName: widget.otherName,
    );
  }
}
