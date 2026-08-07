import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../config/supabase_config.dart';
import '../utils.dart';

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

class AuthService {
  final SupabaseClient _sb = SupabaseConfig.client;

  User? get currentUser => _sb.auth.currentUser;
  String? get uid => _sb.auth.currentUser?.id;
  bool get isSignedIn => _sb.auth.currentUser != null;

  bool get isAnonymous => _sb.auth.currentUser?.isAnonymous ?? true;
  String? get userEmail => _sb.auth.currentUser?.email;

  Future<void> signInAnonymously() async {
    if (_sb.auth.currentUser != null) return;
    final res = await _sb.auth.signInAnonymously();
    debugPrint('[AUTH] signInAnonymously -> ${res.user?.id}');
  }

  /// Login dengan email + password.
  /// Setelah ini, getProfile() akan mengembalikan profile user.
  Future<void> signInWithEmail(String email, String password) async {
    final res = await _sb.auth.signInWithPassword(email: email, password: password);
    if (res.user == null) throw Exception('Login failed');
  }

  /// Upgrade anonymous account ke email account.
  /// UID tidak berubah — semua data (chat, profile) dipertahankan.
  Future<void> linkEmailToAccount(String email, String password) async {
    await _sb.auth.updateUser(UserAttributes(email: email, password: password));
  }

  /// Cek apakah email sudah terdaftar di Auth (RPC security definer).
  /// Kalau RPC belum dibuat di DB, fallback ke [fallback]
  /// (reset: true = lanjut kirim seperti lama; signup: false = lanjut daftar).
  Future<bool> checkEmailRegistered(String email, {bool fallback = true}) async {
    try {
      final res = await _sb.rpc('check_email_registered', params: {'p_email': email});
      return res == true;
    } catch (e) {
      debugPrint('[AUTH] checkEmailRegistered error, fallback=$fallback: $e');
      return fallback;
    }
  }

  /// Daftar akun baru dengan email + password.
  /// Mengembalikan userId — caller harus panggil registerProfile() setelahnya.
  /// Lempar [EmailAlreadyRegisteredException] jika email sudah terdaftar.
  Future<String> signUpWithEmail(String email, String password) async {
    if (await checkEmailRegistered(email, fallback: false)) {
      throw EmailAlreadyRegisteredException();
    }
    final res = await _sb.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: 'chatyuk://login-callback',
    );
    final user = res.user;
    if (user == null) throw Exception('Sign up failed: no user returned');
    return user.id;
  }

  /// Kirim ulang email verifikasi (untuk user yang sudah signup tapi belum verify).
  Future<void> resendVerificationEmail(String email) async {
    await _sb.auth.resend(type: OtpType.signup, email: email);
  }

  /// Kirim email reset password.
  Future<void> sendPasswordResetEmail(String email) async {
    await _sb.auth.resetPasswordForEmail(
      email,
      redirectTo: 'chatyuk://login-callback',
    );
  }

  /// Set password baru. Dipanggil dari screen reset password
  /// setelah user membuka link recovery di email.
  Future<void> resetPassword(String newPassword) async {
    await _sb.auth.updateUser(UserAttributes(password: newPassword));
    // Logout agar user login ulang dengan password baru
    await _sb.auth.signOut();
  }

  /// Cek apakah nickname sudah dipakai oleh user lain.
  Future<bool> isNicknameAvailable(String nickname) async {
    final id = uid;
    var query = _sb.from('profiles').select('id').eq('nickname', nickname);
    if (id != null) query = query.neq('id', id);
    final res = await query.maybeSingle();
    return res == null; // null = tidak ada yang pakai
  }

  Future<UserModel> registerProfile({
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
    String ipAddress = '', // disimpan di server saja, tidak disimpan di aplikasi
  }) async {
    // Jangan fallback ke anonymous — kalau tidak ada user, lempar error
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('registerProfile: no authenticated user');
    final now = DateTime.now().toUtc();
    final profile = UserModel(
      uid: user.id,
      nickname: nickname,
      gender: gender,
      age: age,
      country: country,
      city: city,
      ipAddress: '', // tidak disimpan di model lokal — hanya di server
      status: 'online',
      avatar: '',
      loginAt: now,
      createdAt: now,
      lastSeen: now,
    );

    await _sb.from('profiles').upsert({
      'id': user.id,
      'nickname': nickname,
      'gender': gender,
      'age': age,
      'country': country,
      'city': city,
      // IP dicatat di server untuk keperluan keamanan/moderasi,
      // tidak disimpan di perangkat aplikasi.
      if (ipAddress.isNotEmpty) 'ip_address': ipAddress,
      'status': 'online',
      'avatar': '',
      'fcm_token': '',
      'login_at': now.toUtc().toIso8601String(),
      'created_at': now.toUtc().toIso8601String(),
      'last_seen': now.toUtc().toIso8601String(),
    }, onConflict: 'id');

    return profile;
  }

  Future<UserModel?> getProfile() async {
    final id = uid;
    if (id == null) return null;
    // Exclude fcm_token dan ip_address — tidak dibutuhkan di model
    const cols = 'id,nickname,gender,age,country,city,status,avatar,login_at,created_at,last_seen';
    final res = await _sb.from('profiles').select(cols).eq('id', id).maybeSingle();
    if (res == null) return null;
    return UserModel.fromMap(id, snakeToCamel(res));
  }

  Future<void> updateProfile({int? age, String? country, String? city}) async {
    final id = uid;
    if (id == null) return;
    final data = <String, dynamic>{
      if (age != null) 'age': age,
      if (country != null) 'country': country,
      if (city != null) 'city': city,
    };
    await _sb.from('profiles').update(data).eq('id', id);
  }

  /// Update IP address di server (keamanan/moderasi).
  /// IP hanya disimpan di server, tidak disimpan di aplikasi.
  Future<void> updateIpAddress(String ip) async {
    final id = uid;
    if (id == null || ip.isEmpty) return;
    try {
      await _sb.from('profiles').update({'ip_address': ip}).eq('id', id);
    } catch (e) {
      debugPrint('[AUTH] updateIpAddress error: $e');
    }
  }

  Future<void> updateAvatar(String base64) async {
    final id = uid;
    if (id == null) return;
    // Validasi base64 adalah JPEG atau PNG yang valid
    if (base64.isNotEmpty && !isValidImageBase64(base64)) {
      throw Exception('Invalid image format');
    }
    // Limit ukuran: max 512KB base64 (~384KB file)
    if (base64.length > 524288) {
      throw Exception('Image too large (max 384KB)');
    }
    await _sb.from('profiles').update({'avatar': base64}).eq('id', id);
  }

  Future<void> removeAvatar() async {
    final id = uid;
    if (id == null) return;
    await _sb.from('profiles').update({'avatar': ''}).eq('id', id);
  }

  Future<void> updateFcmToken(String? token) async {
    final id = uid;
    if (id == null) return;
    await _sb.from('profiles').update({'fcm_token': token ?? ''}).eq('id', id);
  }

  Future<void> goOffline() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb.from('profiles').update({'status': 'offline', 'last_seen': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
    } catch (_) {}
  }

  Future<void> goIdle() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb.from('profiles').update({'status': 'idle'}).eq('id', id);
    } catch (_) {}
  }

  Future<void> goOnline() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb.from('profiles').update({'status': 'online', 'last_seen': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
    } catch (_) {}
  }

  Future<void> signOut() async {
    await _sb.auth.signOut();
  }

  Stream<bool> get authState {
    return _sb.auth.onAuthStateChange.map((data) {
      final session = data.session;
      return session != null;
    });
  }
}
