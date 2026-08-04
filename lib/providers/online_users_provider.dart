import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';

class OnlineUsersProvider extends ChangeNotifier {
  final ChatService _service = ChatService();
  List<UserModel> _users = [];
  StreamSubscription? _sub;

  List<UserModel> get users => _users;

  OnlineUsersProvider() {
    _sub = _service.getOnlineUsers().listen((users) {
      _users = users;
      notifyListeners();
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
