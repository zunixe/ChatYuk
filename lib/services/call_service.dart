import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/call_config.dart';
import '../config/supabase_config.dart';

/// Fase panggilan.
enum CallPhase { connecting, ringing, inCall, ended, error }

/// Alasan panggilan berakhir — buat pesan di UI.
enum CallEndReason { ended, declined, busy, canceled, missed, error }

/// CallService: tabel `calls` + signaling via Realtime broadcast.
/// SDP/ICE TIDAK lewat DB — broadcast channel `call-signal-<callId>`
/// (ephemeral, pola sama seperti typing indicator).
class CallService {
  static final CallService instance = CallService._();
  CallService._();

  final SupabaseClient _sb = SupabaseConfig.client;
  final Map<String, RealtimeChannel> _signalChannels = {};
  final Map<String, StreamController<Map<String, dynamic>>> _signalStreams = {};
  final Set<String> _signalBound = {};

  String? get uid => _sb.auth.currentUser?.id;

  // ── Tabel calls ──
  Future<String> startCall(String calleeUid, String callType) async {
    final row = await _sb
        .from('calls')
        .insert({
          'caller_id': uid,
          'callee_id': calleeUid,
          'call_type': callType,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateStatus(String callId, String status) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final patch = <String, dynamic>{'status': status};
    if (status == 'answered') patch['answered_at'] = now;
    if (status == 'ended' || status == 'canceled') patch['ended_at'] = now;
    await _sb.from('calls').update(patch).eq('id', callId);
  }

  Future<Map<String, dynamic>?> getCall(String callId) async {
    return _sb.from('calls').select('*').eq('id', callId).maybeSingle();
  }

  /// Heartbeat peserta call (fire-and-forget) — dipakai admin monitor
  /// untuk membedakan call hidup vs zombie.
  void touchCall(String callId) {
    _sb
        .rpc('touch_call', params: {'p_call_id': callId})
        .then((_) {})
        .catchError((_) {});
  }

  Future<String?> getNickname(String uid) async {
    final row = await _sb
        .from('profiles')
        .select('nickname')
        .eq('id', uid)
        .maybeSingle();
    return row?['nickname'] as String?;
  }

  /// Cek apakah uid adalah admin ChatYuk — dipakai sebelum melayani
  /// permintaan "watch" dari admin panel (pantau call).
  Future<bool> isAdminUid(String uid) async {
    try {
      final r = await _sb.rpc('is_chatyuk_admin', params: {'p_uid': uid});
      return r == true;
    } catch (_) {
      return false;
    }
  }

  /// Kirim pesan riwayat call ke private chat.
  Future<void> sendCallMessage({
    required String myUid,
    required String otherUid,
    required String myName,
    required String myGender,
    required String callType,
    required String status,
    required int durationSeconds,
  }) async {
    final ids = [myUid, otherUid]..sort();
    final chatId = '${ids[0]}_${ids[1]}';
    final durText = durationSeconds > 0
        ? ' (${durationSeconds ~/ 60}:${(durationSeconds % 60).toString().padLeft(2, '0')})'
        : '';
    final text = '${callType == 'video' ? '📹' : '📞'} $status$durText';
    try {
      await _sb.from('private_messages').insert({
        'chat_id': chatId,
        'sender_id': myUid,
        'sender_name': myName,
        'sender_gender': myGender,
        'text': text,
        'type': 'call',
        'image_data': '',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[CallService] sendCallMessage error: $e');
    }
  }

  /// Stream panggilan masuk (insert calls dengan callee_id = aku).
  Stream<Map<String, dynamic>> onIncomingCall() {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final me = uid;
    if (me == null) {
      scheduleMicrotask(controller.close);
      return controller.stream;
    }
    final channel = _sb.channel('calls-incoming-$me');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'calls',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'callee_id',
        value: me,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        final row = payload.newRecord;
        if (row['status'] != 'ringing') return;
        controller.add(row);
      },
    );
    channel.subscribe();
    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }

  /// Stream perubahan status satu call (mis. callee melihat caller cancel).
  Stream<String> onCallStatus(String callId) {
    final controller = StreamController<String>.broadcast();
    final channel = _sb.channel('call-status-$callId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'calls',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: callId,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        debugPrint(
          '[CallService] onCallStatus -> ${payload.newRecord['status']}',
        );
        controller.add(payload.newRecord['status'] as String? ?? '');
      },
    );
    channel.subscribe();
    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }

  // ── Signaling (postgres — reliable & replayable via catch-up SELECT) ──
  Stream<Map<String, dynamic>> onSignal(String callId) {
    final controller = _signalStreams.putIfAbsent(
      callId,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    );
    if (!_signalBound.contains(callId)) {
      _signalBound.add(callId);
      // Catch-up: ambil signal yang sudah ada (dikirim sebelum subscribe).
      _catchUpSignals(callId, controller);
      final channel = _sb.channel('call-signals-$callId');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_signals',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'call_id',
          value: callId,
        ),
        callback: (payload) {
          if (controller.isClosed) return;
          _emitSignal(payload.newRecord, controller);
        },
      );
      channel.subscribe();
      _signalChannels[callId] = channel;
    }
    return controller.stream;
  }

  Future<void> _catchUpSignals(
    String callId,
    StreamController<Map<String, dynamic>> controller,
  ) async {
    try {
      final rows = await _sb
          .from('call_signals')
          .select()
          .eq('call_id', callId)
          .order('created_at');
      for (final row in rows) {
        _emitSignal(row, controller);
      }
    } catch (_) {}
  }

  void _emitSignal(
    Map<String, dynamic> row,
    StreamController<Map<String, dynamic>> controller,
  ) {
    if (controller.isClosed) return;
    if (row['from_uid'] == uid) return;
    final type = row['type'] as String?;
    final payload = (row['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    controller.add({'id': row['id']?.toString(), 'type': type, ...payload});
  }

  Future<void> sendSignal(
    String callId,
    String type, {
    Map<String, dynamic>? payload,
  }) async {
    debugPrint('[CallService] sendSignal callId=$callId type=$type');
    try {
      await _sb.from('call_signals').insert({
        'call_id': callId,
        'from_uid': uid,
        'type': type,
        'payload': {...?payload},
      });
    } catch (e) {
      debugPrint('[CallService] sendSignal error: $e');
    }
  }

  /// Ambil semua signal (offer/candidates) untuk sebuah call — dipakai untuk
  /// re-sync agar tidak ada kandidat yang terlewat.
  Future<List<Map<String, dynamic>>> syncCallSignals(String callId) async {
    try {
      final rows = await _sb
          .from('call_signals')
          .select()
          .eq('call_id', callId)
          .order('created_at');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  void disposeSignal(String callId) {
    final controller = _signalStreams.remove(callId);
    if (controller != null && !controller.isClosed) controller.close();
    _signalBound.remove(callId);
    final channel = _signalChannels.remove(callId);
    if (channel != null) _sb.removeChannel(channel);
  }
}

/// CallSession: manajemen RTCPeerConnection + media lokal/remote.
///
/// Alur:
/// - Caller: startCall (status ringing) → init() (preview + peer connection,
///   TANPA offer) → tunggu status 'answered' → buat offer.
/// - Callee: terima → updateStatus answered → init() → terima offer →
///   buat answer.
/// Offer hanya dibuat setelah callee jawab — broadcast tidak replay,
/// jadi callee tidak boleh ketinggalan offer saat masih ringing.
class CallSession extends ChangeNotifier {
  final String callId;
  final String remoteUid;
  final String remoteName;
  final String callType;
  final bool isCaller;
  final String myName;
  final String myGender;
  final List<Map<String, dynamic>> pendingSignals;

  final CallService _service = CallService.instance;

  CallSession({
    required this.callId,
    required this.remoteUid,
    required this.remoteName,
    required this.callType,
    required this.isCaller,
    this.myName = '',
    this.myGender = 'other',
    this.pendingSignals = const [],
  });

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<Map<String, dynamic>>? _signalSub;
  StreamSubscription<String>? _statusSub;
  Timer? _ringTimer;
  Timer? _syncTimer;
  bool _closed = false;
  bool _offered = false;
  // Sinyal yang datang sebelum peer connection siap (offer bisa sampai
  // sebelum getUserMedia selesai di callee) — diproses setelah setup.
  final List<Map<String, dynamic>> _pendingSignals = [];
  // Candidate yang datang sebelum remoteDescription di-set (answer/offer
  // belum diproses) — di-queue dulu, flush setelah remoteDescription ada.
  final List<Map<String, dynamic>> _pendingCandidates = [];
  // Dedup sinyal berdasarkan id baris call_signals (hindari double-process
  // akibat realtime + re-sync SELECT).
  final Set<String> _processedSignalIds = {};
  // ── Watcher (pantau dari admin panel) ──
  // Peer connection per watcher (uid admin) + antrian candidate yang datang
  // sebelum remoteDescription terpasang + throttle balasan watch_request.
  final Map<String, RTCPeerConnection> _watchPcs = {};
  final Map<String, List<Map<String, dynamic>>> _watchPendingCands = {};
  final Map<String, DateTime> _lastWatchReply = {};
  final Map<String, Future<bool>> _watcherAdminChecks = {};

  CallPhase _phase = CallPhase.connecting;
  CallEndReason _endReason = CallEndReason.ended;
  bool _micOn = true;
  bool _cameraOn = true;
  bool _remoteCameraOn = true;
  bool _speakerOn = true;
  DateTime? _connectedAt;

  CallPhase get phase => _phase;
  CallEndReason get endReason => _endReason;
  bool get micOn => _micOn;
  bool get cameraOn => _cameraOn;
  bool get remoteCameraOn => _remoteCameraOn;
  bool get speakerOn => _speakerOn;
  DateTime? get connectedAt => _connectedAt;
  MediaStream? get remoteStream => _remoteStream;
  bool get hasRemoteVideo {
    final tracks = _remoteStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return false;
    if (!_remoteCameraOn) return false;
    // Device beda-beda cara melaporkan state track: sebagian menandai
    // muted=true sampai frame pertama tiba sehingga syarat lama
    // (enabled && !muted) membuat video lawan tak pernah tampil walau
    // media sudah mengalir. Cukup track enabled → anggap ada video;
    // kamera lawan mati tetap terdeteksi lewat sinyal 'camera'.
    return tracks.any((t) => t.enabled);
  }

  /// Siapkan renderer + media lokal + peer connection + listener sinyal.
  /// Belum membuat offer — caller menunggu callee jawab.
  Future<void> init() async {
    debugPrint(
      '[ICE] ===== init#${hashCode} start isCaller=$isCaller callId=$callId (pc=${_pc != null}) =====',
    );
    if (_pc != null) {
      debugPrint(
        '[ICE] init() already ran (pc exists) -> skip to avoid phase reset',
      );
      return;
    }
    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _signalSub = _service.onSignal(callId).listen(_onSignal);

    // Status call: caller lihat declined/busy, callee lihat canceled.
    _statusSub = _service.onCallStatus(callId).listen((status) {
      if (_closed) return;
      switch (status) {
        case 'declined':
          _finish(CallEndReason.declined);
        case 'busy':
          _finish(CallEndReason.busy);
        case 'canceled':
          _finish(isCaller ? CallEndReason.ended : CallEndReason.canceled);
        case 'ended':
          // Lawan bicara menutup call → tutup sesi ini segera juga.
          _finish(CallEndReason.ended);
        case 'answered':
          // Caller: callee sudah terima → pastikan offer sudah dibuat.
          if (isCaller && _phase == CallPhase.ringing) {
            _ringTimer?.cancel();
            _phase = CallPhase.connecting;
            debugPrint('[SESSION] answered#${hashCode} caller -> connecting');
            notifyListeners();
            _createOffer();
          }
      }
    });

    await _setupMediaAndPeer();

    // Callee: cek status terakhir — caller bisa sudah membatalkan sebelum
    // kita subscribe status (Realtime tidak replay event lama).
    if (!isCaller && !_closed) {
      try {
        final row = await _service.getCall(callId);
        final st = row?['status'] as String?;
        if (st == 'canceled' || st == 'ended') {
          _finish(CallEndReason.canceled);
          return;
        }
        if (st == 'declined' || st == 'busy') {
          _finish(
            st == 'declined' ? CallEndReason.declined : CallEndReason.busy,
          );
          return;
        }
      } catch (_) {}
    }

    if (isCaller) {
      _phase = CallPhase.ringing;
      debugPrint(
        '[SESSION] init#${hashCode} tail -> ringing (caller)',
      ); // Caller menyerah setelah 30 detik tidak dijawab → cancel.
      _ringTimer = Timer(const Duration(seconds: 30), () {
        if (_closed || _phase != CallPhase.ringing) return;
        _service.sendSignal(callId, 'bye');
        _service.updateStatus(callId, 'canceled');
        _finish(CallEndReason.missed);
      });
      // Buat offer segera (callee sudah subscribe signal sejak layar
      // incoming call terbuka) — jangan tunggu event 'answered' dari DB
      // yang bisa tidak sampai ke caller.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!_closed && _pc != null) _createOffer();
      });
    } else {
      _phase = CallPhase.connecting;
      debugPrint('[SESSION] init#${hashCode} tail -> connecting (callee)');
    }
    notifyListeners();
    // Re-sync berkala sebagai jaring pengaman bila realtime signal terlewat.
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _syncAll());
  }

  Future<void> _setupMediaAndPeer() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': callType == 'video' ? {'facingMode': 'user'} : false,
      });
      localRenderer.srcObject = _localStream;

      _pc = await createPeerConnection(await CallConfig.getPeerConfig());
      _pc!.onTrack = (event) async {
        debugPrint('[ICE] onTrack kind=${event.track.kind}');
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
        debugPrint(
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
        debugPrint('[ICE] local candidate: ${candidate.candidate}');
        _service.sendSignal(
          callId,
          'candidate',
          payload: {'candidate': candidate.toMap()},
        );
      };
      _pc!.onConnectionState = (state) {
        debugPrint('[ICE] connectionState: $state');
        if (_closed) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          if (!_closed && _phase != CallPhase.inCall) {
            _phase = CallPhase.inCall;
            _connectedAt = DateTime.now();
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
                debugPrint('[ICE] grace-timeout still $cur -> bye + _finish');
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
        final cur = _pc?.connectionState;
        if (cur == RTCPeerConnectionState.RTCPeerConnectionStateConnected)
          return;
        debugPrint(
          '[ICE] 15s timeout still $cur phase=$_phase -> bye + _finish error',
        );
        try {
          await _service.sendSignal(callId, 'bye');
          await _service.updateStatus(callId, 'ended');
        } catch (_) {}
        _finish(CallEndReason.error);
      });
      _pc!.onIceConnectionState = (state) {
        debugPrint('[ICE] iceConnectionState: $state');
        if (_closed) return;
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          if (_phase != CallPhase.inCall) {
            debugPrint('[ICE] iceConnected -> SET inCall');
            _phase = CallPhase.inCall;
            _connectedAt = _connectedAt ?? DateTime.now();
            notifyListeners();
          }
        }
      };
      _pc!.onIceGatheringState = (state) {
        debugPrint('[ICE] iceGatheringState: $state');
      };
      _pc!.onSignalingState = (state) {
        debugPrint('[ICE] signalingState: $state');
      };
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
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
      debugPrint('[CallSession] media/peer setup failed: $e');
      if (!_closed) {
        _phase = CallPhase.error;
        notifyListeners();
      }
    }
  }

  Future<void> _createOffer() async {
    if (_closed || _pc == null || _offered) return;
    _offered = true;
    try {
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _service.sendSignal(
        callId,
        'offer',
        payload: {'sdp': offer.toMap()},
      );
    } catch (e) {
      debugPrint('[CallSession] createOffer failed: $e');
    }
  }

  Future<void> _onSignal(Map<String, dynamic> msg) async {
    final id = msg['id'] as String?;
    if (id != null) {
      if (_processedSignalIds.contains(id)) return;
      _processedSignalIds.add(id);
    }
    debugPrint(
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
          debugPrint('[ICE] queue candidate (pc not ready)');
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
            debugPrint('[ICE] duplicate offer ignored');
            return;
          }
          await _pc!.setRemoteDescription(
            RTCSessionDescription(sdp['sdp'], sdp['type']),
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
          await _pc!.setLocalDescription(answer);
          await _service.sendSignal(
            callId,
            'answer',
            payload: {'sdp': answer.toMap()},
          );
          await _syncAll();
        case 'answer':
          final sdp = msg['sdp'] as Map<String, dynamic>?;
          if (sdp == null) return;
          await _pc!.setRemoteDescription(
            RTCSessionDescription(sdp['sdp'], sdp['type']),
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
            debugPrint('[ICE] queue candidate (remoteDescription null)');
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
              debugPrint('[ICE] queue candidate (add failed, will retry)');
            } else {
              rethrow;
            }
          }
        case 'camera':
          final en = msg['enabled'];
          if (en is bool) {
            _remoteCameraOn = en;
            debugPrint('[CallSession] remoteCameraOn=$_remoteCameraOn');
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
      debugPrint('[CallSession] signal error: $e');
    }
  }

  // ── Watcher: pantau call dari admin panel ────────────────────────────────
  // Admin membuat peer connection penerima (tanpa media lokal). Sisi user
  // yang memegang stream lokal: terima watch_request → buat pc kedua →
  // kirim watch_offer. Tipe sinyal ber-namespace "watch_*" supaya tidak
  // menyentuh negosiasi offer/answer P2P utama.

  /// Admin minta menonton/mendengar call ini. Hanya admin terverifikasi
  /// yang dilayani — uid lain diabaikan (anti intip).
  Future<void> _handleWatchRequest(Map<String, dynamic> msg) async {
    final watcher = msg['from'] as String?;
    final me = _service.uid;
    if (_closed || watcher == null || watcher.isEmpty || watcher == me) return;
    if (_localStream == null || _pc == null) return;
    // Throttle: request ulang <8s diabaikan agar pc tidak dibuat-ulang
    // tiap polling; request setelah itu dianggap retry negosiasi mati.
    final last = _lastWatchReply[watcher];
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _lastWatchReply[watcher] = DateTime.now();
    try {
      final isAdmin = await (_watcherAdminChecks.putIfAbsent(
        watcher,
        () => _service.isAdminUid(watcher),
      ));
      if (!isAdmin) return;
      final old = _watchPcs.remove(watcher);
      if (old != null) {
        try {
          await old.close();
        } catch (_) {}
      }
      _watchPendingCands.remove(watcher);
      final pc = await createPeerConnection(await CallConfig.getPeerConfig());
      _watchPcs[watcher] = pc;
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
      debugPrint('[WATCH] offer sent to watcher=$watcher');
    } catch (e) {
      debugPrint('[WATCH] handle watch_request failed: $e');
      final broken = _watchPcs.remove(watcher);
      try {
        await broken?.close();
      } catch (_) {}
    }
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
      debugPrint('[WATCH] handle watch_answer failed: $e');
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
      debugPrint('[WATCH] candidate error: $e');
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
  void _touchHeartbeat() {
    final now = DateTime.now();
    if (_lastTouch != null && now.difference(_lastTouch!).inSeconds < 15)
      return;
    _lastTouch = now;
    _service.touchCall(callId);
  }

  Future<void> _syncAll() async {
    if (_closed) return;
    _touchHeartbeat();
    try {
      // Fallback status check — tangkap ended/canceled yang miss dari realtime
      final row = await _service.getCall(callId);
      if (!_closed) {
        final st = row?['status'] as String?;
        if (st == 'ended' || st == 'canceled') {
          _finish(CallEndReason.ended);
          return;
        }
      }
    } catch (_) {}
    if (_closed) return;
    // Safety-net fase: kadang callback onConnectionState/onIceConnectionState
    // tidak dipanggil di sebagian device sehingga UI nyangkut "Menghubungkan"
    // padahal media sudah mengalir. Cek state PC langsung tiap sync.
    final curState = _pc?.connectionState;
    if (curState == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
        _phase != CallPhase.inCall) {
      debugPrint('[ICE] sync safety-net -> SET inCall');
      _phase = CallPhase.inCall;
      _connectedAt = _connectedAt ?? DateTime.now();
      notifyListeners();
    }
    try {
      final rows = await _service.syncCallSignals(callId);
      for (final row in rows) {
        if (_closed) return;
        if (row['from_uid'] == _service.uid) continue;
        final id = row['id']?.toString();
        if (id != null && _processedSignalIds.contains(id)) continue;
        final type = row['type'] as String?;
        final payload = (row['payload'] as Map?)?.cast<String, dynamic>() ?? {};
        await _onSignal({'id': id, 'type': type, ...payload});
      }
    } catch (_) {}
  }

  // ── Kontrol ──
  Future<void> toggleMic() async {
    _micOn = !_micOn;
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track != null) track.enabled = _micOn;
    _notifyWatchersState();
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    if (callType != 'video') return;
    _cameraOn = !_cameraOn;
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) track.enabled = _cameraOn;
    _notifyWatchersState();
    notifyListeners();
    try {
      await _service.sendSignal(
        callId,
        'camera',
        payload: {'enabled': _cameraOn},
      );
    } catch (_) {}
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);
    notifyListeners();
  }

  /// Caller membatalkan panggilan (masih ringing) atau mengakhiri.
  Future<void> end() async {
    if (_closed) return;
    if (isCaller && _phase == CallPhase.ringing) {
      _ringTimer?.cancel();
      await _service.sendSignal(callId, 'bye');
      await _service.updateStatus(callId, 'canceled');
      _finish(CallEndReason.missed);
      return;
    }
    await _service.sendSignal(callId, 'bye');
    await _service.updateStatus(callId, 'ended');
    _finish(CallEndReason.ended);
  }

  void _finish(CallEndReason reason) {
    if (_closed) return;
    debugPrint('[CallService] _finish reason=$reason phase=$_phase');
    _closed = true;
    _endReason = reason;
    _ringTimer?.cancel();
    _syncTimer?.cancel();
    _phase = CallPhase.ended;
    notifyListeners();
    // Kirim pesan riwayat call ke private chat (hanya caller yang kirim,
    // supaya tidak duplikat di kedua sisi).
    if (isCaller) {
      final myUid = _service.uid;
      if (myUid != null) {
        final dur = _connectedAt != null
            ? DateTime.now().difference(_connectedAt!).inSeconds
            : 0;
        final statusText = switch (reason) {
          CallEndReason.ended => 'Call ended',
          CallEndReason.declined => 'Call declined',
          CallEndReason.missed => 'Missed call',
          CallEndReason.canceled => 'Call canceled',
          CallEndReason.busy => 'Busy',
          CallEndReason.error => 'Call failed',
        };
        _service.sendCallMessage(
          myUid: myUid,
          otherUid: remoteUid,
          myName: myName,
          myGender: myGender,
          callType: callType,
          status: statusText,
          durationSeconds: dur,
        );
      }
    }
  }

  /// Bersihkan semua resource WebRTC. Panggil dari dispose screen.
  Future<void> close() async {
    _closed = true;
    _ringTimer?.cancel();
    _syncTimer?.cancel();
    _pendingCandidates.clear();
    _pendingSignals.clear();
    for (final pc in _watchPcs.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _watchPcs.clear();
    _watchPendingCands.clear();
    _lastWatchReply.clear();
    _watcherAdminChecks.clear();
    await _signalSub?.cancel();
    await _statusSub?.cancel();
    _service.disposeSignal(callId);
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      await localRenderer.dispose();
    } catch (_) {}
    try {
      await remoteRenderer.dispose();
    } catch (_) {}
  }
}
