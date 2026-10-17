part of '../private_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _PcBuildMx on _PrivateChatBase {
  /// Kirim STIKER KOLEKSI (path server sudah ada) — tanpa upload ulang.
  /// Download 1× untuk seed cache bubble, lalu kirim pesan type 'sticker'.
  /// Di mixin ini (satu file dengan pemakai di composer) supaya resolve
  /// nama selalu dalam satu unit part.
  Future<void> _sendStickerPath(String path) async {
    dlog('[STICKER] _sendStickerPath $path');
    if (path.isEmpty) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(authProvider.notifier);
    final uid = auth.uid;
    if (uid == null) return;
    final prof = auth.profile;
    try {
      final bytes =
          await container.read(storageProvider).downloadBytes(path);
      if (bytes != null && bytes.isNotEmpty) {
        StickerBubble.seedCache(path, bytes);
      }
      await container.read(chatRiverpod.chatProvider.notifier).sendPrivateMessage(
            chatId: widget.chatId,
            senderId: uid,
            senderName: prof?.nickname ?? 'Anon',
            senderGender: prof?.gender ?? 'other',
            text: '',
            type: 'sticker',
            imageData: path,
          );
    } catch (e) {
      dlog('[STICKER] kirim path gagal: $e');
      if (mounted) {
        showChatSnack(
          context,
          container.read(localeProvider).s.stickerSendFail,
        );
      }
    }
  }

  @override
  Future<bool> chatDeleteMessage(String id) async {
    final ok = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatRiverpod.chatProvider.notifier).deletePrivateMessage(id);
    // Optimistic lokal: tandai terhapus SEGERA supaya UI tidak menunggu
    // realtime/refetch. DB sudah menyimpan semua id, tapi tampilan bisa
    // tertinggal (gejala "pilih beberapa, hanya 1 yang kelihatan terhapus").
    if (ok && mounted) {
      setState(() => _localDeletedIds.add(id));
    }
    return ok;
  }

  @override
  Future<bool> chatUndeleteMessage(String id) async {
    final ok = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatRiverpod.chatProvider.notifier).undeletePrivateMessage(id);
    if (ok && mounted) {
      setState(() => _localDeletedIds.remove(id));
    }
    return ok;
  }

  @override
  Future<Map<String, dynamic>> chatUndoMessage(String id) async {
    final n = int.tryParse(id);
    if (n == null) return {};
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier).undoMessage(n);
  }

  /// Tombol kamera → layar kamera in-app (SAMA seperti Story): preview live +
  /// toggle Foto/Video DI DALAM kamera. Foto → preview composer; video
  /// (maks 60 dtk) → kompres → preview.
  ///
  /// Bila kamera in-app GAGAL init (sebagian MIUI menutup pipeline kamera
  /// pihak-ketiga) → fallback ke kamera SISTEM (foto) supaya tombol tetap
  /// berfungsi.
  Future<void> _openCameraCapture() async {
    final result = await Navigator.of(context).push<StoryCaptureResult>(
      MaterialPageRoute(
        builder: (_) => const StoryCameraCaptureScreen(maxRecordSecs: 60),
      ),
    );
    if (!mounted) return;
    if (result == null) {
      if (StoryCameraCaptureScreen.lastInitFailed) {
        await photoTakeToPreview();
      }
      return;
    }
    if (result.isVideo) {
      await videoFromFileToPreview(result.file.path);
    } else {
      final bytes = await result.file.readAsBytes();
      if (!mounted) return;
      await photoFromFileToPreview(bytes);
    }
  }

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
          .sendPrivateMessage(
            chatId: widget.chatId,
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
      showChatSnack(
        context,
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(localeProvider).s.errSendFailed,
      );
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

  @override
  String get photoUploadChatId => widget.chatId;
  @override
  void photoFirstBonus(PointsNotifier pp) {
    // Bonus "first photo" DIHAPUS (overhaul coin: tidak ada poin gratis).
  }
  @override
  void photoSetPreview(String base64) {
    setState(() {
      _pendingPhotoBase64 = base64;
      // Foto, video, & lokasi tidak boleh tampil bareng di preview.
      _pendingVideoPath = null;
      _pendingVideoPoster = null;
      _pendingVideoMs = 0;
      _pendingVideoOnce = false;
      _pendingLocation = null;
      _viewTimerSecs = null;
      _inputFocus.requestFocus();
    });
    _scrollToBottom();
  }

  // ── Kontrak video (private) ──
  @override
  bool get videoSendEnabled => true;
  @override
  int get pendingVideoMs => _pendingVideoMs;
  @override
  MessageModel? get sendEditingMessage => editingMessage;
  @override
  MessageModel? get sendReplyingTo => replyingTo;
  @override
  set sendPendingPhotoBase64(String? v) => _pendingPhotoBase64 = v;
  @override
  Future<bool> sendPreCheck() async {
    if (ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatRiverpod.chatProvider.notifier).isBlocked(widget.otherUid)) {
      if (mounted) {
        final s = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(localeProvider).s;
        showChatSnack(context, s.msgBlocked);
      }
      return false;
    }
    return true;
  }

  @override
  Future<bool> sendEditPersist(MessageModel editing, String raw) =>
      ProviderScope.containerOf(context, listen: false)
          .read(chatRiverpod.chatProvider.notifier)
          .editPrivateMessage(editing.id, raw);
  @override
  void sendOnSentText() {
    _maybeNewChatBonus();
    _schedulePendingConfirmFallback();
  }

  Future<void> _fetchImageQueued(String id) async {
    try {
      await _msgsHandleFetchImage(id);
    } catch (_) {
      // Gagal memuat satu foto tidak boleh menghentikan antrean foto lain.
    } finally {
      _imgInFlight.remove(id);
      _drainImageQueue();
    }
  }

  void _trimConfirmed(Set<String> ids) {
    while (ids.length > _confirmedCap) {
      ids.remove(ids.first);
    }
  }

  /// Baca last-read lawan SECARA SINKRON sebelum frame pertama, dari DUA
  /// sumber memori (diambil yang terbaru): snapshot live `_privateChatsLast`
  /// (ter-fresh — update tiap event realtime) + `peekRawList` (hasil preload
  /// bootstrap). Tidak ada await → centang-2 tampil instan sejak buka chat.
  void _primeReadFromCache() {
    try {
      final myUid = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authProvider.notifier).uid;
      if (myUid == null) return;
      final candidates = <DateTime?>[];
      // 1) Snapshot live — paling fresh di sesi ini.
      final snap = ProviderScope.containerOf(context, listen: false)
          .read(chatRiverpod.chatProvider.notifier)
          .lastPrivateChatsSnapshot(myUid);
      if (snap != null) {
        for (final c in snap) {
          if (c.chatId != widget.chatId) continue;
          candidates.add(c.lastReadAt[widget.otherUid]);
          break;
        }
      }
      // 2) Snapshot list chat di memori MessageCache (isian bootstrap).
      final rows = MessageCache.instance.peekRawList(myUid);
      for (final row in rows) {
        if ('${row['chatId']}' != widget.chatId) continue;
        final raw = row['lastReadAt'];
        if (raw is Map) candidates.add(ReadReceipt.parse(raw[widget.otherUid]));
        break;
      }
      final best = ReadReceipt.best(candidates);
      if (best != null) _patchHdr((h) => h.copyWith(otherLastRead: best));
      // WAJIB: prime jalan di initState (sebelum ref.listen terpasang di
      // build pertama) → tanpa ini notifier list tetap null walau _hdr sudah
      // terisi → centang-2 tak pernah biru sampai ada read BARU dari network.
      if (best != null) _lastReadNotifier.value = best;
    } catch (_) {}
  }

  /// Slider ukuran font chat berubah → rebuild bubble & composer langsung.
  void _onFontScaleChanged() {
    if (mounted) setState(() {});
  }

  void _onCallChanged() {
    final sess = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(callProvider.notifier).activeSession;
    // Signature state call yang RELEVAN untuk layar ini: overlay hidup/mati
    // ditentukan oleh (ada sesi? uid lawan? phase?). Dulu cukup `sess == null
    // || remoteUid==other` → setState SELALU saat chat biasa (sess==null
    // selalu true) tiap CallProvider.notify → rebuild penuh tak perlu.
    // Kini setState hanya bila signature benar-benar berubah.
    final relevantForThisChat =
        sess != null && sess.remoteUid == widget.otherUid;
    final sig = relevantForThisChat ? '${sess.callId}|${sess.phase}' : '_none';
    // Call baru berakhir di chat ini → tampilkan bubble "Call ended" INSTAN
    // (optimistic) agar tidak nunggu Realtime 1-2 detik. Nanti saat pesan
    // server tiba, dedup di _msgsSub akan hapus pending.
    if (sess != null &&
        sess.remoteUid == widget.otherUid &&
        sess.phase == CallPhase.ended &&
        _prevCallPhase != CallPhase.ended) {
      final auth = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authProvider.notifier);
      final uid = auth.uid;
      final profile = auth.profile;
      if (uid != null && profile != null) {
        final dur = sess.connectedAt != null
            ? DateTime.now().difference(sess.connectedAt!).inSeconds
            : 0;
        final statusText = switch (sess.endReason) {
          CallEndReason.ended => 'Call ended',
          CallEndReason.declined => 'Call declined',
          CallEndReason.missed => 'Missed call',
          CallEndReason.canceled => 'Call canceled',
          CallEndReason.busy => 'Busy',
          CallEndReason.error => 'Call failed',
        };
        final durText = dur > 0
            ? ' (${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')})'
            : '';
        final text =
            '${sess.callType == 'video' ? '📹' : '📞'} $statusText$durText';
        final pendingCall = MessageModel(
          id: 'pending-call-${DateTime.now().microsecondsSinceEpoch}',
          senderId: uid,
          senderName: profile.nickname,
          senderGender: profile.gender,
          isRegistered: profile.isRegistered,
          text: text,
          type: 'call',
          imageData: '',
          timestamp: DateTime.now(),
        );
        setState(() => _pending.add(pendingCall));
        _scrollToBottom();
      }
    }
    _prevCallPhase = sess?.phase ?? _prevCallPhase;
    // Overlay hidup/mati bergantung pada `activeSession` — termasuk saat sesi
    // di-NULL-kan (clearSession setelah tombol end). Dulu `sess == null` lolos
    // ke `return` (null != otherUid) TANPA setState → overlay TIDAK hilang
    // sampai ada rebuild lain ("end call lama matinya", terutama di MIUI).
    // GRANULAR: rebuild hanya bila signature relevan berubah (bukan tiap
    // notify CallProvider) — hindari rebuild penuh saat chat tanpa call.
    if (sig != _prevCallSig) {
      _prevCallSig = sig;
      if (relevantForThisChat || _prevCallSig == '_none') {
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _expandCall() async {
    // Guard anti tap-ganda: dua push beruntun membuat stack kacau &
    // `_callExpanded` salah reset → tombol perbesar terasa "tidak jalan".
    if (_expandingCall) return;
    final sess = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(callProvider.notifier).activeSession;
    if (sess == null) return;
    _expandingCall = true;
    setState(() => _callExpanded = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          settings: const RouteSettings(name: kCallScreenRoute),
          builder: (_) => CallScreen(
            callId: sess.callId,
            remoteUid: sess.remoteUid,
            remoteName: sess.remoteName,
            callType: sess.callType,
            isCaller: sess.isCaller,
            pendingSignals: const [],
            session: sess,
            onMinimize: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } finally {
      _expandingCall = false;
      if (mounted) setState(() => _callExpanded = false);
    }
  }

  void _subscribeStatus() {
    _statusSub?.cancel();
    _statusSub = ProviderScope.containerOf(context, listen: false)
        .read(chatRiverpod.chatProvider.notifier)
        .getUserStatus(widget.otherUid)
        .listen(
          (status) {
            if (!mounted) return;
            // Fetch last_seen saat status TIDAK online agar bisa tampilkan
            // "terakhir dilihat" di header; saat online tidak perlu (null).
            // Throttle 30 dtk — status flapping tidak memicu N+1 query.
            if (status == 'online') {
              if (_hdr.otherStatus != status || _hdr.otherLastSeen != null) {
                _patchHdr(
                  (h) => h.copyWith(otherStatus: status, clearLastSeen: true),
                );
              }
            } else {
              final now = DateTime.now();
              final lastFetch = _lastSeenFetchedAt;
              // Guard perubahan: stream status bisa emit nilai SAMA berulang
              // (heartbeat presence). `ChatHeader` value-equal → patch no-op
              // bila tak berubah (nol rebuild, lebih kuat dari guard manual).
              _patchHdr((h) => h.copyWith(otherStatus: status));
              if (lastFetch != null &&
                  now.difference(lastFetch).inSeconds < 30) {
                return;
              }
              _lastSeenFetchedAt = now;
              ProviderScope.containerOf(context, listen: false)
                  .read(chatRiverpod.chatProvider.notifier)
                  .getUserLastSeen(widget.otherUid)
                  .then((t) {
                    if (!mounted || t == null) return;
                    _patchHdr((h) => h.copyWith(otherLastSeen: t));
                  });
            }
          },
          onError: (e) {
            // OFFLINE: stream status realtime error → jangan tak tertangkap.
            debugPrint('[NAV] status stream error private-chat: $e');
          },
        );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        // reverse: true → offset 0 = paling bawah (pesan terbaru)
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  // Scroll ke atas (reverse list, offset menuju maxScrollExtent = pesan lama)
  // → trigger load pesan lama dari server.
  void _onScrollToLoadOlder() {
    if (!_scrollCtrl.hasClients || _loadingOlder) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    final px = _scrollCtrl.position.pixels;
    // 200px dari paling atas (pesan tertua) → load older
    if (max - px < 200) {
      _loadingOlder = true;
      _loadOlder().whenComplete(() => _loadingOlder = false);
    }
  }

  @override
  String get outboxKind => 'private';
  @override
  List<MessageModel> get outboxPending => _pending;
  @override
  set outboxIsFlushing(bool v) => _flushingOutbox = v;
  void _toggleAttachRow() {
    if (!_showAttachRow) {
      FocusScope.of(context).unfocus(); // tutup keyboard saat buka menu
    }
    setState(() => _showAttachRow = !_showAttachRow);
  }

  Future<void> _showSendCoinDialog() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final points = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier);

    if (!auth.canUsePaid) {
      showChatSnack(
        context,
        auth.profile?.isRegistered != true
            ? s.errCoinRegisterOnly
            : s.msgVerifyToUsePaid,
      );
      return;
    }
    final amount = await showSendCoinDialog(
      context,
      otherName: widget.otherName,
      pointsEnabled: points.enabled,
      paidBalance: points.paidBalance,
    );
    if (amount == null || !mounted) return;
    await _sendCoins(amount);
  }

  Future<void> _showGiftPicker() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final points = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier);
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);

    if (!auth.canUsePaid) {
      showChatSnack(
        context,
        auth.profile?.isRegistered != true
            ? s.errCoinRegisterOnly
            : s.msgVerifyToUsePaid,
      );
      return;
    }

    final gift = await showGiftPickerSheet(
      context,
      pointsEnabled: points.enabled,
      paidBalance: points.paidBalance,
      bonusBalance: points.bonusBalance,
      bonusMultiplier: points.bonusMultiplier,
    );
    if (gift != null && mounted) {
      setState(() => _showAttachRow = false);
      await _sendGift(gift.id, s.isId ? gift.nameId : gift.nameEn, gift.coins);
    }
  }

  Widget _buildBottomBar(BuildContext context, S s) {
    // L2: baca enabled DI SINI (bukan di root build) — perub. poin tak
    // rebuild header/list; hanya composer.
    final pointsEnabled = ref.watch(pointsProvider.select((p) => p.enabled));
    return Container(
      padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lawan sudah hapus akun → ganti composer dengan
            // banner info. Tidak bisa kirim apa pun lagi.
            if (_hdr.otherDeleted)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_off_outlined,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.accountDeletedHint,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              if (_queuedIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                  child: Row(
                    children: [
                      Icon(Icons.done, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
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
                  senderLabel: replyingTo!.senderId != widget.otherUid
                      ? s.labelYou
                      : replyingTo!.senderName,
                  s: s,
                  onCancel: cancelReply,
                ),
              if (editingMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 16, color: AppTheme.primary),
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
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: cancelEdit,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              // Insets keyboard HANYA di composer. PENTING:
              // `MediaQuery.viewInsetsOf` JANGAN dibaca di build
              // PrivateChatScreen — itu mendaftarkan ELEMENT layar
              // sebagai depend → tiap IME frame MIUI (puluhan/detik)
              // rebuild SELURUH layar. `_KeyboardInset` membacanya di
              // element kecil sendiri → hanya composer yang rebuild.
              KeyboardInset(
                child: ChatComposerInput(
                  controller: _msgCtrl,
                  focusNode: _inputFocus,
                  onSend: sendMessage,
                  showAttachRow: _showAttachRow,
                  onToggleAttach: _toggleAttachRow,
                  onPickGalleryPhoto: (bytes) {
                    setState(() => _showAttachRow = false);
                    photoFromFileToPreview(bytes);
                  },
                  onTakePhoto: () {
                    setState(() => _showAttachRow = false);
                    _openCameraCapture();
                  },
                  onSendPhoto: () {
                    setState(() => _showAttachRow = false);
                    photoPickFromGalleryToPreview();
                  },
                  onSendViewOnce: () {
                    setState(() => _showAttachRow = false);
                    sendViewOnceFromPicker();
                  },
                  onSendVoice: (path, ms) => voiceFinishRecording(path, ms),
                  onSendSticker: _sendSticker,
                  onSendStickerPath: _sendStickerPath,
                  onRecordingSignal: _sendRecordingSignal,
                  onTyping: _sendTypingSignal,
                  // Koin & hadiah hanya bila sistem koin aktif —
                  // hilang total saat dimatikan admin.
                  onSendCoin: pointsEnabled ? _showSendCoinDialog : null,
                  onSendLocation: _sendLocation,
                  pendingLocation: _pendingLocation,
                  onCancelLocation: _pendingLocation != null
                      ? () => setState(() => _pendingLocation = null)
                      : null,
                  onOpenGiftPanel: pointsEnabled ? _showGiftPicker : null,
                  pendingPhotoBase64: _pendingPhotoBase64,
                  onCancelPhoto: _pendingPhotoBase64 != null
                      ? () => setState(() {
                          _pendingPhotoBase64 = null;
                          _viewTimerSecs = null;
                          photoClearPreviewState();
                        })
                      : null,
                  photoHd: photoHd,
                  onHdChanged: _pendingPhotoBase64 != null
                      ? (v) => setState(() => photoHd = v)
                      : null,
                  viewTimerSecs: _viewTimerSecs,
                  onViewTimerChanged: _pendingPhotoBase64 != null
                      ? (v) => setState(() => _viewTimerSecs = v)
                      : null,
                  // ── Video (private) ──
                  onSendVideo: () {
                    if (mounted) {
                      setState(() => _showAttachRow = false);
                    }
                    unawaited(videoPickToPreview());
                  },
                  pendingVideoPoster: _pendingVideoPoster,
                  pendingVideoPath: _pendingVideoPath,
                  pendingVideoMs: _pendingVideoMs,
                  videoOnce: _pendingVideoOnce,
                  onVideoOnceChanged: (v) =>
                      setState(() => _pendingVideoOnce = v),
                  videoCompressing: videoCompressProgress,
                  onCancelVideo: () {
                    if (mounted) {
                      setState(() => _showAttachRow = false);
                    }
                    videoClearPreview();
                  },
                  mentionCandidates: _mentionCandidates,
                  mentionAllowAll: false,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

