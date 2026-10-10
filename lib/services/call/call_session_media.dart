part of 'call_session.dart';

mixin _CallSessionMediaMx on _CallBase {
  Future<void> _setupMediaAndPeer() async {
    try {
      _mediaError = null;
      // Relay-only saat Cloudflare OK (deterministik & cepat). Fallback ke
      // semua tipe kandidat terjadi lewat `_retryWithAllCandidates()` bila
      // ICE gagal menetap — di sini cukup pakai default.
      final peerConfig = await CallConfig.getPeerConfig(relayOnly: _relayOnly);
      // Sinkronkan flag dengan kebijakan yang BENAR-BENAR diterapkan —
      // relay-only hanya aktif bila Cloudflare tersedia. Kalau tidak,
      // kandidat host/srflx sudah dipakai → fallback tak perlu.
      _relayOnly = CallConfig.lastConfigWasRelayOnly;
      // Constraint audio eksplisit (latency rendah + jernih):
      // AEC/NS/AGC standar + perbaikan Google (highpass = low-rumble hilang,
      // typing-noise = ketikan keyboard tidak bocor) + mono (hemat bandwidth).
      // Tanpa constraint eksplisit, tiap device memakai default berbeda —
      // di Xiaomi pernah mic jauh yang kepilih (suara pelan).
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googAutoGainControl': true,
          'googNoiseSuppression': true,
          'googHighpassFilter': true,
          'googTypingNoiseDetection': true,
          'channelCount': 1,
        },
        'video': callType == 'video' ? {'facingMode': 'user'} : false,
      });
      localRenderer.srcObject = _localStream;
      // Pilih mic terbaik (audioinput pertama): di sebagian device (Xiaomi)
      // default bisa jatuh ke mic jauh sehingga suara pelan. Best-effort.
      try {
        final devices = await navigator.mediaDevices.enumerateDevices();
        for (final d in devices) {
          if (d.kind == 'audioinput' && d.deviceId.isNotEmpty) {
            await Helper.selectAudioInput(d.deviceId);
            break;
          }
        }
      } catch (_) {}

      _pc = await createPeerConnection(peerConfig);
      _pc!.onTrack = (event) async {
        dlog('[ICE] onTrack kind=${event.track.kind}');
        // Sender menaruh audio + video dalam satu stream lokal yang sama,
        // jadi event.streams.first untuk kedua track adalah objek stream
        // identik yang sudah memuat video. Pakai stream ini langsung (bukan
        // merge manual) agar flutter_webrtc melaporkan video track dan
        // renderer menampilkan gambar. Assign + set srcObject di SETIAP
        // onTrack supaya view ikut refresh saat video tiba.
        final stream = event.streams.isNotEmpty
            ? event.streams.first
            : (_remoteStream ??= await createLocalMediaStream('remote'));
        if (event.streams.isEmpty) {
          try {
            await stream.addTrack(event.track);
          } catch (_) {}
        }
        _remoteStream = stream;
        remoteRenderer.srcObject = stream;
        dlog(
          '[ICE] remoteStream videoTracks=${stream.getVideoTracks().length} audioTracks=${stream.getAudioTracks().length}',
        );
        // JANGAN set inCall dari onTrack: track remote bisa tiba SEBELUM
        // ICE benar-benar connect, sehingga timer 00:00 sempat "blink" lalu
        // balik ke "Menghubungkan". inCall (timer) hanya dipasang saat
        // connectionState / iceConnectionState = Connected — itu arti
        // "sudah nyambung" yang sebenarnya. Audio tetap jalan karena
        // remoteRenderer sudah di-set di atas & selalu di-render di UI.
        if (!_closed) notifyListeners();
      };
      _pc!.onIceCandidate = (candidate) {
        dlog('[ICE] local candidate: ${candidate.candidate}');
        _service.sendSignal(
          callId,
          'candidate',
          payload: {'candidate': candidate.toMap()},
        );
      };
      _pc!.onConnectionState = (state) {
        dlog('[ICE] connectionState: $state');
        if (_closed) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          if (!_closed && _phase != CallPhase.inCall) {
            _phase = CallPhase.inCall;
            _connectedAt = DateTime.now();
            _recordConnected('pcState');
            _startBilling();
            _setProximity(true);
            notifyListeners();
          }
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          Future.delayed(const Duration(seconds: 4), () async {
            if (_closed) return;
            try {
              final cur = _pc?.connectionState;
              if (cur == RTCPeerConnectionState.RTCPeerConnectionStateConnected)
                return;
              if (cur == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                  cur == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
                // Relay-only gagal menetap → coba all-candidates (P2P) dulu;
                // ini menyelamatkan call saat relay TURN tak terjangkau.
                if (_relayOnly && !_iceAllCandidatesTried) {
                  dlog(
                    '[ICE] grace-timeout still $cur -> fallback all-candidates',
                  );
                  await _retryWithAllCandidates();
                  return;
                }
                // Otomatis restart 1× dulu; kalau masih gagal → tombol manual
                // (jangan auto-tutup; user pilih sambung-ulang/akhiri).
                if (!_iceRestarted) {
                  dlog('[ICE] grace-timeout still $cur -> restart otomatis');
                  await _attemptIceRestart();
                  return;
                }
                dlog('[ICE] grace-timeout still $cur -> tombol manual');
                _iceReconnectFailed = true;
                notifyListeners();
              }
            } catch (_) {
              if (!_closed) {
                try {
                  await _service.sendSignal(callId, 'bye');
                  await _service.updateStatus(callId, 'ended');
                } catch (_) {}
                _finish(
                  _phase == CallPhase.inCall
                      ? CallEndReason.ended
                      : CallEndReason.error,
                );
              }
            }
          });
        }
      };
      Future.delayed(const Duration(seconds: 15), () async {
        if (_closed) return;
        if (_phase == CallPhase.inCall) return;
        // Restart/retry manual sedang berjalan → jangan auto-tutup di sini;
        // user yang pegang kendali (tombol sambung-ulang / akhiri).
        if (_iceRestarted || _iceReconnectFailed) return;
        final cur = _pc?.connectionState;
        final ice = _pc?.iceConnectionState;
        // PENTING: sebagian device tidak memanggil onConnectionState/
        // onIceConnectionState walau media sudah mengalir → `_phase` tetap
        // "connecting" → dulu timer ini MENUTUP call yang sebenarnya
        // tersambung ("call mati sendiri" setelah ~15-20 dtk). Cek state PC
        // LANGSUNG; kalau sudah Connected → set inCall (jangan putus).
        if (cur == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
            ice == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            ice == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          if (_phase != CallPhase.inCall) {
            dlog(
              '[ICE] 15s check: pc/ice Connected -> SET inCall (anti putus)',
            );
            _phase = CallPhase.inCall;
            _connectedAt = _connectedAt ?? DateTime.now();
            _recordConnected('timeout15Check');
            _startBilling();
            _setProximity(true);
            notifyListeners();
          }
          return;
        }
        // Relay-only belum tersambung & fallback belum dicoba → jangan
        // menyerah; coba all-candidates (P2P) dulu sebelum menyatakan gagal.
        if (_relayOnly && !_iceAllCandidatesTried) {
          dlog('[ICE] 15s timeout still $cur -> fallback all-candidates');
          await _retryWithAllCandidates();
          return;
        }
        dlog(
          '[ICE] 15s timeout still $cur phase=$_phase -> bye + _finish error',
        );
        try {
          await _service.sendSignal(callId, 'bye');
          await _service.updateStatus(callId, 'ended');
        } catch (_) {}
        _finish(CallEndReason.error);
      });
      _pc!.onIceConnectionState = (state) {
        dlog('[ICE] iceConnectionState: $state');
        if (_closed) return;
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          var changed = false;
          if (_iceReconnectFailed) {
            _iceReconnectFailed = false;
            changed = true;
          }
          if (_phase != CallPhase.inCall) {
            dlog('[ICE] iceConnected -> SET inCall');
            _phase = CallPhase.inCall;
            _connectedAt = _connectedAt ?? DateTime.now();
            _recordConnected('iceState');
            _startBilling();
            _setProximity(true);
            changed = true;
          }
          if (changed) notifyListeners();
        }
        if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          // Putus sementara (pindah WiFi/data): tunggu 2 dtk, kalau belum
          // pulih → restart otomatis 1×; masih gagal → tombol manual.
          dlog('[ICE] iceDisconnected -> grace 2s');
          Future.delayed(const Duration(seconds: 2), () async {
            if (_closed) return;
            final cur = _pc?.connectionState;
            if (cur == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
              return;
            }
            if (!_iceRestarted) {
              await _attemptIceRestart();
            } else {
              _iceReconnectFailed = true;
              dlog('[ICE] still bad after restart -> tombol manual');
              notifyListeners();
            }
          });
        }
      };
      _pc!.onIceGatheringState = (state) {
        dlog('[ICE] iceGatheringState: $state');
      };
      _pc!.onSignalingState = (state) {
        dlog('[ICE] signalingState: $state');
      };
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
      // Paksa codec Opus untuk transceiver audio — HARUS setelah addTrack
      // (transceiver baru ada) dan SEBELUM createOffer/createAnswer agar
      // efektif. Default bisa jatuh ke PCMU/PCMA (boros + tanpa FEC).
      // Best-effort: platform tak mendukung → pakai default.
      try {
        await _preferOpusCodec();
      } catch (_) {}
      // Proses sinyal yang diterima sebelum screen terbuka (dari IncomingCallScreen).
      if (pendingSignals.isNotEmpty) {
        for (final msg in pendingSignals) {
          _pendingSignals.add(msg);
        }
      }
      // Proses sinyal yang datang saat peer connection belum siap.
      if (_pendingSignals.isNotEmpty) {
        final queued = List.of(_pendingSignals);
        _pendingSignals.clear();
        for (final msg in queued) {
          await _handleSignal(msg);
        }
      }
    } catch (e) {
      dlog('[CallSession] media/peer setup failed: $e');
      if (!_closed) {
        _mediaError = _classifyMediaError(e);
        _phase = CallPhase.error;
        notifyListeners();
      }
    }
  }

  /// Terjemahkan error getUserMedia/createPeerConnection ke [CallMediaError]
  /// supaya UI bisa menampilkan alasan yang benar (izin vs kamera terpakai).
  CallMediaError _classifyMediaError(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains('notallowederror') ||
        m.contains('permission') ||
        m.contains('securityerror')) {
      return CallMediaError.permission;
    }
    if (m.contains('notreadableerror') ||
        m.contains('trackstarterror') ||
        m.contains('could not start') ||
        m.contains('in use')) {
      return CallMediaError.inUse;
    }
    if (m.contains('notfounderror') ||
        m.contains('devicesnotfound') ||
        m.contains('overconstrained')) {
      return CallMediaError.notFound;
    }
    return CallMediaError.other;
  }

  /// Paksa codec Opus untuk transceiver audio (latency rendah + FEC).
  /// Dipanggil setelah addTrack (transceiver sudah ada) dan sebelum
  /// createOffer/createAnswer. Best-effort: gagal → pakai default.
  Future<void> _preferOpusCodec() async {
    final pc = _pc;
    if (pc == null || _closed) return;
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

  /// Sampling RTT audio (getStats inbound-rtp) 3× tiap 5 dtk setelah connect.
  /// Nilai terburuk dicatat sebagai `call.audioRttMs` — pembanding latency
  /// suara sebelum/sesudah optimasi Opus. Best-effort, tanpa mengganggu call.
  Future<void> _sampleAudioRtt() async {
    double? worst;
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(seconds: 5));
      if (_closed) return;
      try {
        final stats = await _pc?.getStats();
        for (final r in stats ?? const []) {
          if (r.type != 'inbound-rtp') continue;
          final kind = '${r.values['kind'] ?? r.values['mediaType'] ?? ''}';
          if (kind.isNotEmpty && kind != 'audio') continue;
          final rtt = (r.values['roundTripTime'] as num?)?.toDouble();
          if (rtt != null && rtt.isFinite && rtt >= 0) {
            worst = worst == null || rtt > worst ? rtt : worst;
          }
        }
      } catch (_) {}
    }
    if (worst != null) {
      final ms = (worst * 1000).round();
      PerfProbe.record('call.audioRttMs', Duration(milliseconds: ms));
      dlog('[PERF] audio RTT worst=${ms}ms');
    }
  }

  Future<void> _attemptIceRestart() async {
    final pc = _pc;
    if (pc == null || _closed) return;
    _iceRestarted = true;
    dlog('[ICE] restart attempt (isCaller=$isCaller)');
    try {
      await pc.restartIce();
    } catch (e) {
      dlog('[ICE] restartIce failed: $e');
    }
    if (isCaller && !_closed && _pc != null) {
      _offered = false;
      await _createOffer();
    }
    // Recheck: masih buruk → serahkan ke tombol manual.
    Future.delayed(const Duration(seconds: 5), () {
      if (_closed) return;
      if (_phase == CallPhase.inCall) {
        if (_iceReconnectFailed) {
          _iceReconnectFailed = false;
          notifyListeners();
        }
        return;
      }
      final cur = _pc?.connectionState;
      if (cur == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        return;
      }
      _iceReconnectFailed = true;
      dlog('[ICE] still bad after restart -> tombol manual');
      notifyListeners();
    });
  }

  /// Tombol "Sambung ulang" manual: ulangi ICE restart (reset status
  /// percobaan otomatis supaya bisa dicoba berkali-kali). Bila setup media
  /// sebelumnya gagal (phase `error`, pc belum ada) → ulangi setup penuh,
  /// supaya panggilan bisa pulih tanpa harus menutup & menelepon ulang.
  Future<void> reconnect() async {
    if (_closed) return;
    _iceReconnectFailed = false;
    _iceRestarted = false;
    _offered = false;
    notifyListeners();
    // pc tidak pernah terbentuk (gagal getUserMedia dsb) → setup ulang.
    if (_pc == null) {
      _phase = CallPhase.connecting;
      notifyListeners();
      await _setupMediaAndPeer();
      if (_pc != null && isCaller && !_closed) {
        await _createOffer();
      }
      return;
    }
    // Relay-only & belum pernah coba all-candidates → fallback P2P dulu
    // (relay bisa tak terjangkau), baru ICE restart biasa.
    if (_relayOnly && !_iceAllCandidatesTried) {
      await _retryWithAllCandidates();
      return;
    }
    await _attemptIceRestart();
  }
}
