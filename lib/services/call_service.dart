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

  Future<String?> getNickname(String uid) async {
    final row = await _sb
        .from('profiles')
        .select('nickname')
        .eq('id', uid)
        .maybeSingle();
    return row?['nickname'] as String?;
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
        controller.add(payload.newRecord['status'] as String? ?? '');
      },
    );
    channel.subscribe();
    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }

  // ── Signaling (broadcast ephemeral) ──
  RealtimeChannel _signalChannel(String callId) {
    return _signalChannels.putIfAbsent(callId, () {
      final ch = _sb.channel('call-signal-$callId');
      ch.subscribe();
      return ch;
    });
  }

  Stream<Map<String, dynamic>> onSignal(String callId) {
    final controller = _signalStreams.putIfAbsent(
      callId,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    );
    _signalChannel(callId).onBroadcast(event: 'signal', callback: (payload) {
      if (controller.isClosed) return;
      // Broadcast ikut ter-echo ke pengirim — lewati pesan sendiri.
      if (payload['from_uid'] == uid) return;
      controller.add(Map<String, dynamic>.from(payload));
    });
    return controller.stream;
  }

  Future<void> sendSignal(String callId, String type,
      {Map<String, dynamic>? payload}) {
    return _signalChannel(callId).sendBroadcastMessage(
      event: 'signal',
      payload: {
        'from_uid': uid,
        'type': type,
        if (payload != null) ...payload,
      },
    );
  }

  void disposeSignal(String callId) {
    final controller = _signalStreams.remove(callId);
    if (controller != null && !controller.isClosed) controller.close();
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
  final String callType; // 'audio' | 'video'
  final bool isCaller;

  final CallService _service = CallService.instance;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<Map<String, dynamic>>? _signalSub;
  StreamSubscription<String>? _statusSub;
  Timer? _ringTimer;
  bool _closed = false;
  // Sinyal yang datang sebelum peer connection siap (offer bisa sampai
  // sebelum getUserMedia selesai di callee) — diproses setelah setup.
  final List<Map<String, dynamic>> _pendingSignals = [];

  CallPhase _phase = CallPhase.connecting;
  CallEndReason _endReason = CallEndReason.ended;
  bool _micOn = true;
  bool _cameraOn = true;
  bool _speakerOn = true;
  DateTime? _connectedAt;

  CallPhase get phase => _phase;
  CallEndReason get endReason => _endReason;
  bool get micOn => _micOn;
  bool get cameraOn => _cameraOn;
  bool get speakerOn => _speakerOn;
  DateTime? get connectedAt => _connectedAt;
  MediaStream? get remoteStream => _remoteStream;

  CallSession({
    required this.callId,
    required this.remoteUid,
    required this.remoteName,
    required this.callType,
    required this.isCaller,
  });

  /// Siapkan renderer + media lokal + peer connection + listener sinyal.
  /// Belum membuat offer — caller menunggu callee jawab.
  Future<void> init() async {
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
        case 'answered':
          // Caller: callee sudah terima → baru buat offer.
          if (isCaller && _phase == CallPhase.ringing) {
            _ringTimer?.cancel();
            _phase = CallPhase.connecting;
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
          _finish(st == 'declined'
              ? CallEndReason.declined
              : CallEndReason.busy);
          return;
        }
      } catch (_) {}
    }

    if (isCaller) {
      _phase = CallPhase.ringing;
      // Caller menyerah setelah 30 detik tidak dijawab → cancel.
      _ringTimer = Timer(const Duration(seconds: 30), () {
        if (_closed || _phase != CallPhase.ringing) return;
        _service.sendSignal(callId, 'bye');
        _service.updateStatus(callId, 'canceled');
        _finish(CallEndReason.missed);
      });
    } else {
      _phase = CallPhase.connecting;
    }
    notifyListeners();
  }

  Future<void> _setupMediaAndPeer() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video':
            callType == 'video' ? {'facingMode': 'user'} : false,
      });
      localRenderer.srcObject = _localStream;

      _pc = await createPeerConnection(CallConfig.peerConfig);
      _pc!.onTrack = (event) async {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams.first;
        } else if (event.track != null) {
          // Jarang terjadi — sebagian implementasi tidak mengirim streams.
          final stream = await createLocalMediaStream('remote');
          await stream.addTrack(event.track!);
          _remoteStream = stream;
        }
        if (_remoteStream != null) {
          remoteRenderer.srcObject = _remoteStream;
        }
        if (!_closed && _phase != CallPhase.inCall) {
          _phase = CallPhase.inCall;
          _connectedAt = DateTime.now();
          notifyListeners();
        }
      };
      _pc!.onIceCandidate = (candidate) {
        _service.sendSignal(callId, 'candidate',
            payload: {'candidate': candidate.toMap()});
      };
      _pc!.onConnectionState = (state) {
        if (_closed) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _finish(_phase == CallPhase.inCall
              ? CallEndReason.ended
              : CallEndReason.error);
        }
      };
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
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
    if (_closed || _pc == null) return;
    try {
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _service.sendSignal(callId, 'offer',
          payload: {'sdp': offer.toMap()});
    } catch (e) {
      debugPrint('[CallSession] createOffer failed: $e');
    }
  }

  Future<void> _onSignal(Map<String, dynamic> msg) async {
    if (_closed) return;
    if (_pc == null) {
      _pendingSignals.add(msg);
      return;
    }
    await _handleSignal(msg);
  }

  Future<void> _handleSignal(Map<String, dynamic> msg) async {
    if (_closed || _pc == null) return;
    try {
      switch (msg['type']) {
        case 'offer':
          final sdp = msg['sdp'] as Map<String, dynamic>?;
          if (sdp == null) return;
          await _pc!.setRemoteDescription(
              RTCSessionDescription(sdp['type'], sdp['sdp']));
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          await _service.sendSignal(callId, 'answer',
              payload: {'sdp': answer.toMap()});
        case 'answer':
          final sdp = msg['sdp'] as Map<String, dynamic>?;
          if (sdp == null) return;
          await _pc!.setRemoteDescription(
              RTCSessionDescription(sdp['type'], sdp['sdp']));
        case 'candidate':
          final c = msg['candidate'] as Map<String, dynamic>?;
          if (c == null) return;
          await _pc!.addCandidate(RTCIceCandidate(
            c['candidate'] ?? '',
            c['sdpMid'],
            (c['sdpMLineIndex'] as num?)?.toInt(),
          ));
        case 'bye':
          _finish(CallEndReason.ended);
      }
    } catch (e) {
      debugPrint('[CallSession] signal error: $e');
    }
  }

  // ── Kontrol ──
  Future<void> toggleMic() async {
    _micOn = !_micOn;
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track != null) track.enabled = _micOn;
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    if (callType != 'video') return;
    _cameraOn = !_cameraOn;
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) track.enabled = _cameraOn;
    notifyListeners();
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
    _closed = true;
    _endReason = reason;
    _ringTimer?.cancel();
    _phase = CallPhase.ended;
    notifyListeners();
  }

  /// Bersihkan semua resource WebRTC. Panggil dari dispose screen.
  Future<void> close() async {
    _closed = true;
    _ringTimer?.cancel();
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