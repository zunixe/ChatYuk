import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/user_photo.dart';
import '../config/supabase_config.dart';
import '../services/storage_photo_service.dart';
import '../services/avatar_service.dart';
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

  /// Email sudah terverifikasi? (null = anonymous / belum terverifikasi)
  bool get emailConfirmed =>
      _sb.auth.currentUser?.emailConfirmedAt != null;

  /// Sign in dengan Google via Supabase OAuth.
  /// Native google_sign_in — butuh Android OAuth client (keystore v2)
  /// dan Web client untuk serverClientId.
  /// Return AuthResponse + email Google yang digunakan.
  Future<({AuthResponse response, String? googleEmail})?>
  signInWithGoogle() async {
    const webClientId =
        '688425181671-r38u670b2l6l5fvnionlcl5fu020h72n.apps.googleusercontent.com';

    final googleSignIn = GoogleSignIn(serverClientId: webClientId);
    // google_sign_in: user batal → signIn() mengembalikan null (tidak
    // melempar). Null dikembalikan ke atas supaya UI diam-diam kembali
    // tanpa snackbar error.
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleEmail = googleUser.email;
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) throw Exception('Google idToken null');

    final response = await _sb.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );

    // Simpan email ke profile jika belum ada
    final id = _sb.auth.currentUser?.id;
    if (id != null) {
      try {
        await _sb.from('profiles').update({'email': googleEmail}).eq('id', id);
      } catch (e) {
        debugPrint('[AUTH] signInWithGoogle email update error: $e');
      }
    }

    return (response: response, googleEmail: googleEmail);
  }

  /// Cek apakah email sudah terdaftar di akun lain.
  Future<Map<String, dynamic>?> checkEmailExists(String email) async {
    try {
      final res = await _sb.rpc(
        'check_email_exists',
        params: {'p_email': email},
      );
      if (res == null) return null;
      final map = Map<String, dynamic>.from(res as Map);
      return map['exists'] == true ? map : null;
    } catch (e) {
      debugPrint('[AUTH] checkEmailExists error: $e');
      return null;
    }
  }

  /// Pindahkan profile dari akun lama ke akun Google baru.
  /// Ini "partial linking" — profile lama (nickname, avatar, dll) dipindah ke uid Google.
  Future<void> linkGoogleProfile(String oldProfileId) async {
    final newId = uid;
    if (newId == null) return;
    try {
      // Copy profile lama ke uid baru.
      // Exclude ip_address & fcm_token — kolom ini di-revoke dari akses
      // publik (hardening), dan tidak boleh ditimpa saat link akun.
      const cols =
          'id,nickname,gender,age,country,city,status,avatar,is_registered,hashtags,points';
      final old = await _sb
          .from('profiles')
          .select(cols)
          .eq('id', oldProfileId)
          .maybeSingle();
      if (old == null) return;

      // Upsert profile lama ke uid baru
      await _sb.from('profiles').upsert({
        ...old,
        'id': newId,
        'email': _sb.auth.currentUser?.email,
      });

      debugPrint('[AUTH] linkGoogleProfile: linked $oldProfileId -> $newId');
    } catch (e) {
      debugPrint('[AUTH] linkGoogleProfile error: $e');
    }
  }

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
      await _sb.rpc(
        'cleanup_stale_anonymous',
        params: {'min_age_days': minAgeDays},
      );
    } catch (e) {
      debugPrint('[AUTH] cleanupStaleAnonymous error (abaikan): $e');
    }
  }

  /// Bersihkan presence room yang basi (> 10 menit) di server — row yang
  /// ditinggalkan app yang di-kill/force-stop tanpa sempat leaveRoom.
  /// Fire-and-forget dari app saat start.
  Future<void> cleanupStalePresence({int minAgeMinutes = 10}) async {
    try {
      await _sb.rpc(
        'cleanup_stale_presence',
        params: {'min_age_minutes': minAgeMinutes},
      );
    } catch (e) {
      debugPrint('[AUTH] cleanupStalePresence error (abaikan): $e');
    }
  }

  /// Ambil setting admin global: apakah screenshot aplikasi diizinkan.
  /// Default true (bisa screenshot) jika gagal / belum ada data.
  Future<bool> fetchScreenshotEnabled() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('screenshot_enabled')
          .eq('id', 'global')
          .maybeSingle();
      return res?['screenshot_enabled'] == true;
    } catch (e) {
      debugPrint('[AUTH] fetchScreenshotEnabled error: $e');
      return true;
    }
  }

  /// Update setting admin global. RLS membatasi hanya email admin (zunixe@gmail.com).
  Future<void> updateScreenshotEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'screenshot_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Ambil setting admin global: apakah foto view-once di-watermark forensik.
  /// Default false (kirim biasa) jika gagal / belum ada data.
  Future<bool> fetchWatermarkEnabled() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('watermark_enabled')
          .eq('id', 'global')
          .maybeSingle();
      return res?['watermark_enabled'] == true;
    } catch (e) {
      debugPrint('[AUTH] fetchWatermarkEnabled error: $e');
      return false;
    }
  }

  /// Update setting admin global. RLS membatasi hanya email admin (zunixe@gmail.com).
  Future<void> updateWatermarkEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'watermark_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Ambil setting admin: invisible (admin tidak muncul di daftar online).
  /// Return Map {'enabled': bool, 'adminUid': String?}.
  Future<Map<String, dynamic>> fetchInvisibleSetting() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('invisible_enabled,invisible_admin_uid')
          .eq('id', 'global')
          .maybeSingle();
      return {
        'enabled': res?['invisible_enabled'] == true,
        'adminUid': res?['invisible_admin_uid'] as String?,
      };
    } catch (e) {
      debugPrint('[AUTH] fetchInvisibleSetting error: $e');
      return {'enabled': false, 'adminUid': null};
    }
  }

  /// Update setting admin invisible. RLS membatasi hanya admin.
  /// Saat enabled=true, simpan UID admin supaya trigger server bisa
  /// memaksa status 'invisible' pada user itu.
  Future<void> updateInvisibleEnabled(bool enabled) async {
    final myUid = uid;
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'invisible_enabled': enabled,
      'invisible_admin_uid': enabled ? myUid : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Ambil setting admin global: apakah wajib registrasi sebelum masuk.
  /// Default false (bisa mulai chat tanpa daftar) jika gagal / belum ada data.
  Future<bool> fetchRequireRegistration() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('require_registration')
          .eq('id', 'global')
          .maybeSingle();
      return res?['require_registration'] == true;
    } catch (e) {
      debugPrint('[AUTH] fetchRequireRegistration error: $e');
      return false;
    }
  }

  /// Update setting admin global. RLS membatasi hanya admin.
  Future<void> updateRequireRegistration(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'require_registration': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Stream perubahan setting app_settings (realtime) — dipakai AuthProvider
  /// supaya toggle admin langsung berdampak di semua device tanpa polling.
  Stream<Map<String, dynamic>> onAppSettingsUpdated() {
    final channel = _sb.channel('auth-app-settings');
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'app_settings',
      callback: (payload) {
        controller.add(Map<String, dynamic>.from(payload.newRecord));
      },
    );
    channel.subscribe();
    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }

  /// Login dengan email + password.
  /// Setelah ini, getProfile() akan mengembalikan profile user.
  Future<void> signInWithEmail(String email, String password) async {
    final res = await _sb.auth.signInWithPassword(
      email: email,
      password: password,
    );
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
    } catch (e) {
      debugPrint('[AUTH] markRegistered error: $e');
    }
  }

  /// Cek apakah email sudah terdaftar di Auth (RPC security definer).
  /// Kalau RPC belum dibuat di DB, fallback ke [fallback]
  /// (reset: true = lanjut kirim seperti lama; signup: false = lanjut daftar).
  Future<bool> checkEmailRegistered(
    String email, {
    bool fallback = true,
  }) async {
    try {
      final res = await _sb.rpc(
        'check_email_registered',
        params: {'p_email': email},
      );
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

  /// Kirim ulang kode verifikasi (OTP) ke email — untuk user belum terverifikasi.
  Future<void> resendEmailOtp(String email) async {
    await _sb.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: 'chatyuk://login-callback',
    );
  }

  /// Verifikasi kode OTP 6 digit. Return true bila sukses.
  Future<bool> verifyEmailOtp(String email, String token) async {
    try {
      // type harus SAMA dengan yang dipakai resend (OtpType.signup) —
      // kalau beda (mis. 'email'), server menolak kode yang valid.
      await _sb.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.signup,
      );
      return true;
    } catch (e) {
      debugPrint('[AUTH] verifyEmailOtp error: $e');
      return false;
    }
  }
  /// Ikat diri sendiri ke referrer (sekali). Return {ok}.
  Future<bool> bindReferrer(String referrerUid) async {
    try {
      final res = await _sb.rpc('bind_referrer', params: {'p_referrer': referrerUid});
      return res is Map && res['ok'] == true;
    } catch (e) {
      debugPrint('[AUTH] bindReferrer error: $e');
      return false;
    }
  }  /// Kirim email reset password.
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

  /// Akun punya password? Akun Google (sign-in via Google) tidak punya
  /// password — user harus "set password" dulu sebelum bisa ganti.
  bool get hasPassword =>
      currentUser?.appMetadata['provider'] != 'google';

  /// Set password baru (untuk akun Google yang belum punya password).
  Future<void> setPassword(String newPassword) async {
    await _sb.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Ganti password: verifikasi password lama dulu, lalu update.
  /// Lempar error bila password lama salah.
  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final email = userEmail;
    if (email == null || email.isEmpty) {
      throw Exception('No email on account');
    }
    await _sb.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    await _sb.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Cek apakah nickname sudah dipakai oleh user lain.
  Future<bool> isNicknameAvailable(String nickname) async {
    final id = uid;
    var query = _sb.from('profiles').select('id').eq('nickname', nickname);
    if (id != null) query = query.neq('id', id);
    final res = await query.maybeSingle();
    return res == null; // null = tidak ada yang pakai
  }

  /// Ambil alih nickname milik akun anon yang tidak aktif > 7 hari
  /// (dummy yang di-uninstall tidak terhapus di server).
  Future<bool> claimNickname(String nickname) async {
    final res = await _sb.rpc('claim_nickname', params: {'p_nickname': nickname});
    return res == true;
  }

  Future<UserModel> registerProfile({
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
    String ipAddress =
        '', // disimpan di server saja, tidak disimpan di aplikasi
  }) async {
    // Kalau session hilang (misal habis logout Google), buat session
    // anonymous baru supaya user baru tetap bisa daftar.
    var user = _sb.auth.currentUser;
    if (user == null) {
      debugPrint('[AUTH] registerProfile: no session, signInAnonymously first');
      try {
        final res = await _sb.auth.signInAnonymously();
        user = res.user;
      } catch (e) {
        debugPrint('[AUTH] registerProfile: signInAnonymously error: $e');
        throw Exception('registerProfile: no authenticated user');
      }
    }
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
    // Exclude fcm_token dan ip_address — tidak dibutuhkan di model
    const cols =
        'id,nickname,gender,age,country,city,status,avatar,is_registered,login_at,created_at,last_seen,hashtags,points,share_location,followers_count,following_count,subscriber_count,subscription_price,friends_count';
    final res = await _sb
        .from('profiles')
        .select(cols)
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    final model = UserModel.fromMap(id, snakeToCamel(res));
    // avatar berupa PATH storage → download → isi base64 (UI tetap pakai base64).
    // Pakai AvatarB64Service yang punya cache per path — getProfile dipanggil
    // sering (startup, sign-in, reload) tanpa download berulang.
    if (model.avatar.isNotEmpty &&
        StoragePhotoService.instance.isAvatarPath(model.avatar)) {
      final b64 = await AvatarB64Service.instance.getByPath(model.avatar);
      return model.copyWith(avatar: b64);
    }
    return model;
  }

  /// Ambil profil user lain (untuk halaman info pengguna).
  Future<UserModel?> getProfileById(String id) async {
    if (id.isEmpty) return null;
    const cols =
        'id,nickname,gender,age,country,city,status,avatar,is_registered,login_at,created_at,last_seen,hashtags,points,share_location,followers_count,following_count,subscriber_count,subscription_price,friends_count';
    final res = await _sb
        .from('profiles')
        .select(cols)
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    final model = UserModel.fromMap(id, snakeToCamel(res));
    if (model.avatar.isNotEmpty &&
        StoragePhotoService.instance.isAvatarPath(model.avatar)) {
      final b64 = await AvatarB64Service.instance.getByPath(model.avatar);
      return model.copyWith(avatar: b64);
    }
    return model;
  }

  /// Stream realtime profil sendiri — poin, status, email terdaftar, dll.
  /// Dipakai AuthProvider untuk update badge di seluruh app tanpa reload.
  Stream<UserModel> onMyProfileUpdates() {
    final id = uid;
    if (id == null) return const Stream.empty();
    final controller = StreamController<UserModel>.broadcast();

    final channel = _sb.channel('my-profile-$id');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'profiles',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: id,
      ),
      callback: (payload) async {
        if (controller.isClosed) return;
        try {
          final row = payload.newRecord;
          var model = UserModel.fromMap(id, snakeToCamel(row));
          // avatar PATH storage → download → base64 (UI tetap pakai base64).
          // Pakai cache supaya update profil tidak download avatar berulang.
          if (model.avatar.isNotEmpty &&
              StoragePhotoService.instance.isAvatarPath(model.avatar)) {
            final b64 = await AvatarB64Service.instance.getByPath(model.avatar);
            model = model.copyWith(avatar: b64);
          }
          controller.add(model);
        } catch (e) {
          debugPrint('[AuthService] onMyProfileUpdates ignored: $e');
        }
      },
    );
    channel.subscribe();

    controller.onCancel = () {
      _sb.removeChannel(channel);
    };
    return controller.stream;
  }

  Future<void> updateHashtags(List<String> hashtags) async {
    final id = uid;
    if (id == null) return;
    await _sb.from('profiles').update({'hashtags': hashtags}).eq('id', id);
  }

  Future<void> updateProfile({
    int? age,
    String? country,
    String? city,
    String? nickname,
  }) async {
    final id = uid;
    if (id == null) return;
    final data = <String, dynamic>{
      if (age != null) 'age': age,
      if (country != null) 'country': country,
      if (city != null) 'city': city,
      if (nickname != null) 'nickname': nickname,
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
    // Upload ke Storage — DB hanya simpan path (hemat ruang).
    final path = base64.isEmpty
        ? ''
        : await StoragePhotoService.instance.uploadAvatar(
                uid: id,
                base64: base64,
              ) ??
              '';
    await _sb.from('profiles').update({'avatar': path}).eq('id', id);
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
      await _sb
          .from('profiles')
          .update({
            'status': 'offline',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      debugPrint('[AUTH] goOffline error: $e');
    }
  }

  /// Admin invisible — status khusus 'invisible' di DB. User lain melihatnya
  /// offline (via effectiveStatusOf) & tidak muncul di daftar online.
  Future<void> goInvisible() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb
          .from('profiles')
          .update({
            'status': 'invisible',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      debugPrint('[AUTH] goInvisible error: $e');
    }
  }

  Future<void> goIdle() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb
          .from('profiles')
          .update({
            'status': 'idle',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      debugPrint('[AUTH] goIdle error: $e');
    }
  }

  Future<void> goOnline() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb
          .from('profiles')
          .update({
            'status': 'online',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      debugPrint('[AUTH] goOnline error: $e');
    }
  }

  /// Heartbeat: update last_seen tanpa mengubah status.
  /// Dipanggil berkala supaya kalau app di-kill, last_seen jadi basi
  /// dan bisa dideteksi sebagai offline.
  Future<void> updateLastSeen() async {
    final id = uid;
    if (id == null) return;
    try {
      await _sb
          .from('profiles')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id);
    } catch (e) {
      debugPrint('[AUTH] updateLastSeen error: $e');
    }
  }

  /// Ambil semua foto galeri milik satu user.
  Future<List<UserPhoto>> getPhotos(String userId) async {
    if (userId.isEmpty) return [];
    final rows = await _sb
        .from('user_photos')
        .select('id,user_id,photo,created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    final result = <UserPhoto>[];
    for (final row in rows) {
      var photo = row['photo'] as String? ?? '';
      // photo bisa berupa PATH storage (foto baru) → download → base64.
      if (photo.isNotEmpty &&
          StoragePhotoService.instance.isGalleryPath(photo)) {
        photo = await StoragePhotoService.instance.download(photo) ?? '';
      }
      result.add(
        UserPhoto.fromMap('${row['id']}', {
          'userId': row['user_id'],
          'photo': photo,
          'createdAt': row['created_at'],
        }),
      );
    }
    return result;
  }

  /// Ambil foto galeri user LAIN dengan kontrol akses paywall.
  /// Index 0 gratis; sisanya terkunci (kirim preview blur) sampai dibuka.
  /// Foto terbuka: field photo = path/base64 asli. Terkunci: photo = preview.
  Future<List<UserPhoto>> getPhotosWithAccess(String userId) async {
    if (userId.isEmpty) return [];
    final res = await _sb.rpc(
      'get_user_photos_access',
      params: {'p_user_id': userId},
    );
    final list = res is List ? res : <dynamic>[];
    final result = <UserPhoto>[];
    for (final row in list) {
      final m = Map<String, dynamic>.from(row as Map);
      final unlocked = m['unlocked'] == true;
      var photo = m['photo'] as String? ?? '';
      // Foto terbuka bisa berupa PATH storage → download jadi base64.
      // Foto terkunci = preview base64 (bukan path) → pakai apa adanya.
      if (unlocked &&
          photo.isNotEmpty &&
          StoragePhotoService.instance.isGalleryPath(photo)) {
        photo = await StoragePhotoService.instance.download(photo) ?? '';
      }
      result.add(
        UserPhoto.fromMap('${m['id']}', {
          'userId': userId,
          'photo': photo,
          'unlocked': unlocked,
          'preview': m['preview'] ?? '',
          'createdAt': m['created_at'],
        }),
      );
    }
    return result;
  }

  /// Upload foto galeri milik sendiri. Max 6 foto per user.
  Future<void> uploadPhoto(String base64, {String? preview}) async {
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
    final rows = await _sb.from('user_photos').select('id').eq('user_id', id);
    if (rows.length >= 6) {
      throw Exception('Max 6 photos');
    }
    // Upload ke Storage — DB hanya simpan path (hemat ruang).
    final path =
        await StoragePhotoService.instance.uploadPhoto(
          uid: id,
          base64: base64,
        ) ??
        base64;
    await _sb.from('user_photos').insert({
      'user_id': id,
      'photo': path,
      if (preview != null && preview.isNotEmpty) 'photo_preview': preview,
    });
  }

  /// Hapus foto galeri (hanya punya sendiri, RLS menjamin).
  Future<void> deletePhoto(String photoId) async {
    if (photoId.isEmpty) return;
    try {
      final row = await _sb
          .from('user_photos')
          .select('photo')
          .eq('id', photoId)
          .maybeSingle();
      final photo = row?['photo'] as String? ?? '';
      if (photo.isNotEmpty &&
          StoragePhotoService.instance.isGalleryPath(photo)) {
        await StoragePhotoService.instance.delete(photo);
      }
    } catch (_) {}
    await _sb.from('user_photos').delete().eq('id', photoId);
  }

  Future<void> signOut() async {
    _dummySessionActive = false;
    _dummyUid = null;
    await _clearAdminTokens();
    try {
      // Teardown total realtime: cegah socket/channel lama nyangkut saat
      // login ulang di proses yang sama (race disconnect/connect di
      // realtime_client bisa bikin socket mati permanen).
      await _sb.realtime.removeAllChannels();
      await _sb.realtime.disconnect();
    } catch (e) {
      debugPrint('[AuthService] realtime teardown error: $e');
    }
    await _sb.auth.signOut();
  }

  // ── Dummy session (admin berpindah akun tanpa login manual) ──
  String? _adminAccessToken;
  String? _adminRefreshToken;
  String? _dummyUid;
  bool _dummySessionActive = false;
  static const _kAdminAccessToken = 'dummy_admin_access_token';
  static const _kAdminRefreshToken = 'dummy_admin_refresh_token';

  /// True saat sesi aktif adalah akun dummy (bukan admin).
  bool get dummySessionActive => _dummySessionActive;

  /// UID dummy yang sedang aktif (null jika bukan sesi dummy).
  String? get activeDummyUid => _dummyUid;

  Future<void> _saveAdminTokens(
    String? accessToken,
    String? refreshToken,
  ) async {
    if (accessToken == null || refreshToken == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAdminAccessToken, accessToken);
    await prefs.setString(_kAdminRefreshToken, refreshToken);
  }

  Future<void> _clearAdminTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAdminAccessToken);
    await prefs.remove(_kAdminRefreshToken);
  }

  /// Pulihkan state dummy setelah app restart: sesi aktif anonymous milik
  /// dummy → restore flag + token admin dari SharedPreferences.
  Future<void> restoreDummyIfNeeded() async {
    final user = _sb.auth.currentUser;
    if (user == null || !user.isAnonymous) return;
    final uid = user.id;
    try {
      final isDummy =
          await _sb.rpc('is_dummy_account', params: {'p_uid': uid}) as bool? ??
          false;
      if (!isDummy) return;
    } catch (e) {
      debugPrint('[AUTH] restoreDummyIfNeeded check error: $e');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_kAdminRefreshToken);
    final access = prefs.getString(_kAdminAccessToken);
    if (refresh == null || refresh.isEmpty) return;
    _adminRefreshToken = refresh;
    _adminAccessToken = access;
    _dummyUid = uid;
    _dummySessionActive = true;
    debugPrint('[AUTH] dummy session restored: $uid');
  }

  /// Pindah ke akun dummy: tukar session ke refresh_token dummy
  /// (GoTrue memutar token tiap swap → simpan token baru di DB).
  /// Kembali ke admin via [backToAdmin].
  Future<void> becomeDummy(String uid) async {
    final session = _sb.auth.currentSession;
    _adminAccessToken = session?.accessToken;
    _adminRefreshToken = session?.refreshToken;
    _dummyUid = uid;
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
      // Token dummy mati/invalid → regenerasi lalu coba sekali lagi.
      debugPrint('[AUTH] becomeDummy setSession failed: $e — renewing');
      try {
        final renewed =
            await _sb.rpc('admin_renew_dummy_token', params: {'p_uid': uid})
                as String?;
        if (renewed != null && renewed.isNotEmpty) {
          await _sb.auth.setSession(renewed);
        } else {
          throw Exception('dummy_token_invalid');
        }
      } catch (e2) {
        // JANGAN biarkan sesi rusak (user jadi logout) — pulihkan admin.
        debugPrint('[AUTH] becomeDummy renew failed: $e2 — restoring admin');
        final a = _adminAccessToken;
        final r = _adminRefreshToken;
        _adminAccessToken = null;
        _adminRefreshToken = null;
        _dummyUid = null;
        _dummySessionActive = false;
        if (r != null && a != null) {
          try {
            await _sb.auth.setSession(r, accessToken: a);
          } catch (_) {}
        }
        await _clearAdminTokens();
        throw Exception('dummy_token_invalid');
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
        debugPrint('[AUTH] admin_update_dummy_token error: $e');
      }
    }
    _dummySessionActive =
        _adminAccessToken != null && _adminRefreshToken != null;
  }

  /// Kembali ke akun admin. Sesi dummy TIDAK di-logout dan statusnya
  /// TIDAK diubah — apa pun status dummy (online/idle/offline) yang di-set
  /// admin panel tetap dipertahankan. Hanya user aktif yang balik ke admin.
  /// Return false jika token admin kedaluwarsa (perlu login manual).
  Future<bool> backToAdmin() async {
    _dummySessionActive = false;
    var adminAccess = _adminAccessToken;
    var adminRefresh = _adminRefreshToken;
    _adminAccessToken = null;
    _adminRefreshToken = null;
    _dummyUid = null;
    if (adminAccess == null || adminRefresh == null) {
      final prefs = await SharedPreferences.getInstance();
      adminAccess = prefs.getString(_kAdminAccessToken);
      adminRefresh = prefs.getString(_kAdminRefreshToken);
    }
    if (adminRefresh == null || adminAccess == null) return false;
    try {
      await _sb.auth.setSession(adminRefresh, accessToken: adminAccess);
      await _clearAdminTokens();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ada token admin (dummy) tersimpan di SharedPreferences? Dipakai untuk
  /// recovery otomatis saat sesi dummy mati server-side.
  Future<bool> hasStoredAdminTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_kAdminRefreshToken);
    return refresh != null && refresh.isNotEmpty;
  }

  Stream<bool> get authState {
    return _sb.auth.onAuthStateChange.map((data) {
      final session = data.session;
      return session != null;
    });
  }

  /// Raw auth state changes (event + session) — dipakai untuk menunggu
  /// session selesai di-set setelah OAuth web flow redirect balik.
  Stream<AuthState> get authStateChanges => _sb.auth.onAuthStateChange;
}
