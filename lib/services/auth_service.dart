import 'dart:async';
import 'dart:convert';
import '../core/cache/media_disk_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/user_photo.dart';
import '../config/supabase_config.dart';
import '../core/admin_gate.dart';
import '../services/storage_photo_service.dart';
import '../services/avatar_service.dart';
import '../services/device_info_service.dart';
import '../utils.dart';

part 'auth_service_auth.dart';
part 'auth_service_settings.dart';
part 'auth_service_profile.dart';

/// Dilempar saat email tidak terdaftar di Auth (cek via RPC sebelum kirim reset).
class EmailNotRegisteredException implements Exception {
  @override
  String toString() => 'EmailNotRegisteredException';
}

/// Dilempar saat email sudah terdaftar — cegah register berulang.
class EmailAlreadyRegisteredException implements Exception {
  @override
  String toString() => 'EmailAlreadyRegisteredException';
}

/// State instance BERSAMA lintas domain AuthService.
abstract class AuthBase {
  SupabaseClient get _sb => SupabaseConfig.client;
  User? get currentUser => _sb.auth.currentUser;
  String? get uid => _sb.auth.currentUser?.id;
  bool get isSignedIn => _sb.auth.currentUser != null;
  bool get isAnonymous => _sb.auth.currentUser?.isAnonymous ?? true;
  String? get userEmail => _sb.auth.currentUser?.email;
  bool get emailConfirmed => _sb.auth.currentUser?.emailConfirmedAt != null;
  static const String googleWebClientIdDefault =
      '599111437536-hg56bq0nc2m6kig6hg41lmrbtfel5n2c.apps.googleusercontent.com';
  static String? googleWebClientIdOverride;
  Future<({AuthResponse response, String? googleEmail})?>
  signInWithGoogle() async {
    final webClientId = googleWebClientIdOverride ?? googleWebClientIdDefault;
    final googleSignIn = GoogleSignIn(serverClientId: webClientId);
    try {
      await googleSignIn.signOut();
    } catch (_) {}
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return null;
    final googleEmail = googleUser.email;
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;
    if (idToken == null) throw Exception('Google idToken null');
    dlog(
      '[GOOGLE] idToken len=${idToken.length} accessToken len=${accessToken?.length ?? 0} webClientId=$webClientId',
    );
    try {
      final parts = idToken.split('.');
      if (parts.length == 3) {
        final payload = String.fromCharCodes(
          base64Url.decode(base64Url.normalize(parts[1])),
        );
        dlog(
          '[GOOGLE] idToken payload aud check: ${payload.substring(0, payload.length > 500 ? 500 : payload.length)}',
        );
      }
    } catch (_) {}
    AuthResponse response;
    try {
      response = await _sb.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e, st) {
      dlog('[GOOGLE] signInWithIdToken FAILED: $e');
      dlog('[GOOGLE] stack: $st');
      if (e is AuthApiException) {
        dlog(
          '[GOOGLE] AuthApiException statusCode=${e.statusCode} code=${e.code} message=${e.message}',
        );
      }
      rethrow;
    }
    final id = _sb.auth.currentUser?.id;
    if (id != null) {
      try {
        await _sb.from('profiles').update({'email': googleEmail}).eq('id', id);
      } catch (e) {
        dlog('[AUTH] signInWithGoogle email update error: $e');
      }
    }
    return (response: response, googleEmail: googleEmail);
  }
  bool _cachedHasPassword = false;
  bool _hasPasswordFetched = false;
  bool get hasPassword {
    if (_hasPasswordFetched) return _cachedHasPassword;
    final user = currentUser;
    if (user == null) return false;
    final providers = user.appMetadata['providers'];
    if (providers is List) return providers.contains('email');
    final identities = user.identities;
    if (identities != null) {
      for (final id in identities) {
        final p = (id as dynamic).provider as String?;
        if (p == 'email') return true;
        final map = (id as dynamic).toJson is Function
            ? (id as dynamic).toJson() as Map
            : null;
        if (map != null && map['provider'] == 'email') return true;
      }
    }
    return user.appMetadata['provider'] != 'google';
  }
  String? _dummyUid;
  bool _dummySessionActive = false;
  bool get dummySessionActive => _dummySessionActive;
  String? get activeDummyUid => _dummyUid;
  Stream<bool> get authState {
    return _sb.auth.onAuthStateChange.map((data) {
      final session = data.session;
      return session != null;
    });
  }
  Stream<AuthState> get authStateChanges => _sb.auth.onAuthStateChange;
  /// Download foto galeri dengan DISK FIRST — b64 di-cache disk per path
  /// (path unik per upload), buka profil berikutnya tanpa network.
  Future<String> _galleryPhotoB64(String path) async {
    final disk = await MediaDiskCache.instance.read(path);
    if (disk != null && disk.isNotEmpty) return base64Encode(disk);
    final b64 = await StoragePhotoService.instance.download(path) ?? '';
    if (b64.isNotEmpty) {
      try {
        await MediaDiskCache.instance.write(
          path,
          Uint8List.fromList(base64Decode(b64)),
        );
      } catch (_) {}
    }
    return b64;
  }
}

class AuthService extends AuthBase
    with AuthServiceAuthMx, AuthServiceSettingsMx, AuthServiceProfileMx {
  /// Singleton sejati — semua pemanggil `AuthService()` (provider, screen,
  /// FCM handler) dapat OBJEK YANG SAMA, sehingga flag sesi dummy yang di-set
  /// modul admin selalu terlihat di seluruh app.
  static final AuthService instance = AuthService._();
  factory AuthService() => instance;
  AuthService._();
}
