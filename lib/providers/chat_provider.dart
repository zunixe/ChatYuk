import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../services/message_cache.dart';

class ChatProvider extends ChangeNotifier {
  final ChatService _service = ChatService();
  List<String> _blockedUids = [];

  // Stream cache untuk private chats — mencegah StreamBuilder resubscribe setiap build
  final _roomMsgCache = <String, Stream<List<MessageModel>>>{};
  final _privateChatsCache = <String, Stream<List<PrivateChatInfo>>>{};
  final _roomUsersCache = <String, Stream<List<UserModel>>>{};

  List<String> get blockedUids => _blockedUids;

  // Room chat — TIDAK di-cache karena stream mati saat RoomChatScreen dispose.
  // Setiap kali masuk room, stream baru dibuat agar pesan selalu fresh.
  Stream<List<MessageModel>> getRoomMessages(String roomId) {
    return _service.getRoomMessagesCached(roomId);
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
    // Jangan cache stream private chat — controller.onCancel di _cachedMessagesStream
    // memanggil removeChannel saat screen ditutup, sehingga stream lama tidak emit lagi.
    // Setiap buka chat harus dapat stream baru yang fresh.
    return _service.getPrivateChatMessages(chatId);
  }

  Stream<String> getUserStatus(String uid) => _service.getUserStatus(uid);

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

  Future<void> unblockUser(String myUid, String otherUid) async {
    await _service.unblockUser(myUid, otherUid);
    await loadBlockedUids(myUid);
  }

  // Hide Chat (client-side delete)
  Future<void> hideChat(String myUid, String chatId) async {
    await _service.hideChat(myUid, chatId);
  }

  Future<Set<String>> getHiddenChats(String myUid) {
    return _service.getHiddenChats(myUid);
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
    _privateChatsCache.clear();
    _service.clearCachedStreams();
    MessageCache.instance.clearAll();
    notifyListeners();
  }
}
