import 'dart:async';
import '../utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'subscription_rpc.dart';
import '../core/perf/rpc_probe.dart';

class PointsService {
  final SupabaseClient? _client;

  PointsService([SupabaseClient? sb]) : _client = sb;

  /// Client di-resolve LAZY (bukan di konstruktor) supaya test yang tidak
  /// menginisialisasi Supabase tetap bisa membuat instance ini.
  SupabaseClient get _sb => _client ?? Supabase.instance.client;

  /// Dedupe RPC idempoten: bila panggilan untuk [key] sedang berjalan,
  /// panggilan berikutnya MENUNGGU future yang sama (bukan menembak RPC
  /// baru). Terukur: `get_points_enabled` sampai 5× + `get_wallet` 3×
  /// ditembak bersamaan saat boot → membanjiri koneksi & bikin lag. Hasil
  /// di-cache singkat (TTL) supaya burst dalam window singkat = 0 RPC.
  final Map<String, Future<Object?>> _inflight = {};
  final Map<String, ({Object? value, DateTime at})> _ttlCache = {};
  static const _ttl = Duration(seconds: 3);
  // TTL lebih panjang untuk data yang jarang berubah (quests/topup).
  static const _ttlLong = Duration(seconds: 45);

  /// Invalidasi cache TTL untuk 1 key (mis. setelah claim quest).
  void invalidateTtl(String key) => _ttlCache.remove(key);
  void invalidateTtlPrefix(String prefix) =>
      _ttlCache.removeWhere((k, _) => k.startsWith(prefix));

  Future<T> _coalesce<T>(
    String key,
    Future<T> Function() fn, {
    bool ttl = false,
    Duration? ttlDuration,
  }) {
    final ttlDur = ttlDuration ?? _ttl;
    if (ttl) {
      final c = _ttlCache[key];
      if (c != null && DateTime.now().difference(c.at) < ttlDur) {
        return Future<T>.value(c.value as T);
      }
    }
    final running = _inflight[key];
    if (running != null) return running.then((v) => v as T);
    final fut = fn();
    _inflight[key] = fut;
    // Bookkeeping inflight — future buangannya HARUS di-ignore: kalau `fut`
    // reject (mis. RPC 400 di widget test), future hasil whenComplete ikut
    // reject tanpa penanganan → unhandled async error (test gagal & log
    // berisik). Error asli tetap mengalir ke pemanggil lewat `return fut`.
    fut.whenComplete(() {
      if (identical(_inflight[key], fut)) _inflight.remove(key);
    }).ignore();
    if (ttl) {
      fut
          .then((v) {
            _ttlCache[key] = (value: v, at: DateTime.now());
          })
          .catchError((_) {});
    }
    return fut;
  }

  Future<bool> fetchEnabled() {
    // TTL 30s (dulu 3s): banyak screen memanggil saat boot & saat pindah
    // tab. Terukur `get_points_enabled` 10x per sesi boot (~1,2 dtk masing-
    // masing saat server antre) — 3 dtk terlalu pendek sehingga burst
    // berikutnya menembak RPC lagi. Nilai ini jarang berubah (toggle admin).
    return _coalesce<bool>(
      'get_points_enabled',
      () async {
        final res = await measuredRpc(_sb, 'get_points_enabled');
        return res == true;
      },
      ttl: true,
      ttlDuration: const Duration(seconds: 30),
    );
  }

  /// Harga fitur berbayar (call per menit, filter, nearby) untuk UI.
  Future<Map<String, dynamic>> meteredPricing() {
    return _coalesce<Map<String, dynamic>>('metered_pricing_public', () async {
      try {
        final res = await measuredRpc(_sb, 'metered_pricing_public');
        if (res is Map) return Map<String, dynamic>.from(res);
      } catch (e) {
        dlog('[PointsService] meteredPricing error: $e');
      }
      return {
        'call_audio_cost_per_min': 6,
        'call_video_cost_per_min': 20,
        'filter_gender_cost': 15,
        'nearby_cost': 25,
      };
    }, ttl: true);
  }

