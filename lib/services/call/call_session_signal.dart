part of 'call_session.dart';

mixin _CallSessionSignalMx on _CallBase {
  Future<void> _createOffer() async {
    if (_closed || _pc == null || _offered) return;
    _offered = true;
    _offerSentAt = DateTime.now();
    try {
      final offer = await _pc!.createOffer();
      // Munge SDP lokal SEBELUM setLocalDescription: Opus low-latency + FEC.
      // applyOpusLowLatencyPrefs idempoten & mengembalikan input utuh bila
      // tak ada Opus → aman (fallback implisit, tak pernah string kosong).
      final munged = applyOpusLowLatencyPrefs(offer.sdp ?? '');
      final local = RTCSessionDescription(
        munged.isEmpty ? (offer.sdp ?? '') : munged,
        offer.type,
      );
      await _pc!.setLocalDescription(local);
      await _service.sendSignal(
        callId,
        'offer',
        payload: {'sdp': local.toMap()},
      );
    } catch (e) {
      dlog('[CallSession] createOffer failed: $e');
    }
  }

  /// Catat metrik connect (sekali per sesi): init→connected dan offer→connected.
  /// Dipakai `PerfProbe.report` untuk membandingkan sebelum/sesudah optimasi.
  /// Plus sampling RTT audio (3× tiap 5 dtk setelah connect) sebagai metrik
  /// latency suara (`call.audioRttMs`, diambil nilai terburuk).
  bool _connectedRecorded = false;
  void _recordConnected(String source) {
    if (_connectedRecorded) return;
    _connectedRecorded = true;
    final now = DateTime.now();
    final start = _initStartedAt;
    if (start != null) {
      PerfProbe.record('call.initToConnected', now.difference(start));
    }
    final offerAt = _offerSentAt;
    if (offerAt != null) {
      PerfProbe.record('call.offerToConnected', now.difference(offerAt));
    }
    dlog('[PERF] call connected via $source');
    unawaited(_sampleAudioRtt());
  }

  Future<void> _onSignal(Map<String, dynamic> msg) async {
    final id = msg['id'] as String?;
    if (id != null) {
      if (_processedSignalIds.contains(id)) return;
      _processedSignalIds.add(id);
    }
    dlog(
      '[CallSession] onSignal type=${msg['type']} isCaller=$isCaller pc=${_pc != null}',
    );
    if (_closed) return;
    if (_pc == null) {
      _pendingSignals.add(msg);
      return;
    }
    await _handleSignal(msg);
  }

  Future<void> _handleSignal(Map<String, dynamic> msg) async {
    if (_closed) return;
    if (_pc == null) {
      // pc belum siap → kandidat ICE JANGAN dibuang; simpan untuk di-flush
      // setelah remote description terpasang. Sinyal lain memang harus nunggu.
      if (msg['type'] == 'candidate') {
        final c = msg['candidate'] as Map<String, dynamic>?;
        if (c != null) {
          _pendingCandidates.add(c);
          dlog('[ICE] queue candidate (pc not ready)');
        }
      }
      return;
    }
    try {
      switch (msg['type']) {
        case 'offer':
          final sdp = msg['sdp'] as Map<String, dynamic>?;
          if (sdp == null) return;
          final existing = await _pc!.getRemoteDescription();
          if (existing != null) {
            // Offer duplikat (realtime + sync polling) → abaikan; memproses
            // ulang membuat negosiasi & fase UI kacau.
            dlog('[ICE] duplicate offer ignored');
            return;
          }
          final remoteSdpRaw = sdp['sdp'] as String? ?? '';
          final remoteSdpMunged = applyOpusLowLatencyPrefs(remoteSdpRaw);
          await _pc!.setRemoteDescription(
            RTCSessionDescription(
              remoteSdpMunged.isEmpty ? remoteSdpRaw : remoteSdpMunged,
              sdp['type'],
            ),
          );
          // Flush candidate yang sudah antri sebelum offer diproses
          for (final cand in List<Map<String, dynamic>>.from(
            _pendingCandidates,
          )) {
            try {
              await _pc!.addCandidate(
                RTCIceCandidate(
                  cand['candidate'] ?? '',
                  cand['sdpMid'],
                  (cand['sdpMLineIndex'] as num?)?.toInt(),
                ),
              );
            } catch (_) {}
          }
          _pendingCandidates.clear();
          final answer = await _pc!.createAnswer();
          final answerMunged = applyOpusLowLatencyPrefs(answer.sdp ?? '');
          final localAnswer = RTCSessionDescription(
            answerMunged.isEmpty ? (answer.sdp ?? '') : answerMunged,
            answer.type,
          );
          await _pc!.setLocalDescription(localAnswer);
          await _service.sendSignal(
            callId,
            'answer',
            payload: {'sdp': localAnswer.toMap()},
          );
          await _syncAll();
        case 'answer':
          final sdp = msg['sdp'] as Map<String, dynamic>?;
          if (sdp == null) return;
          final ansSdpRaw = sdp['sdp'] as String? ?? '';
          final ansSdpMunged = applyOpusLowLatencyPrefs(ansSdpRaw);
          await _pc!.setRemoteDescription(
            RTCSessionDescription(
              ansSdpMunged.isEmpty ? ansSdpRaw : ansSdpMunged,
              sdp['type'],
            ),
          );
          for (final cand in List<Map<String, dynamic>>.from(
            _pendingCandidates,
          )) {
            try {
              await _pc!.addCandidate(
                RTCIceCandidate(
                  cand['candidate'] ?? '',
                  cand['sdpMid'],
                  (cand['sdpMLineIndex'] as num?)?.toInt(),
                ),
              );
            } catch (_) {}
          }
          _pendingCandidates.clear();
          await _syncAll();
        case 'candidate':
          final c = msg['candidate'] as Map<String, dynamic>?;
          if (c == null) return;
          final rd = await _pc!.getRemoteDescription();
          if (rd == null) {
            _pendingCandidates.add(c);
            dlog('[ICE] queue candidate (remoteDescription null)');
            return;
          }
          try {
            await _pc!.addCandidate(
              RTCIceCandidate(
                c['candidate'] ?? '',
                c['sdpMid'],
                (c['sdpMLineIndex'] as num?)?.toInt(),
              ),
            );
          } catch (e) {
            // Jika masih gagal karena belum siap, queue dan coba lagi setelah answer
            if ((e.toString().contains('remoteDescription') ||
                e.toString().contains('InvalidState'))) {
              _pendingCandidates.add(c);
              dlog('[ICE] queue candidate (add failed, will retry)');
            } else {
              rethrow;
            }
          }
        case 'camera':
          final en = msg['enabled'];
          if (en is bool) {
            _remoteCameraOn = en;
            dlog('[CallSession] remoteCameraOn=$_remoteCameraOn');
            notifyListeners();
          }
          break;
        case 'bye':
          _finish(CallEndReason.ended);
        case 'watch_request':
          await _handleWatchRequest(msg);
        case 'watch_answer':
          await _handleWatchAnswer(msg);
        case 'watch_candidate':
          await _handleWatchCandidate(msg);
      }
    } catch (e) {
      dlog('[CallSession] signal error: $e');
    }
  }
}
