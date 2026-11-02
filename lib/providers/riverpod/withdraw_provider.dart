import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/withdraw_request.dart';
import 'points_provider.dart';
import 'earnings_provider.dart';
import '../../utils.dart';

/// Setting withdraw dari server (untuk kalkulator preview).
class WithdrawConfig {
  final int rate;
  final int minCoins;
  final int feePct;
  final int feeMinIdr;
  final int maxPerDay;
  final int minIntervalHours;
  final int minAccountAgeHours;

  const WithdrawConfig({
    this.rate = 7,
    this.minCoins = 2000,
    this.feePct = 5,
    this.feeMinIdr = 1000,
    this.maxPerDay = 3,
    this.minIntervalHours = 1,
    this.minAccountAgeHours = 72,
  });

  WithdrawQuote quote(int coins) =>
      WithdrawQuote.calc(coins, rate: rate, feePct: feePct, feeMinIdr: feeMinIdr);
}

class WithdrawState {
  final int earnedBalance;
  final WithdrawAccount? account;
  final List<WithdrawRequest> history;
  final WithdrawConfig config;
  final bool loading;
  final bool submitting;
  final String? error;
  /// Pesan sukses terakhir (ditampilkan sebagai snackbar).
  final String? successMessage;

  const WithdrawState({
    this.earnedBalance = 0,
    this.account,
    this.history = const [],
    this.config = const WithdrawConfig(),
    this.loading = true,
    this.submitting = false,
    this.error,
    this.successMessage,
  });

  WithdrawState copyWith({
    int? earnedBalance,
    WithdrawAccount? account,
    List<WithdrawRequest>? history,
    WithdrawConfig? config,
    bool? loading,
    bool? submitting,
    String? error,
    String? successMessage,
  }) =>
      WithdrawState(
        earnedBalance: earnedBalance ?? this.earnedBalance,
        account: account ?? this.account,
        history: history ?? this.history,
        config: config ?? this.config,
        loading: loading ?? this.loading,
        submitting: submitting ?? this.submitting,
        error: error,
        successMessage: successMessage,
      );

  bool get hasAccount => account != null;
  bool get canWithdraw => earnedBalance >= config.minCoins;
}

class WithdrawNotifier extends Notifier<WithdrawState> {
  SupabaseClient get _sb => Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;

  @override
  WithdrawState build() {
    // Ganti user → muat ulang saldo withdrawable + akun DANA + riwayat.
    _authSub?.cancel();
    _authSub = _sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.signedOut ||
          s.event == AuthChangeEvent.initialSession ||
          s.event == AuthChangeEvent.tokenRefreshed) {
        refresh();
      }
    }, onError: (e) => dlog('[WITHDRAW] auth stream error: $e'));

    ref.onDispose(() {
      _authSub?.cancel();
      _authSub = null;
    });

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const WithdrawState(loading: false);
    _loadAll();
    return const WithdrawState();
  }

  Future<void> _loadAll() async {
    try {
      final cfg = await _sb.rpc('get_withdraw_config');
      final config = WithdrawConfig(
        rate: _i(cfg['rate']),
        minCoins: _i(cfg['min_coins']),
        feePct: _i(cfg['fee_pct']),
        feeMinIdr: _i(cfg['fee_min_idr']),
        maxPerDay: _i(cfg['max_per_day']),
        minIntervalHours: _i(cfg['min_interval_hours']),
        minAccountAgeHours: _i(cfg['min_account_age_hours']),
      );

      final accRes = await _sb.rpc('get_withdraw_account');
      final account = accRes['has_account'] == true
          ? WithdrawAccount.fromJson(accRes)
          : null;

      final histRes = await _sb.rpc('get_withdraw_history', params: {'p_limit': 30});
      final history = ((histRes['requests'] as List?) ?? const [])
          .map((e) => WithdrawRequest.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

      state = state.copyWith(
        earnedBalance: _i(histRes['earned_balance']),
        account: account,
        history: history,
        config: config,
        loading: false,
      );
    } catch (e) {
      dlog('[WITHDRAW] load error: $e');
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Simpan / ubah akun DANA.
  Future<bool> saveAccount(String number, String name) async {
    try {
      final res = await _sb.rpc('save_withdraw_account', params: {
        'p_dana_number': number,
        'p_dana_name': name,
      });
      if (res['ok'] == true) {
        state = state.copyWith(
          account: WithdrawAccount(
            danaNumber: res['dana_number'] ?? '',
            danaName: res['dana_name'] ?? '',
          ),
        );
        return true;
      }
      state = state.copyWith(error: res['error']?.toString());
      return false;
    } catch (e) {
      dlog('[WITHDRAW] saveAccount error: $e');
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Segarkan saldo global + ringkasan penghasilan setelah saldo berubah.
  /// `ref` tersedia di Notifier; keduanya no-op bila provider tak dipakai.
  void _refreshGlobalBalances() {
    try {
      unawaited(ref.read(pointsProvider.notifier).refreshWallet());
    } catch (_) {}
    try {
      unawaited(ref.read(earningsProvider.notifier).refresh());
    } catch (_) {}
  }

  /// Ajukan withdraw. Mengembalikan pesan error (null = sukses).
  Future<String?> request(int coins) async {
    if (state.submitting) return null;
    state = state.copyWith(submitting: true, error: null, successMessage: null);
    try {
      final res = await _sb.rpc('request_withdraw', params: {
        'p_coins': coins,
      });
      if (res['ok'] == true) {
        state = state.copyWith(
          submitting: false,
          successMessage: 'ok',
        );
        await _loadAll();
        // Saldo berubah di server (ledger didebit) → segarkan juga saldo
        // global & ringkasan penghasilan, kalau tidak layar Saldo masih
        // menunjukkan angka lama sampai polling 20 detik.
        _refreshGlobalBalances();
        return null;
      }
      final err = res['error']?.toString() ?? 'UNKNOWN';
      state = state.copyWith(submitting: false, error: err);
      return err;
    } catch (e) {
      dlog('[WITHDRAW] request error: $e');
      state = state.copyWith(submitting: false, error: e.toString());
      return e.toString();
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: null);
    await _loadAll();
  }

  void clearMessages() {
    if (state.error != null || state.successMessage != null) {
      state = state.copyWith(error: null, successMessage: null);
    }
  }

  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
}

final withdrawProvider =
    NotifierProvider<WithdrawNotifier, WithdrawState>(WithdrawNotifier.new);
