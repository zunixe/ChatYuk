import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/random_match.dart';
import '../../services/random_match_service.dart';
import '../../utils.dart';
import 'auth_provider.dart';
import 'call_provider.dart';
import 'locale_provider.dart';
import 'points_provider.dart';

/// Service I/O fitur ini — di-override di test supaya provider bisa diuji
/// tanpa jaringan (pola yang sama dengan provider lain di repo).
final randomMatchServiceProvider = Provider<RandomMatchService>(
  (_) => RandomMatchService.instance,
);

/// Fase layar Random Video Call.
enum RandomMatchPhase {
  /// Belum mencari (layar dibuka, tombol Match tersedia).
  idle,

  /// Sedang menunggu pasangan (tombol berubah jadi Batal).
  searching,

  /// Sudah dipasangkan, sesi media sedang dibangun.
  connecting,

  /// Video call berjalan.
  inCall,
}

class RandomMatchState {
  final RandomMatchPhase phase;
  final String wantGender;
  final int waiting;
  final int online;
  final List<RandomRadarUser> sample;
  final RandomPartner? partner;
  final String? callId;
  final bool isCaller;

  /// Kode error server (mis. `FEATURE_DISABLED`) — layar memetakan ke teks.
  final String? errorCode;

  /// Lawan menutup panggilan (bukan kita yang Next/Hangup). Layar
  /// menampilkan banner "panggilan berakhir" dan Next tetap tersedia —
  /// JANGAN auto-cari diam-diam (terlihat seperti spinner tanpa akhir).
  final bool partnerEnded;

  const RandomMatchState({
    this.phase = RandomMatchPhase.idle,
    this.wantGender = 'all',
    this.waiting = 0,
    this.online = 0,
    this.sample = const <RandomRadarUser>[],
    this.partner,
    this.callId,
    this.isCaller = true,
    this.errorCode,
    this.partnerEnded = false,
  });

  bool get isSearching => phase == RandomMatchPhase.searching;
  bool get inCall =>
      phase == RandomMatchPhase.inCall || phase == RandomMatchPhase.connecting;

  RandomMatchState copyWith({
    RandomMatchPhase? phase,
    String? wantGender,
    int? waiting,
    int? online,
    List<RandomRadarUser>? sample,
    RandomPartner? partner,
    bool clearPartner = false,
    String? callId,
    bool clearCallId = false,
    bool? isCaller,
    String? errorCode,
    bool clearError = false,
    bool? partnerEnded,
  }) => RandomMatchState(
    phase: phase ?? this.phase,
    wantGender: wantGender ?? this.wantGender,
    waiting: waiting ?? this.waiting,
    online: online ?? this.online,
    sample: sample ?? this.sample,
    partner: clearPartner ? null : (partner ?? this.partner),
    // callId WAJIB dibersihkan eksplisit saat sesi berakhir — callId basi
    // membuat dedup `_openSession` lolos untuk 'matched' telat dari call
    // yang sudah mati → sesi kedua dibuka ("layar kaya double" + lag).
    callId: clearCallId ? null : (callId ?? this.callId),
    isCaller: isCaller ?? this.isCaller,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    partnerEnded: partnerEnded ?? this.partnerEnded,
  );
}

/// Orkestrasi Random Video Call: antrean → pasangan → sesi media → Next.
///
/// Kepemilikan sesi media tetap di [callProvider] (pola yang sama dengan
/// panggilan 1:1), sehingga layar hanya menampilkan state.
class RandomMatchNotifier extends Notifier<RandomMatchState> {
  RandomMatchService get _svc => ref.read(randomMatchServiceProvider);

  Timer? _pingTimer;
  Timer? _statsTimer;
  StreamSubscription<void>? _queueSub;
  bool _busy = false;

  @override
  RandomMatchState build() {
    ref.onDispose(_cleanup);
    return const RandomMatchState();
  }

  // ── Data radar ──
  Future<void> refreshStats() async {
    try {
      final st = await _svc.stats();
      state = state.copyWith(
        waiting: st.waiting,
        online: st.online,
        sample: st.sample,
      );
    } catch (e) {
      dlog('[RandomMatch] stats error: $e');
    }
  }

