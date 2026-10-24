part of '../room_chat_screen.dart';


mixin _RcRoomMx on _RoomChatBase {
  /// Cap dedupe-id pesan terkonfirmasi (MEDIUM, 2026-10-11): dulu Set tumbuh
  /// per foto/voice server seumur layar room dibuka → memori naik monoton.
  /// FIFO buang id terlama (pola sama `_trimConfirmed` private chat).
  void _trimConfirmed(Set<String> ids) {
    while (ids.length > 200) {
      ids.remove(ids.first);
    }
  }
  Future<void> _refreshGrant() async {
    try {
      final granted = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(roomProvider.notifier).myBroadcastGranted(widget.room.id);
      final g = granted || _liveUid == _auth.uid;
      dlog(
        '[BDBG] refreshGrant granted=$granted live=$_liveUid uid=${_auth.uid} g=$g',
      );
      if (mounted && g != _isGrantedBroadcast)
        setState(() => _isGrantedBroadcast = g);
      // Simpan untuk buka berikutnya (tampil sejak frame 1, tanpa blink).
      BroadcastStateCache.save(
        widget.room.id,
        granted: g,
        liveUid: _liveUid,
      );
    } catch (e) {
      dlog('[BDBG] refreshGrant error: $e');
    }
  }

  // ── Room gift (live) ──

  /// Setiap batch pesan masuk, ambil type='gift' yang belum ditampilkan
  /// → mainkan animasi fly. Stream mengirim snapshot penuh, jadi
  /// dedup via id pesan.
  void _onMessagesForGift(List<MessageModel> msgs) {
    _lastMsgs = msgs;
    // Cap peta key lompat-pesan — tanpa ini tumbuh tanpa batas di
    // sesi panjang (GlobalKey per pesan yang pernah dirender).
    if (_msgKeys.length > 500) {
      final keep = msgs.map((m) => m.id).toSet();
      _msgKeys.removeWhere((k, _) => !keep.contains(k));
    }
    final gifts = msgs.where((m) => m.type == 'gift');
    for (final m in gifts) {
      final id = m.id;
      if (_seenGiftMsgIds.contains(id)) continue;
      _seenGiftMsgIds.add(id);
      final gift = giftById(m.text);
      if (gift == null) continue;
      // Snapshot lama tidak diputar ulang: hanya gift yang masuk live
      // (timestamp < 5 detik lalu) yang dianimasikan. Guard fresh ini
      // yang mencegah re-play — cap seen-set tidak perlu clear() (clear
      // bikin gift lama yang masih di list dianggap baru lagi).
      final fresh =
          DateTime.now().difference(m.timestamp) < const Duration(seconds: 5);
      if (!fresh) continue;
      _giftFly.push(gift, m.senderName, 1);
    }
    // Dedupe bubble optimistik milik sendiri (centang-1 → centang-2):
    // teks dicocokkan isi, foto/voice FIFO via id server (thumbnail di
    // stream beda dari base64 pending). Hanya pesan setelah layar dibuka
    // yang menghapus pending foto/voice (history lama di-skip).
    if (_pending.isNotEmpty) {
      var changed = false;
      final myId = _auth.uid;
      if (myId != null) {
        // Teks: recency + sekali pakai + FIFO (lihat consumeConfirmedText).
        // Pencocokan mentah via isi membuat pesan lama yang sama isinya
        // membuang pending baru → "kirim lalu hilang, muncul telat".
        for (final m in msgs) {
          if (m.senderId != myId) continue;
          final idx = consumeConfirmedText(
            server: m,
            openedAt: _openedAt,
            consumedIds: _confirmedTextIds,
            pendings: _pending,
          );
          if (idx != -1) {
            _queuedIds.remove(_pending[idx].id);
            _pending.removeAt(idx);
            changed = true;
          }
        }
        for (final m in msgs) {
          if (m.senderId == myId &&
              (m.type == 'image' ||
                  m.type == 'view_once' ||
                  m.type == 'view_once_expired') &&
              m.timestamp.isAfter(_openedAt) &&
              _confirmedPhotoIds.add(m.id)) {
            _trimConfirmed(_confirmedPhotoIds);
            final idx = _pending.indexWhere(
              (p) =>
                  p.type == 'image' ||
                  p.type == 'view_once' ||
                  p.type == 'view_once_expired',
            );
            if (idx != -1) {
              _queuedIds.remove(_pending[idx].id);
              _pending.removeAt(idx);
              changed = true;
            }
          }
        }
        // Video (biasa & sekali-lihat): bubble optimistik lokal vs baris
        // server — tanpa loop ini video tampil DOBEL (pending + server).
        for (final m in msgs) {
          if (m.senderId == myId &&
              (m.type == 'video' ||
                  m.type == 'video_once' ||
                  m.type == 'video_once_expired') &&
              m.timestamp.isAfter(_openedAt) &&
              _confirmedVideoIds.add(m.id)) {
            _trimConfirmed(_confirmedVideoIds);
            final idx = _pending.indexWhere(
              (p) =>
                  p.type == 'video' ||
                  p.type == 'video_once' ||
                  p.type == 'video_once_expired',
            );
            if (idx != -1) {
              _queuedIds.remove(_pending[idx].id);
              _pending.removeAt(idx);
              changed = true;
            }
          }
        }
        for (final m in msgs) {
          if (m.senderId == myId &&
              m.type == 'voice' &&              m.timestamp.isAfter(_openedAt) &&
              _confirmedVoiceIds.add(m.id)) {
            _trimConfirmed(_confirmedVoiceIds);
            final idx = _pending.indexWhere((p) => p.type == 'voice');
            if (idx != -1) {
              _queuedIds.remove(_pending[idx].id);
              _pending.removeAt(idx);
              changed = true;
            }
          }
        }
        // Stiker: path persis / FIFO, id server sekali pakai.
        for (final m in msgs) {
          if (m.senderId != myId) continue;
          final idx = consumeConfirmedSticker(
            server: m,
            openedAt: _openedAt,
            consumedIds: _confirmedPhotoIds,
            pendings: _pending,
          );
          if (idx != -1) {
            _pending.removeAt(idx);
            changed = true;
          }
        }
        // Poll room: id server sekali pakai + teks '📊 <tanya>' (FIFO).
        for (final m in msgs) {
          if (m.senderId != myId) continue;
          final idx = consumeConfirmedPoll(
            server: m,
            openedAt: _openedAt,
            consumedIds: _confirmedTextIds,
            pendings: _pending,
          );
          if (idx != -1) {
            _queuedIds.remove(_pending[idx].id);
            _pending.removeAt(idx);
            changed = true;
          }
        }
        // Kontak: id server sekali pakai + teks '📇 <nama>' (FIFO).
        for (final m in msgs) {
          if (m.senderId != myId) continue;
          final idx = consumeConfirmedContact(
            server: m,
            openedAt: _openedAt,
            consumedIds: _confirmedTextIds,
            pendings: _pending,
          );
          if (idx != -1) {
            _queuedIds.remove(_pending[idx].id);
            _pending.removeAt(idx);
            changed = true;
          }
        }
        // File: id server sekali pakai + nama file (FIFO).
        for (final m in msgs) {
          if (m.senderId != myId) continue;
          final idx = consumeConfirmedFile(
            server: m,
            openedAt: _openedAt,
            consumedIds: _confirmedVoiceIds,
            pendings: _pending,
          );
          if (idx != -1) {
            _pending.removeAt(idx);
            changed = true;
          }
        }
      }
      if (changed && mounted) setState(() {});
    }
    // Cap seen-set TANPA clear: buang yang paling lama (FIFO) — id gift
    // lama tidak bisa re-play karena guard fresh di atas sudah memfilter.
    if (_seenGiftMsgIds.length > 500) {
      _seenGiftMsgIds = _seenGiftMsgIds
          .skip(_seenGiftMsgIds.length - 300)
          .toSet();
    }
  }

  Future<void> _openRoomGiftPanel() async {
    final scope = ProviderScope.containerOf(context, listen: false);
    final s = scope.read(localeProvider).s;
    final auth = scope.read(authProvider.notifier);
    if (!auth.canUsePaid) {
      showChatSnack(
        context,
        auth.profile?.isRegistered != true
            ? s.errCoinRegisterOnly
            : s.msgVerifyToUsePaid,
      );
      return;
    }
    final pick = await RoomGiftPanel.show(context);
    if (pick == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await _chat.sendRoomGift(
        widget.room.id,
        pick.gift.id,
        qty: pick.qty,
      );
      if (res['ok'] == true) {
        if (res['points'] != null) {
          _pointsProv?.setPoints((res['points'] as num).toInt());
        }
        if (mounted) {
          _pointsProv?.showPointsToast(
            context,
            s.giftSentToast(s.isId ? pick.gift.nameId : pick.gift.nameEn),
          );
        }
      }
    } catch (e) {
      final msg = e.toString();
      showChatSnackVia(
        messenger,
        mounted ? context : messenger.context,
        msg.contains('Not enough')
            ? s.giftInsufficient
            : msg.contains('registered')
            ? s.errCoinRegisterOnly
            : s.errSendCoin,
      );
    }
  }

  /// Pastikan viewer session jalan kalau ada orang lain yang broadcast.
  /// Menutup celah: live_uid tidak berubah (broadcast restart) atau event
  /// realtime terlewat → tanpa ini viewer harus keluar-masuk room dulu.
  Future<void> _ensureViewerSession() async {
    if (!isPrivateRoom || !mounted) return;
    if (_liveUid == null || _liveUid == _auth.uid) return;
    if (_broadcastSession != null && !_broadcastSession!.isBroadcaster) return;
    try {
      final cnt = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(roomProvider.notifier).broadcastCount(widget.room.id);
      if (!mounted) return;
      if (cnt == 0) return;
      unawaited(_startViewerSession());
    } catch (_) {}
  }

  Future<void> _refreshLiveUid() async {
    final row = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(roomProvider.notifier).fetchRoomById(widget.room.id);
    final live = row?['live_uid']?.toString();
    dlog('[BDBG] refreshLiveUid fetched=$live current=$_liveUid');
    if (!mounted) return;
    if (live == _liveUid) return;
    setState(() {
      _liveUid = (live != null && live.isNotEmpty) ? live : null;
    });
    BroadcastStateCache.save(
      widget.room.id,
      granted: _isGrantedBroadcast || _liveUid == _auth.uid,
      liveUid: _liveUid,
    );
    _syncBroadcastSession();
  }

  void _syncBroadcastSession() {
    final iAmLive = _liveUid != null && _liveUid == _auth.uid;
    final someoneElse = _liveUid != null && _liveUid != _auth.uid;

    if (iAmLive) {
      // Jangan auto-start — biarkan user klik manual dari chip/broadcast button.
    } else if (someoneElse) {
      if (_broadcastSession == null || _broadcastSession!.isBroadcaster) {
        unawaited(_startViewerSession());
      }
    } else {
      // Tidak ada live → bersihkan.
      unawaited(_broadcastSession?.stop());
      _voiceSession?.removeListener(_onVoiceChanged);
      unawaited(_voiceSession?.stop());
      _voiceSession = null;
      _broadcastSession = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _startBroadcastSession() async {
    // cap 4
    final scope = ProviderScope.containerOf(context, listen: false);
    try {
      final cnt = await scope.read(roomProvider.notifier).broadcastCount(widget.room.id);
      if (cnt >= 4) {
        if (!mounted) return;
        final s = scope.read(localeProvider).s;
        showChatSnack(
          context,
          s.roomBroadcastFull,
          backgroundColor: AppTheme.danger,
        );
        return;
      }
    } catch (_) {}
    unawaited(_broadcastSession?.stop());
    _broadcastSession = null;
    final session = scope
        .read(roomProvider.notifier)
        .createBroadcastSession(
          roomId: widget.room.id,
          isBroadcaster: true,
          onEnded: () {
            scope.read(callProvider.notifier).notifStopLive();
            if (mounted) {
              setState(() {
                _broadcastSession = null;
                _liveUid = null;
              });
            }
          },
        );
    _broadcastSession = session;
    try {
      await session.start();
      if (!mounted) return;
      // Foreground service: broadcast tetap hidup saat app di-background
      scope
          .read(callProvider.notifier)
          .notifStartLive(
            text: scope.read(localeProvider).s.broadcastLiveNotif,
          );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('Broadcast full')
          ? scope.read(localeProvider).s.roomBroadcastFull
          : '$e';
      showChatSnack(context, msg);
      _broadcastSession = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _startViewerSession() async {
    unawaited(_broadcastSession?.stop());
    _broadcastSession = null;
    final session = ProviderScope.containerOf(context, listen: false)
        .read(roomProvider.notifier)
        .createBroadcastSession(
          roomId: widget.room.id,
          isBroadcaster: false,
          onEnded: () {
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(callProvider.notifier).notifStopLive();
            if (mounted) {
              setState(() => _broadcastSession = null);
            }
          },
        );
    _broadcastSession = session;
    await session.start();
    if (!mounted) return;
    // Foreground service: menonton broadcast tetap hidup di background
    ProviderScope.containerOf(context, listen: false)
        .read(callProvider.notifier)
        .notifStartLive(
          text: ProviderScope.containerOf(
            context,
            listen: false,
          ).read(localeProvider).s.broadcastWatchingNotif,
        );
    await session.requestStream();
    if (mounted) setState(() {});
  }

  /// Hand raise — kirim signal ke admin.
  Future<void> _raiseHand() async {
    await ProviderScope.containerOf(context, listen: false)
        .read(roomProvider.notifier)
        .sendSignal(
          widget.room.id,
          type: 'hand_raise',
          payload: {'nickname': _auth.profile?.nickname ?? ''},
        );
    if (!mounted) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    showChatSnack(
      context,
      s.roomHandRaised,
      duration: const Duration(seconds: 2),
    );
  }

  /// Menu ⋮ grup ala WA: tambah anggota, info, media, cari, bisu, lainnya.
  void _onGroupMenu(String v) {
    switch (v) {
      case 'add':
        unawaited(() async {
          // Exclude MEMBER ASLI (bukan tebakan dari pengirim pesan) —
          // tanpa ini member lama bisa muncul lagi di picker.
          final memberIds = <String>{};
          try {
            final members = await ProviderScope.containerOf(
              context,
              listen: false,
            ).read(roomProvider.notifier).listMembers(widget.room.id);
            for (final m in members) {
              memberIds.add('${m['user_id'] ?? ''}');
            }
          } catch (_) {}
          if (!mounted) return;
          await showGroupInvitePicker(
            context: context,
            roomId: widget.room.id,
            excludeUids: memberIds,
            onInvited: () {
              // Anggota baru → segarkan daftar grupku (biar langsung ada
              // di tab Grup) + hitung ulang jumlah anggota tampilan.
              ProviderScope.containerOf(
                context,
                listen: false,
              ).read(roomProvider.notifier).loadMyGroups(refresh: true);
              setState(() {});
            },
          );
        }());
        break;
      case 'info':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                GroupInfoScreen(room: widget.room, myRole: _myRole ?? 'member'),
          ),
        );
        break;
      case 'media':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupMediaScreen(room: widget.room),
          ),
        );
        break;
      case 'search':
        _openRoomSearch();
        break;
      case 'mute':
        _toggleMute();
        break;
      case 'more':
        _showMoreMenu();
        break;
    }
  }

  Future<void> _toggleMute() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final next = !_muted;
    try {
      // Sinkron ke server (rooms.muted_by) + cermin lokal — model sama
      // dengan mute private chat, biar konsisten antar device.
      await _chat.muteRoom(widget.room.id, next);
      if (!mounted) return;
      setState(() => _muted = next);
      showChatSnack(context, next ? s.roomMutedOn : s.roomMutedOff);
    } catch (_) {}
  }

  /// Cari pesan dalam room: sheet hasil → tap lompat ke pesan
  /// (loadOlder berulang bila belum termuat, maks 10x).
  Future<void> _openRoomSearch() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    await showRoomSearchSheet(
      context,
      roomId: widget.room.id,
      s: s,
      onJump: _jumpToMessage,
    );
  }

  /// Lompat ke pesan: loadOlder berulang bila belum termuat (maks 10x),
  /// lalu scroll + highlight 2 detik.
  Future<void> _jumpToMessage(String id) async {
    if (id.isEmpty || _msgsHandle == null) return;
    for (var i = 0; i < 10 && !_lastMsgs.any((m) => m.id == id); i++) {
      try {
        await _msgsHandle!.loadOlder();
      } catch (_) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    final key = _msgKeys[id];
    final ctx = key?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    setState(() => _highlightId = id);
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _highlightId = null);
  }

  /// Submenu "Lainnya": keluar grup (+ hapus grup khusus owner).
  void _showMoreMenu() {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final isOwner = _myRole == 'owner';
    // Admin build boleh hapus SETIAP room (server cek owner/admin ulang).
    final canDelete = isOwner || AdminGate.enabled;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.exit_to_app_rounded),
              title: Text(s.menuExitGroup),
              onTap: () {
                Navigator.pop(ctx);
                _confirm(s.exitGroupTitle, s.exitGroupBody, _exitGroup);
              },
            ),
            if (canDelete)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.danger,
                ),
                title: Text(
                  s.menuDeleteGroup,
                  style: TextStyle(color: AppTheme.danger),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirm(s.deleteGroupTitle, s.deleteGroupBody, _deleteGroup);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirm(String title, String body, Future<void> Function() fn) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              ProviderScope.containerOf(
                context,
                listen: false,
              ).read(localeProvider).s.btnCancel,
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await fn();
            },
            child: Text(
              ProviderScope.containerOf(
                context,
                listen: false,
              ).read(localeProvider).s.btnDelete,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exitGroup() async {
    try {
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(roomProvider.notifier).leavePrivate(widget.room.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showChatSnack(
        context,
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(localeProvider).s.errGeneric,
        backgroundColor: AppTheme.danger,
      );
    }
  }

  Future<void> _deleteGroup() async {
    try {
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(roomProvider.notifier).deleteRoom(widget.room.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showChatSnack(
        context,
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(localeProvider).s.errGeneric,
        backgroundColor: AppTheme.danger,
      );
    }
  }

  Future<void> _openMembersSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => RoomMembersSheet(
        roomId: widget.room.id,
        myRole: _myRole ?? 'member',
        onChanged: () async {
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
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// Heartbeat presence: refresh joined_at tiap 60 detik selama room terbuka.
  /// Kalau app di-kill/force-stop, heartbeat berhenti → row presence basi
  /// dan otomatis hilang dari daftar online room setelah 5 menit.
  void _startPresenceHeartbeat() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final profile = _auth.profile;
      if (profile == null) return;
      _chat.joinRoom(widget.room.id, profile);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = _auth.uid;
    if (uid == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // App di-background/ditutup → keluar dari room supaya tidak jadi
      // ghost "online" di daftar member room.
      // Hentikan heartbeat presence juga — kalau tidak, timer terus
      // re-join tiap 60s dan membangkitkan row presence ghost.
      _presenceTimer?.cancel();
      _chat.leaveRoom(widget.room.id, uid);
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && _auth.profile != null) {
        _chat.joinRoom(widget.room.id, _auth.profile!);
        _startPresenceHeartbeat();
      }
    }
  }

  Future<void> _joinRoom() async {
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final chat = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatRiverpod.chatProvider.notifier);
    if (auth.profile != null) {
      await chat.joinRoom(widget.room.id, auth.profile!);
      await chat.loadBlockedUids(auth.uid!);
    }
  }

  @override
  void dispose() {
    hideActionBar();
    _reactionsSub?.cancel();
    _starredSub?.cancel();
    // conn listener dikelola Riverpod (ref.listen).
    ChatTextScale.notifier.removeListener(_onFontScaleChanged);
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _roomUsersEmptyTimer?.cancel();
    _livePoll?.cancel();
    _liveTimer?.cancel();
    _giftFly.dispose();
    unawaited(_msgsSub?.cancel());
    _msgsSub = null;
    unawaited(_usersSub?.cancel());
    _usersSub = null;
    try {
      final ch = _roomLiveChannel;
      _roomLiveChannel = null;
      if (ch != null) unawaited(Supabase.instance.client.removeChannel(ch));
    } catch (_) {}
    unawaited(_broadcastSession?.stop());
    // Keluar room WAJIB hentikan voice stage: tanpa ini mic tetap hidup
    // (track tidak di-stop) + speakerphone/wakelock tidak dilepas. Dulu
    // `stop()` voice hanya dipanggil saat user tap-tahan mic, bukan saat
    // keluar layar → "keluar room mic masih nyala".
    _voiceSession?.removeListener(_onVoiceChanged);
    unawaited(_voiceSession?.stop());
    _voiceSession = null;
    // DEFER: dispose berjalan saat widget tree terkunci (unmount IndexedStack
    // saat pindah tab) — menulis ValueNotifier sekarang memicu
    // markNeedsBuild pada CallBanner → glitch "widget tree was locked".
    final roomToClear = widget.room.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (activeChatId.value == roomToClear) activeChatId.value = null;
    });
    final uid = _auth.uid;
    if (uid != null) {
      _chat.leaveRoom(widget.room.id, uid);
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

}
