import '../utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../core/admin_gate.dart';
import '../services/auth_service.dart';

/// Sesi dummy: admin berpindah akun tanpa login manual.
/// HANYA di-import oleh build admin (via admin_wiring.dart) — seluruh
/// nama RPC dan kredensial di file ini tidak ada di binary rilis.
///
/// Mekanisme:
/// - Token admin disimpan ke SharedPreferences sebelum swap, supaya bisa
///   pulih saat restart atau saat sesi dummy mati server-side.
/// - GoTrue memutar refresh_token tiap setSession → token baru selalu
///   ditulis balik ke tabel dummy_accounts lewat admin_update_dummy_token.
class DummySession {
  DummySession._();

  // Getter (bukan static final) — Supabase.instance.client baru ada setelah
  // Supabase.initialize; kalau di-inisialisasi di static final, mereferensikan
  // DummySession sekecil apa pun sebelum initialize = crash startup.
  static SupabaseClient get _sb => SupabaseConfig.client;
  static const _kAdminAccessToken = 'dummy_admin_access_token';
  static const _kAdminRefreshToken = 'dummy_admin_refresh_token';

  static String? _adminAccessToken;
  static String? _adminRefreshToken;

  /// Pindah ke akun dummy [uid]. Lempar exception kalau gagal — sesi admin
  /// dipulihkan otomatis supaya tidak logout.
  static Future<void> becomeDummy(String uid) async {
    // Sudah menjadi dummy ini? Tidak perlu swap ulang.
    final cur = _sb.auth.currentUser;
    if (cur != null &&
        cur.id == uid &&
        AuthService.instance.dummySessionActive) {
      dlog('[DUMMY] already active as $uid — skip');
      return;
    }
    final session = _sb.auth.currentSession;
    _adminAccessToken = session?.accessToken;
    _adminRefreshToken = session?.refreshToken;
    await _saveAdminTokens(_adminAccessToken, _adminRefreshToken);
    // Tandai dummy SEBELUM swap — event signedIn/tokenRefreshed dari
    // setSession di bawah tiba async dan bisa menyalip mark di akhir;
    // tanpa ini token DUMMY tersimpan sebagai "token admin" (prefs
    // keracunan → backToAdmin gagal permanen sampai login manual).
    AuthService.instance.markDummyState(active: true, uid: uid);
    // SELALU renew dulu — refresh token GoTrue sifatnya sekali-pakai
    // (dirotasi tiap pemakaian, dan auto-refresh client app dummy di HP
    // lain bisa sudah memutar token tersimpan). Pakai token tersimpan
    // dulu = "kadang berhasil kadang tidak". Renew = deterministik.
    var refreshToken = await _renewViaEdgeFunction(uid);
    if (refreshToken == null || refreshToken.isEmpty) {
      // Fallback: token tersimpan (bisa basi).
      refreshToken =
          await _sb.rpc('admin_get_dummy_token', params: {'p_uid': uid})
              as String?;
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception('dummy_token_missing');
    }
    try {
      await _sb.auth.setSession(refreshToken);
    } catch (e) {
      dlog('[DUMMY] setSession failed: $e — renewing');
      try {
        final renewed = await _renewViaEdgeFunction(uid);
        if (renewed == null || renewed.isEmpty) {
          throw Exception('dummy_token_invalid');
        }
        await _sb.auth.setSession(renewed);
      } catch (e2) {
        dlog('[DUMMY] renew failed: $e2 — restoring admin');
        final a = _adminAccessToken;
        final r = _adminRefreshToken;
        _adminAccessToken = null;
        _adminRefreshToken = null;
        AuthService.instance.markDummyState(active: false);
        await _restoreAdmin(a, r);
        await clearStored();
        rethrow;
      }
    }
    final newToken = _sb.auth.currentSession?.refreshToken;
    if (newToken != null) {
      try {
        await _sb.rpc(
          'admin_update_dummy_token',
          params: {'p_uid': uid, 'p_refresh_token': newToken},
        );
      } catch (e) {
        dlog('[DUMMY] update token error: $e');
      }
    }
    AuthService.instance.markDummyState(active: true, uid: uid);
    // HOLD: tandai dummy ini dipegang manusia → AI-nya vakum (tidak
    // membalas otomatis) sampai kembali ke admin. Fire-and-forget.
    try {
      await _sb.rpc(
        'set_dummy_hold',
        params: {'p_uid': uid, 'p_held': true},
      );
    } catch (_) {}
    dlog('[DUMMY] becomeDummy OK uid=$uid '
        'sessionUid=${_sb.auth.currentUser?.id}');
  }

