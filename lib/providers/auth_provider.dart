import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final String instanceId = 'AP-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}';
  UserModel? _profile;
  bool _loading = true;

  String? _error;

  Timer? _idleTimer;
  bool _isIdle = false;
  static const Duration idleTimeout = Duration(minutes: 3);

  UserModel? get profile => _profile;
  bool get loading => _loading;
  String? get error => _error;
  bool get isSignedIn => _auth.isSignedIn;
  String? get uid => _auth.uid;
  bool get isAnonymous => _auth.isAnonymous;
  String? get userEmail => _auth.userEmail;

  AuthProvider() {
    debugPrint('[AUTH-PROVIDER] CONSTRUCTED $instanceId');
    _init();
  }

  Future<void> _init() async {
    debugPrint('[AUTH] _init start');
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      debugPrint('[AUTH] signInAnonymously...');
      await _auth.signInAnonymously();
      debugPrint('[AUTH] signInAnonymously OK');
      _profile = await _auth.getProfile();
      debugPrint('[AUTH] getProfile -> ${_profile?.uid}');
      if (_profile != null) await updateFcmToken();
    } catch (e) {
      debugPrint('[AUTH] _init ERROR: $e');
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
    debugPrint('[AUTH] _init done loading=false');
  }

  Future<void> updateFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      await _auth.updateFcmToken(token);
    } catch (_) {
      // token tidak tersedia: abaikan
    }
  }

  Future<void> retry() => _init();

  /// Sign up dengan email — membuat akun Supabase baru.
  /// Setelah ini user perlu verifikasi email, lalu registerProfile().
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
  }) async {
    await _auth.signUpWithEmail(email, password);
    // Profile akan di-save setelah verifikasi email + login
  }

  /// Login dengan email + password.
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmail(email, password);
    _profile = await _auth.getProfile();
    if (_profile != null) await updateFcmToken();
    notifyListeners();
  }

  /// Upgrade anonymous account ke email account. UID tetap sama.
  Future<void> linkEmailToAccount(String email, String password) async {
    await _auth.linkEmailToAccount(email, password);
    notifyListeners();
  }

  /// Kirim email reset password.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email);
  }

  /// Set password baru setelah recovery. Logout otomatis agar login ulang.
  Future<void> resetPassword(String newPassword) async {
    _idleTimer?.cancel();
    _isIdle = false;
    await _auth.resetPassword(newPassword);
    _profile = null;
    notifyListeners();
  }

  /// Cek apakah nickname tersedia.
  Future<bool> isNicknameAvailable(String nickname) {
    return _auth.isNicknameAvailable(nickname);
  }

  Future<void> registerProfile({
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
    String ipAddress = '',
  }) async {
    debugPrint('[AUTH] registerProfile START: $nickname inst=$instanceId');
    _profile = await _auth.registerProfile(
      nickname: nickname,
      gender: gender,
      age: age,
      country: country,
      city: city,
      ipAddress: ipAddress,
    );
    debugPrint('[AUTH] registerProfile DONE: ${_profile?.uid} inst=$instanceId hasListeners=$hasListeners');
    notifyListeners();
    debugPrint('[AUTH] notifyListeners called, profile=${_profile?.uid} inst=$instanceId hasListeners=$hasListeners');
    resetIdleTimer();
    updateFcmToken();
  }

  Future<void> updateProfile({int? age, String? country, String? city}) async {
    await _auth.updateProfile(age: age, country: country, city: city);
    _profile = _profile?.copyWith(
      age: age ?? _profile?.age,
      country: country ?? _profile?.country,
      city: city ?? _profile?.city,
    );
    notifyListeners();
  }

  Future<void> updateAvatar(String base64) async {
    await _auth.updateAvatar(base64);
    _profile = _profile?.copyWith(avatar: base64);
    notifyListeners();
  }

  Future<void> removeAvatar() async {
    await _auth.removeAvatar();
    _profile = _profile?.copyWith(avatar: '');
    notifyListeners();
  }

  Future<void> signOut() async {
    _idleTimer?.cancel();
    _isIdle = false;
    await _auth.goOffline(); // set status offline di DB sebelum sign out
    await _auth.signOut();
    _profile = null;
    notifyListeners();
  }

  /// Call on any user interaction (tap, scroll, typing...).
  /// If user was idle, go back online. Resets the idle countdown.
  void notifyActivity() {
    if (_idleTimer == null) return; // not signed in yet
    if (_isIdle) {
      _isIdle = false;
      _auth.goOnline();
      _profile = _profile?.copyWith(status: 'online');
      notifyListeners();
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _becomeIdle);
  }

  void resetIdleTimer() {
    _isIdle = false;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _becomeIdle);
  }

  Future<void> _becomeIdle() async {
    _isIdle = true;
    await _auth.goIdle();
    _profile = _profile?.copyWith(status: 'idle');
    notifyListeners();
  }

  Future<void> goOnline() async {
    await _auth.goOnline();
    _profile = _profile?.copyWith(status: 'online');
    notifyListeners();
    resetIdleTimer();
  }

  Future<void> goOffline() async {
    _idleTimer?.cancel();
    _isIdle = false;
    await _auth.goOffline();
    _profile = _profile?.copyWith(status: 'offline');
    notifyListeners();
  }
}
