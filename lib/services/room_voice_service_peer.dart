part of 'room_voice_service.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _VoicePeerMx on _VoiceBase {
  Future<void> _applyForcedMute() async {
    if (!_onStage) return;
    try {
      for (final t in _localStream?.getAudioTracks() ?? const []) {
        t.enabled = false;
      }
    } catch (_) {}
    _muted = true;
    await stopSpeaking(announce: false);
    await _sendSignal(type: 'v_mute', payload: {'muted': true});
    onMutedByAdmin?.call();
    if (!_closed) notifyListeners();
  }

  // ── Daftar speaker (realtime table + refresh) ──
  Future<void> _refreshSpeakers() async {
    if (_closed) return;
    try {
      // Baca langsung (RLS select mengizinkan); fallback: biarkan state lama.
      final rows = await _sb
          .from('room_voice_speakers')
          .select('uid')
          .eq('room_id', roomId)
          .limit(20);
      final ids = <String>{
        for (final r in (rows as List? ?? const []))
          '${(r as Map)['uid'] ?? ''}',
      }..removeWhere((e) => e.isEmpty);
      // Baris server milikku dari SESI SEBELUMNYA (keluar-masuk cepat,
      // leave belum diproses) jangan dianggap stage-ku sekarang — stage-ku
      // ditentukan state lokal. Selalu sertakan diriku bila di stage
      // (heartbeat-ku mungkin belum terbaca realtime).
      ids.remove(myUid);
      if (_onStage) ids.add(myUid);
      _applySpeakers(ids);
    } catch (_) {}
  }

  void _applySpeakers(Iterable<String> ids) {
    final next = Set<String>.from(ids)..removeWhere((e) => e.isEmpty);
    // FULL MESH: bila aku di stage, tawarkan uplink ke speaker lain yang
    // BELUM punya pc (baru muncul di daftar). Menjamin tiap pasangan
    // terbentuk walau `v_speak`/v_join terlewat (realtime telat). Idempoten:
    // `_makeOfferTo` guard `_offerBusy` + cek pc existing.
    if (_onStage) {
      for (final uid in next) {
        if (meshNeedsOfferTo(
          myUid: myUid,
          peerUid: uid,
          onStage: _onStage,
          hasUplinkPc: _peers.containsKey(uid),
        )) {
          unawaited(_makeOfferTo(uid));
        }
      }
    }
    // Peer yang hilang dari stage → drop.
    // PENTING: iterasi hanya pc UPLINK (key uid asli). Key downlink `dn_<uid>`
    // TIDAK boleh dibandingkan dengan daftar speaker (next berisi uid tanpa
    // prefix) — dulu `dn_B` dianggap "bukan speaker" → downlink dari B
    // DIBUANG tiap refresh daftar speaker → koneksi mesh terus dibongkar
    // (gejala "3 orang semua muter-putus"). Downlink dibersihkan lewat
    // `_dropPeer`/v_bye saat peer benar-benar keluar, bukan di sini.
    for (final uid in _peers.keys.toList()) {
      if (uid.startsWith('dn_')) continue;
      if (uid == myUid) continue;
      if (!next.contains(uid) && !_joinSentTo.contains(uid)) {
        unawaited(_dropPeer(uid));
      }
    }
    _speakers
      ..clear()
      ..addAll(next);
    if (_onStage) _speakers.add(myUid);
    _speakerCount = _speakers.length;
    notifyListeners();
  }

  // ── Offer/answer/candidate: TRICKLE ICE ──
  // Offer/answer dikirim SEGERA setelah setLocalDescription; kandidat menyusul
  // via v_cand (antrean _pendingCands menampung yang datang duluan).
  // Dulu non-trickle (tunggu gathering ≤2 dtk) → handshake lambat + macet
  // total bila gathering tak kunjung complete di jaringan aneh.

  Future<void> _makeOfferTo(String peerUid) async {
    if (_closed || !_onStage || _localStream == null) return;
    if (peerUid.isEmpty || peerUid == myUid) return;
    if (_offerBusy.contains(peerUid)) return;
    _offerBusy.add(peerUid);
    try {
      // Uplink ke peerUid ada di key `peerUid`; downlink dari peerUid yang
      // sama ada di key `dn_$peerUid` (mesh dua arah: aku dengar dia VIA pc
      // downlink, dia dengar aku VIA pc uplink). Key BERBEDA → tak saling
      // timpa. Tutup hanya pc uplink yang mungkin sudah ada (rebuild offer
      // segar) — JANGAN sentuh pc downlink.
      final old = _peers[peerUid];
      if (old != null) {
        // pc existing masih hidup/menghubung → JANGAN rebuild (dulu selalu
        // close → memutus koneksi sehat yang sudah Connecting/Connected).
        final st = old.connectionState;
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
          return;
        }
        try {
          await old.close();
        } catch (_) {}
        _peers.remove(peerUid);
        _pcIds.remove(peerUid);
        _pendingCands.remove(peerUid);
      }
      final pc = await createPeerConnection(
        await CallConfig.getPeerConfig(relayOnly: _relayOnlyFor(peerUid)),
      );
      _peers[peerUid] = pc;
      // Set pcId LEBIH DULU: onIceCandidate di bawah membacanya saat kandidat
      // mengalir (yang bisa mulai tepat setelah setLocalDescription) — bila
      // di-set belakangan, kandidat pertama terkirim dengan pcId null →
      // penerima tak bisa me-routing → ICE gagal ("spinner muter terus").
      final pcId = 'up_${DateTime.now().microsecondsSinceEpoch}';
      _pcIds[peerUid] = pcId;
      _uplinkSince.putIfAbsent(peerUid, () => DateTime.now());
      final tracks = _localStream!.getAudioTracks();
      if (tracks.isEmpty) return;
      await pc.addTrack(tracks.first, _localStream!);
      // Opus low-latency + FEC: setelah addTrack (transceiver ada) & sebelum
      // createOffer. Best-effort (pola call 1:1 _preferOpusCodec).
      await _preferOpusCodec(pc);
      pc.onIceCandidate = (c) {
        _sendSignal(
          type: 'v_cand',
          toUid: peerUid,
          payload: {
            'candidate': c.toMap(),
            // pcId arah uplink TARGET — agar penerima menaruh kandidat ke pc
            // downlink yang benar (bukan tertukar saat mesh dua arah).
            'pcId': _pcIds[peerUid],
            'dir': 'down',
          },
        );
      };
      pc.onConnectionState = (st) {
        if (!identical(_peers[peerUid], pc)) return;
        // Connected = uplink hidup → matikan status pairing.
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _uplinkOk.add(peerUid);
        } else if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _uplinkOk.remove(peerUid);
        }
        // Disconnected SERING transient di Android (jaringan goyang) & ICE
        // pulih sendiri — JANGAN langsung re-offer/close (dulu ini memutus
        // koneksi sehat → audio "kadang ada kadang muter"). Cukup serahkan
        // ke watchdog (_reOfferTimer) yang menunggu >10 dtk sebelum membangun
        // ulang. Failed/Closed = benar-benar mati → drop + jadwalkan re-join
        // terarah agar koneksi pulih sendiri (bukan hilang sampai lawan join).
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          unawaited(_dropPeer(peerUid));
          if (_onStage && !_closed && _speakers.contains(peerUid)) {
            Future.delayed(const Duration(seconds: 2), () {
              if (_closed || !_onStage) return;
              if (_peers.containsKey(peerUid)) return;
              if (!_speakers.contains(peerUid)) return;
              unawaited(
                _sendSignal(
                  type: 'v_join',
                  toUid: peerUid,
                  payload: {
                    'ts': DateTime.now().toIso8601String(),
                    'sess': sessId,
                  },
                ),
              );
            });
          }
        }
        notifyListeners();
      };
      final offer = await pc.createOffer();
      // Opus low-latency + FEC (helper yang sama dengan call 1:1).
      final offerMunged = applyOpusLowLatencyPrefs(offer.sdp ?? '');
      final localOffer = RTCSessionDescription(
        offerMunged.isEmpty ? (offer.sdp ?? '') : offerMunged,
        offer.type,
      );
      await pc.setLocalDescription(localOffer);
      // Trickle: kirim LANGSUNG (tanpa tunggu gathering) — kandidat susul.
      final desc = await pc.getLocalDescription();
      _offerSentAt[peerUid] = DateTime.now();
      await _sendSignal(
        type: 'v_offer',
        toUid: peerUid,
        payload: {
          'sdp': (desc ?? offer).toMap(),
          'pcId': pcId,
          // Beritahu policy ICE-ku agar penerima MIRROR (dua arah konsisten).
          // Bila aku sudah fallback all-candidates, penerima ikut melepas
          // relay-only → negosiasi punya kandidat yang bisa berpasangan.
          'relay': _relayOnlyFor(peerUid),
        },
      );
      notifyListeners();
    } catch (e) {
      dlog('[VOICE] offer to $peerUid failed: $e');
    } finally {
      _offerBusy.remove(peerUid);
    }
  }

  Future<void> _handleOffer(String from, Map<String, dynamic> payload) async {
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    if (sdp == null || _closed) return;
    final offerPcId = '${payload['pcId'] ?? ''}';
    // MIRROR policy ICE pengirim: bila dia offer dengan all-candidates
    // (relay=false), tandai peer ini juga → pc jawabanku pakai all-candidates
    // agar kandidat dua arah bisa berpasangan (mencegah mixed relay/host
    // yang tak pernah connect).
    if (payload['relay'] == false) {
      _allCandTriedPeers.add(from);
    }
    try {
      // Downlink selalu key 'dn_$from' (terpisah dari uplink key `from`).
      final key = 'dn_$from';
      var pc = _peers[key];
      if (pc != null) {
        // Offer duplikat (retry lawan) saat downlink MASIH hidup → abaikan,
        // jangan close-rebuild (dulu ini memutus audio yang sedang jalan).
        final st = pc.connectionState;
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
          return;
        }
        // GLARE/dedup: offer dengan pcId yang SAMA & remoteDescription sudah
        // terpasang = duplikat (realtime + burst sync). Jangan close-rebuild
        // — rebuild saat state have-remote-offer memicu error
        // "cannot createAnswer in state other than have-remote-offer" saat
        // negosiasi mesh 3+ orang.
        if (offerPcId.isNotEmpty && _pcIds[key] == offerPcId) {
          final rd = await pc.getRemoteDescription();
          if (rd != null) return;
        }
        try {
          await pc.close();
        } catch (_) {}
        _peers.remove(key);
      }
      pc = await createPeerConnection(
        await CallConfig.getPeerConfig(relayOnly: _relayOnlyFor(from)),
      );
      _peers[key] = pc;
      // Tandai arah downlink + pcId supaya routing kandidat ICE pasti
      // (bukan lagi menebak via containsKey yang ambigu saat mesh dua arah).
      final dnPcId = offerPcId.isNotEmpty
          ? offerPcId
          : 'dn_${DateTime.now().microsecondsSinceEpoch}';
      _pcIds[key] = dnPcId;
      pc.onConnectionState = (st) {
        if (_closed || !identical(_peers[key], pc)) return;
        // Connected = downlink sehat → bersihkan timer re-join.
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _lastJoinReqAt.remove(from);
          notifyListeners();
          return;
        }
        // Disconnected transient (Android) → ICE biasanya pulih sendiri,
        // JANGAN langsung minta join ulang (dulu memicu close+rebuild yang
        // memutus audio). Failed/Closed = benar-benar mati baru re-join.
        final hardDead =
            st == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            st == RTCPeerConnectionState.RTCPeerConnectionStateClosed;
        if (hardDead) {
          _remoteStreams.remove(from);
          _speakingNow.remove(from);
          // Downlink mati total: minta offer ulang ke speaker (dia yang
          // pegang uplink). Debounce 4 dtk; hanya bila dia masih di stage.
          if (_speakers.contains(from)) {
            final now = DateTime.now();
            final last = _lastJoinReqAt[from];
            if (last == null ||
                now.difference(last) > const Duration(seconds: 4)) {
              _lastJoinReqAt[from] = now;
              unawaited(
                _sendSignal(
                  type: 'v_join',
                  toUid: from,
                  payload: {'ts': now.toIso8601String(), 'sess': sessId},
                ),
              );
            }
          }
          notifyListeners();
        }
      };
      // FALLBACK relay→all-candidates untuk PENDENGAR (tanpa pc uplink —
      // watchdog `_reOfferTimer` hanya iterasi uplink). Bila downlink ini
      // belum Connected setelah 6 dtk & masih relay-only → buka semua
      // kandidat. `_retryPeerAllCandidates` menutup pc ini & minta offer
      // ulang (v_join) → dibangun lagi dengan config all-candidates.
      final dnPc = pc;
      Future.delayed(const Duration(seconds: 6), () {
        if (_closed || !identical(_peers[key], dnPc)) return;
        if (dnPc.connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          return;
        }
        if (_relayOnlyFor(from)) unawaited(_retryPeerAllCandidates(from));
      });
      pc.onTrack = (event) async {
        // Fallback: sebagian device tak mengirim event.streams → bikin
        // stream sendiri agar audio tetap disimpan & diputar (pola call).
        var stream = event.streams.isNotEmpty ? event.streams.first : null;
        if (stream == null) {
          stream = await createLocalMediaStream('remote-$from');
          try {
            await stream.addTrack(event.track);
          } catch (_) {}
        }
        if (!_closed) {
          _remoteStreams[from] = stream;
          notifyListeners();
        }
      };
      pc.onIceCandidate = (c) {
        _sendSignal(
          type: 'v_cand',
          toUid: from,
          payload: {
            'candidate': c.toMap(),
            // pcId arah downlink-ku TARGET (offerPcId dari speaker) — agar
            // speaker menaruh kandidat ke pc uplink yang benar.
            'pcId': dnPcId,
            'dir': 'up',
          },
        );
      };
      await pc.setRemoteDescription(
        RTCSessionDescription(_munged(sdp['sdp']), sdp['type']),
      );
      for (final c in List<Map<String, dynamic>>.from(
        _pendingCands[dnPcId] ?? const [],
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
      _pendingCands.remove(dnPcId);
      // Opus low-latency + FEC untuk audio jawaban (setelah setRemoteDescription
      // offer, sebelum createAnswer). Best-effort.
      await _preferOpusCodec(pc);
      final answer = await pc.createAnswer();
      final answerMunged = applyOpusLowLatencyPrefs(answer.sdp ?? '');
      final localAnswer = RTCSessionDescription(
        answerMunged.isEmpty ? (answer.sdp ?? '') : answerMunged,
        answer.type,
      );
      await pc.setLocalDescription(localAnswer);
      // Trickle: kirim LANGSUNG (tanpa tunggu gathering) — kandidat susul.
      final desc = await pc.getLocalDescription();
      await _sendSignal(
        type: 'v_answer',
        toUid: from,
        payload: {'sdp': (desc ?? answer).toMap(), 'pcId': offerPcId},
      );
    } catch (e) {
      dlog('[VOICE] handle offer from $from failed: $e');
    }
  }

  Future<void> _handleAnswer(String from, Map<String, dynamic> payload) async {
    final sdp = payload['sdp'] as Map<String, dynamic>?;
    final pc = _peers[from];
    if (sdp == null || pc == null || _closed) return;
    final pcId = '${payload['pcId'] ?? ''}';
    if (pcId.isNotEmpty && pcId != (_pcIds[from] ?? '')) return;
    try {
      final local = await pc.getLocalDescription();
      if (local == null || local.type != 'offer') return;
      final remote = await pc.getRemoteDescription();
      if (remote != null) return;
      await pc.setRemoteDescription(
        RTCSessionDescription(_munged(sdp['sdp']), sdp['type']),
      );
      _offerSentAt.remove(from);
      // Flush kandidat tertunda untuk pc uplink ini via pcId (konsisten
      // dengan key yang dipakai _handleCandidate).
      final upPcId = _pcIds[from] ?? '';
      final pend = upPcId.isNotEmpty ? _pendingCands[upPcId] : null;
      for (final c in List<Map<String, dynamic>>.from(pend ?? const [])) {
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
      if (upPcId.isNotEmpty) _pendingCands.remove(upPcId);
    } catch (e) {
      dlog('[VOICE] answer from $from failed: $e');
    }
  }

  Future<void> _handleCandidate(
    String from,
    Map<String, dynamic> payload,
  ) async {
    final c = payload['candidate'] as Map<String, dynamic>?;
    if (c == null || _closed) return;
    // Routing PASTI via pcId yang dikirim: cari pc yang _pcIds-nya cocok.
    // Sebelumnya menebak via containsKey(from) → ambigu saat mesh dua arah
    // (uid sama punya pc uplink `from` DAN downlink `dn_from`) → kandidat
    // masuk slot salah → ICE gagal / "mic hijau tapi bisu".
    final candPcId = '${payload['pcId'] ?? ''}';
    final key = resolveCandidateKey(
      from: from,
      candPcId: candPcId,
      dir: '${payload['dir'] ?? ''}',
      pcIds: _pcIds,
      peerKeys: _peers.keys.toSet(),
    );
    // Key simpan kandidat tertunda = pcId bila ada (agar flush cocok),
    // else key peer.
    final storeKey = candPcId.isNotEmpty ? candPcId : key;
    final pc = _peers[key];
    if (pc == null) {
      _pendingCands.putIfAbsent(storeKey, () => []).add(c);
      return;
    }
    try {
      final remote = await pc.getRemoteDescription();
      if (remote == null) {
        _pendingCands.putIfAbsent(storeKey, () => []).add(c);
        return;
      }
    } catch (_) {
      _pendingCands.putIfAbsent(storeKey, () => []).add(c);
      return;
    }
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

  /// Fallback relay-only → semua kandidat (host/srflx/relay) UNTUK SATU PEER.
  /// Dipakai bila relay-only belum juga Connected (TURN tak terjangkau / NAT
  /// sama) — menyelamatkan audio mesh walau Cloudflare TURN mati. SEKALI per
  /// peer (guard `_allCandTriedPeers`). Beda dari call 1:1 (pc tunggal): di
  /// mesh, satu peer punya pc uplink (`uid`) & downlink (`dn_uid`) — keduanya
  /// dibangun ulang dengan config all-candidates supaya konsisten dua arah.
  Future<void> _retryPeerAllCandidates(String peerUid) async {
    if (_closed) return;
    if (!_allCandTriedPeers.add(peerUid)) return; // sudah pernah → stop
    dlog('[VOICE] fallback relay→all-candidates untuk $peerUid');
    // Tutup pc uplink + downlink peer ini agar negosiasi dibangun ulang
    // dengan config baru (bukan menambah offer di pc relay lama).
    for (final k in [peerUid, 'dn_$peerUid']) {
      final pc = _peers.remove(k);
      try {
        await pc?.close();
      } catch (_) {}
      _pendingCands.remove(k);
      _pcIds.remove(k);
      _offerSentAt.remove(k);
    }
    _uplinkOk.remove(peerUid);
    _uplinkSince[peerUid] = DateTime.now();
    if (_closed) return;
    // Uplink: aku (jika di stage) tawarkan ulang dengan all-candidates.
    if (_onStage && _speakers.contains(peerUid)) {
      unawaited(_makeOfferTo(peerUid));
    }
    // Downlink: minta speaker menawarkan ulang (dia pegang uplink ke aku).
    if (_speakers.contains(peerUid)) {
      unawaited(
        _sendSignal(
          type: 'v_join',
          toUid: peerUid,
          payload: {'ts': DateTime.now().toIso8601String(), 'sess': sessId},
        ),
      );
    }
  }

  Future<void> _dropPeer(String uid) async {
    _uplinkOk.remove(uid);
    _uplinkSince.remove(uid);
    for (final k in [uid, 'dn_$uid']) {
      final pc = _peers.remove(k);
      try {
        await pc?.close();
      } catch (_) {}
      _pendingCands.remove(k);
      _pcIds.remove(k);
      _offerSentAt.remove(k);
    }
    _remoteStreams.remove(uid);
    _speakingNow.remove(uid);
    // Peer benar-benar lepas → reset fallback agar koneksi berikutnya ke peer
    // ini mencoba relay-only dulu lagi (config terbaik), bukan terjebak
    // all-candidates dari sesi sebelumnya.
    _allCandTriedPeers.remove(uid);
    notifyListeners();
  }

  // ── Indikator bicara via getStats audioLevel (inbound-rtp audio) ──
  Future<void> _pollLevels() async {
    if (_closed || _peers.isEmpty) {
      if (_speakingNow.isNotEmpty) {
        _speakingNow.clear();
        notifyListeners();
      }
      return;
    }
    final next = <String>{};
    for (final entry in _peers.entries) {
      final key = entry.key;
      final uid = key.startsWith('dn_') ? key.substring(3) : key;
      // Hanya downlink (suara masuk) yang diukur.
      if (!key.startsWith('dn_')) continue;
      try {
        final stats = await entry.value.getStats();
        for (final r in stats) {
          if (r.type != 'inbound-rtp') continue;
          final v = r.values['audioLevel'];
          final level = v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
          if (level > 0.02) next.add(uid);
          break;
        }
      } catch (_) {}
    }
    if (next.length != _speakingNow.length || !next.containsAll(_speakingNow)) {
      _speakingNow
        ..clear()
        ..addAll(next);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