  /// Dipanggil layar saat dibuka: data radar + refresh berkala.
  void attach() {
    unawaited(refreshStats());
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (state.phase == RandomMatchPhase.idle ||
          state.phase == RandomMatchPhase.searching) {
        unawaited(refreshStats());
      }
    });
  }

  void detach() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// Riwayat random call (layar `RandomCallHistoryScreen`) — passthrough
  /// ke service; screen dilarang import services langsung.
  Future<List<RandomCallEntry>> history({int limit = 30, int offset = 0}) =>
      _svc.history(limit: limit, offset: offset);

  void setWantGender(String v) {
    if (state.wantGender == v) return;
    state = state.copyWith(wantGender: v);
    // Sedang mencari → ganti filter berarti masuk ulang antrean.
    if (state.isSearching) unawaited(_joinAgain());
  }

  // ── Antrean ──
  // Fee match (2 poin) dipotong SERVER saat pair terbentuk — koin tidak
  // hangus bila tak ketemu siapa pun. Server return 'no_funds' bila male
  // tak mampu bayar → dialog top-up via MATCH_NEED_COIN.
  Future<void> start() async {
    if (_busy) return;
    if (state.isSearching) return;
    _busy = true;
    state = state.copyWith(
      phase: RandomMatchPhase.searching,
      clearPartner: true,
      clearError: true,
      partnerEnded: false,
      clearCallId: true,
    );
    _listenQueue();
    try {
      final res = await _svc.join(state.wantGender);
      final status = '${res['status'] ?? ''}';
      if (status == 'matched') {
        await _openSession(res);
      } else if (status == 'waiting') {
        _startPing();
      } else if (status == 'no_funds') {
        _fail('MATCH_NEED_COIN');
      } else {
        _fail('GENERIC');
      }
    } catch (e) {
      dlog('[RandomMatch] join error: $e');
      _fail(_errorCodeOf(e));
    } finally {
      _busy = false;
    }
  }

  Future<void> _joinAgain() async {
    if (_busy) return;
    _busy = true;
    try {
      final res = await _svc.join(state.wantGender);
      final st = '${res['status']}';
      if (st == 'matched') {
        await _openSession(res);
      } else if (st == 'no_funds') {
        _fail('MATCH_NEED_COIN');
      }
    } catch (e) {
      dlog('[RandomMatch] rejoin error: $e');
    } finally {
      _busy = false;
    }
  }

  /// Batal mencari (tetap di layar, kembali ke idle).
  Future<void> cancel() async {
    _stopSearching();
    state = state.copyWith(
      phase: RandomMatchPhase.idle,
      clearCallId: true,
    );
    try {
      await _svc.leave();
    } catch (e) {
      dlog('[RandomMatch] leave error: $e');
    }
  }

  /// Keluar layar: putus call (bila ada) + keluar antrean.
  Future<void> leaveScreen() async {
    _cleanup();
    await _endCall();
    try {
      await _svc.leave();
    } catch (_) {}
    state = const RandomMatchState();
  }

  /// Tombol "Next": akhiri call sekarang, lalu cari orang baru.
  /// Fee 2 poin dipotong server HANYA bila pair baru terbentuk.
  Future<void> next() async {
    _stopSearching();
    await _endCall();
    _busy = true;
    state = state.copyWith(
      phase: RandomMatchPhase.searching,
      clearPartner: true,
      clearError: true,
      partnerEnded: false,
      clearCallId: true,
    );
    _listenQueue();
    _busy = false;
    await _joinAgain();
    if (state.isSearching) _startPing();
  }

  /// Akhiri call lalu kembali ke layar radar (tidak mencari lagi).
  /// `leave()` ikut menghapus baris antrean supaya `matched_call_id` mati
  /// tidak dikembalikan ping berikutnya (call mati jangan dibuka ulang).
  Future<void> hangup() async {
    _stopSearching();
    await _endCall();
    unawaited(_svc.leave());
    state = state.copyWith(
      phase: RandomMatchPhase.idle,
      clearPartner: true,
      partnerEnded: false,
      clearCallId: true,
    );
  }

  /// Dipanggil layar call saat sesi berakhir dari sisi lawan (atau media
  /// gagal). JANGAN auto-cari diam-diam — user dulu melihat spinner tanpa
  /// penjelasan selamanya. Kini: berhenti, beri tahu lewat `partnerEnded`,
  /// dan biarkan user menekan Next kalau mau lanjut.
  Future<void> onRemoteEnded() async {
    if (!state.inCall) return;
    await _endCall();
    _stopSearching();
    unawaited(_svc.leave());
    state = state.copyWith(
      phase: RandomMatchPhase.idle,
      partnerEnded: true,
      clearCallId: true,
    );
  }

  // ── Internal ──
  void _listenQueue() {
    _queueSub?.cancel();
    _queueSub = _svc.watchQueue().listen((_) {
      unawaited(_checkMatched());
    });
  }

  Future<void> _checkMatched() async {
    if (state.phase != RandomMatchPhase.searching) return;
    try {
      final res = await _svc.ping();
      if ('${res['status']}' == 'matched') await _openSession(res);
    } catch (e) {
      dlog('[RandomMatch] ping error: $e');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_checkMatched());
    });
  }

  void _stopSearching() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _queueSub?.cancel();
    _queueSub = null;
  }

  Future<void> _openSession(Map<String, dynamic> res) async {
    final partner = RandomPartner.tryParse(res['partner']);
    final callId = '${res['call_id'] ?? ''}';
    if (partner == null || callId.isEmpty) {
      _fail('GENERIC');
      return;
    }
    // 'matched' bisa tiba dua kali: respons join() + ping/watchQueue
    // realtime. Tanpa dedup ini, DUA CallSession dibuat untuk callId sama
    // (pc, getUserMedia, timer ICE ganda → offer/answer dobel & zombie).
    if (state.phase == RandomMatchPhase.connecting ||
        state.phase == RandomMatchPhase.inCall) {
      // Sudah di sesi → 'matched' sama = duplikat (dedup); 'matched' lain
      // = BASI dari antrean call yang sudah mati (queue event telat/ping
      // lama). JANGAN buka sesi kedua di atas sesi hidup: kamera/mic/pc
      // ganda = lag + video tampak "double".
      if (state.callId != callId) {
        dlog('[RandomMatch] matched basi diabaikan (aktif=${state.callId}, datang=$callId)');
      }
      return;
    }
    // Sesi untuk callId ini sudah hidup di callProvider tapi fase provider
    // belum inCall (mis. 'matched' datang dua kali berdekatan): pulihkan
    // state — JANGAN startSession kedua untuk call yang sama.
    final live = ref.read(callProvider.notifier).activeSession;
    if (live != null && live.callId == callId) {
      _stopSearching();
      state = state.copyWith(
        phase: RandomMatchPhase.inCall,
        partner: partner,
        callId: callId,
        isCaller: res['is_caller'] == true,
      );
      return;
    }
    _stopSearching();
    state = state.copyWith(
      phase: RandomMatchPhase.connecting,
      partner: partner,
      callId: callId,
      isCaller: res['is_caller'] == true,
    );

    final auth = ref.read(authProvider.notifier);
    final s = ref.read(localeProvider).s;
    final profile = auth.profile;
    try {
      await ref
          .read(callProvider.notifier)
          .startSession(
            callId: callId,
            remoteUid: partner.uid,
            remoteName: partner.nickname,
            callType: 'video',
            isCaller: res['is_caller'] == true,
            mode: CallMode.fullscreen,
            myName: profile?.nickname ?? '',
            myGender: profile?.gender ?? 'other',
            // Random match: server menagih pihak MALE siapa pun caller
            // signaling-nya. Tick billing hanya di device payer; gender
            // tak dikenal → fallback isCaller (perilaku lama).
            billingPayer: profile?.gender == 'male'
                ? true
                : (profile?.gender == 'female' ? false : null),
            // Grace 30 detik dari media connect — UI countdown + jangkar
            // billing server (media_connected_at) menunjuk momen yang sama.
            billingFreeGraceSec: 30,
            notifBody: s.callNotifActiveVideo,
            notifChannel: s.callNotifActiveAudio,
            notifDesc: s.callNotifActiveAudio,
            chatId: '$kRandomChatIdPrefix$callId',
          );
      state = state.copyWith(phase: RandomMatchPhase.inCall);
      // Misi dihitung saat media benar-benar tersambung (phase→inCall),
      // bukan saat sesi dibuat — call yang gagal connect tak dihitung.
      final sess = ref.read(callProvider.notifier).activeSession;
      if (sess != null) {
        void onConnect() {
          if (sess.phase != CallPhase.inCall) return;
          sess.removeListener(onConnect);
          ref.read(pointsProvider.notifier).trackMission('match_calls');
          ref.read(pointsProvider.notifier).trackMission('daily_match_calls');
        }

        sess.addListener(onConnect);
        onConnect();
      }
      // Fee match (−2) dipotong server saat pair terbentuk → segarkan
      // saldo (kartu YukCoin/counter header call ikut akurat).
      unawaited(ref.read(pointsProvider.notifier).refreshWallet());
    } catch (e) {
      dlog('[RandomMatch] startSession error: $e');
      _fail('MEDIA');
    }
  }

  Future<void> _endCall() async {
    try {
      await ref.read(callProvider.notifier).hangup();
    } catch (e) {
      dlog('[RandomMatch] hangup error: $e');
    }
  }

  void _fail(String code) {
    _stopSearching();
    state = state.copyWith(
      phase: RandomMatchPhase.idle,
      errorCode: code,
      clearCallId: true,
    );
  }

  String _errorCodeOf(Object e) {
    final m = '$e';
    for (final k in const [
      'FEATURE_DISABLED',
      'ALREADY_IN_CALL',
      'CALL_DISABLED',
      'CALL_REGISTERED_ONLY',
    ]) {
      if (m.contains(k)) return k;
    }
    return 'GENERIC';
  }

  void _cleanup() {
    _stopSearching();
    _statsTimer?.cancel();
    _statsTimer = null;
  }
}

final randomMatchProvider =
    NotifierProvider<RandomMatchNotifier, RandomMatchState>(
      RandomMatchNotifier.new,
    );
