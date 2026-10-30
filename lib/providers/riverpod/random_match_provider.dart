import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/random_match.dart';
import '../../services/random_match_service.dart';
import '../../utils.dart';
import 'auth_provider.dart';
import 'call_provider.dart';
import 'locale_provider.dart';

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
    bool? isCaller,
    String? errorCode,
    bool clearError = false,
  }) => RandomMatchState(
    phase: phase ?? this.phase,
    wantGender: wantGender ?? this.wantGender,
    waiting: waiting ?? this.waiting,
    online: online ?? this.online,
    sample: sample ?? this.sample,
    partner: clearPartner ? null : (partner ?? this.partner),
    callId: callId ?? this.callId,
    isCaller: isCaller ?? this.isCaller,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
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

  void setWantGender(String v) {
    if (state.wantGender == v) return;
    state = state.copyWith(wantGender: v);
    // Sedang mencari → ganti filter berarti masuk ulang antrean.
    if (state.isSearching) unawaited(_joinAgain());
  }

  // ── Antrean ──
  Future<void> start() async {
    if (_busy) return;
    if (state.isSearching) return;
    _busy = true;
    state = state.copyWith(
      phase: RandomMatchPhase.searching,
      clearPartner: true,
      clearError: true,
    );
    _listenQueue();
    try {
      final res = await _svc.join(state.wantGender);
      final status = '${res['status'] ?? ''}';
      if (status == 'matched') {
        await _openSession(res);
      } else if (status == 'waiting') {
        _startPing();
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
      if ('${res['status']}' == 'matched') await _openSession(res);
    } catch (e) {
      dlog('[RandomMatch] rejoin error: $e');
    } finally {
      _busy = false;
    }
  }

  /// Batal mencari (tetap di layar, kembali ke idle).
  Future<void> cancel() async {
    _stopSearching();
    state = state.copyWith(phase: RandomMatchPhase.idle);
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
  Future<void> next() async {
    _stopSearching();
    await _endCall();
    state = state.copyWith(
      phase: RandomMatchPhase.searching,
      clearPartner: true,
      clearError: true,
    );
    _listenQueue();
    _busy = false;
    await _joinAgain();
    if (state.isSearching) _startPing();
  }

  /// Akhiri call lalu kembali ke layar radar (tidak mencari lagi).
  Future<void> hangup() async {
    _stopSearching();
    await _endCall();
    state = state.copyWith(phase: RandomMatchPhase.idle, clearPartner: true);
  }

  /// Dipanggil layar call saat sesi berakhir dari sisi lawan (atau media
  /// gagal) → otomatis cari orang baru seperti perilaku "Next".
  Future<void> onRemoteEnded() async {
    if (!state.inCall) return;
    await _endCall();
    state = state.copyWith(
      phase: RandomMatchPhase.searching,
      clearPartner: true,
    );
    _listenQueue();
    await _joinAgain();
    if (state.isSearching) _startPing();
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
    _stopSearching();
    final partner = RandomPartner.tryParse(res['partner']);
    final callId = '${res['call_id'] ?? ''}';
    if (partner == null || callId.isEmpty) {
      _fail('GENERIC');
      return;
    }
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
            notifBody: s.callNotifActiveVideo,
            notifChannel: s.callNotifActiveAudio,
            notifDesc: s.callNotifActiveAudio,
            chatId: 'random_$callId',
          );
      state = state.copyWith(phase: RandomMatchPhase.inCall);
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
    state = state.copyWith(phase: RandomMatchPhase.idle, errorCode: code);
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
