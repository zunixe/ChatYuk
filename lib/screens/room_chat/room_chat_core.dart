part of '../room_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _RcCoreMx on _RoomChatBase {
  // ── Kontrak ChatSelectionMixin ──
  @override
  String get chatKind => 'room';

  @override
  String get chatId => widget.room.id;

  @override
  AuthNotifier get chatAuth => _auth;

  @override
  chatRiverpod.ChatNotifier get chatProvider => _chat;

  @override
  TextEditingController get chatMsgCtrl => _msgCtrl;

  void chatFocusComposer() {}

  @override
  void chatScrollToBottom() => _scrollToBottom();

  @override
  Future<bool> chatDeleteMessage(String id) => _chat.deleteRoomMessage(id);

  @override
  Future<bool> chatUndeleteMessage(String id) => _chat.undeleteRoomMessage(id);

  @override
  String chatDeletedLabel(S s) => s.msgDeletedRoom;

  @override
  Map<String, String> get chatReactionKnownNames => const {};

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
    // Video belum aktif di room (videoSendEnabled=false) — parameter
    // tetap diterima demi kontrak mixin bersama.
    int? videoDurationMs,
    String videoPoster = '',
  }) async {
    return _chat.sendRoomMessage(
      roomId: widget.room.id,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      text: text,
      type: type,
      imageData: imageData,
      durationMs: videoDurationMs ?? viewOnceSecs,
      repliedToId: repliedToId,
      repliedToText: repliedToText,
      repliedToSenderName: repliedToSenderName,
      videoPoster: videoPoster,
    );
  }

  @override
  String get photoUploadChatId => 'room_${widget.room.id}';

  @override
  String get photoCacheChatKey => 'room_${widget.room.id}';

  @override
  String get photoSeed => widget.room.id;

  @override
  void photoOnSent(String kind) {}

  @override
  void photoFirstBonus(PointsNotifier pp) {}

  @override
  void photoSetPreview(String base64) {
    // Foto & lokasi tidak boleh tampil bareng di preview.
    setState(() {
      _pendingPhotoBase64 = base64;
      _pendingLocation = null;
    });
  }

  // ── Kontrak ChatSendMixin ──
  @override
  TextEditingController get sendMsgCtrl => _msgCtrl;

  @override
  bool get sendIsSending => _isSending;

  @override
  set sendIsSending(bool v) => _isSending = v;

  @override
  MessageModel? get sendEditingMessage => editingMessage;

  @override
  set sendEditingMessage(MessageModel? v) => editingMessage = v;

  @override
  MessageModel? get sendReplyingTo => replyingTo;

  @override
  set sendReplyingTo(MessageModel? v) => replyingTo = v;

  // Caption & balasan untuk view-once dari picker (kirim langsung tanpa
  // preview) — dulu teks yang diketik diabaikan.
  @override
  String get photoComposerText => _msgCtrl.text;
  @override
  MessageModel? get photoReplyingTo => replyingTo;
  @override
  void photoClearComposerText() {
    sendClearComposer();
    if (mounted) setState(() => replyingTo = null);
  }

  @override
  String? get sendPendingPhotoBase64 => _pendingPhotoBase64;

  @override
  set sendPendingPhotoBase64(String? v) => _pendingPhotoBase64 = v;

  @override
  List<Mention> sendMentionCandidates() => _mentionCandidates;

  @override
  Future<bool> sendPreCheck() async {
    // Private room: cek role SEBELUM kirim — komposer interaktif sejak
    // awal (tanpa gerbang loading). Bukan member → snackbar ajak join.
    if (isPrivateRoom && !_roleChecked) {
      _myRole = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(roomProvider.notifier).myRole(widget.room.id);
      _roleChecked = true;
      if (!mounted) return false;
      setState(() {});
      if (_myRole == null) {
        showChatSnack(
          context,
          ProviderScope.containerOf(
            context,
            listen: false,
          ).read(localeProvider).s.privateRoomNeedApproval,
        );
        return false;
      }
    }
    return true;
  }

  @override
  void sendCancelEdit() => cancelEdit();

  @override
  Future<bool> sendEditPersist(MessageModel editing, String raw) =>
      ProviderScope.containerOf(context, listen: false)
          .read(chatRiverpod.chatProvider.notifier)
          .editRoomMessage(editing.id, raw);

  @override
  Future<void> sendDispatchText({
    required String text,
    required MessageModel? reply,
    required List<Mention> mentions,
  }) async {
    await _chat.sendRoomMessage(
      roomId: widget.room.id,
      senderId: _auth.uid!,
      senderName: _auth.profile!.nickname,
      senderGender: _auth.profile!.gender,
      text: text,
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
      mentions: mentions,
    );
  }

  @override
  void sendOnSentText() {
    final pp = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier);
    if (pp.enabled) {
      pp.showPointsToast(
        context,
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(localeProvider).s.pointsDeduct(1),
      );
    }
    // Bonus "first room chat" DIHAPUS (overhaul coin: tidak ada poin gratis).
    _scrollToBottom();
  }







  void _scheduleRebuild() {
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  /// Derivasikan `(items, deletedIds)` di-cache berbasis IDENTITAS list pesan
  /// sumber ([msgsSrc], referensinya stabil dari stream antar rebuild parent)
  /// + jumlah `_pending` + locale + hari. `all` dipakai untuk hasil.
  (List<ChatItem>, Set<String>) _deriveItems(
    S s,
    List<MessageModel> msgsSrc,
    List<MessageModel> all, {
    required DateTime day,
  }) {
    final locale = s.isId ? 'id' : 'en';
    if (identical(_cacheItemsMsgsSrc, msgsSrc) &&
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
    for (final m in all) {
      final local = m.timestamp.toLocal();
      final dateKey = '${local.year}-${local.month}-${local.day}';
      if (prevDateKey != dateKey) {
        items.add(ChatItem.date(dateChipLabel(m.timestamp, s)));
      }
      prevDateKey = dateKey;
      items.add(ChatItem.message(m));
    }
    _cacheItemsMsgsSrc = msgsSrc;
    _cacheItemsPendingLen = _pending.length;
    _cacheItemsLocale = locale;
    _cacheItemsDay = day;
    _cachedItems = items;
    _cachedDeletedIds = deletedIds;
    return (items, deletedIds);
  }

  bool get isPrivateRoom => widget.room.isPrivate == true;
  bool get canModerate =>
      isPrivateRoom && (_myRole == 'owner' || _myRole == 'admin');
  // Moderasi voice global room: owner room ATAU app admin (server cek ulang).
  bool get canModerateVoice =>
      !isPrivateRoom && (widget.room.ownerId == _auth.uid || _auth.isRealAdmin);


  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  void _attachVoiceSession(RoomVoiceSession session) {
    _voiceSession?.removeListener(_onVoiceChanged);
    _voiceSession = session;
    session.addListener(_onVoiceChanged);
    if (mounted) setState(() {});
  }

  /// Uid yang sudah tampil di strip voice (atas) — disembunyikan dari list
  /// user (bawah) supaya avatar tidak dobel atas-bawah.
  Set<String> get _stripUids {
    final s = _voiceSession;
    if (isPrivateRoom || s == null) return const {};
    return s.speakers;
  }

  /// True bila SEMUA user (cache) sudah terwakili strip → list bawah collapse
  /// total (tidak menyisakan kotak 90px kosong).
  bool get _voiceStripCoversUsers {
    final s = _voiceSession;
    if (isPrivateRoom || s == null || !_showUsers) return false;
    final ids = {for (final u in _lastRoomUsers) u.uid};
    final me = _auth.uid;
    if (me != null && _auth.profile != null) ids.add(me);
    if (ids.isEmpty) return false;
    return ids.every(s.speakers.contains);
  }

  /// Pastikan izin mikrofon sebelum mic dipakai (naik stage). Semua jalur
  /// call lain memakai ini; voice stage dulu TERLEWAT → di device yang belum
  /// grant mic, `getUserMedia` gagal senyap tanpa dialog. Return false bila
  /// belum granted (dialog sudah ditampilkan).
  Future<bool> _ensureMicPermission() async {
    final perm = await ensureCallPermissions(video: false);
    if (perm == CallPermissionResult.granted) return true;
    if (!mounted) return false;
    showCallPermissionDialog(
      context,
      video: false,
      permanentlyDenied: perm == CallPermissionResult.permanentlyDenied,
    );
    return false;
  }

  /// Tap tombol mic: belum join → join + langsung naik stage;
  /// di stage → toggle mute; belum stage → naik stage.
  Future<void> _onMicTap() async {
    if (_voiceJoining) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final messenger = ScaffoldMessenger.of(context);
    var session = _voiceSession;
    if (session == null) {
      // try/finally: _voiceJoining WAJIB reset apa pun yang terjadi
      // (RPC/getUserMedia gantung/timeout) — kalau tidak spinner muter
      // selamanya dan tap berikutnya ditolak mentah-mentah.
      setState(() => _voiceJoining = true);
      try {
        // Izin mikrofon WAJIB sebelum mic dipakai (naik stage = getUserMedia).
        if (!await _ensureMicPermission()) return;
        if (!mounted) return;
        final myUid = _auth.uid;
        if (myUid == null) return;
        session = ref.read(roomVoiceProvider).create(
          roomId: widget.room.id,
          myUid: myUid,
          onStageFull: () {
            if (!mounted) return;
            showChatSnackVia(messenger, context, s.roomVoiceStageFull);
          },
          onMutedByAdmin: () {
            if (!mounted) return;
            showChatSnackVia(messenger, context, s.roomVoiceMutedByAdmin);
          },
        );
        _attachVoiceSession(session);
        final ok = await session.startSpeaking();
        if (!mounted) return;
        if (!ok && !session.joined) {
          // Gagal total (mic ditolak/timeout/jaringan): buang sesi + kasih tahu.
          showChatSnackVia(messenger, context, s.roomVoiceConnectFail);
          session.removeListener(_onVoiceChanged);
          await session.stop();
          _voiceSession = null;
          if (mounted) setState(() {});
        }
      } finally {
        if (mounted) setState(() => _voiceJoining = false);
      }
      return;
    }
    if (!session.joined) {
      await session.startListening();
      return;
    }
    if (!session.onStage) {
      if (!await _ensureMicPermission()) return;
      final ok = await session.startSpeaking();
      if (!ok && mounted) {
        showChatSnackVia(messenger, context, s.roomVoiceStageFull);
      }
      return;
    }
    await session.setMuted(!session.muted);
  }

  /// Tahan tombol mic = keluar voice sepenuhnya.
  Future<void> _onMicLongPress() async {
    final session = _voiceSession;
    if (session == null) return;
    session.removeListener(_onVoiceChanged);
    await session.stop();
    _voiceSession = null;
    if (mounted) setState(() {});
  }

  /// Sheet diagnostik voice (tap avatar sendiri di strip): state sesi +
  /// kondisi tiap peer (conn/ice/pasangan kandidat/level audio).
  /// Untuk debug "mic hijau tapi bisu" — kirim screenshot ke dev.
  Future<void> _showVoiceDiagnostics() async {
    final session = _voiceSession;
    if (session == null || !mounted) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final names = {for (final u in _lastRoomUsers) u.uid: u.nickname};
    await showVoiceDiagnosticsSheet(
      context,
      session: session,
      names: names,
      myUid: _auth.uid,
      s: s,
    );
  }

  /// Tap avatar speaker lain → sheet mute (hanya bila boleh moderasi).
  Future<void> _onSpeakerTap(String uid) async {
    if (!canModerateVoice || !mounted) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final session = _voiceSession;
    if (session == null) return;
    final names = {for (final u in _lastRoomUsers) u.uid: u.nickname};
    final name = names[uid] ?? 'User';
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.mic_off_rounded,
                color: AppTheme.danger,
              ),
              title: Text(s.roomVoiceMute),
              subtitle: Text(
                name,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc(
        'room_voice_mute',
        params: {'p_room_id': widget.room.id, 'p_target': uid},
      );
    } catch (_) {}
  }

  bool get iAmBroadcasting =>
      _broadcastSession != null &&
      _broadcastSession!.isBroadcaster &&
      _liveUid == _auth.uid;
  bool get isGrantedBroadcast => _isGrantedBroadcast;
  bool get watchingLive => _broadcastSession != null && !iAmBroadcasting;

  /// Slider ukuran font chat berubah → rebuild bubble & composer room.
  void _onFontScaleChanged() {
    if (mounted) setState(() {});
  }

  List<Mention> get _mentionCandidates {
    final myUid = _auth.uid;
    final seen = <String>{};
    final out = <Mention>[];
    if (isPrivateRoom) {
      for (final m in _roomMembers) {
        final uid = '${m['user_id'] ?? ''}';
        final name = '${m['nickname'] ?? ''}';
        if (uid.isEmpty || uid == myUid || !seen.add(uid)) continue;
        out.add(Mention(uid: uid, name: name));
      }
    } else {
      for (final u in _lastRoomUsers) {
        if (u.uid.isEmpty || u.uid == myUid || !seen.add(u.uid)) continue;
        out.add(Mention(uid: u.uid, name: u.nickname));
      }
    }
    return out;
  }

  /// Target `@all` (owner/admin) — dibatasi 100 uid agar payload aman.
  List<Mention> _mentionAllExpansion() => _mentionCandidates.take(100).toList();

  /// Resolusi teks → mention ber-uid. `@all` hanya di grup oleh owner/admin.

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    // Ukuran font chat berubah (slider) → rebuild bubble & composer room.
    ChatTextScale.notifier.addListener(_onFontScaleChanged);
    _auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    _chat = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatRiverpod.chatProvider.notifier);
    // DEFER seperti private chat — hindari setState-during-build glitch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) activeChatId.value = widget.room.id;
    });
    // Tandai room sudah dibaca di MANA PUN dibuka dari sini — jaring terakhir
    // supaya badge unread hilang walau pemanggil (explore/grup/notif) lupa.
    // Aman dipanggil berulang (RPC idempoten, provider pakai _readRoomIds).
    unawaited(
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(roomProvider.notifier).markRoomRead(widget.room.id),
    );
    final msgsHandle = _chat.getRoomMessages(widget.room.id);
    _msgsHandle = msgsHandle;
    _msgsStream = msgsHandle.stream;
    _usersStream = _chat.getOnlineUsersInRoom(widget.room.id);
    _pointsProv = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier);
    _msgsSub = _msgsStream.listen(_onMessagesForGift);
    // Kandidat mention room global butuh daftar user online walau strip
    // horizontal sedang disembunyikan — simpan snapshot di _lastRoomUsers.
    _usersSub = _usersStream.listen(
      (users) {
        if (users.isNotEmpty) _lastRoomUsers = users;
      },
      onError: (e) {
        // OFFLINE: stream user room (.stream() mentah) bisa error — tanpa
        // onError, error tak tertangkap merusak frame/dispatcher (back mati).
        debugPrint('[NAV] room users stream error: $e');
      },
    );
    if (isPrivateRoom) {
      unawaited(_initPrivate());
    }
    _joinRoom();
    _startPresenceHeartbeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Cache dulu (tampil instan), stream menimpa sesudahnya.
      ProviderScope.containerOf(context, listen: false)
          .read(messageReactionProvider)
          .loadCachedReactions(widget.room.id)
          .then((cached) {
            if (!mounted || cached.isEmpty || reactions.isNotEmpty) return;
            reactions = cached;
            _scheduleRebuild();
          });
      _reactionsSub = ProviderScope.containerOf(context, listen: false)
          .read(messageReactionProvider)
          .watchReactions(widget.room.id)
          .listen(
            (m) {
              reactions = m;
              _scheduleRebuild();
              ProviderScope.containerOf(context, listen: false)
                  .read(messageReactionProvider)
                  .saveCachedReactions(widget.room.id, m);
            },
            onError: (e) {
              // OFFLINE: reactions (.stream() mentah) error → jangan tak tertangkap.
              debugPrint('[NAV] room reactions stream error: $e');
            },
          );
      _starredSub = ProviderScope.containerOf(context, listen: false)
          .read(messageReactionProvider)
          .watchStarred(widget.room.id)
          .listen(
            (m) {
              starredIds = m;
              _scheduleRebuild();
            },
            onError: (e) {
              debugPrint('[NAV] room starred stream error: $e');
            },
          );
    });
    // Antrean offline: koneksi pulih → kirim otomatis; muat sisa antrean
    // sesi lalu (app sempat ditutup saat offline).
    // `ref.listen` dipasang di build() (Riverpod melarang di initState).
    _connOnline = ref.read(connectivityProvider);
    loadQueuedForChat();
  }


  /// Satu pintu mulai broadcast — cegah double-tap (toggle ke stop) dan
  /// beri feedback loading di tombol/banner.
  Future<void> _onStartBroadcastTap() async {
    if (_broadcastStarting || iAmBroadcasting) return;
    setState(() => _broadcastStarting = true);
    try {
      if (_liveUid != _auth.uid) {
        await ProviderScope.containerOf(
          context,
          listen: false,
        ).read(roomProvider.notifier).startBroadcast(widget.room.id);
        await _refreshLiveUid();
      }
      await _startBroadcastSession();
    } finally {
      if (mounted) setState(() => _broadcastStarting = false);
    }
  }

  Future<void> _initPrivate() async {
    dlog('[BDBG] initPrivate start room=${widget.room.id} uid=${_auth.uid}');
    try {
      _myRole = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(roomProvider.notifier).myRole(widget.room.id);
      dlog('[BDBG] myRole=$_myRole isPrivate=${widget.room.isPrivate}');
      // Anggota untuk kandidat mention grup (termasuk yang offline).
      try {
        _roomMembers = await ProviderScope.containerOf(
          context,
          listen: false,
        ).read(roomProvider.notifier).listMembers(widget.room.id);
      } catch (_) {}
      if (canModerate) {
        try {
          final req = await ProviderScope.containerOf(
            context,
            listen: false,
          ).read(roomProvider.notifier).listJoinRequests(widget.room.id);
          _pendingCount = req.length;
        } catch (_) {}
      }
      await _refreshLiveUid();
      try {
        _muted = await ProviderScope.containerOf(
          context,
          listen: false,
        ).read(notificationPrefsProvider).isChatMuted(widget.room.id);
      } catch (_) {}
      try {
        final granted = await ProviderScope.containerOf(
          context,
          listen: false,
        ).read(roomProvider.notifier).myBroadcastGranted(widget.room.id);
        _isGrantedBroadcast = granted || _liveUid == _auth.uid;
        dlog('[BDBG] init granted=$_isGrantedBroadcast live=$_liveUid');
      } catch (e) {
        dlog('[BDBG] init myBroadcastGranted error: $e');
      }
      _listenRoomLive();
      // Fallback poll JARANG (30s): realtime channel (_listenRoomLive)
      // adalah jalur utama update live_uid/grant — poll 5s seumur room
      // buang-buang RPC & battery.
      _livePoll?.cancel();
      _livePoll = Timer.periodic(const Duration(seconds: 30), (_) {
        // P2a (baterai): jangan RPC saat background/layar mati.
        if (!AppForeground.now) return;
        _refreshLiveUid();
        _refreshGrant();
        _ensureViewerSession();
      });
    } catch (e) {
      dlog('[BDBG] initPrivate ERROR: $e');
    }
    _roleChecked = true;
    if (!mounted) return;
    setState(() {});
  }


  void _listenRoomLive() {
    try {
      final old = _roomLiveChannel;
      _roomLiveChannel = null;
      if (old != null) unawaited(Supabase.instance.client.removeChannel(old));
    } catch (_) {}
    try {
      final ch = Supabase.instance.client.channel(
        'room-live-${widget.room.id}',
      );
      ch.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'rooms',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: widget.room.id,
        ),
        callback: (payload) {
          if (!mounted) return;
          final live = payload.newRecord['live_uid']?.toString();
          dlog('[BDBG] realtime rooms update live=$live current=$_liveUid');
          if (live != _liveUid) {
            _liveUid = (live != null && live.isNotEmpty) ? live : null;
            setState(() {});
          }
          // Selalu sync — kalau live_uid sama dengan sebelumnya (broadcast
          // restart), viewer tetap harus mulai sesi.
          _refreshGrant();
          _syncBroadcastSession();
        },
      );
      ch.subscribe((status, err) {
        if (err != null) debugPrint('[ROOM] live realtime error: $err');
      });
      _roomLiveChannel = ch;
    } catch (_) {}
  }

}
