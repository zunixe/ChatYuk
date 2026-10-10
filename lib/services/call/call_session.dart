import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../config/call_config.dart';
import '../../config/strings.dart';
import '../../core/call/call_permissions.dart' show CallMediaError;
import '../../core/call/opus_sdp.dart';
import '../../core/call/watch_policy.dart';
import '../../core/perf/perf_probe.dart';
import '../../utils.dart';
import '../call_service.dart';

part 'call_session_media.dart';
part 'call_session_signal.dart';
part 'call_session_watch.dart';

const _watchPcStale = Duration(seconds: 20);

/// Fase panggilan.
enum CallPhase { connecting, ringing, inCall, ended, error }

/// Alasan panggilan berakhir — buat pesan di UI.
enum CallEndReason { ended, declined, busy, canceled, missed, error }

/// Pemetaan alasan berakhir → pesan. Satu sumber kebenaran supaya CallScreen
/// (fullscreen) & ChatCallOverlay (video-in-chat) tidak pernah beda teks.
extension CallEndReasonMessage on CallEndReason {
  String message(S s) {
    switch (this) {
      case CallEndReason.declined:
        return s.msgCallDeclined;
      case CallEndReason.busy:
        return s.msgCallBusy;
      case CallEndReason.missed:
        return s.msgCallMissed;
      case CallEndReason.error:
        return s.msgCallError;
      case CallEndReason.ended:
      case CallEndReason.canceled:
        return s.msgCallEnded;
    }
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
/// State instance + helper bersama — dipakai mixin per-domain (file `part`).
abstract class _CallBase extends ChangeNotifier {
  final String callId;
  final String remoteUid;
  final String remoteName;
  final String callType;
  final bool isCaller;
  final String myName;
  final String myGender;
  final List<Map<String, dynamic>> pendingSignals;

  final CallService _service = CallService.instance;

  _CallBase({
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
  int _syncTick = 0;
  bool _closed = false;
  bool _offered = false;
  // ICE restart: otomatis 1× saat Disconnected/Failed (tunggu 2 dtk dulu).
  // Kalau masih gagal → flag _iceReconnectFailed, UI tampilkan tombol
  // "Sambung ulang" manual (jangan auto-tutup; user pilih retry/akhiri).
  bool _iceRestarted = false;
  bool _iceReconnectFailed = false;

  /// True bila peer config saat ini memaksa `iceTransportPolicy: 'relay'`
  /// (Cloudflare OK). Dipakai sebagai sinyal untuk fallback sekali ke
  /// "semua tipe kandidat" saat relay tak terjangkau & ICE gagal — supaya
  /// P2P di jaringan sama masih bisa connect tanpa TURN.
  /// Default **true** = perilaku lama (relay-only bila Cloudflare tersedia).
  bool _relayOnly = true;

  /// True bila fallback "all candidates" (tanpa relay-only) sudah dicoba —
  /// hindari loop; cukup sekali per sesi.
  bool _iceAllCandidatesTried = false;

  /// True bila ICE sudah dicoba restart tapi masih buruk — UI menampilkan
  /// tombol sambung-ulang manual di samping tombol akhiri.
  bool get iceReconnectFailed => _iceReconnectFailed;

  /// True bila sesi masih hidup (belum `_finish`) dan tombol "Sambung ulang"
  /// manual masih bisa memulihkan koneksi. Setelah `_finish` (ended/timeout)
  /// `_closed` = true → `reconnect()` no-op, jadi UI jangan menampilkannya.
  bool get canReconnect => !_closed;

  /// Alasan spesifik kegagalan setup media — dipakai UI supaya user tahu
  /// apakah masalahnya izin (buka Pengaturan) atau kamera dipakai app lain.
  /// Null bila bukan kegagalan media (mis. ICE timeout).
  CallMediaError? _mediaError;
  CallMediaError? get mediaError => _mediaError;

  // ── Billing call (YukCoin) ──
  // Penelepon didebit per menit oleh server (call_billing_tick) — server
  // otoritatif dari calls.answered_at. Client hanya PEMICU tick tiap menit.
  Timer? _billingTimer;
  int _billingPerMin = 0;
  int _billingCharged = 0;
  bool _billingEndedNoCoin = false;
  int get billingPerMinute => _billingPerMin;
  int get billingChargedTotal => _billingCharged;
  bool get endedDueToNoCoin => _billingEndedNoCoin;

  /// Tarif per menit call ini (dari client pricing) — dipakai UI untuk
  /// menampilkan banner SEBELUM tick pertama tiba.
  void setBillingPerMinute(int v) => _billingPerMin = v;

  /// Test-only: paksa fase & alasan kegagalan media untuk memverifikasi UI
  /// (mis. overlay menampilkan pesan error + tombol sambung ulang).
  @visibleForTesting
  void debugSetPhase(CallPhase phase, {CallMediaError? mediaError}) {
    _phase = phase;
    _mediaError = mediaError;
    notifyListeners();
  }

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
  // Watcher yang minta pantau SEBELUM media lokal siap — diantre, dibalas
  // begitu `_setupMediaAndPeer` selesai (dulu request dibuang diam-diam →
  // admin menunggu tick permintaan berikutnya = audio telat).
  final Set<String> _pendingWatchRequests = {};

  /// Waktu pc watch dibuat per watcher — kunci anti-deadlock: pc yang belum
  /// `connected` lebih dari [_watchPcStale] dianggap mati → boleh rebuild
  /// (mis. offer hilang / ICE nyangkut di `connecting`).
  final Map<String, DateTime> _watchPcCreatedAt = {};

  CallPhase _phase = CallPhase.connecting;
  CallEndReason _endReason = CallEndReason.ended;
  bool _micOn = true;
  bool _cameraOn = true;
  bool _remoteCameraOn = true;
  // Inisialisasi di init(): audio call → earpiece (privasi + echo rendah),
  // video call → speaker. Di-set lewat _initAudioRoute().
  bool _speakerOn = true;
  DateTime? _connectedAt;
  // Instrumentasi (PERF_PROBE): tonggak waktu untuk metrik connect.
  DateTime? _initStartedAt;
  DateTime? _offerSentAt;

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

  // Kontrak lintas-mixin (didefinisikan di CallSession / mixin lain) — agar
  // mixin per-domain (`on _CallBase`) bisa memanggilnya tanpa siklik.
  void _recordConnected(String source);
  void _setProximity(bool on);
  void _startBilling();
  void _finish(CallEndReason reason);
  Future<void> _retryWithAllCandidates();
  Future<void> _createOffer();
  Future<void> _handleSignal(Map<String, dynamic> msg);
  Future<void> _sampleAudioRtt();
  Future<void> _syncAll();
  Future<void> _handleWatchRequest(Map<String, dynamic> msg);
  Future<void> _handleWatchAnswer(Map<String, dynamic> msg);
  Future<void> _handleWatchCandidate(Map<String, dynamic> msg);
}

class CallSession extends _CallBase
    with _CallSessionMediaMx, _CallSessionSignalMx, _CallSessionWatchMx {
  CallSession({
    required super.callId,
    required super.remoteUid,
    required super.remoteName,
    required super.callType,
    required super.isCaller,
    super.myName,
    super.myGender,
    super.pendingSignals,
  });

  /// Siapkan renderer + media lokal + peer connection + listener sinyal.
  /// Belum membuat offer — caller menunggu callee jawab.
  Future<void> init() async {
    dlog(
      '[ICE] ===== init#${hashCode} start isCaller=$isCaller callId=$callId (pc=${_pc != null}) =====',
    );
    if (_pc != null) {
      dlog('[ICE] init() already ran (pc exists) -> skip to avoid phase reset');
      return;
    }
    _initStartedAt = DateTime.now();
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    // Route audio default: audio call → earpiece (privasi + echo rendah),
    // video call → speaker. Bluetooth yang tersambung tetap diprioritaskan
    // (headset tidak terputus saat masuk call). Best-effort.
    await _initAudioRoute();

    _signalSub = _service
        .onSignal(callId)
        .listen(
          _onSignal,
          onError: (e) => dlog('[CallService] signal stream error: $e'),
        );

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
            dlog('[SESSION] answered#${hashCode} caller -> connecting');
            notifyListeners();
            _createOffer();
          }
      }
    }, onError: (e) => dlog('[CallService] status stream error: $e'));

    await PerfProbe.timed('call.setupMedia', _setupMediaAndPeer);

    // Media siap → balas permintaan pantau yang datang terlalu dini.
    unawaited(_flushPendingWatchRequests());

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
      dlog(
        '[SESSION] init#${hashCode} tail -> ringing (caller)',
      ); // Caller menyerah setelah 30 detik tidak dijawab → cancel.
      _ringTimer = Timer(const Duration(seconds: 30), () {
        if (_closed || _phase != CallPhase.ringing) return;
        _service.sendSignal(callId, 'bye');
        _service.updateStatus(callId, 'canceled');
        _finish(CallEndReason.missed);
      });
      // Buat offer SEGERA (callee sudah subscribe signal sejak layar
      // incoming call terbuka) — jangan tunggu event 'answered' dari DB
      // yang bisa tidak sampai ke caller. _createOffer idempoten (guard
      // _offered): panggil langsung + fallback 150ms bila _pc belum siap
      // tepat saat ini.
      // ignore: discarded_futures
      unawaited(_createOffer());
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!_closed && _pc != null) _createOffer();
      });
    } else {
      _phase = CallPhase.connecting;
      dlog('[SESSION] init#${hashCode} tail -> connecting (callee)');
      // RACE: penelepon bisa menekan akhiri SETELAH cek status awal di atas
      // tapi SEBELUM langganan realtime benar-benar aktif — Realtime tidak
      // me-replay event lama → penerima nyangkut "menghubungkan…" padahal
      // penelepon sudah gagal. Poll pendek menutup celah itu.
      unawaited(_watchCallerAlive());
    }
    notifyListeners();
    // Re-sync berkala sebagai jaring pengaman bila realtime signal terlewat.
    // 12 dtk (dulu 2 dtk) — realtime onSignal/onCallStatus jalur utama;
    // _syncAll skip sendiri saat sudah connected & ICE stabil.
    _syncTimer = Timer.periodic(const Duration(seconds: 12), (_) => _syncAll());
  }

  /// Pengaman sisi PENERIMA: selama masih `connecting` (belum tersambung),
  /// cek status call berkala. Kalau penelepon sudah membatalkan/mengakhiri
  /// tapi event realtime-nya terlewat (race langganan), tutup di sini supaya
  /// layar tidak nyangkut "menghubungkan…". Berhenti otomatis saat tersambung
  /// atau sesi ditutup.
  Future<void> _watchCallerAlive() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_closed || _phase == CallPhase.inCall) return;
      try {
        final row = await _service.getCall(callId);
        final st = row?['status'] as String?;
        if (st == 'canceled' || st == 'ended') {
          dlog('[SESSION] callee: caller sudah $st (poll) -> tutup');
          _finish(CallEndReason.canceled);
          return;
        }
      } catch (_) {}
    }
  }

  /// ICE restart: dipanggil otomatis 1× saat Disconnected/Failed menetap,
  /// atau manual lewat tombol "Sambung ulang" ([reconnect]).
  /// Caller men-drive re-negosiasi (restartIce + offer ulang); callee cukup
  /// restartIce (offer ulang dari caller akan tiba via signaling).

  /// Fallback saat relay-only tidak connect: buat ulang peer connection
  /// TANPA `iceTransportPolicy: 'relay'` sehingga kandidat host/srflx ikut
  /// dinegosiasikan — P2P di jaringan sama (WiFi/hotspot) bisa tersambung
  /// walau TURN tak terjangkau. Cukup SEKALI per sesi (guard
  /// `_iceAllCandidatesTried`).
  Future<void> _retryWithAllCandidates() async {
    if (_closed) return;
    _iceAllCandidatesTried = true;
    dlog('[ICE] fallback relay-only -> all candidates (P2P)');
    // Tutup pc lama & sinyal stale supaya negosiasi bersih.
    final old = _pc;
    _pc = null;
    try {
      await old?.close();
    } catch (_) {}
    // Lepas stream lokal lama agar kamera/mik tidak bocor (setup ulang
    // di bawah membuka track baru; izin sudah ada jadi cepat).
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    await _signalSub?.cancel();
    _signalSub = null;
    _service.disposeSignal(callId);
    _pendingSignals.clear();
    _pendingCandidates.clear();
    _processedSignalIds.clear();
    _offered = false;
    _relayOnly = false;
    _phase = CallPhase.connecting;
    notifyListeners();
    // Bangun ulang peer connection + media.
    await _setupMediaAndPeer();
    if (_closed) return;
    // Langganan sinyal WAJIB dipasang ulang (dibatalkan di atas) — tanpa ini
    // answer/offer balasan tidak pernah tiba & call gantung selamanya.
    _signalSub = _service
        .onSignal(callId)
        .listen(
          _onSignal,
          onError: (e) => dlog('[CallService] signal stream error: $e'),
        );
    if (_pc == null) {
      _iceReconnectFailed = true;
      notifyListeners();
      return;
    }
    // Caller men-drive offer ulang; callee menunggu offer baru tiba.
    if (isCaller && !_closed) {
      await _createOffer();
    }
    // Recheck: kalau masih tak connect setelah jendela fallback → tombol manual.
    Future.delayed(const Duration(seconds: 8), () {
      if (_closed || _phase == CallPhase.inCall) return;
      final st = _pc?.connectionState;
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) return;
      _iceReconnectFailed = true;
      dlog('[ICE] still bad after all-candidates fallback -> tombol manual');
      notifyListeners();
    });
  }

  // ── Watcher: pantau call dari admin panel ────────────────────────────────
  // Admin membuat peer connection penerima (tanpa media lokal). Sisi user
  // yang memegang stream lokal: terima watch_request → buat pc kedua →
  // kirim watch_offer. Tipe sinyal ber-namespace "watch_*" supaya tidak
  // menyentuh negosiasi offer/answer P2P utama.

  /// Admin minta menonton/mendengar call ini. Hanya admin terverifikasi
  /// yang dilayani — uid lain diabaikan (anti intip).
  ///
  /// ANTI PUTUS-AUDIO: bila pc watch untuk watcher ini MASIH ADA & sehat
  /// (connecting/connected/disconnected), JANGAN tutup-buat-ulang —
  /// cukup kirim ulang status mic/kamera. Dulu tiap `watch_request` yang
  /// lolos throttle 8 dtk menutup pc lama → audio peserta putus sesaat
  /// ("suara sempat hilang, muncul lagi"). Lihat `watch_policy.dart`.

  Future<void> _syncAll() async {
    if (_closed) return;
    _touchHeartbeat();
    // Hemat: saat sudah inCall & ICE connected, sinyal lengkap via realtime —
    // lewati poll DB berat (getCall + full syncCallSignals) kecuali sesekali.
    // Counter statis per sesi: sync penuh tiap tick ke-3 (~36 dtk).
    _syncTick = (_syncTick + 1) % 3;
    final curStateEarly = _pc?.connectionState;
    final stableConnected =
        curStateEarly ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
        _phase == CallPhase.inCall;
    if (stableConnected && _syncTick != 0) return;
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
      dlog('[ICE] sync safety-net -> SET inCall');
      _phase = CallPhase.inCall;
      _connectedAt = _connectedAt ?? DateTime.now();
      _recordConnected('syncSafetyNet');
      _startBilling();
      _setProximity(true);
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

  /// Route audio awal sesi (dipanggil sekali di init()).
  /// Audio call → earpiece (privasi + echo rendah); video call → speaker.
  /// Tombol speaker di UI tetap bisa mengubah setelahnya. Best-effort.
  Future<void> _initAudioRoute() async {
    _speakerOn = callType == 'video';
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);
    notifyListeners();
  }

  /// Caller membatalkan panggilan (masih ringing) atau mengakhiri.
  Future<void> end() async {
    if (_closed) return;
    // OPTIMISTIK: tandai selesai SEKARANG (UI langsung hilang/berubah),
    // lalu kirim signal + update status di belakang. Dulu await 2 round-trip
    // network DULU → tombol "Akhiri" terasa tidak merespons di jaringan lambat.
    final wasRinging = isCaller && _phase == CallPhase.ringing;
    _finish(wasRinging ? CallEndReason.missed : CallEndReason.ended);
    _ringTimer?.cancel();
    // Fire-and-forget: kegagalan kirim tidak boleh menahan UI.
    unawaited(_service.sendSignal(callId, 'bye'));
    unawaited(_service.updateStatus(callId, wasRinging ? 'canceled' : 'ended'));
  }

  // ── Billing call ──
  // Hanya PEMANGGIL (isCaller) yang ditagih. Tick tiap menit; server
  // memutuskan biaya dari answered_at. Bila server bilang can_continue=false
  // → akhiri call ini (saldo habis).
  void _startBilling() {
    if (!isCaller) return;
    _billingTimer?.cancel();
    unawaited(_billingTick());
    _billingTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_billingTick()),
    );
  }

  Future<void> _billingTick() async {
    if (_closed) return;
    try {
      final res = await _service.callBillingTick(callId);
      if (_closed) return;
      _billingCharged = (res['charged_total'] as num?)?.toInt() ?? 0;
      // Tarif per menit dari server → banner "N coin/menit" hidup.
      final perMin = (res['per_minute'] as num?)?.toInt();
      if (perMin != null && perMin > 0) _billingPerMin = perMin;
      if (res['can_continue'] == false) {
        _billingEndedNoCoin = true;
        _service.sendSignal(callId, 'bye');
        _service.updateStatus(callId, 'ended');
        _finish(CallEndReason.ended);
        return;
      }
      notifyListeners();
    } catch (e) {
      // Kegagalan tick TIDAK memutus call (jaringan buruk).
      dlog('[CALL] billing tick error: $e');
    }
  }

  void _stopBilling() {
    _billingTimer?.cancel();
    _billingTimer = null;
  }

  // ── Proximity (audio call) ──
  // Layar mati saat HP didekatkan ke telinga — hemat baterai + cegah pipi
  // menyentuh tombol. HANYA audio (video butuh layar hidup). Best-effort.
  bool _proximityOn = false;

  void _setProximity(bool on) {
    if (callType != 'audio') return; // video: layar harus tetap hidup
    if (_proximityOn == on) return;
    _proximityOn = on;
    unawaited(_service.callUi.setProximity(on).catchError((_) {}));
  }

  void _finish(CallEndReason reason) {
    if (_closed) return;
    dlog('[CallService] _finish reason=$reason phase=$_phase');
    _closed = true;
    _endReason = reason;
    _ringTimer?.cancel();
    _syncTimer?.cancel();
    _stopBilling();
    _setProximity(false);
    _service.releaseCallStatus(callId);
    _phase = CallPhase.ended;
    notifyListeners();
    // Pesan riwayat call di private chat kini dibuat SATU sumber saja di
    // server (trigger call_history_insert saat status calls berubah) —
    // supaya tidak ada pesan ganda (client + server) yang memicu
    // notifikasi missed_call ganda.
  }

  /// Bersihkan semua resource WebRTC. Panggil dari dispose screen.
  Future<void> close() async {
    _closed = true;
    _ringTimer?.cancel();
    _syncTimer?.cancel();
    _stopBilling();
    _setProximity(false);
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
    _watchPcCreatedAt.clear();
    _pendingWatchRequests.clear();
    await _signalSub?.cancel();
    await _statusSub?.cancel();
    _service.disposeSignal(callId);
    // Bersihkan channel status sharing SETELAH cancel (dulu di _finish saat
    // listener masih aktif → hasListener guard menolak → bocor permanen).
    _service.releaseCallStatus(callId);
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
