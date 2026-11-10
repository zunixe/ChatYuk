import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/mission.dart';
import '../../utils.dart';
import 'earnings_provider.dart';

/// State of mission progress
class MissionsState {
  final List<Mission> mainMissions;
  final List<Mission> dailyMissions;
  final int totalCoins;
  final bool loading;
  final String? error;

  /// Sign-in streak (grid Bonus): 0 = belum klaim hari ini, 1..7 siklus.
  final int loginStreak;

  /// Tanggal klaim terakhir (yyyy-mm-dd) — deteksi "sudah klaim hari ini".
  final String? lastLoginDate;

  /// Gender user — grid sign-in hanya tampil untuk male.
  final String? gender;

  const MissionsState({
    this.mainMissions = const [],
    this.dailyMissions = const [],
    this.totalCoins = 0,
    this.loading = true,
    this.error,
    this.loginStreak = 0,
    this.lastLoginDate,
    this.gender,
  });

  MissionsState copyWith({
    List<Mission>? mainMissions,
    List<Mission>? dailyMissions,
    int? totalCoins,
    bool? loading,
    String? error,
    int? loginStreak,
    String? lastLoginDate,
    String? gender,
  }) => MissionsState(
    mainMissions: mainMissions ?? this.mainMissions,
    dailyMissions: dailyMissions ?? this.dailyMissions,
    totalCoins: totalCoins ?? this.totalCoins,
    loading: loading ?? this.loading,
    error: error,
    loginStreak: loginStreak ?? this.loginStreak,
    lastLoginDate: lastLoginDate ?? this.lastLoginDate,
    gender: gender ?? this.gender,
  );

  /// Grid sign-in hanya untuk male (server menolak klaim non-male).
  bool get showSignIn => gender == 'male';

  /// Misi nyonya (female-only) — di layar Bonus tampil sebagai counter di
  /// samping judul "Tugas Pemula", bukan baris misi biasa. Null untuk male
  /// (server memang tidak mengirimnya).
  Mission? get nyonyaMission {
    for (final m in mainMissions) {
      if (m.missionKey == 'nyonya_1000') return m;
    }
    return null;
  }

  int get completedCount =>
      mainMissions.where((m) => m.isCompleted).length +
      dailyMissions.where((m) => m.isCompleted).length;

  int get claimableCount =>
      mainMissions.where((m) => m.canClaim).length +
      dailyMissions.where((m) => m.canClaim).length;

  int get totalRewardPotential =>
      mainMissions.fold<int>(0, (sum, m) => sum + m.rewardCoins) +
      dailyMissions.fold<int>(0, (sum, m) => sum + m.rewardCoins);

  List<Mission> get uncompletedMain =>
      mainMissions.where((m) => !m.isCompleted).toList();

  List<Mission> get uncompletedDaily =>
      dailyMissions.where((m) => !m.isCompleted).toList();
}

/// Notifier untuk misi - load dari DB, track progress
class MissionsNotifier extends Notifier<MissionsState> {
  /// Client opsional untuk test (pola `PointsService([sb])`) — default
  /// `Supabase.instance.client`, jadi perilaku produksi tidak berubah.
  final SupabaseClient? _client;
  MissionsNotifier([SupabaseClient? client]) : _client = client;
  SupabaseClient get _sb => _client ?? Supabase.instance.client;

  StreamSubscription<AuthState>? _authSub;

