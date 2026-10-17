part of '../room_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _RcLiveMx on _RoomChatBase {
  void _scrollToBottom() {
    // Instan (acuan private): dulu room animateTo 250ms — scroll panjang
    // saat buka chat terasa "meluncur". Sama seperti private = jumpTo(0).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  bool get _isNearBottom {
    if (!_scrollCtrl.hasClients) return true;
    return _scrollCtrl.position.pixels < 100;
  }


  // ── Antrean offline: implementasi BERSAMA di ChatOutboxMixin ──
  bool get outboxIsOnline => _connOnline;

  @override
  String get outboxKind => 'room';

  @override
  String get outboxChatId => widget.room.id;

  @override
  String get outboxUploadChatId => 'room_${widget.room.id}';

  @override
  List<MessageModel> get outboxPending => _pending;

  @override
  Set<String> get outboxQueuedIds => _queuedIds;

  @override
  bool get outboxIsFlushing => _flushingOutbox;

  @override
  set outboxIsFlushing(bool v) => _flushingOutbox = v;

  @override
  void outboxScrollToBottom() => _scrollToBottom();

  @override
  Future<void> outboxSendEntry(OutboxEntry e, String imageData) async {
    await _chat.sendRoomMessage(
      roomId: widget.room.id,
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
      isForwarded: e.isForwarded,
      mentions: e.mentions,
    );
  }

  @override
  void outboxOnSent() {
    // Bonus "first room chat" DIHAPUS (overhaul coin: tidak ada poin gratis).
  }

  /// Izinkan → ambil posisi → sheet pilihan → konfirmasi (room) → LANGSUNG
  /// terkirim ke chat (tanpa preview/caption).
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
  set sendPendingLocation(ChatLocation? v) => _pendingLocation = v;

  @override
  Future<void> sendLocationFromPreviewAt(
    ChatLocation loc, {
    String text = '',
    MessageModel? reply,
  }) async {
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    // Konfirmasi: lokasi akan terlihat semua anggota room.
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(s.locSendRoomTitle),
        content: Text(s.locSendRoomConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(s.locSendCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(s.locSendConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Caption ikut terkirim di dalam payload (bukan pesan terpisah);
    // place/live/expiresAt dibawa apa adanya (lokasi & lokasi live).
    final payload = ChatLocation(
      lat: loc.lat,
      lng: loc.lng,
      label: loc.label,
      caption: text.trim(),
      place: loc.place,
      live: loc.live,
      expiresAt: loc.expiresAt,
      accuracyM: loc.accuracyM,
    );
    String? sentId;
    try {
      sentId = await ProviderScope.containerOf(context, listen: false)
          .read(chatRiverpod.chatProvider.notifier)
          .sendRoomMessage(
            roomId: widget.room.id,
            senderId: uid,
            senderName: profile.nickname,
            senderGender: profile.gender,
            text: payload.encode(),
            type: 'location',
            repliedToId: reply?.id,
            repliedToText: reply?.text,
            repliedToSenderName: reply?.senderName,
          );
    } catch (_) {
      if (!mounted) return;
      showChatSnack(context, s.errSendFailed);
      return;
    }
    if (mounted) {
      setState(() => _pendingLocation = null);
      _scrollToBottom();
    }
    // Lokasi LIVE → mulai kirim pembaruan posisi berkala sampai kedaluwarsa.
    if (payload.live && sentId != null && payload.expiresAt != null) {
      _startLiveLocationUpdates(sentId, payload);
    }
  }


  /// Kirim pembaruan koordinat lokasi live (room) tiap 30 detik.
  void _startLiveLocationUpdates(String messageId, ChatLocation initial) {
    _liveTimer?.cancel();
    final lp = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(locationProvider);
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (t) async {
      final exp = initial.expiresAt;
      if (exp == null || DateTime.now().toUtc().isAfter(exp)) {
        t.cancel();
        return;
      }
      // P1b: jangan GPS + update DB saat background/layar mati.
      if (!AppForeground.now) return;
      final pos = await lp.precisePosition();
      if (pos == null || !mounted) return;
      final updated = initial.copyWith(lat: pos.$1, lng: pos.$2);
      await ProviderScope.containerOf(context, listen: false)
          .read(chatRiverpod.chatProvider.notifier)
          .updateRoomLocationMessage(messageId, updated.encode());
    });
  }

  /// Kirim STIKER di room: upload PNG → pesan type 'sticker'.
  Future<void> _sendSticker(Uint8List pngBytes) async {
    if (pngBytes.isEmpty) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final b64 = base64Encode(pngBytes);
    try {
      final path = await container
          .read(storageProvider)
          .uploadSticker(uid: uid, base64: b64, ext: 'png');
      if (path == null || path.isEmpty || !mounted) return;
      // Titip bytes ke cache bubble (lihat private).
      try {
        StickerBubble.seedCache(path, pngBytes);
      } catch (_) {}
      await container.read(chatRiverpod.chatProvider.notifier).sendRoomMessage(
            roomId: widget.room.id,
            senderId: uid,
            senderName: profile.nickname,
            senderGender: profile.gender,
            text: '',
            type: 'sticker',
            imageData: path,
          );
      if (mounted) _scrollToBottom();
    } catch (e) {
      dlog('[Sticker] room kirim gagal: $e');
      if (mounted) {
        showChatSnack(context, container.read(localeProvider).s.stickerSendFail);
      }
    }
  }

  /// Kirim STIKER KOLEKSI di room (path server) — tanpa upload ulang.
  Future<void> _sendStickerPath(String path) async {
    if (path.isEmpty) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    try {
      final bytes =
          await container.read(storageProvider).downloadBytes(path);
      if (bytes != null && bytes.isNotEmpty) {
        try {
          StickerBubble.seedCache(path, bytes);
        } catch (_) {}
      }
      await container.read(chatRiverpod.chatProvider.notifier).sendRoomMessage(
            roomId: widget.room.id,
            senderId: uid,
            senderName: profile.nickname,
            senderGender: profile.gender,
            text: '',
            type: 'sticker',
            imageData: path,
          );
      if (mounted) _scrollToBottom();
    } catch (e) {
      dlog('[Sticker] room kirim path gagal: $e');
      if (mounted) {
        showChatSnack(context, container.read(localeProvider).s.stickerSendFail);
      }
    }
  }

  Future<void> _sendVoiceMessage(String filePath, int durationMs) async {
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final chat = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatRiverpod.chatProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    // Offline: bubble tetap tampil (centang-1) + antre, terkirim otomatis
    // saat koneksi pulih. Voice tidak pakai poin.
    Future<void> queueVoiceOffline(Uint8List bytes, File f) async {
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
        durationMs: durationMs,
      );
      setState(() => _pending.add(optimisticOffline));
      _scrollToBottom();
      try {
        await f.delete();
      } catch (_) {}
      await queueOffline(
        pending: optimisticOffline,
        pointsKind: 'none',
        pointsDeducted: true,
        imagePayload: base64Encode(bytes),
        needsUpload: true,
        uploadKind: 'voice',
        durationMs: durationMs,
      );
    }

    try {
      final f = File(filePath);
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      if (!outboxIsOnline) {
        await queueVoiceOffline(bytes, f);
        return;
      }
      final storagePath =
          await ProviderScope.containerOf(context, listen: false)
              .read(storageProvider)
              .uploadVoice(chatId: 'room_${widget.room.id}', bytes: bytes);
      if (storagePath == null || storagePath.isEmpty) {
        if (!outboxIsOnline) {
          await queueVoiceOffline(bytes, f);
          return;
        }
        if (mounted) {
          showChatSnack(
            context,
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(localeProvider).s.errVoiceUploadFailed,
          );
        }
        return;
      }
      final pendingVoice = MessageModel(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        isRegistered: profile.isRegistered,
        text: '',
        type: 'voice',
        imageData: storagePath,
        timestamp: DateTime.now(),
        durationMs: durationMs,
      );
      setState(() => _pending.add(pendingVoice));
      _scrollToBottom();
      await chat.sendRoomMessage(
        roomId: widget.room.id,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'voice',
        imageData: storagePath,
        durationMs: durationMs,
      );
      try {
        await f.delete();
      } catch (_) {}
      _scrollToBottom();
    } catch (e) {
      dlog('[RoomVoice] send error: $e');
      if (OfflineOutbox.isNetworkError(e) || !outboxIsOnline) {
        try {
          final f = File(filePath);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            await queueVoiceOffline(bytes, f);
            return;
          }
        } catch (_) {}
      }
      if (mounted) {
        showChatSnack(
          context,
          ProviderScope.containerOf(
            context,
            listen: false,
          ).read(localeProvider).s.errSendFailed,
        );
      }
    }
  }

  // LayerLink per pesan — anchor action bar (Balas / Hapus) tepat di atas bubble.


  void _toggleAttachRow() {
    if (!_showAttachRow) FocusScope.of(context).unfocus();
    setState(() => _showAttachRow = !_showAttachRow);
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('RoomChat');
    ref.watch(themeProvider);
    // Koneksi pulih → flush outbox. `ref.listen` WAJIB di build (bukan
    // initState) — Riverpod mengelolanya (aman saat dispose).
    ref.listen<bool>(connectivityProvider, (prev, next) {
      _connOnline = next;
      if (mounted && next) flushOutbox();
    });
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final s = ref.watch(localeProvider).s;
    // select (bukan watch penuh): perubahan saldo/poin tidak perlu
    // me-rebuild seluruh layar room — hanya flag enabled yang dipakai.
    final points = ref.watch(pointsProvider.select((p) => p.enabled));

    return PopScope(
      // `_backEscape` = katup sekali-pakai anti "back mati permanen".
      canPop: !inSelection || _backEscape,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          NavJournal.log('back room-chat didPop (tutup layar)');
          _backGuard.reset();
          return;
        }
        // Veto BASI (seleksi sudah bersih konkuren) → NO-OP. Escape hanya
        // bila basi yang SAMA berulang (macet beneran).
        if (!inSelection) {
          if (_backGuard.shouldEscape('rc:clean')) {
            debugPrint('[NAV] back escape room-chat (macet, paksa pop)');
            NavJournal.log('back room-chat ESCAPE macet (paksa pop)');
            _backEscape = true;
            BackVetoGuard.safePop(context);
          } else {
            NavJournal.log('back room-chat veto basi, abaikan');
          }
          return;
        }
        _backGuard.reset();
        debugPrint('[NAV] back veto room-chat selection=${selectedIds.length}');
        NavJournal.log('back room-chat veto selection=${selectedIds.length}');
        try {
          if (inSelection) clearSelection();
        } catch (e) {
          // Handler melempar + route masih ada & tertahan → escape sekali.
          debugPrint('[NAV] back handler error room-chat: $e');
          if (!mounted) return;
          NavJournal.log('back room-chat ESCAPE error (paksa pop)');
          _backEscape = true;
          BackVetoGuard.safePop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgCard,
        appBar: inSelection
            ? buildSelectionAppBar()
            : _buildRoomAppBar(context, s),
        body: _buildRoomBody(context, s, auth, points),
      ),
    );
  }

  Widget _buildRoomBody(
    BuildContext context,
    S s,
    AuthNotifier auth,
    bool points,
  ) {
    final showStageInline =
        isPrivateRoom &&
        !_stageMinimized &&
        _liveUid != null &&
        _broadcastSession != null;
    final showPip =
        isPrivateRoom &&
        _stageMinimized &&
        _liveUid != null &&
        _broadcastSession != null;
    // Bottom bar 3-state (private room): sebelum role selesai dicek,
    // tampilkan composer yang SAMA tapi non-interaktif — layout stabil
    // sejak frame pertama, tidak ada fase aktif-palsu lalu hilang.
    // SafeArea bawah: composer tidak kepotong nav bar Android.
    final Widget bottomBar;
    if (isPrivateRoom && _roleChecked && _myRole == null) {
      // Pending approval: composer diganti bar info — jangan biarkan user
      // mencoba kirim lalu gagal diam-diam.
      bottomBar = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        color: AppTheme.bgCard,
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.privateRoomNeedApproval,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      final input = ChatComposerInput(
        controller: _msgCtrl,
        onSend: sendMessage,
        showAttachRow: _showAttachRow,
        onToggleAttach: _toggleAttachRow,
        onSendFile: () {
          setState(() => _showAttachRow = false);
          pickAndSendFile();
        },
        onPickGalleryPhoto: (bytes) {
          setState(() => _showAttachRow = false);
          photoFromFileToPreview(bytes);
        },
        onTakePhoto: () {
          setState(() => _showAttachRow = false);
          photoTakeToPreview();
        },
        onSendPhoto: () {
          setState(() => _showAttachRow = false);
          photoPickFromGalleryToPreview();
        },
        onSendViewOnce: () {
          setState(() => _showAttachRow = false);
          sendViewOnceFromPicker();
        },
        onSendVoice: _sendVoiceMessage,
        onSendSticker: _sendSticker,
        onSendStickerPath: _sendStickerPath,
        // Gift (fitur koin) hanya bila sistem koin aktif — hilang
        // total saat dimatikan admin (ikut flag points.enabled).
        onOpenGiftPanel: points && isPrivateRoom && _myRole != 'owner'
            ? _openRoomGiftPanel
            : null,
        onSendLocation: _sendLocation,
        pendingLocation: _pendingLocation,
        onCancelLocation: _pendingLocation != null
            ? () => setState(() => _pendingLocation = null)
            : null,
        pendingPhotoBase64: _pendingPhotoBase64,
        onCancelPhoto: _pendingPhotoBase64 != null
            ? () => setState(() {
                _pendingPhotoBase64 = null;
                photoClearPreviewState();
              })
            : null,
        photoHd: photoHd,
        onHdChanged: _pendingPhotoBase64 != null
            ? (v) => setState(() => photoHd = v)
            : null,
        mentionCandidates: _mentionCandidates,
        mentionAllowAll: isPrivateRoom && canModerate,
        mentionAllExpansion: _mentionAllExpansion(),
        // Room/grup: scaffold = bgCard (putih) → pill wajib bgInput agar
        // kontras. Private chat tidak mengirim ini (tetap bgCard di atas
        // background foto).
        inputFillColor: AppTheme.bgInput,
      );
      bottomBar = input;
    }
    final column = Column(
      children: [
        // Banner "menunggu persetujuan" kini mengambang di atas list pesan
        // (overlay) — tidak menggeser layout saat muncul.
        if (isPrivateRoom &&
            isGrantedBroadcast &&
            (!iAmBroadcasting || _broadcastStarting))
          GestureDetector(
            onTap: _broadcastStarting ? null : _onStartBroadcastTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: AppTheme.primary.withValues(alpha: 0.12),
              child: Row(
                children: [
                  if (_broadcastStarting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.videocam_rounded,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _broadcastStarting
                          ? s.roomBroadcastConnecting
                          : s.privateRoomsStartBroadcast,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        if (showStageInline) ...[
          BroadcastStage(
            session: _broadcastSession!,
            isBroadcaster: iAmBroadcasting,
            onMinimize: () => setState(() => _stageMinimized = true),
          ),
        ],
        // Strip speaker voice (global room): tampil bila ikut voice.
        // Tap avatar SENDIRI → sheet diagnostik (debug suara).
        if (!isPrivateRoom && _voiceSession != null)
          VoiceStageStrip(
            session: _voiceSession!,
            usersByUid: {for (final u in _lastRoomUsers) u.uid: u},
            myUid: _auth.uid,
            onSpeakerTap: (uid) =>
                uid == _auth.uid ? _showVoiceDiagnostics() : _onSpeakerTap(uid),
          ),
        // User list horizontal — private room selalu tampil, global room via toggle.
        // Anti-dobel avatar: yang sudah tampil di strip voice (atas) tidak
        // diulang di list (bawah). Gate sinkron dari cache (builder di dalam
        // memfilter ulang dengan data stream segar).
        if (isPrivateRoom || (_showUsers && !_voiceStripCoversUsers))
          Container(
            height: 90,
            color: AppTheme.bgCard,
            child: StreamBuilder<List<UserModel>>(
              stream: _usersStream,
              builder: (_, snap) {
                // Persisten anti-glitch: stream presence bisa blip kosong
                // sesaat (realtime/heartbeat race). Tahan list terakhir;
                // kosong hanya diakui setelah 4 detik konsisten.
                final data = snap.data;
                if (data != null && data.isNotEmpty) {
                  _lastRoomUsers = data;
                  _roomUsersEmpty = false;
                  _roomUsersEmptyTimer?.cancel();
                } else if (data != null &&
                    data.isEmpty &&
                    _lastRoomUsers.isNotEmpty &&
                    !_roomUsersEmpty) {
                  _roomUsersEmptyTimer?.cancel();
                  _roomUsersEmptyTimer = Timer(const Duration(seconds: 4), () {
                    if (mounted) {
                      setState(() => _roomUsersEmpty = true);
                    }
                  });
                }
                final cached = _roomUsersEmpty
                    ? const <UserModel>[]
                    : _lastRoomUsers;
                // "Kamu" optimistis: presence sendiri (joinRoom upsert)
                // butuh roundtrip network → chip sendiri telat muncul
                // dan menggeser strip. Sisipkan langsung dari profil.
                final users = [...cached];
                final myUid = auth.uid;
                final me = auth.profile;
                if (myUid != null &&
                    me != null &&
                    !users.any((u) => u.uid == myUid)) {
                  final now = DateTime.now();
                  users.insert(
                    0,
                    UserModel(
                      uid: myUid,
                      nickname: me.nickname,
                      gender: me.gender,
                      age: me.age,
                      country: me.country,
                      city: me.city,
                      ipAddress: '',
                      status: 'online',
                      avatar: me.avatar,
                      isRegistered: me.isRegistered,
                      loginAt: now,
                      createdAt: now,
                      lastSeen: now,
                    ),
                  );
                }
                // Saring yang sudah ada di strip voice (anti-dobel avatar).
                final stripGone = _stripUids;
                final visible = stripGone.isEmpty
                    ? users
                    : users.where((u) => !stripGone.contains(u.uid)).toList();
                if (visible.isEmpty) {
                  // Semua sudah di strip → tak ada sisa untuk list bawah.
                  if (users.isNotEmpty) {
                    return const SizedBox.shrink();
                  }
                  // Belum pernah load → placeholder bulat (tinggi sama,
                  // tanpa teks kedip). Sudah load & kosong → teks info.
                  if (data == null) {
                    return ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: 4,
                      itemBuilder: (_, __) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppTheme.primary.withValues(
                                alpha: 0.10,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 36,
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: Text(
                      s.noOnlineUsers,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, i) => RoomUserChip(
                    key: ValueKey(visible[i].uid),
                    user: visible[i],
                    myUid: auth.uid,
                    color: Color(
                      userColorPalette[colorHashForUid(visible[i].uid) %
                          userColorPalette.length],
                    ),
                  ),
                );
              },
            ),
          ),

        _buildMessageList(s, auth),

        if (_queuedIds.isNotEmpty)
          Container(
            color: AppTheme.bgCard,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.msgQueuedCount(_queuedIds.length),
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (replyingTo != null)
          ReplyComposerPreview(
            message: replyingTo!,
            senderLabel: replyingTo!.senderId == auth.uid
                ? s.labelYou
                : replyingTo!.senderName,
            s: s,
            onCancel: cancelReply,
          ),
        if (editingMessage != null)
          Container(
            color: AppTheme.bgCard,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.edit, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.editingMessage,
                    style: AppText.chatBodySmall.copyWith(
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: cancelEdit,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        // Bottom bar 3-state didefinisikan di atas (bottomBar) —
        // SafeArea bawah agar tidak kepotong nav bar Android.
        SafeArea(top: false, child: bottomBar),
      ],
    );
    // Overlay gift fly + kombo — di atas semua konten (IgnorePointer,
    // tidak mengganggu gesture chat/stage).
    final giftOverlay = GiftFlyOverlay(controller: _giftFly);
    if (!showPip) {
      return Stack(
        children: [
          column,
          Positioned.fill(child: giftOverlay),
        ],
      );
    }
    return Stack(
      children: [
        column,
        Positioned.fill(child: giftOverlay),
        Builder(
          builder: (context) {
            final mq = MediaQuery.of(context);
            final minW = 100.0, maxW = mq.size.width * 0.8;
            final minH = 130.0, maxH = mq.size.height * 0.6;
            _pipSize = Size(
              _pipSize.width.clamp(minW, maxW),
              _pipSize.height.clamp(minH, maxH),
            );
            final w = _pipSize.width;
            final h = _pipSize.height;
            _pipPos ??= Offset(mq.size.width - w - 12, 24);
            final pos = Offset(
              _pipPos!.dx.clamp(8.0, mq.size.width - w - 8),
              _pipPos!.dy.clamp(8.0, mq.size.height - h - 8),
            );
            final handle = 28.0;
            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => setState(() => _stageMinimized = false),
                onPanStart: (d) {
                  _pipResizing =
                      d.localPosition.dx > w - handle &&
                      d.localPosition.dy > h - handle;
                  _pipResizeStartSize = _pipSize;
                  _pipResizeStartLocal = d.localPosition;
                },
                onPanUpdate: (d) {
                  setState(() {
                    if (_pipResizing) {
                      _pipSize = Size(
                        (_pipResizeStartSize.width +
                                d.localPosition.dx -
                                _pipResizeStartLocal.dx)
                            .clamp(minW, maxW),
                        (_pipResizeStartSize.height +
                                d.localPosition.dy -
                                _pipResizeStartLocal.dy)
                            .clamp(minH, maxH),
                      );
                    } else {
                      _pipPos = Offset(
                        (_pipPos!.dx + d.delta.dx).clamp(
                          8.0,
                          mq.size.width - w - 8,
                        ),
                        (_pipPos!.dy + d.delta.dy).clamp(
                          8.0,
                          mq.size.height - h - 8,
                        ),
                      );
                    }
                  });
                },
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 8),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BroadcastStage(
                          session: _broadcastSession!,
                          isBroadcaster: iAmBroadcasting,
                          compact: true,
                        ),
                        // Handle resize pojok kanan bawah
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Icon(
                            Icons.zoom_out_map_rounded,
                            size: 14,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

}
