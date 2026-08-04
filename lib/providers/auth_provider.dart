import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
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

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _auth.signInAnonymously();
      _profile = await _auth.getProfile();
      if (_profile != null) await updateFcmToken();
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
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

  Future<void> registerProfile({
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
    String ipAddress = '',
  }) async {
    _profile = await _auth.registerProfile(
      nickname: nickname,
      gender: gender,
      age: age,
      country: country,
      city: city,
      ipAddress: ipAddress,
    );
    // Daftarkan FCM token supaya user BARU langsung dapat notifikasi
    await updateFcmToken();
    notifyListeners();
    resetIdleTimer();
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
