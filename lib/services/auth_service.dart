import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../config/supabase_config.dart';
import '../utils.dart';

class AuthService {
  final SupabaseClient _sb = SupabaseConfig.client;

  User? get currentUser => _sb.auth.currentUser;
  String? get uid => _sb.auth.currentUser?.id;
  bool get isSignedIn => _sb.auth.currentUser != null;

  Future<void> signInAnonymously() async {
    if (_sb.auth.currentUser != null) return;
    final res = await _sb.auth.signInAnonymously();
    print('[AUTH] signInAnonymously -> ${res.user?.id}');
  }

  Future<UserModel> registerProfile({
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
    String ipAddress = '',
  }) async {
    if (_sb.auth.currentUser == null) {
      await signInAnonymously();
    }
    final user = _sb.auth.currentUser!;
    final now = DateTime.now().toUtc();
    final profile = UserModel(
      uid: user.id,
      nickname: nickname,
      gender: gender,
      age: age,
      country: country,
      city: city,
      ipAddress: ipAddress,
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
      'ip_address': ipAddress,
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
    final res = await _sb.from('profiles').select().eq('id', id).maybeSingle();
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

  Future<void> updateAvatar(String base64) async {
    final id = uid;
    if (id == null) return;
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
