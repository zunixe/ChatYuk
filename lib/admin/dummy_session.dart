import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
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

  static final SupabaseClient _sb = SupabaseConfig.client;
  static const _kAdminAccessToken = 'dummy_admin_access_token';
  static const _kAdminRefreshToken = 'dummy_admin_refresh_token';

  static String? _adminAccessToken;
  static String? _adminRefreshToken;

  /// Pindah ke akun dummy [uid]. Lempar exception kalau gagal — sesi admin
  /// dipulihkan otomatis supaya tidak logout.
  static Future<void> becomeDummy(String uid) async {
    final session = _sb.auth.currentSession;
    _adminAccessToken = session?.accessToken;
    _adminRefreshToken = session?.refreshToken;
    await _saveAdminTokens(_adminAccessToken, _adminRefreshToken);
    // Token lama bisa basi (GoTrue me-revoke saat auto-refresh client).
    // Fallback: regenerasi sesi dummy lewat RPC supaya swap selalu berhasil.
    var refreshToken =
        await _sb.rpc('admin_get_dummy_token', params: {'p_uid': uid})
            as String?;
    if (refreshToken == null || refreshToken.isEmpty) {
      refreshToken =
          await _sb.rpc('admin_renew_dummy_token', params: {'p_uid': uid})
              as String?;
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception('dummy_token_missing');
    }
    try {
      await _sb.auth.setSession(refreshToken);
    } catch (e) {
      debugPrint('[DUMMY] setSession failed: $e — renewing');
      try {
        final renewed =
            await _sb.rpc('admin_renew_dummy_token', params: {'p_uid': uid})
                as String?;
        if (renewed == null || renewed.isEmpty) {
          throw Exception('dummy_token_invalid');
        }
        await _sb.auth.setSession(renewed);
      } catch (e2) {
        debugPrint('[DUMMY] renew failed: $e2 — restoring admin');
        final a = _adminAccessToken;
        final r = _adminRefreshToken;
        _adminAccessToken = null;
        _adminRefreshToken = null;
        _restoreAdmin(a, r);
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
        debugPrint('[DUMMY] update token error: $e');
      }
    }
    AuthService.instance?.markDummyState(active: true, uid: uid);
  }

  /// Kembali ke akun admin. Sesi dummy TIDAK di-logout & statusnya tetap.
  /// Return false jika token admin kedaluwarsa (perlu login manual).
  static Future<bool> backToAdmin() async {
    var adminAccess = _adminAccessToken;
    var adminRefresh = _adminRefreshToken;
    _adminAccessToken = null;
    _adminRefreshToken = null;
    if (adminAccess == null || adminRefresh == null) {
      final prefs = await SharedPreferences.getInstance();
      adminAccess = prefs.getString(_kAdminAccessToken);
      adminRefresh = prefs.getString(_kAdminRefreshToken);
    }
    if (adminRefresh == null || adminAccess == null) {
      return false;
    }
    try {
      await _sb.auth.setSession(adminRefresh, accessToken: adminAccess);
      await clearStored();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pulihkan state dummy setelah app restart: sesi aktif anonymous milik
  /// dummy → restore flag + token admin dari SharedPreferences.
  static Future<void> restoreIfNeeded() async {
    final user = _sb.auth.currentUser;
    if (user == null || !user.isAnonymous) return;
    final uid = user.id;
    bool isDummy = false;
    try {
      isDummy =
          await _sb.rpc('is_dummy_account', params: {'p_uid': uid}) as bool? ??
          false;
    } catch (e) {
      debugPrint('[DUMMY] restore check error: $e');
      return;
    }
    if (!isDummy) return;
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_kAdminRefreshToken);
    final access = prefs.getString(_kAdminAccessToken);
    if (refresh == null || refresh.isEmpty) return;
    _adminRefreshToken = refresh;
    _adminAccessToken = access;
    AuthService.instance?.markDummyState(active: true, uid: uid);
    debugPrint('[DUMMY] session restored: $uid');
  }

  /// Ada token admin tersimpan di SharedPreferences? Dipakai recovery.
  static Future<bool> hasStoredTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_kAdminRefreshToken);
    return refresh != null && refresh.isNotEmpty;
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
  static void _restoreAdmin(String? access, String? refresh) {
    if (refresh != null && access != null) {
      try {
        _sb.auth.setSession(refresh, accessToken: access);
      } catch (_) {}
    }
  }
}
