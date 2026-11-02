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

  MyLevelState copyWith({bool? loading, String? error}) => MyLevelState(
    loading: loading ?? this.loading,
    error: error,
    level: level,
    cumulative: cumulative,
    nextLevel: nextLevel,
    nextAt: nextAt,
    remaining: remaining,
    ladder: ladder,
    justRewarded: justRewarded,
  );
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
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.signedOut ||
          s.event == AuthChangeEvent.initialSession ||
          s.event == AuthChangeEvent.tokenRefreshed) {
        refresh();
      }
    }, onError: (e) => dlog('[MYLEVEL] auth stream error: $e'));
    ref.onDispose(() {
      _authSub?.cancel();
      _authSub = null;
    });

    // Topup sukses → saldo berubah → level bisa naik (reward dicetak
    // server). Refresh level saat itu (debounce via coalesce/TTL service).
    ref.listen(pointsProvider.select((p) => p.points), (prev, next) {
      if (prev != next) refresh();
    });

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return const MyLevelState(loading: false);
    _load();
    return const MyLevelState();
  }

  Future<void> _load() async {
    try {
      final res = await _service.getMyLevel();
      state = MyLevelState.fromJson(res);
      // Reward naik-level BARU dicetak server (bucket bonus) → segarkan
      // saldo agar kartu/counter YukCoin tidak stale.
      if (state.justRewarded.isNotEmpty) {
        ref.read(pointsProvider.notifier).refreshWallet();
      }
    } catch (e) {
      dlog('[MYLEVEL] load error: $e');
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Tarik ulang (setelah topup sukses / pull-to-refresh).
  Future<void> refresh() async {
    _service.invalidateTtl('get_my_level');
    state = state.copyWith(loading: true);
    await _load();
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
