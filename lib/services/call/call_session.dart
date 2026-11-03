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

  /// Siapa yang men-tick billing di sisi client. Default = isCaller
  /// (private: caller selalu payer). Random match: server menagih pihak
  /// MALE siapa pun caller-nya — caller di sini murni peran signaling.
  /// null → fallback isCaller; provider random-match mengisinya dari
  /// gender lokal supaya yang tick adalah device sang payer.
  final bool? billingPayer;

  bool get isBillingPayer => billingPayer ?? isCaller;

  /// Durasi gratis di awal call (detik) sebelum billing berjalan —
  /// Random Match = 30 (dijangkar ke `media_connected_at` di server);
  /// private = 0 (menit pertama langsung tertagih / kuota female).
  /// Diisi provider; UI memakai untuk countdown "gratis Ns".
  final int billingFreeGraceSec;

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
    this.billingPayer,
    this.billingFreeGraceSec = 0,
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
  /// Pengawas cepat fase: sebagian device (dilaporkan di Xiaomi) tidak
  /// memanggil onConnectionState/onIceConnectionState walau media sudah
  /// mengalir → layar tertahan "Menyambungkan…" sampai sync 12 dtk.
  /// Cek `pc.connectionState` langsung tiap 700 ms selama belum inCall.
  Timer? _phaseWatchTimer;
  int _syncTick = 0;
  bool _closed = false;
  bool _offered = false;
  // ICE restart: otomatis 1× saat Disconnected/Failed (tunggu 2 dtk dulu).
  // Kalau masih gagal → flag _iceReconnectFailed, UI tampilkan tombol
  // "Sambung ulang" manual (jangan auto-tutup; user pilih retry/akhiri).
  bool _iceRestarted = false;
  bool _iceReconnectFailed = false;

  /// Static: true setelah relay-only terbukti gagal sekali (pc pertama
  /// mencapai Failed sebelum fallback). Sesi berikutnya langsung
  /// all-candidates — menghemat ~3-4 dtk tunggu gagal TURN per call.
  /// Bukan paparan IP baru: call itu toh akan jatuh ke P2P juga.
  /// In-memory saja (per sesi aplikasi) + di-reset bila call non-relay
  /// ikut gagal total — jaringan mungkin berubah, relay diuji ulang.
  static bool _relaySuspect = false;

  /// True bila peer config saat ini memaksa `iceTransportPolicy: 'relay'`
  /// (Cloudflare OK). Dipakai sebagai sinyal untuk fallback sekali ke
  /// "semua tipe kandidat" saat relay tak terjangkau & ICE gagal — supaya
  /// P2P di jaringan sama masih bisa connect tanpa TURN.
  /// Default **true** = perilaku lama (relay-only bila Cloudflare tersedia),
  /// kecuali [_relaySuspect] sudah menandai relay mati di jaringan ini.
  bool _relayOnly = !_relaySuspect;

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
  /// Auto-hangup saat call dijeda karena koin habis — tanpa ini panggilan
  /// jalan terus GRATIS selamanya sampai salah satu pihak hangup manual.
  Timer? _pauseTimer;
  int _billingPerMin = 0;
  int _billingCharged = 0;
  int _billingIncome = 0;
  bool _billingEndedNoCoin = false;
  /// Error tick terakhir (jaringan/server) — untuk indikator kecil di UI.
  String? _billingTickError;
  String? get billingTickError => _billingTickError;
  /// Saldo habis di tengah panggilan → panggilan DIJEDA (bukan diputus) dan
  /// UI menampilkan dialog "lanjutkan + isi koin". Di-set oleh _billingTick.
  bool _awaitingContinue = false;
  /// Alasan server saat can_continue=false ('insufficient' | 'free_limit').
  /// 'free_limit' = kuota gratis female harian habis — top-up TIDAK bisa
  /// melanjutkan, UI harus menawarkan Akhiri saja.
  String? _billingPauseReason;
  /// Batas menit gratis female/hari dari server (untuk teks dialog).
  int _billingFreeLimitMin = 0;
  int get billingPerMinute => _billingPerMin;
  int get billingChargedTotal => _billingCharged;
  // Pendapatan live sisi penerima (female): diisi dari income_total pada
  // cabang info-only call_billing_tick — tanpa menagih siapa pun.
  int get billingIncome => _billingIncome;
  bool get endedDueToNoCoin => _billingEndedNoCoin;

  /// ICE lagi disambung-ulang (restart/fallback) padahal call sudah inCall —
  /// UI menampilkan indikator "Menyambungkan ulang" TANPA mengosongkan video
  /// (fase tetap inCall sehingga frame terakhir tak dibuang → tidak blank).
  bool _reconnecting = false;
  bool get isReconnecting => _reconnecting;

  /// Sisa detik gratis — dihitung lokal dari `connectedAt` (momen yang sama
  /// dengan yang di-stamp server sebagai `media_connected_at`). >0 hanya
  /// selama masa grace call match; private call selalu 0.
  int get billingFreeSecondsLeft {
    if (billingFreeGraceSec <= 0) return 0;
    final start = _connectedAt;
    if (start == null) return billingFreeGraceSec;
    final left =
        billingFreeGraceSec - DateTime.now().difference(start).inSeconds;
    return left > 0 ? left : 0;
  }

  /// Callback saldo: `call_billing_tick` mengembalikan `remaining` (saldo
  /// sisa) di SETIAP respons — dipakai untuk menyegarkan counter/kartu
  /// YukCoin tanpa RPC tambahan. Di-wire oleh callProvider (bridge ke
  /// pointsProvider); null = tidak dipakai (test).
  void Function(int total)? onBalanceUpdate;
  bool get awaitingContinue => _awaitingContinue;
  String? get billingPauseReason => _billingPauseReason;
  int get billingFreeLimitMin => _billingFreeLimitMin;

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

  /// Test-only: paksa total tagihan supaya UI counter koin bisa diverifikasi
  /// tanpa menjalankan tick billing sungguhan.
  @visibleForTesting
  void debugSetBilling({int? charged, int? remaining}) {
    if (charged != null) _billingCharged = charged;
    if (remaining != null) onBalanceUpdate?.call(remaining);
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
  // SDP offer remote terakhir yang sudah di-apply — dedup replay
  // (realtime + sync DB bisa mengirim offer yang sama berkali-kali)
  // TANPA menelan offer BARU dari retry/restart caller. Dedup lama
  // (`getRemoteDescription() != null → abaikan`) menelan semua offer
  // renegosiasi → caller & callee beda generasi pc → ICE tak pernah connect.
  String? _lastRemoteOfferSdp;
  // Sama untuk answer: replay DB bisa mengirim answer yang sama — dedup
  // per-konten supaya tak error "Called in wrong state: stable".
  String? _lastRemoteAnswerSdp;
  // Generasi offer/answer — caller menaikkan tiap `_createOffer` (retry /
  // ICE restart = sesi baru). Callee menolak offer dengan gen ≤ terakhir
  // (replay/stale) dan meng-echo gen di answer; caller menolak answer yang
  // bukan untuk gen penawaran terakhirnya. Tanpa ini, sinyal stale dari
  // sync DB bisa MENURUNKAN negosiasi ke generasi lama → ufrag beda →
  // ICE tak pernah connect (terbukti di logcat Redmi/Xiaomi).
  int _offerGen = 0;
  int _remoteOfferGen = -1;
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

  /// Konfirmasi ke server: apakah call ini sudah ditutup (status terminal)?
  /// Dipakai jalur kegagalan ICE — kematian media tak bisa membedakan
  /// "jaringan blip" dari "lawan menutup call" (sinyal `bye`/event realtime
  /// `ended` bisa terlewat saat channel drop). Status terminal → [_finish];
  /// error jaringan → dianggap belum berakhir (ICE retry tetap berjalan).
  Future<bool> _remoteEnded() async {
    if (_closed) return true;
    try {
      final row = await _service.getCall(callId);
      if (_closed) return true;
      final st = row?['status'] as String?;
      if (st == 'ended' || st == 'canceled') {
        dlog('[CALL] status call=$st (cek jalur ICE) -> _finish');
        _finish(CallEndReason.ended);
        return true;
      }
    } catch (e) {
      dlog('[CALL] cek status remote gagal: $e');
    }
    return false;
  }

  // Kontrak lintas-mixin (didefinisikan di CallSession / mixin lain) — agar
  // mixin per-domain (`on _CallBase`) bisa memanggilnya tanpa siklik.
  void _recordConnected(String source);
  void _setProximity(bool on);
  void _startBilling();
  void _finish(CallEndReason reason);
  Future<void> _retryWithAllCandidates();
  Future<void> reconnect();
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
    super.billingPayer,
    super.billingFreeGraceSec,
  });

  /// Siapkan renderer + media lokal + peer connection + listener sinyal.
  /// Belum membuat offer — caller menunggu callee jawab.
  Future<void> init() async {
    dlog(
      '[ICE] ===== init#$hashCode start isCaller=$isCaller callId=$callId (pc=${_pc != null}) =====',
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
            dlog('[SESSION] answered#$hashCode caller -> connecting');
            notifyListeners();
            _createOffer();
          } else if (isCaller && _phase == CallPhase.inCall) {
            // Sudah tersambung (ICE cepat) → jangan sentuh fase.
            _ringTimer?.cancel();
          }
      }
    }, onError: (e) => dlog('[CallService] status stream error: $e'));

    await PerfProbe.timed('call.setupMedia', _setupMediaAndPeer);
    _startPhaseWatch();

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
      } catch (e) { dlog('[CALL] cek status awal callee gagal: $e'); }
    }

    if (isCaller) {
      // JANGAN turunkan fase bila media sudah tersambung lebih dulu
      // (`_setupMediaAndPeer` + cek status di atas bisa memakan waktu,
      // sementara onConnectionState/onIceConnectionState sudah men-set
      // inCall). Dulu baris ini menimpa inCall → layar "Menyambungkan…"
      // selamanya walau suara/video sudah mengalir.
      if (_phase != CallPhase.inCall) {
        _phase = CallPhase.ringing;
      }
      dlog(
        '[SESSION] init#$hashCode tail -> ringing (caller)',
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
      // Idem: kalau ICE sudah Connected saat init masih berjalan, jangan
      // kembalikan ke connecting.
      if (_phase != CallPhase.inCall) {
        _phase = CallPhase.connecting;
      }
      dlog('[SESSION] init#$hashCode tail -> connecting (callee)');
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

  /// Cek state PC langsung (bukan menunggu callback). Berhenti sendiri
  /// begitu fase inCall atau sesi ditutup.
  void _startPhaseWatch() {
    _phaseWatchTimer?.cancel();
    _phaseWatchTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (_closed || _phase == CallPhase.inCall) {
        _phaseWatchTimer?.cancel();
        _phaseWatchTimer = null;
        return;
      }
      final cur = _pc?.connectionState;
      if (cur == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        dlog('[ICE] phaseWatch -> SET inCall');
        _reconnecting = false;
        _phase = CallPhase.inCall;
        _connectedAt = _connectedAt ?? DateTime.now();
        _recordConnected('phaseWatch');
        _startBilling();
        _setProximity(true);
        notifyListeners();
        _phaseWatchTimer?.cancel();
        _phaseWatchTimer = null;
      }
    });
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
      } catch (e) { dlog('[CALL] poll status callee gagal: $e'); }
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
  @override
  Future<void> _retryWithAllCandidates() async {
    if (_closed) return;
    _iceAllCandidatesTried = true;
    if (!isCaller) {
      // Callee TIDAK membangun ulang pc-nya sendiri — hanya caller yang
      // men-drive offer. Membangun ulang lokal menciptakan race generasi
      // (offer baru caller tertelan dedup di pc lama / kandidat beda
      // ufrag) → dua sisi tak pernah sinkron. Cukup minta caller re-offer;
      // pc lama dipertahankan: Failed ≠ Closed — offer baru menghidupkan
      // kembali lewat ICE restart, tanpa melepas kamera/mic.
      dlog('[ICE] callee minta fallback via ice_retry (bukan rebuild)');
      // Sudah inCall → tandai "menyambungkan" saja; menurunkan fase ke
      // connecting membuat UI membuang video → blank + "menghubungkan"
      // walau media cuma blip. Layar pra-sambung tetap pakai connecting.
      if (_phase == CallPhase.inCall) {
        _reconnecting = true;
      } else {
        _phase = CallPhase.connecting;
      }
      notifyListeners();
      unawaited(
        _service.sendSignal(callId, 'ice_retry').catchError((_) {}),
      );
      // Recheck seperti jalur caller: masih tak connect → cek dulu apakah
      // lawan sudah menutup call (ice_retry-nya tak akan pernah dibalas),
      // baru tawarkan tombol manual.
      Future.delayed(const Duration(seconds: 8), () async {
        if (_closed || _phase == CallPhase.inCall) return;
        final st = _pc?.connectionState;
        if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          return;
        }
        if (await _remoteEnded()) return;
        _iceReconnectFailed = true;
        dlog('[ICE] still bad after ice_retry request -> tombol manual');
        notifyListeners();
      });
      return;
    }
    dlog('[ICE] fallback relay-only -> all candidates (P2P)');
    // Tutup pc lama & sinyal stale supaya negosiasi bersih.
    final old = _pc;
    _pc = null;
    try {
      await old?.close();
    } catch (_) {} // cleanup best-effort: kegagalan tutup tidak memengaruhi UX
    // Stream lokal DIPERTAHANKAN: track kamera/mic hidup independen dari pc
    // dan bisa langsung di-addTrack ke pc baru — kamera tak re-init (yang
    // di Xiaomi lambat + bikin PiP blink) dan preview tak pernah kosong.
    await _signalSub?.cancel();
    _signalSub = null;
    _service.disposeSignal(callId);
    _pendingSignals.clear();
    _pendingCandidates.clear();
    _processedSignalIds.clear();
    _offered = false;
    _relayOnly = false;
    if (_phase == CallPhase.inCall) {
      _reconnecting = true;
    } else {
      _phase = CallPhase.connecting;
    }
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
    // Recheck: kalau masih tak connect setelah jendela fallback → cek dulu
    // apakah lawan sudah menutup call, baru tawarkan tombol manual.
    Future.delayed(const Duration(seconds: 8), () async {
      if (_closed || _phase == CallPhase.inCall) return;
      final st = _pc?.connectionState;
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateConnected) return;
      if (await _remoteEnded()) return;
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

  @override
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
    } catch (e) { dlog('[CALL] fallback cek status gagal: $e'); }
    if (_closed) return;
    // Safety-net fase: kadang callback onConnectionState/onIceConnectionState
    // tidak dipanggil di sebagian device sehingga UI nyangkut "Menghubungkan"
    // padahal media sudah mengalir. Cek state PC langsung tiap sync.
    final curState = _pc?.connectionState;
    if (curState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _reconnecting = false;
      if (_phase != CallPhase.inCall) {
        dlog('[ICE] sync safety-net -> SET inCall');
        _phase = CallPhase.inCall;
        _connectedAt = _connectedAt ?? DateTime.now();
        _recordConnected('syncSafetyNet');
        _startBilling();
        _setProximity(true);
        notifyListeners();
      }
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
    } catch (e) { dlog('[CALL] catch-up sinyal gagal: $e'); }
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
    } catch (e) { dlog('[CALL] kirim sinyal camera gagal: $e'); }
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
    } catch (_) {} // cleanup best-effort: kegagalan tutup tidak memengaruhi UX
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
  // Hanya sisi PAYER yang men-tick (isBillingPayer — private = caller,
  // random = pihak male, ditentukan provider). Tick tiap menit + tick
  // sekali di detik ~30 supaya grace 30 detik match ter-charge tepat
  // waktu; server memutuskan biaya dari answered_at. Bila server bilang
  // can_continue=false → jeda call ini (saldo habis).
  @override
  void _startBilling() {
    // Payer men-tick untuk menagih; sisi PENERIMA tetap men-tick — server
    // menjawab cabang info-only (income_total) tanpa menagih siapa pun,
    // supaya UI female bisa menampilkan pendapatan live.
    _billingTimer?.cancel();
    unawaited(_billingTick());
    Timer(const Duration(seconds: 30), () => unawaited(_billingTick()));
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
      _billingTickError = null;
      _billingCharged = (res['charged_total'] as num?)?.toInt() ?? 0;
      // income_total TIDAK selalu ada di respons (pause/error payer) —
      // jangan reset ke 0: pendapatan female adalah total kumulatif.
      if (res['income_total'] != null) {
        _billingIncome = (res['income_total'] as num).toInt();
      }
      // Saldo sisa dari tick → segarkan UI saldo (counter header call &
      // kartu profil) tanpa RPC tambahan.
      final remaining = (res['remaining'] as num?)?.toInt();
      if (remaining != null) onBalanceUpdate?.call(remaining);
      // Tarif per menit dari server → banner "N coin/menit" hidup.
      final perMin = (res['per_minute'] as num?)?.toInt();
      if (perMin != null && perMin > 0) _billingPerMin = perMin;
      if (res['can_continue'] == false) {
        // 2026-10-31: JANGAN putus. Jeda + minta user lanjutkan/top-up.
        // Hanya sisi PAYER yang menjeda+dialog — recipient (female) tak
        // perlu dan tak bisa apa-apa (server memberi respons read-only).
        // 'ended' = call sudah selesai → bukan jeda koin.
        if (isBillingPayer && res['ended'] != true) {
          _billingEndedNoCoin = true;
          _awaitingContinue = true;
          _billingPauseReason = res['reason'] as String?;
          _billingFreeLimitMin =
              (res['free_limit_min'] as num?)?.toInt() ?? _billingFreeLimitMin;
          _stopBilling();
          // Auto-hangup 60 dtk bila user tak melanjutkan — panggilan yang
          // dijeda tidak boleh jalan gratis selamanya.
          _pauseTimer?.cancel();
          _pauseTimer = Timer(const Duration(seconds: 60), () {
            if (_awaitingContinue && !_closed) endCallNoCoin();
          });
        }
        notifyListeners();
        return;
      }
      // Saldo cukup lagi → lanjut normal.
      if (_awaitingContinue) {
        _pauseTimer?.cancel();
        _awaitingContinue = false;
        _billingEndedNoCoin = false;
        _billingPauseReason = null;
      }
      notifyListeners();
    } catch (e) {
      // Kegagalan tick TIDAK memutus call (jaringan buruk) — tapi catat
      // supaya UI bisa menandai status billing tak terbarui.
      _billingTickError = e.toString();
      dlog('[CALL] billing tick error: $e');
      notifyListeners();
    }
  }

  /// User membuka pembelian koin: tahan auto-hangup selama Google Play
  /// memproses (dulu timer 60 dtk tetap jalan → call putus di tengah bayar).
  /// [resumeBillingAfterTopup] menyalakan lagi timer bila saldo masih kurang.
  void holdForTopup() {
    if (_awaitingContinue) _pauseTimer?.cancel();
  }

  /// Dipanggil UI setelah user mengisi koin: coba tagih lagi.
  /// Return true bila panggilan bisa lanjut.
  Future<bool> resumeBillingAfterTopup() async {
    if (!_awaitingContinue) return true;
    _pauseTimer?.cancel();
    _awaitingContinue = false;
    _billingEndedNoCoin = false;
    await _billingTick();
    if (_awaitingContinue) {
      // Masih kurang → mulai ulang penghitung auto-hangup.
      _pauseTimer?.cancel();
      _pauseTimer = Timer(const Duration(seconds: 60), () {
        if (_awaitingContinue && !_closed) endCallNoCoin();
      });
      return false;
    }
    // Mulai lagi timer per menit.
    if (!_closed && phase == CallPhase.inCall) {
      _billingTimer?.cancel();
      _billingTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => unawaited(_billingTick()),
      );
    }
    return true;
  }

  /// User memilih "Akhiri" saat koin habis.
  void endCallNoCoin() {
    _pauseTimer?.cancel();
    _awaitingContinue = false;
    _billingEndedNoCoin = true;
    _service.sendSignal(callId, 'bye');
    _service.updateStatus(callId, 'ended');
    _finish(CallEndReason.ended);
  }

  void _stopBilling() {
    _billingTimer?.cancel();
    _billingTimer = null;
  }

  void _stopPauseTimer() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
  }

  // ── Proximity (audio call) ──
  // Layar mati saat HP didekatkan ke telinga — hemat baterai + cegah pipi
  // menyentuh tombol. HANYA audio (video butuh layar hidup). Best-effort.
  bool _proximityOn = false;

  @override
  void _setProximity(bool on) {
    if (callType != 'audio') return; // video: layar harus tetap hidup
    if (_proximityOn == on) return;
    _proximityOn = on;
    unawaited(_service.callUi.setProximity(on).catchError((_) {}));
  }

  @override
  void _finish(CallEndReason reason) {
    if (_closed) return;
    dlog('[CallService] _finish reason=$reason phase=$_phase');
    _closed = true;
    _endReason = reason;
    _ringTimer?.cancel();
    _syncTimer?.cancel();
    _phaseWatchTimer?.cancel();
    _stopBilling();
    _stopPauseTimer();
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
    _phaseWatchTimer?.cancel();
    _stopBilling();
    _stopPauseTimer();
    _setProximity(false);
    _pendingCandidates.clear();
    _pendingSignals.clear();
    for (final pc in _watchPcs.values) {
      try {
        await pc.close();
      } catch (_) {} // cleanup best-effort: kegagalan tutup tidak memengaruhi UX
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
    } catch (_) {} // cleanup best-effort: kegagalan tutup tidak memengaruhi UX
    _pc = null;
    try {
      await _localStream?.dispose();
    } catch (_) {} // cleanup best-effort: kegagalan tutup tidak memengaruhi UX
    _localStream = null;
    try {
      await localRenderer.dispose();
    } catch (_) {} // cleanup best-effort: kegagalan tutup tidak memengaruhi UX
    try {
      await remoteRenderer.dispose();
    } catch (_) {} // cleanup best-effort: kegagalan tutup tidak memengaruhi UX
  }
}
