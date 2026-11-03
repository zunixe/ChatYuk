import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils.dart';

/// Ringkasan penghasilan + statistik aktivitas untuk layar Saldo.
class EarningsState {
  final int totalEarnings;
  final int weeklyEarnings;
  final int todayEarnings;
  final int privateCall;
  final int matchCall;
  final int message;
  final int gift;
  final int mission;
  final int bonus;
  final int other;
  final int videoCallCount;
  final int videoCallSeconds;
  final int matchCallCount;
  final int matchCallSeconds;
  final int avgMatchSeconds;
  final int privateCallTotal;
  final int privateCallAnswered;
  final int privateAnswerRate;
  final int withdrawable;
  /// Total SEMUA bucket (bonus+topup+earned) — untuk informasi; yang bisa
  /// ditarik hanya `withdrawable` (bucket earned).
  final int totalBalance;
  final bool loading;
  final String? error;

  const EarningsState({
    this.totalEarnings = 0,
    this.weeklyEarnings = 0,
    this.todayEarnings = 0,
    this.privateCall = 0,
    this.matchCall = 0,
    this.message = 0,
    this.gift = 0,
    this.mission = 0,
    this.bonus = 0,
    this.other = 0,
    this.videoCallCount = 0,
    this.videoCallSeconds = 0,
    this.matchCallCount = 0,
    this.matchCallSeconds = 0,
    this.avgMatchSeconds = 0,
    this.privateCallTotal = 0,
    this.privateCallAnswered = 0,
    this.privateAnswerRate = 0,
    this.withdrawable = 0,
    this.totalBalance = 0,
    this.loading = true,
    this.error,
  });

  factory EarningsState.fromJson(Map<String, dynamic> json) {
    // Toleran tipe: breakdown/stats yang bukan Map (null, string, angka)
    // tidak boleh melempar — respons server bisa berubah bentuk.
    final b = json['breakdown'] is Map
        ? (json['breakdown'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final s = json['stats'] is Map
        ? (json['stats'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;
    return EarningsState(
      totalEarnings: i(json['total_earnings']),
      weeklyEarnings: i(json['weekly_earnings']),
      todayEarnings: i(json['today_earnings']),
      privateCall: i(b['private_call']),
      matchCall: i(b['match_call']),
      message: i(b['message']),
      gift: i(b['gift']),
      mission: i(b['mission']),
      bonus: i(b['bonus']),
      other: i(b['other']),
      videoCallCount: i(s['video_call_count']),
      videoCallSeconds: i(s['video_call_seconds']),
      matchCallCount: i(s['match_call_count']),
      matchCallSeconds: i(s['match_call_seconds']),
      avgMatchSeconds: i(s['avg_match_seconds']),
      privateCallTotal: i(s['private_call_total']),
      privateCallAnswered: i(s['private_call_answered']),
      privateAnswerRate: i(s['private_answer_rate']),
      withdrawable: i(json['withdrawable']),
      totalBalance: i(json['total_balance']),
      loading: false,
    );
  }

  EarningsState copyWith({bool? loading, String? error}) => EarningsState(
    totalEarnings: totalEarnings,
    weeklyEarnings: weeklyEarnings,
    todayEarnings: todayEarnings,
    privateCall: privateCall,
    matchCall: matchCall,
    message: message,
    gift: gift,
    mission: mission,
    bonus: bonus,
    other: other,
    videoCallCount: videoCallCount,
    videoCallSeconds: videoCallSeconds,
    matchCallCount: matchCallCount,
    matchCallSeconds: matchCallSeconds,
    avgMatchSeconds: avgMatchSeconds,
    privateCallTotal: privateCallTotal,
    privateCallAnswered: privateCallAnswered,
    privateAnswerRate: privateAnswerRate,
    withdrawable: withdrawable,
    totalBalance: totalBalance,
    loading: loading ?? this.loading,
    error: error,
  );
}

class EarningsNotifier extends Notifier<EarningsState> {
  /// Client opsional untuk test (pola `PointsService([sb])`) — default
  /// `Supabase.instance.client`, jadi perilaku produksi tidak berubah.
  final SupabaseClient? _client;
  EarningsNotifier([SupabaseClient? client]) : _client = client;
  SupabaseClient get _sb => _client ?? Supabase.instance.client;

  StreamSubscription<AuthState>? _authSub;

  @override
  EarningsState build() {
    // Ganti user → muat ulang ringkasan penghasilan.
    _authSub?.cancel();
    _authSub = _sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) {
        // Data penghasilan user lama jangan bocor ke user berikutnya.
        state = const EarningsState(loading: false);
        return;
      }
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.initialSession ||
          s.event == AuthChangeEvent.tokenRefreshed) {
        refresh();
      }
    }, onError: (e) => dlog('[EARNINGS] auth stream error: $e'));

    ref.onDispose(() {
      _authSub?.cancel();
      _authSub = null;
    });

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const EarningsState(loading: false);
    _load(uid);
    return const EarningsState();
  }

  Future<void> _load(String uid) async {
    try {
      final res = await _sb.rpc(
        'get_earnings_summary',
        params: {'p_user_id': uid},
      );
      state = EarningsState.fromJson(
        (res as Map).cast<String, dynamic>(),
      );
    } catch (e) {
      dlog('[EARNINGS] load error: $e');
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      state = const EarningsState(loading: false);
      return;
    }
    state = state.copyWith(loading: true, error: null);
    await _load(uid);
  }
}

final earningsProvider =
    NotifierProvider<EarningsNotifier, EarningsState>(EarningsNotifier.new);
