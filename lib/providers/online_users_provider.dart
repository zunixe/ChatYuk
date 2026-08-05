import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';

class OnlineUsersProvider extends ChangeNotifier {
  final ChatService _service = ChatService();
  List<UserModel> _users = [];
  StreamSubscription? _sub;
  String? _error;

  List<UserModel> get users => _users;
  String? get error => _error;

  OnlineUsersProvider() {
    _sub = _service.getOnlineUsers().listen((users) {
      _users = users;
      _error = null;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[OnlineUsersProvider] stream error: $e');
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
