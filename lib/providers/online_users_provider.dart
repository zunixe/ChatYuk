import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../services/message_cache.dart';

bool _usersEqual(List<UserModel> a, List<UserModel> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].uid != b[i].uid ||
        a[i].status != b[i].status ||
        a[i].lastSeen != b[i].lastSeen ||
        a[i].avatar != b[i].avatar)
      return false;
  }
  return true;
}

class OnlineUsersProvider extends ChangeNotifier {
  final ChatService _service = ChatService();
  List<UserModel> _users = [];
  StreamSubscription? _sub;
  String? _error;
  bool _loaded = false;

  List<UserModel> get users => _users;
  String? get error => _error;
  bool get hasLoaded => _loaded;

  OnlineUsersProvider() {
    // Cold start: tampilkan cache disk dulu (<50ms) sebelum fetch network
    MessageCache.instance.loadRawList('online_users').then((cached) {
      if (cached.isNotEmpty && _users.isEmpty) {
        try {
          _users = cached.map((e) => UserModel.fromMap('${e['uid'] ?? e['id'] ?? ''}', Map<String, dynamic>.from(e))).toList();
          _loaded = true;
          notifyListeners();
        } catch (_) {}
      }
    });
    _sub = _service.getOnlineUsers().listen(
      (users) {
        _loaded = true;
        // Dedupe by uid — pertahanan kedua terhadap duplikat dari stream.
        final seen = <String>{};
        final deduped = users.where((u) => seen.add(u.uid)).toList();
        if (_usersEqual(_users, deduped)) return;
        _users = deduped;
        _error = null;
        notifyListeners();
        // Simpan ke disk untuk cold start berikutnya (tanpa avatar base64 biar kecil)
        if (deduped.isNotEmpty) {
          final rows = deduped.map((u) => {'uid': u.uid, ...u.toMap(), 'avatar': ''}).toList();
          MessageCache.instance.saveRawList('online_users', rows);
        }
      },
      onError: (e) {
        debugPrint('[OnlineUsersProvider] stream error: $e');
        _loaded = true;
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  void updateAvatarForUid(String uid, String base64) {
    final idx = _users.indexWhere((u) => u.uid == uid);
    if (idx >= 0 && _users[idx].avatar != base64) {
      _users[idx] = _users[idx].copyWith(avatar: base64);
      notifyListeners();
    }
  }

  void removeAvatarForUid(String uid) {
    final idx = _users.indexWhere((u) => u.uid == uid);
    if (idx >= 0 && _users[idx].avatar.isNotEmpty) {
      _users[idx] = _users[idx].copyWith(avatar: '');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
