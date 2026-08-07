import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/user_photo.dart';
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

  /// Bersihkan akun anonymous stale (tidak aktif > 7 hari) di server.
  /// Agar nickname mereka bebas dipakai dan tidak muncul sebagai
  /// ghost "online". Fire-and-forget dari app saat start.
  Future<void> cleanupStaleAnonymous({int minAgeDays = 7}) async {
    try {
      await _sb.rpc('cleanup_stale_anonymous', params: {'min_age_days': minAgeDays});
    } catch (e) {
      debugPrint('[AUTH] cleanupStaleAnonymous error (abaikan): $e');
    }
  }

  /// Login dengan email + password.
  /// Setelah ini, getProfile() akan mengembalikan profile user.
  Future<void> signInWithEmail(String email, String password) async {
    final res = await _sb.auth.signInWithPassword(email: email, password: password);
    if (res.user == null) throw Exception('Login failed');
  }

  /// Upgrade anonymous account ke email account.
  /// UID tidak berubah - semua data (chat, profile) dipertahankan.
  Future<void> linkEmailToAccount(String email, String password) async {
    await _sb.auth.updateUser(UserAttributes(email: email, password: password));
  }

  /// Tandai profile sebagai terdaftar (punya email).
  Future<void> markRegistered() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb.from('profiles').update({'is_registered': true}).eq('id', id);
    } catch (_) {}
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
    final hasEmail = (user.email ?? '').isNotEmpty;
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
      isRegistered: hasEmail,
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
      'is_registered': hasEmail,
      'login_at': now.toUtc().toIso8601String(),
      'created_at': now.toUtc().toIso8601String(),
      'last_seen': now.toUtc().toIso8601String(),
    }, onConflict: 'id');

    return profile;
  }

  Future<UserModel?> getProfile() async {
    final id = uid;
    if (id == null) return null;
    // Exclude fcm_token dan ip_address �?" tidak dibutuhkan di model
    const cols = 'id,nickname,gender,age,country,city,status,avatar,is_registered,login_at,created_at,last_seen';
    final res = await _sb.from('profiles').select(cols).eq('id', id).maybeSingle();
    if (res == null) return null;
    return UserModel.fromMap(id, snakeToCamel(res));
  }

  /// Ambil profil user lain (untuk halaman info pengguna).
  Future<UserModel?> getProfileById(String id) async {
    if (id.isEmpty) return null;
    const cols = 'id,nickname,gender,age,country,city,status,avatar,is_registered,login_at,created_at,last_seen';
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

  /// Ambil semua foto galeri milik satu user.
  Future<List<UserPhoto>> getPhotos(String userId) async {
    if (userId.isEmpty) return [];
    final rows = await _sb
        .from('user_photos')
        .select('id,user_id,photo,created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.map((row) => UserPhoto.fromMap('${row['id']}', {
      'userId': row['user_id'],
      'photo': row['photo'],
      'createdAt': row['created_at'],
    })).toList();
  }

  /// Upload foto galeri milik sendiri. Max 6 foto per user.
  Future<void> uploadPhoto(String base64) async {
    final id = uid;
    if (id == null) return;
    if (base64.isNotEmpty && !isValidImageBase64(base64)) {
      throw Exception('Invalid image format');
    }
    // Limit ukuran: max 1MB base64 (~768KB file)
    if (base64.length > 1048576) {
      throw Exception('Photo too large (max 768KB)');
    }
    // Batasi jumlah foto per user = 6
    final rows = await _sb
        .from('user_photos')
        .select('id')
        .eq('user_id', id);
    if (rows.length >= 6) {
      throw Exception('Max 6 photos');
    }
    await _sb.from('user_photos').insert({'user_id': id, 'photo': base64});
  }

  /// Hapus foto galeri (hanya punya sendiri, RLS menjamin).
  Future<void> deletePhoto(String photoId) async {
    if (photoId.isEmpty) return;
    await _sb.from('user_photos').delete().eq('id', photoId);
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
