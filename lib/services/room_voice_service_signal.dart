part of 'room_voice_service.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _VoiceSignalMx on _VoiceBase {
  Future<void> _preferOpusCodec(RTCPeerConnection pc) async {
    if (_closed) return;
    try {
      final transceivers = await pc.getTransceivers();
      for (final t in transceivers) {
        try {
          final kind = t.receiver.track?.kind;
          if (kind != null && kind != 'audio') continue;
          await t.setCodecPreferences([
            RTCRtpCodecCapability(
              mimeType: 'audio/opus',
              clockRate: 48000,
              channels: 2,
              sdpFmtpLine: 'minptime=10;useinbandfec=1',
            ),
          ]);
        } catch (_) {}
      }
    } catch (_) {}
  }

  // ── Mute/unmute mic sendiri (tetap di stage, tanpa renegosiasi). ──
  // Pakai DUA jalur agar benar-benar senyap di semua device:
  //  (1) track.enabled=false (lewat API track),
  //  (2) Helper.setMicrophoneMute (mute di AudioDeviceModule native) — pada
  //      sebagian device `enabled=false` saja TIDAK memutus mic ("mic di-off
  //      tapi tetap kedengar"). Native mute menutup celah itu.
  Future<void> setMuted(bool value) async {
    if (!_onStage) return;
    _muted = value;
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      try {
        t.enabled = !value;
      } catch (_) {}
      try {
        await Helper.setMicrophoneMute(value, t);
      } catch (_) {}
    }
    await _sendSignal(type: 'v_mute', payload: {'muted': value});
    notifyListeners();
  }

  // ── Tutup total (keluar voice). ──
  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    // Kembalikan route audio ke default (lepas speakerphone paksa).
    await _setSpeakerphone(false);
    _hbTimer?.cancel();
    _syncTimer?.cancel();
    _reOfferTimer?.cancel();
    _levelTimer?.cancel();
    _speakersPollTimer?.cancel();
    await _signalSub?.cancel();
    for (final ch in [_signalChannel, _speakersChannel]) {
      if (ch == null) continue;
      try {
        _sb.removeChannel(ch);
      } catch (_) {}
    }
    _signalChannel = null;
    _speakersChannel = null;
    if (_onStage) {
      _onStage = false;
      try {
        await _sb.rpc('room_voice_leave', params: {'p_room_id': roomId});
      } catch (_) {}
      await _sendSignal(type: 'v_bye', payload: {'sess': sessId});
    }
    _uplinkOk.clear();
    _peerSess.clear();
    _lastJoinReqAt.clear();
    _uplinkSince.clear();
    // Matikan mic DULU (native) lalu stop track — sebagian device tidak
    // melepas mic hanya dengan track.stop() ("keluar room mic masih nyala").
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      try {
        await Helper.setMicrophoneMute(true, t);
      } catch (_) {}
      try {
        t.enabled = false;
      } catch (_) {}
      try {
        t.stop();
      } catch (_) {}
    }
    _localStream = null;
    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();
    _remoteStreams.clear();
    _speakers.clear();
    _speakerMuted.clear();
    _speakingNow.clear();
    _pendingCands.clear();
    _pcIds.clear();
    _offerSentAt.clear();
    _joinSentTo.clear();
    _allCandTriedPeers.clear();
    onEnded?.call();
    // dispose() memanggil stop() lalu super.dispose() — notify di sini
    // akan melempar "used after dispose". Lewati bila sudah dispose.
    if (!_disposed) notifyListeners();
  }

  // ── Sinyal ──
  Stream<Map<String, dynamic>> _onSignalStream() {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final channel = _sb.channel('room-voice-$roomId-$myUid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'room_voice_signals',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        final row = Map<String, dynamic>.from(payload.newRecord);
        if ('${row['from_uid']}' == myUid) return;
        // Hanya untukku atau broadcast.
        final to = '${row['to_uid'] ?? ''}';
        if (to.isNotEmpty && to != myUid) return;
        controller.add(row);
      },
    );
    channel.subscribe((status, err) {
      if (err != null) dlog('[RoomVoice] signal realtime error: $err');
    });
    _signalChannel = channel;
    controller.onCancel = () {
      try {
        _sb.removeChannel(channel);
      } catch (_) {}
    };
    return controller.stream;
  }

  Future<void> _sendSignal({
    required String type,
    String? toUid,
    Map<String, dynamic> payload = const {},
  }) async {
    try {
      await _sb.from('room_voice_signals').insert({
        'room_id': roomId,
        'from_uid': myUid,
        'to_uid': toUid,
        'type': type,
        'payload': payload,
      });
    } catch (e) {
      dlog('[VOICE] sendSignal $type error: $e');
    }
  }

  Future<void> _syncMissedSignals() async {
    if (_closed) return;
    try {
      final rows = await _sb
          .from('room_voice_signals')
          .select()
          .eq('room_id', roomId)
          .gt('id', _lastSignalId)
          .gte(
            'created_at',
            DateTime.now()
                .toUtc()
                .subtract(const Duration(seconds: 30))
                .toIso8601String(),
          )
          .order('id')
          .limit(200);
      for (final r in (rows as List? ?? const [])) {
        final m = Map<String, dynamic>.from(r as Map);
        _lastSignalId = max(_lastSignalId, ((m['id'] ?? 0) as num).toInt());
        _onSignal(m);
      }
    } catch (_) {}
  }

  Future<void> _fastForwardSignals() async {
    try {
      final row = await _sb
          .from('room_voice_signals')
          .select('id')
          .eq('room_id', roomId)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();
      _lastSignalId = (((row as Map?) ?? const {})['id'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  void _onSignal(Map<String, dynamic> sig) {
    if (_closed) return;
    final sid = ((sig['id'] ?? 0) as num).toInt();
    if (sid > 0) {
      if (!_seenSignalIds.add(sid)) return;
      _lastSignalId = max(_lastSignalId, sid);
    }
    final ca = DateTime.tryParse('${sig['created_at'] ?? ''}');
    if (ca != null &&
        DateTime.now().toUtc().difference(ca.toUtc()) >
            const Duration(seconds: 30)) {
      return;
    }
    final type = '${sig['type'] ?? ''}';
    final from = '${sig['from_uid'] ?? ''}';
    if (from.isEmpty || from == myUid) return;
    final payload = (sig['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    switch (type) {
      case 'v_speak':
        // Speaker baru (X) mengumumkan diri.
        // Catat generasinya — v_bye lebih tua dari ini diabaikan.
        final speakSess = (payload['sess'] as num?)?.toInt();
        if (speakSess != null) {
          final known = _peerSess[from] ?? -1;
          if (speakSess > known) _peerSess[from] = speakSess;
        }
        _joinSentTo.add(from);
        _speakers.add(from);
        // FULL MESH 3-6 orang: tiap pasangan butuh DUA arah audio (aku→X dan
        // X→aku). Bila aku JUGA di stage, aku harus menawarkan uplink-ku ke X
        // (aku→X). Tanpa ini arah dari speaker-lama ke speaker-baru TIDAK
        // pernah terbentuk (hanya v_join → X offer ke aku = X→aku) → bertiga
        // sebagian pasangan bisu. Bila aku pendengar (tidak di stage), cukup
        // balas v_join (minta X offer ke aku).
        if (_onStage) {
          unawaited(_makeOfferTo(from));
        } else {
          unawaited(
            _sendSignal(
              type: 'v_join',
              toUid: from,
              payload: {'ts': DateTime.now().toIso8601String(), 'sess': sessId},
            ),
          );
        }
        notifyListeners();
        break;
      case 'v_join':
        // Pendengar minta audio → aku offer (hanya bila aku di stage).
        if (_onStage) unawaited(_makeOfferTo(from));
        break;
      case 'v_offer':
        {
          final ca2 =
              DateTime.tryParse('${sig['created_at'] ?? ''}') ??
              DateTime.now().toUtc();
          final last = _lastOfferAt[from];
          if (last != null && !ca2.isAfter(last)) return;
          _lastOfferAt[from] = ca2;
          unawaited(_handleOffer(from, payload));
        }
        break;
      case 'v_answer':
        unawaited(_handleAnswer(from, payload));
        break;
      case 'v_cand':
        unawaited(_handleCandidate(from, payload));
        break;
      case 'v_bye':
        {
          // Abaikan v_bye basi: teardown sesi lama yang telat tiba setelah
          // user keluar-masuk cepat (sesi baru sudah v_speak duluan).
          final byeSess = (payload['sess'] as num?)?.toInt() ?? -1;
          final knownSess = _peerSess[from] ?? -1;
          if (byeSess >= 0 && isStaleBye(knownSess, byeSess)) break;
          _peerSess.remove(from);
          unawaited(_dropPeer(from));
          _speakers.remove(from);
          _speakerMuted.remove(from);
          _speakingNow.remove(from);
          notifyListeners();
        }
        break;
      case 'v_mute':
        {
          final to = '${sig['to_uid'] ?? ''}';
          if (to.isNotEmpty && to != myUid) break;
          final muted = payload['muted'] != false;
          if (to == myUid) {
            // Mute paksa admin/owner: matikan track + turun stage.
            unawaited(_applyForcedMute());
          } else {
            _speakerMuted[from] = muted;
            if (muted) _speakingNow.remove(from);
            notifyListeners();
          }
        }
        break;
    }
  }
}
