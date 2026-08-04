import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';

class ChatProvider extends ChangeNotifier {
  final ChatService _service = ChatService();
  List<String> _blockedUids = [];

  // Stream cache — mencegah StreamBuilder resubscribe setiap build
  // Pakai ShareReplay-like pattern: stream di-share tapi tidak di-close saat 0 subscriber
  final _roomMsgCache = <String, Stream<List<MessageModel>>>{};
  final _privateMsgCache = <String, Stream<List<MessageModel>>>{};
  final _privateChatsCache = <String, Stream<List<PrivateChatInfo>>>{};
  final _roomUsersCache = <String, Stream<List<UserModel>>>{};

  List<String> get blockedUids => _blockedUids;

  // Room chat
  Stream<List<MessageModel>> getRoomMessages(String roomId) {
    return _roomMsgCache.putIfAbsent(roomId, () => _service.getRoomMessages(roomId));
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
    String myGender = '',
    String otherGender = '',
    String myCountry = '',
    String otherCountry = '',
    int myAge = 0,
    int otherAge = 0,
  }) async {
    return _service.startPrivateChat(
      myUid: myUid,
      otherUid: otherUid,
      myName: myName,
      otherName: otherName,
      myGender: myGender,
      otherGender: otherGender,
      myCountry: myCountry,
      otherCountry: otherCountry,
      myAge: myAge,
      otherAge: otherAge,
    );
  }

  Stream<List<MessageModel>> getPrivateChatMessages(String chatId) {
    return _privateMsgCache.putIfAbsent(chatId, () => _service.getPrivateChatMessages(chatId));
  }

  Future<void> sendPrivateMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
    String type = 'text',
    String imageData = '',
    String receiverId = '',
  }) async {
    await _service.sendPrivateMessage(
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      text: text,
      type: type,
      imageData: imageData,
      receiverId: receiverId,
    );
  }

  Future<void> markAsRead(String chatId, String uid) async {
    await _service.markAsRead(chatId, uid);
  }

  Stream<List<PrivateChatInfo>> getMyPrivateChats(String myUid) {
    return _privateChatsCache.putIfAbsent(myUid, () => _service.getMyPrivateChats(myUid));
  }

  // Online users
  Stream<List<UserModel>> getOnlineUsersInRoom(String roomId) {
    return _roomUsersCache.putIfAbsent(roomId, () => _service.getOnlineUsersInRoom(roomId));
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
    _roomMsgCache.clear();
    _privateMsgCache.clear();
    _privateChatsCache.clear();
    _roomUsersCache.clear();
    notifyListeners();
  }
}
