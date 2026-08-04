import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';

class OnlineUsersProvider extends ChangeNotifier {
  final ChatService _service = ChatService();
  List<UserModel> _users = [];

  List<UserModel> get users => _users;

  OnlineUsersProvider() {
    _service.getOnlineUsers().listen((users) {
      _users = users;
      notifyListeners();
    }, onError: (_) {
      // belum login / auth hilang: abaikan, akan tersambung lagi setelah login
    });
  }
}
