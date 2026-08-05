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

  AuthProvider() {
    print('[AUTH-PROVIDER] CONSTRUCTED $instanceId');
    _init();
  }

  Future<void> _init() async {
    print('[AUTH] _init start');
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      print('[AUTH] signInAnonymously...');
      await _auth.signInAnonymously();
      print('[AUTH] signInAnonymously OK');
      _profile = await _auth.getProfile();
      print('[AUTH] getProfile -> ${_profile?.uid}');
      if (_profile != null) await updateFcmToken();
    } catch (e) {
      print('[AUTH] _init ERROR: $e');
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
    print('[AUTH] _init done loading=false');
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
    print('[AUTH] registerProfile START: $nickname inst=$instanceId');
    _profile = await _auth.registerProfile(
      nickname: nickname,
      gender: gender,
      age: age,
      country: country,
      city: city,
      ipAddress: ipAddress,
    );
    print('[AUTH] registerProfile DONE: ${_profile?.uid} inst=$instanceId hasListeners=$hasListeners');
    notifyListeners();
    print('[AUTH] notifyListeners called, profile=${_profile?.uid} inst=$instanceId hasListeners=$hasListeners');
    resetIdleTimer();
    updateFcmToken();
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