  /// Feature flags (published per fitur) untuk gate UI.
  Future<Map<String, dynamic>> featureFlags() {
    return _coalesce<Map<String, dynamic>>('get_feature_flags', () async {
      try {
        final res = await measuredRpc(_sb, 'get_feature_flags');
        if (res is Map) return Map<String, dynamic>.from(res);
      } catch (e) {
        dlog('[PointsService] featureFlags error: $e');
      }
      return {};
    }, ttl: true);
  }

  /// Katalog paket topup (id, coins, price_idr, bonus_label, play_product_id).
  Future<List<Map<String, dynamic>>> listTopupPackages() {
    // PERF: paket topup nyaris tak berubah → TTL cache (kurangi RPC tiap
    // buka sheet topup / TopupService._loadPackages).
    return _coalesce<List<Map<String, dynamic>>>(
      'list_topup_packages',
      () async {
        try {
          final res = await measuredRpc(_sb, 'list_topup_packages');
          if (res is List) {
            return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        } catch (e) {
          dlog('[PointsService] listTopupPackages error: $e');
        }
        return const <Map<String, dynamic>>[];
      },
      ttl: true,
      ttlDuration: _ttlLong,
    );
  }

  /// Verifikasi pembelian Play ke server (edge function play-topup-verify).
  /// Return jumlah coin yang dikredit (0 bila gagal).
  Future<int> verifyPlayTopup({
    required String productId,
    required String purchaseToken,
  }) async {
    try {
      final res = await _sb.functions.invoke(
        'play-topup-verify',
        body: {'product_id': productId, 'purchase_token': purchaseToken},
      );
      final data = res.data;
      if (data is Map && data['coins'] != null) {
        return (data['coins'] as num).toInt();
      }
    } catch (e) {
      dlog('[PointsService] verifyPlayTopup error: $e');
    }
    return 0;
  }

  /// Klaim WELCOME BONUS via edge function `welcome-bonus` (IP server-side,
  /// anti-farming). kind: 'anon' | 'register'. Return map {granted, coins, total}.
  Future<Map<String, dynamic>> claimWelcomeBonus({
    required String installId,
    required String kind,
  }) async {
    try {
      final res = await _sb.functions.invoke(
        'welcome-bonus',
        body: {'install_id': installId, 'kind': kind},
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (e) {
      dlog('[PointsService] claimWelcomeBonus($kind) error: $e');
    }
    return {'granted': false, 'coins': 0};
  }

  /// Potong akses harian (filter gender / nearby). Return {ok, charged, ...}.
  /// Raise 'YukCoin tidak cukup' bila saldo kurang.

  Stream<bool> watchEnabled() async* {
    // TIDAK memakai `.stream()`: ia selalu `SELECT *` (supabase 2.16.x),
    // sementara `app_shared_secret` di-revoke dari anon/authenticated
    // (20260915120000_security_hardening.sql) → stream gagal 42501 dan
    // retry tanpa henti. Polling kolom eksplisit via RPC get_points_enabled
    // (sudah ada) menghindari itu tanpa melonggarkan hardening.
    yield await fetchEnabled();
    yield* Stream<void>.periodic(
      const Duration(seconds: 20),
    ).asyncMap((_) => fetchEnabled());
  }

  /// Realtime saldo koin sendiri (profiles.points). Dipakai supaya saldo
  /// langsung update ketika ada koin masuk/keluar tanpa harus reload app.
  Stream<int> watchOwnPoints() async* {
    final id = uid;
    if (id == null) return;
    // stream() versi ini selalu SELECT *, tetapi profiles membatasi kolom.
    // Polling kolom points eksplisit mencegah 42501 pada security hardening.
    Future<int> fetch() async {
      final row = await _sb
          .from('profiles')
          .select('points')
          .eq('id', id)
          .maybeSingle();
      return ((row?['points'] as num?) ?? 0).toInt();
    }

    yield await fetch();
    yield* Stream<void>.periodic(
      const Duration(seconds: 20),
    ).asyncMap((_) => fetch());
  }

  String? get uid => _sb.auth.currentUser?.id;

  /// Saldo wallet 3 bucket: {bonus, topup, earned, total, withdrawable}.
  Future<Map<String, dynamic>> getWallet() {
    // Dedupe in-flight (tanpa TTL): saldo harus fresh setelah transaksi,
    // tapi burst panggilan bersamaan (boot: 3×) cukup 1 RPC.
    return _coalesce<Map<String, dynamic>>('get_wallet', () async {
      final res = await measuredRpc(_sb, 'get_wallet');
      if (res is Map) return Map<String, dynamic>.from(res);
      return {
        'bonus': 0,
        'topup': 0,
        'earned': 0,
        'total': 0,
        'withdrawable': 0,
      };
    });
  }

  // ── YukCoin v2 ──────────────────────────────────────────────
  // Satu saldo (total) untuk UI, dipotong earned→bonus lewat spend_yukcoin.

  /// Level saya (kumulatif topup) — {level, cumulative, next_level, next_at,
  /// remaining, ladder[], just_rewarded[]}. Reward naik-level dicetak server
  /// (idempoten) → panggil ulang aman. TTL singkat: burst buka screen cukup
  /// 1 RPC; refresh setelah topup lewat invalidateTtl.
  Future<Map<String, dynamic>> getMyLevel() {
    return _coalesce<Map<String, dynamic>>('get_my_level', () async {
      final res = await measuredRpc(_sb, 'get_my_level');
      if (res is Map) return Map<String, dynamic>.from(res);
      return {'level': 0, 'cumulative': 0, 'ladder': const []};
    }, ttl: true);
  }

  /// Level user lain (badge di user_info) — {level}. Level bukan data
  /// sensitif; female/dummy memang 0 (male-only di server).
  Future<int> getUserLevel(String uid) {
    return _coalesce<int>(
      'get_user_level_$uid',
      () async {
        final res = await measuredRpc(
          _sb,
          'get_user_level',
          params: {'p_user': uid},
        );
        if (res is Map) return (res['level'] as num?)?.toInt() ?? 0;
        return 0;
      },
      ttl: true,
      ttlDuration: _ttlLong,
    );
  }

  /// Saldo YukCoin terpadu: {total, bonus, earned}.

  /// Apakah fitur YukCoin v2 aktif untuk user ini (flag server / admin).

  /// Status ringkas YukCoin v2: {active, total, bonus, earned, ghost, extra_slots}.
  Future<Map<String, dynamic>> yukcoinV2Status() {
    return _coalesce<Map<String, dynamic>>('yukcoin_v2_status', () async {
      try {
        final res = await measuredRpc(_sb, 'yukcoin_v2_status');
        if (res is Map) return Map<String, dynamic>.from(res);
      } catch (e) {
        dlog('[PointsService] yukcoinV2Status error: $e');
      }
      return {
        'active': false,
        'total': 0,
        'bonus': 0,
        'earned': 0,
        'ghost': false,
        'extra_slots': 0,
      };
    }, ttl: true);
  }

  /// Slot foto tambahan milik user.

  /// Potong YukCoin (earned→bonus). Return {tier, remaining}.

  /// Undo pesan (soft delete). Return {ok, cost, remaining}.
  Future<Map<String, dynamic>> undoMessage(int messageId) async {
    final res = await measuredRpc(
      _sb,
      'undo_message_v2',
      params: {'p_message_id': messageId},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Edit pesan. Return {ok, cost, remaining}.

  /// Beli slot foto tambahan (default +5). Return {ok, cost, extra, remaining}.
  Future<Map<String, dynamic>> buyExtraPhotoSlots({int slots = 5}) async {
    final res = await measuredRpc(
      _sb,
      'buy_extra_photo_slots_v2',
      params: {'p_slots': slots},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Beli ghost mode (invisible). Return {ok, cost, expires_at, remaining}.

  /// Apakah ghost mode (invisible) aktif.

  /// Riwayat ledger (terbaru dulu). Field:
  /// id, bucket, type, amount, ref_id, metadata, created_at.
  ///
  /// Query langsung ke `coin_ledger` (RLS `coin_ledger_select_own`) dengan
  /// `.range()` supaya bisa paging — hasil identik dengan RPC get_ledger_history
  /// (yang sama-sama `order by created_at desc`, tapi tanpa paging).
  Future<List<Map<String, dynamic>>> pointHistory({
    int limit = 200,
    int offset = 0,
  }) async {
    final id = uid;
    if (id == null) return [];
    final res = await _sb
        .from('coin_ledger')
        .select('id,bucket,type,amount,ref_id,metadata,created_at')
        .eq('user_id', id)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return res.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<Map<String, dynamic>> dailyLoginBonus() async {
    // Offset HP → server menentukan "hari ini" menurut waktu LOKAL pengguna
    // (semua negara), bukan hardcode Asia/Jakarta.
    final res = await measuredRpc(
      _sb,
      'daily_login_bonus',
      params: {'p_tz_offset_minutes': DateTime.now().timeZoneOffset.inMinutes},
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'points': (res as num?)?.toInt() ?? 0, 'streak': 0, 'bonus': 0};
  }

  Future<int> deductChatPoint(String msgType) async {
    final res = await measuredRpc(
      _sb,
      'deduct_chat_point',
      params: {'msg_type': msgType},
    );
    return (res as num).toInt();
  }

  Future<int> refundChatPoint(String msgType) async {
    final res = await measuredRpc(
      _sb,
      'refund_chat_point',
      params: {'msg_type': msgType},
    );
    return (res as num).toInt();
  }

  Future<int> newChatBonus(String otherUid) async {
    final res = await measuredRpc(
      _sb,
      'new_chat_bonus',
      params: {'other_uid': otherUid},
    );
    return (res as num).toInt();
  }

  /// Reward koin upload foto slot 1..5 (sekali per slot). Return total koin.

  /// Biaya buka foto (once, perm) dari app_settings.

  /// Leaderboard. scope: 'weekly' | 'alltime'. Return {scope, entries[], me}.
  ///
  /// `offset` > 0 membutuhkan migration `points_leaderboard(text,int,int)`
  /// (supabase/migrations/20260913000000_leaderboard_history_pagination.sql);
  /// saat offset 0 param tidak dikirim — kompatibel dengan fungsi server lama.
  Future<Map<String, dynamic>> leaderboard(
    String scope, {
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'scope': scope,
      'row_limit': limit,
      if (offset > 0) 'row_offset': offset,
    };
    final res = await measuredRpc(_sb, 'points_leaderboard', params: params);
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'scope': scope, 'entries': [], 'me': null};
  }

  /// "Top Aktif" — leaderboard keaktifan (pesan + reaksi).
  /// scope: 'weekly' (7 hari) | 'alltime'. Return {scope, entries[], me}.
  Future<Map<String, dynamic>> activityLeaderboard(
    String scope, {
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'p_scope': scope,
      'p_limit': limit,
      if (offset > 0) 'p_offset': offset,
    };
    final res = await measuredRpc(_sb, 'activity_leaderboard', params: params);
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'scope': scope, 'entries': [], 'me': null};
  }

  /// Harga room (dual pricing) dari server.
  Future<Map<String, dynamic>> roomPricing() async {
    try {
      final res = await measuredRpc(_sb, 'room_pricing');
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      dlog('[PointsService] roomPricing error: $e');
    }
    return {
      'create_paid': 100,
      'create_pw_paid': 150,
      'join_paid': 5,
      'extend_paid': 50,
      'multiplier': 3,
    };
  }

  /// Subscribe creator (paid-only). Return {ok, points, ...}.
  Future<Map<String, dynamic>> subscribeCreator(
    String creatorUid, {
    int periods = 1,
    int? expectedPrice,
  }) async {
    return subscribeCreatorRpc(
      _sb,
      creatorUid,
      periods: periods,
      expectedPrice: expectedPrice,
    );
  }

  /// Klaim reward referral-install (sekali per referred).
}
