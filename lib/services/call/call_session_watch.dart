part of 'call_session.dart';

mixin _CallSessionWatchMx on _CallBase {
  Future<void> _handleWatchRequest(Map<String, dynamic> msg) async {
    final watcher = msg['from'] as String?;
    final me = _service.uid;
    if (_closed || watcher == null || watcher.isEmpty || watcher == me) return;
    // Bertarget: sinyal watch_request `to` peserta lain bukan untuk kita.
    // (Sinyal lama tanpa `to` tetap diterima demi kompat.)
    final to = msg['to'] as String?;
    if (!isWatchRequestForMe(to: to, me: me)) return;
    if (_localStream == null || _pc == null) {
      // Media belum siap (admin membuka monitor di detik-detik awal call) →
      // ANTRE, balas begitu siap. Dulu request dibuang → admin mengulang
      // menunggu tick berikutnya (audio telat beberapa detik).
      _pendingWatchRequests.add(watcher);
      return;
    }
    // Throttle: request ulang <8s diabaikan agar pc tidak dibuat-ulang
    // tiap polling; request setelah itu dianggap retry negosiasi mati.
    final last = _lastWatchReply[watcher];
    final repliedRecently =
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 8);
    // Kunci PENANDA SEBELUM await: dua request bersamaan (mis. realtime +
    // catch-up SELECT) sama-sama mengecek throttle saat masih kosong → dulu
    // dua-duanya lolos → pc/offer watch dobel → audio peserta putus-nyambung.
    _lastWatchReply[watcher] = DateTime.now();
    try {
      final isAdmin = await (_watcherAdminChecks.putIfAbsent(
        watcher,
        () => _service.isAdminUid(watcher),
      ));
      final existing = _watchPcs[watcher];
      final state = existing?.connectionState;
      final connected =
          state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      // Sehat = ada pc dan bukan failed/closed. Tapi pc yang BELUM connected
      // dan sudah berumur > _watchPcStale dianggap mati (offer hilang / ICE
      // nyangkut) → boleh rebuild supaya tidak deadlock.
      final createdAt = _watchPcCreatedAt[watcher];
      final stale =
          !connected &&
          createdAt != null &&
          DateTime.now().difference(createdAt) > _watchPcStale;
      final healthy =
          existing != null &&
          !stale &&
          state != RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          state != RTCPeerConnectionState.RTCPeerConnectionStateClosed;
      final action = decideWatchReply(
        isForMe: watcher != me,
        hasLocalMedia: _localStream != null && _pc != null,
        isAdminWatcher: isAdmin,
        alreadyRepliedRecently: repliedRecently,
        hasHealthyPc: healthy,
      );
      if (action == WatchReplyAction.ignore) return;
      // pc sehat → cukup kabari status; negosiasi/media TIDAK disentuh.
      if (action == WatchReplyAction.sendState) {
        _sendWatchState(watcher);
        dlog('[WATCH] pc healthy for watcher=$watcher → state only');
        return;
      }
      final old = _watchPcs.remove(watcher);
      if (old != null) {
        try {
          await old.close();
        } catch (_) {}
      }
      _watchPendingCands.remove(watcher);
      final pc = await createPeerConnection(await CallConfig.getPeerConfig());
      _watchPcs[watcher] = pc;
      _watchPcCreatedAt[watcher] = DateTime.now();
      PerfProbe.buildCount('call.watchPc');
      pc.onIceCandidate = (c) {
        _service.sendSignal(
          callId,
          'watch_candidate',
          payload: {'candidate': c.toMap(), 'to': watcher, 'from': me},
        );
      };
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _service.sendSignal(
        callId,
        'watch_offer',
        payload: {
          'sdp': offer.toMap(),
          'to': watcher,
          'from': me,
          'micOn': _micOn,
          'cameraOn': callType == 'video' ? _cameraOn : false,
        },
      );
      dlog('[WATCH] offer sent to watcher=$watcher');
    } catch (e) {
      dlog('[WATCH] handle watch_request failed: $e');
      final broken = _watchPcs.remove(watcher);
      _watchPcCreatedAt.remove(watcher);
      try {
        await broken?.close();
      } catch (_) {}
    }
  }

  /// Balas permintaan pantau yang diantre karena media lokal belum siap.
  Future<void> _flushPendingWatchRequests() async {
    if (_pendingWatchRequests.isEmpty) return;
    final uids = _pendingWatchRequests.toList();
    _pendingWatchRequests.clear();
    for (final uid in uids) {
      if (_closed) return;
      await _handleWatchRequest({'from': uid});
    }
  }

  /// Kirim ulang status mic/kamera ke satu watcher (tanpa rebuild pc).
  void _sendWatchState(String watcher) {
    _service.sendSignal(
      callId,
      'watch_state',
      payload: {
        'micOn': _micOn,
        'cameraOn': callType == 'video' ? _cameraOn : false,
        'to': watcher,
        'from': _service.uid,
      },
    );
  }

  Future<void> _handleWatchAnswer(Map<String, dynamic> msg) async {
    final watcher = msg['from'] as String?;
    final me = _service.uid;
    if (msg['to'] != me || watcher == null) return;
    final pc = _watchPcs[watcher];
    final sdp = msg['sdp'] as Map<String, dynamic>?;
    if (pc == null || sdp == null) return;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
      for (final c in List<Map<String, dynamic>>.from(
        _watchPendingCands[watcher] ?? const [],
      )) {
        try {
          await pc.addCandidate(
            RTCIceCandidate(
              c['candidate'] ?? '',
              c['sdpMid'],
              (c['sdpMLineIndex'] as num?)?.toInt(),
            ),
          );
        } catch (_) {}
      }
      _watchPendingCands.remove(watcher);
    } catch (e) {
      dlog('[WATCH] handle watch_answer failed: $e');
    }
  }

  Future<void> _handleWatchCandidate(Map<String, dynamic> msg) async {
    final me = _service.uid;
    if (msg['to'] != me) return;
    final watcher = msg['from'] as String?;
    final c = msg['candidate'] as Map<String, dynamic>?;
    if (watcher == null || c == null) return;
    final pc = _watchPcs[watcher];
    if (pc == null) return;
    try {
      final rd = await pc.getRemoteDescription();
      if (rd == null) {
        _watchPendingCands.putIfAbsent(watcher, () => []).add(c);
        return;
      }
      await pc.addCandidate(
        RTCIceCandidate(
          c['candidate'] ?? '',
          c['sdpMid'],
          (c['sdpMLineIndex'] as num?)?.toInt(),
        ),
      );
    } catch (e) {
      dlog('[WATCH] candidate error: $e');
    }
  }

  /// Kabari semua watcher status mic/kamera terbaru (overlay admin).
  void _notifyWatchersState() {
    final me = _service.uid;
    if (me == null) return;
    for (final watcher in _watchPcs.keys.toList()) {
      _service.sendSignal(
        callId,
        'watch_state',
        payload: {
          'micOn': _micOn,
          'cameraOn': callType == 'video' ? _cameraOn : false,
          'to': watcher,
          'from': me,
        },
      );
    }
  }

  /// Re-fetch semua call_signals (offer/candidates) dari DB dan proses
  /// yang belum diproses. Menjamin tidak ada kandidat yang terlewat akibat
  /// race antara realtime broadcast dan catch-up SELECT.
  /// Juga cek status call di DB sebagai fallback bila realtime statusSub miss.
  DateTime? _lastTouch;

  /// Heartbeat ke server — admin monitor pakai ini untuk membedakan call
  /// yang masih hidup vs call zombie (app ditutup paksa di tengah call).
  ///
  /// Interval 25 dtk (dulu 15). Ambang zombie server (`admin_sweep_calls`)
  /// = `last_seen_at` lebih tua dari 75 dtk. Dengan 25 dtk, worst-case
  /// (satu tick terlewat karena jaringan) = 50 dtk < 75 dtk → margin 3×.
  /// Untuk call panjang (30 mnt) ini memangkas ~40% write heartbeat
  /// (120 → 72 update) tanpa memperbesar risiko call zombie.
  void _touchHeartbeat() {
    final now = DateTime.now();
    if (_lastTouch != null && now.difference(_lastTouch!).inSeconds < 25) {
      return;
    }
    _lastTouch = now;
    _service.touchCall(callId);
  }
}
