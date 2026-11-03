import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/points_service.dart';
import '../../utils.dart';
import 'points_provider.dart';

/// State My Level (immutable — yang di-watch widget).
class MyLevelState {
  final bool loading;
  final String? error;
  final int level;
  final int cumulative;
  final int? nextLevel;
  final int? nextAt;
  final int remaining;
  final List<Map<String, dynamic>> ladder;
  final List<Map<String, dynamic>> justRewarded;

  const MyLevelState({
    this.loading = true,
    this.error,
    this.level = 0,
    this.cumulative = 0,
    this.nextLevel,
    this.nextAt,
    this.remaining = 0,
    this.ladder = const [],
    this.justRewarded = const [],
  });

  factory MyLevelState.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;
    int? inull(dynamic v) => v == null ? null : i(v);
    List<Map<String, dynamic>> arr(dynamic v) => v is List
        ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : const [];
    return MyLevelState(
      loading: false,
      level: i(json['level']),
      cumulative: i(json['cumulative']),
      nextLevel: inull(json['next_level']),
      nextAt: inull(json['next_at']),
      remaining: i(json['remaining']),
      ladder: arr(json['ladder']),
      justRewarded: arr(json['just_rewarded']),
    );
  }

  MyLevelState copyWith({
    bool? loading,
    String? error,
    List<Map<String, dynamic>>? justRewarded,
  }) => MyLevelState(
    loading: loading ?? this.loading,
    error: error,
    level: level,
    cumulative: cumulative,
    nextLevel: nextLevel,
    nextAt: nextAt,
    remaining: remaining,
    ladder: ladder,
    justRewarded: justRewarded ?? this.justRewarded,
  );

  /// Ambang koin level saat ini (dari tangga) — dasar progress bar.
  int get currentAt {
    for (final r in ladder) {
      if ((r['level'] as num?)?.toInt() == level) {
        return (r['topup_coins'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  /// Progress ke level berikutnya, DIHITUNG dari ambang level saat ini
  /// (dulu dari 0 → Lv9 dgn 600k tampil 60% padahal baru 20% ke Lv10).
  double get progress {
    final next = nextAt;
    if (next == null || next <= currentAt) return 1;
    return ((cumulative - currentAt) / (next - currentAt)).clamp(0.0, 1.0);
  }
}

/// Level saya = kumulatif koin topup (server `get_my_level`).
/// Reward naik-level dicetak server (idempoten) — refresh setelah topup.
class MyLevelNotifier extends Notifier<MyLevelState> {
  /// Service opsional untuk test (pola `PointsService([sb])`) — default
  /// `PointsService()` baru, jadi perilaku produksi tidak berubah.
  final PointsService _service;
  MyLevelNotifier([PointsService? service])
      : _service = service ?? PointsService();

  StreamSubscription<AuthState>? _authSub;

  @override
  MyLevelState build() {
    _authSub?.cancel();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      // Logout → buang data user lama (dulu tetap tampil sampai login lagi).
      if (s.event == AuthChangeEvent.signedOut) {
        _seq++;
        state = const MyLevelState(loading: false);
        return;
      }
      // tokenRefreshed TIDAK memicu RPC (level tak berubah karena token).
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.initialSession) {
        refresh();
      }
    }, onError: (e) => dlog('[MYLEVEL] auth stream error: $e'));
    ref.onDispose(() {
      _authSub?.cancel();
      _authSub = null;
    });

    // Topup sukses → saldo berubah → level bisa naik (reward dicetak
    // server). Refresh level saat itu (debounce via coalesce/TTL service).
    // Hanya saat saldo NAIK (topup/hadiah) — dulu tiap perubahan (termasuk
    // tick billing tiap menit) memicu RPC level yang berat.
    ref.listen(pointsProvider.select((p) => p.points), (prev, next) {
      if (prev != null && next > prev) refresh();
    });

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return const MyLevelState(loading: false);
    _load();
    return const MyLevelState();
  }

  /// Nomor urut permintaan — respons lama yang datang belakangan dibuang.
  int _seq = 0;

  Future<void> _load() async {
    final my = ++_seq;
    try {
      final res = await _service.getMyLevel();
      if (my != _seq) return;
      final next = MyLevelState.fromJson(res);
      // Hadiah baru DIPERTAHANKAN sampai layar menampilkannya
      // ([consumeRewarded]) — dulu refresh berikutnya langsung menimpanya.
      state = next.justRewarded.isEmpty
          ? next.copyWith(justRewarded: state.justRewarded)
          : next;
      // Reward naik-level BARU dicetak server (bucket bonus) → segarkan
      // saldo agar kartu/counter YukCoin tidak stale.
      if (next.justRewarded.isNotEmpty) {
        ref.read(pointsProvider.notifier).refreshWallet();
      }
    } catch (e) {
      if (my != _seq) return;
      dlog('[MYLEVEL] load error: $e');
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Tarik ulang (setelah topup sukses / pull-to-refresh).
  Future<void> refresh() async {
    _service.invalidateTtl('get_my_level');
    // Data sudah ada → jangan kedip ke "…"; muat di belakang layar.
    if (state.ladder.isEmpty) state = state.copyWith(loading: true);
    await _load();
  }

  /// Layar sudah menampilkan hadiah naik level → kosongkan.
  void consumeRewarded() {
    if (state.justRewarded.isEmpty) return;
    state = state.copyWith(justRewarded: const []);
  }
}

final myLevelProvider =
    NotifierProvider<MyLevelNotifier, MyLevelState>(MyLevelNotifier.new);

/// Level user lain (badge di user_info) — cache per uid, gagal = 0.
final userLevelProvider =
    FutureProvider.autoDispose.family<int, String>((ref, uid) async {
  try {
    return await PointsService().getUserLevel(uid);
  } catch (e) {
    dlog('[MYLEVEL] userLevel($uid) error: $e');
    return 0;
  }
});
