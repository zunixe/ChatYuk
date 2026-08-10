import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';

bool _usersEqual(List<UserModel> a, List<UserModel> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].uid != b[i].uid || a[i].status != b[i].status || a[i].lastSeen != b[i].lastSeen) return false;
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
    _sub = _service.getOnlineUsers().listen((users) {
      _loaded = true;
      if (_usersEqual(_users, users)) return;
      _users = users;
      _error = null;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[OnlineUsersProvider] stream error: $e');
      _loaded = true;
      _error = e.toString();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