  @override
  MissionsState build() {
    // Ganti user (login akun lain / logout) → muat ulang data misi.
    // Tanpa ini, provider global menyimpan data user SEBELUMNYA.
    _authSub?.cancel();
    _authSub = _sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.signedOut ||
          s.event == AuthChangeEvent.initialSession ||
          s.event == AuthChangeEvent.tokenRefreshed) {
        refresh();
      }
    }, onError: (e) => dlog('[MISSIONS] auth stream error: $e'));

    ref.onDispose(() {
      _authSub?.cancel();
      _authSub = null;
    });

    final userId = _sb.auth.currentUser?.id;
    if (userId == null) {
      return const MissionsState(loading: false);
    }

    _loadMissions(userId: userId);
    return const MissionsState(loading: true);
  }

  /// Tanggal LOKAL HP (yyyy-mm-dd) — sama dengan batas hari server
  /// (`_local_day` memakai offset zona waktu yang dikirim klien).
  String get _localDate {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Offset zona waktu HP (menit) — misi harian mengikuti waktu lokal
  /// pengguna, jadi user di negara lain tidak ikut WIB.
  int get _tzOffsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  /// Load semua misi dari DB
  Future<void> _loadMissions({required String userId}) async {
    try {
      final today = _localDate;

      final res = await _sb.rpc(
        'get_user_missions',
        params: {
          'p_user_id': userId,
          'p_period_date': today,
          'p_tz_offset_minutes': _tzOffsetMinutes,
        },
      );

      final progress = MissionProgress.fromJson(res);

      // Cek total coins untuk unlock
      final coinRes = await _sb.rpc(
        'check_user_total_coins',
        params: {'p_user_id': userId},
      );
      final totalCoins = (coinRes['total_coins'] as num?)?.toInt() ?? 0;

      // Unlock misi harian jika total coins >= 1200
      final dailyMissions = progress.dailyMissions.map((m) {
        if (!m.isLocked) return m;
        return m.copyWith(isLocked: totalCoins < 1200);
      }).toList();

      state = MissionsState(
        mainMissions: progress.mainMissions,
        dailyMissions: dailyMissions,
        totalCoins: totalCoins,
        loading: false,
        loginStreak: progress.loginStreak,
        lastLoginDate: progress.lastLoginDate,
        gender: progress.gender,
      );
    } catch (e) {
      dlog('[MISSIONS] load error: $e');
      state = MissionsState(loading: false, error: e.toString());
    }
  }

  /// Update progress misi (dipanggil saat user melakukan aktivitas)
  Future<void> updateProgress(String missionKey, {int increment = 1}) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final res = await _sb.rpc(
        'update_mission_progress',
        params: {
          'p_user_id': userId,
          'p_mission_key': missionKey,
          'p_increment': increment,
          'p_tz_offset_minutes': _tzOffsetMinutes,
        },
      );

      if (res['error'] != null) {
        dlog('[MISSIONS] update error: ${res['error']}');
        return;
      }

      // Refresh state setelah update
      await _loadMissions(userId: userId);
    } catch (e) {
      dlog('[MISSIONS] update progress error: $e');
    }
  }

  /// Hasil klaim terakhir dari server: bucket (`earned`/`bonus`) & alasan
  /// bila hadiah jadi bonus (`shared_device`/`shared_ip`/`no_device`).
  String? lastClaimBucket;
  String? lastClaimReason;

  /// Klaim reward misi
  Future<bool> claimReward(String missionKey) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final res = await _sb.rpc(
        'claim_mission_reward',
        params: {
          'p_user_id': userId,
          'p_mission_key': missionKey,
          'p_tz_offset_minutes': _tzOffsetMinutes,
        },
      );

      if (res['success'] == true) {
        lastClaimBucket = res['bucket'] as String?;
        lastClaimReason = res['reason'] as String?;
        await _loadMissions(userId: userId);
        // 2026-11-10: female → `earned` bila device & IP tidak dipakai akun
        // lain; selain itu `bonus` (tidak bisa dicairkan).
        ref.invalidate(earningsProvider);
        return true;
      }

      dlog('[MISSIONS] claim error: ${res['error']}');
      return false;
    } catch (e) {
      dlog('[MISSIONS] claim reward error: $e');
      return false;
    }
  }

  /// Refresh ulang data misi
  Future<void> refresh() async {
    final userId = _sb.auth.currentUser?.id;
    if (userId != null) {
      await _loadMissions(userId: userId);
    }
  }
}

final missionsProvider = NotifierProvider<MissionsNotifier, MissionsState>(
  MissionsNotifier.new,
);