  /// Regenerasi refresh_token ASLI via edge function `dummy-manage`
  /// (action renew): set password via Admin API lalu login password.
  static Future<String?> _renewViaEdgeFunction(String uid) async {
    try {
      final res = await _sb.functions.invoke(
        'dummy-manage',
        body: {'action': 'renew', 'uid': uid},
      );
      if (res.status >= 300) {
        dlog('[DUMMY] renew fn http ${res.status}');
        return null;
      }
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return data['refresh_token'] as String?;
      }
    } catch (e) {
      dlog('[DUMMY] renew fn error: $e');
    }
    return null;
  }

  /// Kembali ke akun admin. Sesi dummy TIDAK di-logout & statusnya tetap.
  /// Return false jika token admin kedaluwarsa (perlu login manual).
  /// Sukses DIVERIFIKASI (email pendaratan harus admin) — token basi atau
  /// tertukar token dummy tidak lagi dilaporkan sukses palsu.
  static Future<bool> backToAdmin() async {
    var adminAccess = _adminAccessToken;
    var adminRefresh = _adminRefreshToken;
    _adminAccessToken = null;
    _adminRefreshToken = null;
    // Uid dummy yang dilepas (untuk lepas HOLD AI-nya).
    final heldUid = _sb.auth.currentUser?.id;
    if (adminAccess == null || adminRefresh == null) {
      final prefs = await SharedPreferences.getInstance();
      adminAccess = prefs.getString(_kAdminAccessToken);
      adminRefresh = prefs.getString(_kAdminRefreshToken);
    }
    if (adminRefresh == null || adminAccess == null) {
      dlog('[DUMMY] backToAdmin: no admin tokens (memory+prefs empty)');
      return false;
    }
    try {
      await _sb.auth.setSession(adminRefresh, accessToken: adminAccess);
      await clearStored();
      final landed = _sb.auth.currentUser?.email;
      dlog('[DUMMY] backToAdmin setSession ok, landed=$landed');
      if (!AdminGate.isRealAdmin(landed)) {
        dlog('[DUMMY] backToAdmin landed on non-admin — tokens poisoned?');
        // Token basi/tertukar → bersihkan flag & token supaya UI tidak
        // "setengah admin" (banner dummy nempel di akun yang salah).
        AuthService.instance.markDummyState(active: false);
        await clearStored();
        return false;
      }
      // Lepas HOLD — AI dummy ini aktif lagi setelah admin kembali.
      if (heldUid != null) {
        try {
          await _sb.rpc(
            'set_dummy_hold',
            params: {'p_uid': heldUid, 'p_held': false},
          );
        } catch (_) {}
      }
      return true;
    } catch (e) {
      dlog('[DUMMY] backToAdmin setSession failed: $e');
      // Token admin kedaluwarsa → flag dummy HARUS dibersihkan; kalau tidak,
      // setelah login manual banner dummy tetap tampil (state basi).
      AuthService.instance.markDummyState(active: false);
      await clearStored();
      return false;
    }
  }

  /// Pulihkan state dummy setelah app restart: cek via RPC is_dummy_account
  /// (TIDAK bergantung flag anonymous — dummy kini punya email+password).
  static Future<void> restoreIfNeeded() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final uid = user.id;
    bool isDummy = false;
    try {
      isDummy =
          await _sb.rpc('is_dummy_account', params: {'p_uid': uid}) as bool? ??
          false;
    } catch (e) {
      dlog('[DUMMY] restore check error: $e');
      return;
    }
    if (!isDummy) {
      // Sesi aktif bukan dummy → flag basi (sisa recovery gagal) harus
      // dibersihkan supaya banner dummy tidak nempel di akun yang salah.
      if (AuthService.instance.dummySessionActive) {
        AuthService.instance.markDummyState(active: false);
        await clearStored();
        dlog('[DUMMY] restore: flag basi dibersihkan (sesi bukan dummy)');
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_kAdminRefreshToken);
    final access = prefs.getString(_kAdminAccessToken);
    if (refresh == null || refresh.isEmpty) return;
    _adminRefreshToken = refresh;
    _adminAccessToken = access;
    AuthService.instance.markDummyState(active: true, uid: uid);
    dlog('[DUMMY] session restored: $uid');
  }

  /// Ada token admin tersimpan di SharedPreferences? Dipakai recovery.
  static Future<bool> hasStoredTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_kAdminRefreshToken);
    return refresh != null && refresh.isNotEmpty;
  }

  /// Simpan ulang token sesi ADMIN yang sedang aktif — dipanggil tiap
  /// auth event (tokenRefreshed/signedIn) supaya token tersimpan TIDAK
  /// pernah basi saat dibutuhkan backToAdmin.
  static Future<void> persistAdminTokensIfAdmin() async {
    if (AuthService.instance.dummySessionActive) return;
    final s = _sb.auth.currentSession;
    if (s == null) return;
    // Jaga memory tetap sinkron dengan prefs (menutup selisih keduanya).
    _adminAccessToken = s.accessToken;
    _adminRefreshToken = s.refreshToken;
    await _saveAdminTokens(s.accessToken, s.refreshToken);
  }

  static bool _tokenPersistenceInstalled = false;

  /// Pasang listener penyimpan token admin. WAJIB dipanggil setelah
  /// Supabase.initialize (dari AdminGate.postInit) — memanggilnya terlalu
  /// awal membuat `Supabase.instance.client` belum ada → crash startup.
  static Future<void> installTokenPersistence() async {
    if (_tokenPersistenceInstalled) return;
    _tokenPersistenceInstalled = true;
    try {
      _sb.auth.onAuthStateChange.listen((d) {
        if (d.event == AuthChangeEvent.tokenRefreshed ||
            d.event == AuthChangeEvent.signedIn) {
          persistAdminTokensIfAdmin();
        }
      });
      await persistAdminTokensIfAdmin();
    } catch (e) {
      dlog('[DUMMY] installTokenPersistence error: $e');
    }
  }

  /// Hapus token admin tersimpan (dipanggil saat logout total).
  static Future<void> clearStored() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAdminAccessToken);
    await prefs.remove(_kAdminRefreshToken);
  }

  static Future<void> _saveAdminTokens(String? access, String? refresh) async {
    if (access == null || refresh == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAdminAccessToken, access);
    await prefs.setString(_kAdminRefreshToken, refresh);
  }

  /// Pulihkan sesi admin tanpa menyentuh state dummy lainnya.
  static Future<void> _restoreAdmin(String? access, String? refresh) async {
    if (refresh != null && access != null) {
      try {
        await _sb.auth.setSession(refresh, accessToken: access);
      } catch (e) {
        dlog('[DUMMY] _restoreAdmin failed: $e');
      }
    }
  }
}
