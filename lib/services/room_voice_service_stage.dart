part of 'room_voice_service.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _VoiceStageMx on _VoiceBase {
  /// Snapshot diagnostik untuk sheet debug di HP (tap avatar sendiri).
  /// Isi: state sesi + per-peer (conn/ice/pasangan kandidat terpilih +
  /// level audio in/out). Semua best-effort + timeout — tak boleh hang.
  Future<Map<String, dynamic>> diagnostics() async {
    final peers = <String, dynamic>{};
    double? micLevel;
    for (final entry in _peers.entries.toList()) {
      final key = entry.key;
      final pc = entry.value;
      final isDown = key.startsWith('dn_');
      final info = <String, dynamic>{
        'dir': isDown ? 'down' : 'up',
        'conn': _shortState('${pc.connectionState}'),
        'ice': _shortState('${pc.iceConnectionState}'),
      };
      try {
        final stats = await pc.getStats().timeout(const Duration(seconds: 2));
        final byId = <String, dynamic>{};
        for (final r in stats as List? ?? const []) {
          try {
            byId['${(r as dynamic).id}'] = r;
          } catch (_) {}
        }
        String? pairDesc;
        for (final r in byId.values) {
          try {
            final d = r as dynamic;
            if ('${d.type}' != 'candidate-pair') continue;
            final v = Map<String, dynamic>.from(d.values as Map? ?? {});
            final nominated = v['nominated'] == true;
            if (!nominated && pairDesc != null) continue;
            final loc = byId['${v['localCandidateId']}'];
            final rem = byId['${v['remoteCandidateId']}'];
            String cand(Map<String, dynamic>? m) {
              if (m == null) return '?';
              return '${m['candidateType'] ?? '?'}'
                  '/${m['protocol'] ?? '?'}';
            }

            Map<String, dynamic>? vals(dynamic x) {
              try {
                return Map<String, dynamic>.from(x.values as Map);
              } catch (_) {
                return null;
              }
            }

            pairDesc =
                '${cand(vals(loc))}>${cand(vals(rem))}'
                ' ${v['state'] ?? ''}';
            if (nominated) break;
          } catch (_) {}
        }
        if (pairDesc != null) info['pair'] = pairDesc;
        for (final r in byId.values) {
          try {
            final d = r as dynamic;
            final t = '${d.type}';
            if (t != 'inbound-rtp' && t != 'outbound-rtp') continue;
            final v = Map<String, dynamic>.from(d.values as Map? ?? {});
            if ('${v['kind']}' != 'audio' && v['kind'] != null) continue;
            final raw = v['audioLevel'];
            final level = raw is num ? raw.toDouble() : double.tryParse('$raw');
            if (level == null) continue;
            if (t == 'inbound-rtp') {
              info['in'] = level.toStringAsFixed(3);
            } else {
              info['out'] = level.toStringAsFixed(3);
              if (!isDown) {
                micLevel = micLevel == null
                    ? level
                    : (level > micLevel ? level : micLevel);
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
      peers[key] = info;
    }
    return {
      'sess': sessId,
      'joined': _joined,
      'onStage': _onStage,
      'muted': _muted,
      'pairing': pairing,
      'mic': micLevel == null ? '-' : micLevel.toStringAsFixed(3),
      'speakers': _speakers.toList(),
      'peers': peers,
    };
  }

  Set<String> get speakers => Set.unmodifiable(_speakers);
  bool isMuted(String uid) => _speakerMuted[uid] ?? false;
  bool isSpeaking(String uid) => _speakingNow.contains(uid);
  int get speakerCount => _speakerCount;

  bool _relayOnlyFor(String peerUid) =>
      relayOnlyFor(peerUid: peerUid, allCandTried: _allCandTriedPeers);

  // Generasi sesi (monotonik per proses): teardown sesi LAMA mengirim v_bye

  // ── Buka sesi sebagai PENDENGAR ──
  Future<void> startListening() async {
    if (_closed || _joined) return;
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    _signalSub = _onSignalStream().listen(
      _onSignal,
      onError: (e) => dlog('[RoomVoice] signal stream error: $e'),
    );
    await _fastForwardSignals();
    // Polling cadangan (pola broadcast): realtime bisa terlewat.
    _syncTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_closed) return;
      unawaited(_syncMissedSignals());
    });
    // Daftar speaker live: realtime table + polling cadangan 20 dtk.
    _speakersChannel = _sb
        .channel('room-voice-speakers-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_voice_speakers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) => unawaited(_refreshSpeakers()),
        )
        .subscribe((status, err) {
          if (err != null) dlog('[RoomVoice] speakers realtime error: $err');
        });
    _speakersPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_closed) return;
      unawaited(_refreshSpeakers());
    });
    // Level bicara: getStats inbound-rtp audio tiap 1 dtk (pemicu animasi
    // avatar — 1.5 dtk terasa telat saat mulai bicara).
    _levelTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (_closed) return;
      unawaited(_pollLevels());
    });
    await _sendSignal(
      type: 'v_join',
      payload: {'ts': DateTime.now().toIso8601String(), 'sess': sessId},
    );
    await _refreshSpeakers();
    _joined = true;
    notifyListeners();
    // Burst sinkron: realtime bisa telat/hilang; kejar sinyal ≤30 dtk yang
    // terlewat dalam 5 dtk pertama supaya handshake kenceng.
    _burstSync();
  }

  /// Kejar sinyal + daftar speaker beberapa kali cepat setelah join (cadangan
  /// realtime). Idempoten (dedup `_seenSignalIds`) — aman dipanggil berulang.
  ///
  /// Tick RAPAT di fase awal (400/1200/2500 ms) supaya handshake
  /// v_speak→v_join→v_offer tak tertahan menunggu realtime/`_syncTimer` (dulu
  /// hanya 1.5s/4s → connect terasa lambat vs call 1:1). Tick terakhir 4s
  /// sebagai jaring pengaman.
  void _burstSync() {
    for (final ms in [400, 1200, 2500, 4000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (_closed) return;
        unawaited(_syncMissedSignals());
        unawaited(_refreshSpeakers());
      });
    }
  }

  // ── Naik stage + mic nyala. Return false bila panggung penuh. ──
  Future<bool> startSpeaking() async {
    if (_closed || _onStage) return _onStage;
    if (!_joined) await startListening();
    if (_closed) return false;
    // Guard server (max 6). RPC me-return speakers aktif.
    // Timeout WAJIB: RPC gantung = _voiceJoining UI muter selamanya.
    try {
      final res = await _sb
          .rpc('room_voice_join', params: {'p_room_id': roomId})
          .timeout(const Duration(seconds: 10));
      final map = res is Map ? Map<String, dynamic>.from(res) : const {};
      if (map['ok'] != true) {
        dlog('[VOICE] stage full');
        onStageFull?.call();
        return false;
      }
      _applySpeakers(((map['speakers'] as List?) ?? const []).map((e) => '$e'));
    } catch (e) {
      dlog('[VOICE] join error: $e');
      return false;
    }
    // Timeout WAJIB: getUserMedia bisa gantung di sebagian HP (mic dipakai
    // app lain / izin menggantung) → join tak pernah selesai.
    // Constraint eksplisit (sama seperti call 1:1): AEC/NS/AGC + perbaikan
    // Google (highpass/typing) + mono → suara jernih & hemat. Tanpa ini tiap
    // device pakai default berbeda (Xiaomi pernah pilih mic jauh = pelan).
    // Fallback: bila device menolak constraint (Overconstrained), coba tanpa
    // constraint supaya voice tetap jalan (jangan gagalkan sesi).
    const audioConstraints = {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'googEchoCancellation': true,
      'googAutoGainControl': true,
      'googNoiseSuppression': true,
      'googHighpassFilter': true,
      'googTypingNoiseDetection': true,
      'channelCount': 1,
    };
    try {
      _localStream = await navigator.mediaDevices
          .getUserMedia({'audio': audioConstraints, 'video': false})
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      dlog(
        '[VOICE] getUserMedia (constraint) failed: $e — coba tanpa constraint',
      );
      try {
        _localStream = await navigator.mediaDevices
            .getUserMedia({'audio': true, 'video': false})
            .timeout(const Duration(seconds: 10));
      } catch (e2) {
        dlog('[VOICE] getUserMedia audio failed: $e2');
        try {
          await _sb.rpc('room_voice_leave', params: {'p_room_id': roomId});
        } catch (_) {}
        return false;
      }
    }
    // Pilih mic terbaik (audioinput pertama): di sebagian device default bisa
    // jatuh ke mic jauh → suara pelan. Best-effort (pola call 1:1).
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      for (final d in devices) {
        if (d.kind == 'audioinput' && d.deviceId.isNotEmpty) {
          await Helper.selectAudioInput(d.deviceId);
          break;
        }
      }
    } catch (_) {}
    _onStage = true;
    _muted = false;
    _speakers.add(myUid);
    // Pastikan mic native UNMUTE saat mulai stage (bisa tertinggal true dari
    // sesi sebelumnya → "mic hijau tapi bisu").
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      try {
        t.enabled = true;
      } catch (_) {}
      try {
        await Helper.setMicrophoneMute(false, t);
      } catch (_) {}
    }
    // Audio route: speakerphone WAJIB agar suara lawan terdengar kencang
    // (default earpiece/volume rendah = "mic hijau tapi bisu"). Best-effort:
    // jangan gagalkan sesi bila tak didukung device.
    await _setSpeakerphone(true);
    // Pairing dimulai: hijau (connected) hanya setelah uplink Connected.
    _uplinkOk.clear();
    // Heartbeat stage tiap 15 dtk (pola broadcast).
    _hbTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_closed || !_onStage) return;
      try {
        await _sb.rpc('room_voice_heartbeat', params: {'p_room_id': roomId});
      } catch (_) {}
    });
    // Umumkan ke pendengar: balas dengan v_join terarah → ku-offer.
    // Sertakan generasi sesi supaya v_bye basi sesi lama tak membunuh peer baru.
    await _sendSignal(
      type: 'v_speak',
      payload: {'ts': DateTime.now().toIso8601String(), 'sess': sessId},
    );
    // OPSI B — percepat handshake: selain menunggu `v_join` dari pendengar,
    // langsung tawarkan uplink ke speaker lain yang SUDAH diketahui dari
    // daftar stage. Memotong 1 round-trip (v_join) sebelum offer pertama.
    // Idempoten & aman duplikat: `_makeOfferTo` di-guard `_offerBusy` +
    // cek connectionState; sisi lawan juga mengirim v_join/offer sendiri →
    // `_handleOffer` mengabaikan offer saat pc sudah Connecting/Connected.
    for (final uid in _speakers.toList()) {
      if (uid == myUid) continue;
      unawaited(_makeOfferTo(uid));
    }
    _burstSync();
    // Re-offer watchdog: pc mati / answer macet >8 dtk / macet total >30 dtk.
    _reOfferTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_closed || !_onStage) return;
      final now = DateTime.now();
      for (final entry in _peers.entries.toList()) {
        // Downlink (dn_uid, suara MASUK dari speaker lain) JANGAN dioffer:
        // _makeOfferTo butuh uid asli — key dn_ menimpa pc downlink (suara
        // masuk mati!) + offer ke "uid" yang tak ada. Downlink pulih via
        // re-request v_join (lihat onConnectionState downlink).
        if (entry.key.startsWith('dn_')) continue;
        // Uplink macet total >30 dtk tanpa pernah Connected: buang (spinner
        // abadi + pc zombie). v_join segar dari pendengar membangun ulang
        // bila mereka masih ada.
        final since = _uplinkSince[entry.key];
        if (since != null &&
            now.difference(since) > const Duration(seconds: 30) &&
            !_uplinkOk.contains(entry.key)) {
          unawaited(_dropPeer(entry.key));
          continue;
        }
        final pc = entry.value;
        final st = pc.connectionState;
        // CONNECTED = sehat → JANGAN diapa-apakan. Dulu timer ini tetap
        // re-offer tiap >8 dtk walau sudah Connected → close+rebuild pc →
        // siklus "putus-nyambung" (~8 dtk) yang memutus audio. Ini akar
        // "kadang ada suara, kadang muter".
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          continue;
        }
        // FALLBACK relay→all-candidates: relay-only belum Connected >6 dtk
        // (TURN tak menjangkau / NAT sama) → buka kandidat host/srflx SEKALI
        // per peer. Meniru grace-timeout fallback call 1:1 ("P2P jalan walau
        // TURN mati"). Dilakukan SEBELUM re-offer biasa supaya negosiasi
        // dibangun ulang dengan config baru (bukan menambah offer di pc lama).
        final since2 = _uplinkSince[entry.key];
        if (_relayOnlyFor(entry.key) &&
            since2 != null &&
            now.difference(since2) > const Duration(seconds: 6)) {
          unawaited(_retryPeerAllCandidates(entry.key));
          continue;
        }
        // Failed/Disconnected benar-benar mati → bangun ulang.
        final dead = st == RTCPeerConnectionState.RTCPeerConnectionStateFailed;
        if (st != null && dead) {
          unawaited(_makeOfferTo(entry.key));
          continue;
        }
        // Disconnected/Connecting baru: beri waktu ICE pulih sendiri
        // (jaringan goyang). Hanya paksa re-offer bila offer terakhir sudah
        // lama (>10 dtk) DAN belum Connected — supaya tak memutus saat pulih.
        final sentAt = _offerSentAt[entry.key];
        if (sentAt != null &&
            now.difference(sentAt) > const Duration(seconds: 10)) {
          unawaited(_makeOfferTo(entry.key));
        }
      }
    });
    notifyListeners();
    return true;
  }

  // ── Turun stage (tetap dengar). ──
  Future<void> stopSpeaking({bool announce = true}) async {
    if (!_onStage) return;
    _onStage = false;
    _muted = true;
    _uplinkOk.clear();
    _hbTimer?.cancel();
    _hbTimer = null;
    try {
      await _sb.rpc('room_voice_leave', params: {'p_room_id': roomId});
    } catch (_) {}
    if (announce) {
      await _sendSignal(type: 'v_bye', payload: {'sess': sessId});
    }
    // Tutup pc uplink (ke listener); pc downlink (dari speaker lain)
    // tetap — kita masih pendengar.
    for (final uid in _peers.keys.toList()) {
      if (_speakers.contains(uid)) continue;
      await _dropPeer(uid);
    }
    _speakers.remove(myUid);
    // Turun stage: matikan mic native dulu (bukan hanya track.stop()).
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
    notifyListeners();
  }

  // ── Audio route: paksa speakerphone (best-effort, aman di semua env). ──
  Future<void> _setSpeakerphone(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (_) {}
  }

  /// Paksa codec Opus untuk transceiver audio (latency rendah + FEC).
  /// Dipanggil setelah addTrack/setRemoteDescription & sebelum
  /// createOffer/createAnswer. Best-effort: gagal → pakai default.
}
