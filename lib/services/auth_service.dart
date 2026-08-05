import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  bool get isSignedIn => _auth.currentUser != null;

  Future<void> signInAnonymously() async {
    if (_auth.currentUser != null) return;
    await _auth.signInAnonymously();
  }

  Future<UserModel> registerProfile({
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
    String ipAddress = '',
  }) async {
    if (_auth.currentUser == null) {
      await signInAnonymously();
    }
    final user = _auth.currentUser!;
    final now = DateTime.now();
    final profile = UserModel(
      uid: user.uid,
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

    // Tulis ke Firestore — ini yang critical, perlu await
    await _db.collection('users').doc(user.uid).set({
      ...profile.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
      'loginAt': FieldValue.serverTimestamp(),
    });

    // Set presence di RTDB — jalankan di background, tidak perlu await
    final presenceRef = _rtdb.ref('presence/${user.uid}');
    presenceRef.set({
      'nickname': nickname,
      'gender': gender,
      'age': age,
      'country': country,
      'city': city,
      'status': 'online',
      'online': true,
      'lastSeen': ServerValue.timestamp,
    });
    presenceRef.onDisconnect().update({
      'status': 'offline',
      'online': false,
      'lastSeen': ServerValue.timestamp,
    });

    return profile;
  }

  Future<UserModel?> getProfile() async {
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(uid!, doc.data()!);
  }

  Future<void> updateAvatar(String base64) async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({'avatar': base64});
    await _rtdb.ref('presence/$uid').update({'avatar': base64});
  }

  Future<void> removeAvatar() async {
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({'avatar': ''});
    await _rtdb.ref('presence/$uid').update({'avatar': ''});
  }

  Future<void> updateFcmToken(String? token) async {
    if (uid == null) return;
    // fcmToken hanya di Firestore (owner-only read), TIDAK di RTDB publik
    await _db.collection('users').doc(uid!).update({'fcmToken': token ?? ''});
  }

  Future<void> goOffline() async {
    if (uid == null) return;
    // Fire-and-forget — tidak perlu await
    _rtdb.ref('presence/$uid').update({
      'status': 'offline',
      'online': false,
      'lastSeen': ServerValue.timestamp,
    });
  }

  Future<void> goIdle() async {
    if (uid == null) return;
    _rtdb.ref('presence/$uid').update({
      'status': 'idle',
      'online': true,
    });
  }

  Future<void> goOnline() async {
    if (uid == null) return;
    final ref = _rtdb.ref('presence/$uid');
    // Fire-and-forget — tidak perlu await
    ref.update({
      'status': 'online',
      'online': true,
      'lastSeen': ServerValue.timestamp,
    });
    ref.onDisconnect().update({
      'status': 'offline',
      'online': false,
      'lastSeen': ServerValue.timestamp,
    });
  }

  Future<void> signOut() async {
    await goOffline();
    await _auth.signOut();
    // Hapus cache lokal Firestore agar history chat tidak tampil
    // untuk user berikutnya di perangkat yang sama.
    // Data di server TIDAK dihapus.
    try {
      await _db.clearPersistence();
    } catch (_) {
      // listener masih aktif / platform tidak mendukung: abaikan,
      // query participants tetap memfilter history per user.
    }
  }

  Stream<bool> get authState => _auth.authStateChanges().map((u) => u != null);
}
