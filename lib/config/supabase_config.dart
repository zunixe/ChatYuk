import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils.dart';
import 'env.dart';

/// [LocalStorage] Supabase yang menyimpan sesi (refresh token) di
/// FlutterSecureStorage (Android Keystore / iOS Keychain) — BUKAN
/// SharedPreferences plaintext. Sesi = kredensial paling sensitif di app
/// (kalau bocor → account takeover), jadi harus terenkripsi seperti
/// MessageCache (yang sudah pakai secure storage + SQLCipher).
///
/// Migrasi satu kali: user lama menyimpan sesi di SharedPreferences (kunci
/// `sb-<ref>-auth-token`). Saat baca pertama, kalau secure storage kosong
/// tapi SharedPreferences punya token, token dipindah ke secure storage lalu
/// salinan plaintext DIHAPUS → user tidak ter-logout paksa saat update.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.persistSessionKey, this.legacyPrefsKey});

  final String persistSessionKey;

  /// Kunci lama di SharedPreferences (dari supabase_flutter default) yang
  /// perlu dimigrasi + dihapus.
  final String? legacyPrefsKey;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _migrated = false;

  Future<void> _migrateLegacyOnce() async {
    if (_migrated || legacyPrefsKey == null) return;
    _migrated = true;
    try {
      final secure = await _storage.read(key: persistSessionKey);
      if (secure != null && secure.isNotEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(legacyPrefsKey!);
      if (legacy == null || legacy.isEmpty) return;
      await _storage.write(key: persistSessionKey, value: legacy);
      await prefs.remove(legacyPrefsKey!);
      dlog('[SecureSessionStorage] migrasi sesi ke secure storage OK');
    } catch (e) {
      dlog('[SecureSessionStorage] migrasi error: $e');
    }
  }

  @override
  Future<void> initialize() async {
    await _migrateLegacyOnce();
  }

  @override
  Future<bool> hasAccessToken() async {
    try {
      await _migrateLegacyOnce();
      return (await _storage.read(key: persistSessionKey)) != null;
    } catch (e) {
      dlog('[SecureSessionStorage] hasAccessToken error: $e');
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      await _migrateLegacyOnce();
      return await _storage.read(key: persistSessionKey);
    } catch (e) {
      dlog('[SecureSessionStorage] accessToken error: $e');
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: persistSessionKey);
    } catch (e) {
      dlog('[SecureSessionStorage] removePersistedSession error: $e');
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _storage.write(key: persistSessionKey, value: persistSessionString);
    } catch (e) {
      dlog('[SecureSessionStorage] persistSession error: $e');
    }
  }
}

class SupabaseConfig {
  // Nilai dari lib/config/env.dart (dart-define, fallback prod).
  static String get url => AppEnv.supabaseUrl;
  static String get publishableKey => AppEnv.supabaseAnonKey;

  /// Link share aplikasi — langsung ke Google Play.
  /// (Dulu: edge function /r dengan uid untuk tracking klik; tracking
  /// dimatikan sesuai permintaan — semua share kini ke listing Play Store.)
  static const String shareLink =
      'https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';

  static Future<void> init() async {
    // Kunci sesi lama di SharedPreferences (default supabase_flutter).
    final legacyKey =
        'sb-${Uri.parse(url).host.split('.').first}-auth-token';
    await Supabase.initialize(
      url: url,
      anonKey: publishableKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        // Sesi disimpan terenkripsi (bukan SharedPreferences plaintext).
        localStorage: SecureSessionStorage(
          persistSessionKey: 'chatyuk_supabase_session_v1',
          legacyPrefsKey: legacyKey,
        ),
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
