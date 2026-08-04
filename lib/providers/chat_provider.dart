import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';

class ChatProvider extends ChangeNotifier {
  final ChatService _service = ChatService();
  List<String> _blockedUids = [];

  List<String> get blockedUids => _blockedUids;

  // Room chat
  Stream<List<MessageModel>> getRoomMessages(String roomId) {
    return _service.getRoomMessages(roomId);
  }

  Future<void> sendRoomMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
  }) async {
    await _service.sendRoomMessage(
      roomId: roomId,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      text: text,
    );
  }

  // Private chat
  Future<String> startPrivateChat({
    required String myUid,
    required String otherUid,
    required String myName,
    required String otherName,
  }) async {
    return _service.startPrivateChat(
      myUid: myUid,
      otherUid: otherUid,
      myName: myName,
      otherName: otherName,
    );
  }

  Stream<List<MessageModel>> getPrivateChatMessages(String chatId) {
    return _service.getPrivateChatMessages(chatId);
  }

  Future<void> sendPrivateMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
    String type = 'text',
    String imageData = '',
  }) async {
    await _service.sendPrivateMessage(
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      text: text,
      type: type,
      imageData: imageData,
    );
  }

  Stream<List<PrivateChatInfo>> getMyPrivateChats(String myUid) {
    return _service.getMyPrivateChats(myUid);
  }

  // Online users
  Stream<List<UserModel>> getOnlineUsersInRoom(String roomId) {
    return _service.getOnlineUsersInRoom(roomId);
  }

  Future<void> joinRoom(String roomId, UserModel user) async {
    await _service.joinRoom(roomId, user);
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    await _service.leaveRoom(roomId, uid);
  }

  // Block / Report
  Future<void> blockUser(String myUid, String otherUid) async {
    await _service.blockUser(myUid, otherUid);
    await loadBlockedUids(myUid);
  }

  Future<void> reportUser({
    required String reporterId,
    required String reportedId,
    required String reason,
  }) async {
    await _service.reportUser(
      reporterId: reporterId,
      reportedId: reportedId,
      reason: reason,
    );
  }

  Future<void> loadBlockedUids(String myUid) async {
    _blockedUids = await _service.getBlockedUids(myUid);
    notifyListeners();
  }

  bool isBlocked(String uid) => _blockedUids.contains(uid);

  void reset() {
    _blockedUids = [];
    notifyListeners();
  }
}
