import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../services/message_cache.dart';
import '../services/photo_cache.dart';

class ChatProvider extends ChangeNotifier {
  final ChatService _service = ChatService();
  List<String> _blockedUids = [];
  Future<List<String>>? _loadingBlockedUids;

  List<String> get blockedUids => _blockedUids;

  // Room chat — TIDAK di-cache karena stream mati saat RoomChatScreen dispose.
  // Setiap kali masuk room, stream baru dibuat agar pesan selalu fresh.
  ChatMessageStream getRoomMessages(String roomId) {
    return _service.getRoomMessages(roomId);
  }

  Future<void> sendRoomMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
    String type = 'text',
    String imageData = '',
  }) async {
    await _service.sendRoomMessage(
      roomId: roomId,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      text: text,
      type: type,
      imageData: imageData,
    );
  }

  // Private chat
  Future<bool> isUserActive(String uid) => _service.isUserActive(uid);

  /// Kirim koin ke lawan bicara (via RPC server). Return {ok, points}.
  Future<Map<String, dynamic>> sendCoins(
    String chatId,
    String receiverId,
    int amount,
  ) {
    return _service.sendCoins(chatId, receiverId, amount);
  }

  /// Kirim hadiah ke lawan bicara (via RPC server). Return {ok, points, net, cut}.
  Future<Map<String, dynamic>> sendGift(
    String chatId,
    String receiverId,
    String giftId,
  ) {
    return _service.sendGift(chatId, receiverId, giftId);
  }

  /// Daftar hadiah dari server (fallback katalog lokal bila gagal).
  Future<List<Map<String, dynamic>>> listGifts() => _service.listGifts();

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

  ChatMessageStream getPrivateChatMessages(String chatId) {
    // Jangan cache stream private chat — controller.onCancel di _cachedMessagesStream
    // memanggil removeChannel saat screen ditutup, sehingga stream lama tidak emit lagi.
    // Setiap buka chat harus dapat stream baru yang fresh.
    return _service.getPrivateChatMessages(chatId);
  }

  Stream<String> getUserStatus(String uid, {String? initialStatus}) =>
      _service.getUserStatus(uid, initialStatus: initialStatus);

  Stream<void> getTypingStream(String chatId) =>
      _service.getTypingStream(chatId);

  void sendTyping(String chatId) => _service.sendTyping(chatId);

  Future<void> sendPrivateMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
    String type = 'text',
    String imageData = '',
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
  }) async {
    await _service.sendPrivateMessage(
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      text: text,
      type: type,
      imageData: imageData,
      repliedToId: repliedToId,
      repliedToText: repliedToText,
      repliedToSenderName: repliedToSenderName,
    );
  }

  Future<void> markAsRead(String chatId, String uid) async {
    await _service.markAsRead(chatId, uid);
  }

  /// Tandai dibaca dari monitor admin (RPC SECURITY DEFINER khusus admin —
  /// mark_chat_read biasa kena RLS participant saat dipanggil akun admin).
  Future<void> markAsReadAdmin(String chatId, String uid) async {
    await _service.markAsReadAdmin(chatId, uid);
  }

  Future<void> clearViewOnceImage(
    String messageId, {
    bool isRoom = false,
  }) async {
    await _service.clearViewOnceImage(messageId, isRoom: isRoom);
  }

  Stream<List<PrivateChatInfo>> getMyPrivateChats(String myUid) {
    return _service.getMyPrivateChats(myUid);
  }

  List<PrivateChatInfo>? lastPrivateChatsSnapshot(String myUid) =>
      _service.lastPrivateChatsSnapshot(myUid);

  /// Refresh paksa list private chat (dipanggil saat tab Pesan di-mount ulang
  /// supaya tidak stuck spinner pada broadcast stream yang di-cache).
  void refreshMyPrivateChats(String myUid) =>
      _service.refreshMyPrivateChats(myUid);

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

  Future<void> unblockUser(String myUid, String otherUid) async {
    await _service.unblockUser(myUid, otherUid);
    await loadBlockedUids(myUid);
  }

  // Hide Chat (client-side delete)
  Future<void> hideChat(String myUid, String chatId) async {
    await _service.hideChat(myUid, chatId);
  }

  Future<void> pinChat(String chatId, bool pin) async {
    await _service.pinPrivateChat(chatId, pin);
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
    if (_loadingBlockedUids != null) {
      await _loadingBlockedUids;
      return;
    }
    _loadingBlockedUids = _service.getBlockedUids(myUid);
    try {
      _blockedUids = await _loadingBlockedUids!;
    } finally {
      _loadingBlockedUids = null;
    }
    notifyListeners();
  }

  bool isBlocked(String uid) => _blockedUids.contains(uid);

  void reset() {
    _blockedUids = [];
    _service.clearCachedStreams();
    MessageCache.instance.clearAll();
    PhotoCache.instance.clearAll();
    notifyListeners();
  }
}
