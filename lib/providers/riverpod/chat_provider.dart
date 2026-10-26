import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_model.dart';
import '../../utils.dart' show dlog;
import '../../utils/mention.dart';
import '../../services/chat_service.dart';
export '../../services/chat_stream_session.dart' show ChatMessageStream;
export '../../services/chat_service.dart' show PrivateChatInfo;
import '../../core/cache/chat_poster_cache.dart';
import '../../core/cache/message_cache.dart';
import '../../core/cache/offline_outbox.dart';
import '../../core/cache/photo_aspect_cache.dart';
import '../../core/cache/photo_cache.dart';

/// State chat (immutable — yang di-watch widget).
class ChatState {
  final List<String> blockedUids;
  const ChatState({this.blockedUids = const []});

  @override
  bool operator ==(Object other) =>
      other is ChatState && listEquals(other.blockedUids, blockedUids);

  @override
  int get hashCode => Object.hashAll(blockedUids);

  bool isBlocked(String uid) => blockedUids.contains(uid);
}

/// Passthrough ChatService + daftar blokir (Riverpod).
/// Migrasi dari ChangeNotifier → Notifier. Global (persist sepanjang sesi).
class ChatNotifier extends Notifier<ChatState> {
  var _disposed = false;

  // Service di-inject untuk test (default produksi) — call site tidak berubah.
  final ChatService _service;
  ChatNotifier({ChatService? service}) : _service = service ?? ChatService();
  List<String> _blockedUids = [];
  Future<List<String>>? _loadingBlockedUids;

  List<String> get blockedUids => _blockedUids;

  @override
  ChatState build() {
    ref.onDispose(_disposeAll);
    return const ChatState();
  }

  void _emit() {
    if (_disposed) return;
    state = ChatState(blockedUids: List.unmodifiable(_blockedUids));
  }

  // Room chat — TIDAK di-cache karena stream mati saat RoomChatScreen dispose.
  // Setiap kali masuk room, stream baru dibuat agar pesan selalu fresh.
  ChatMessageStream getRoomMessages(String roomId) {
    return _service.getRoomMessages(roomId);
  }

  Future<String?> sendRoomMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
    String type = 'text',
    String imageData = '',
    int? durationMs,
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    Map<String, dynamic>? repliedToMeta,
    bool isForwarded = false,
    List<Mention> mentions = const [],
    String videoPoster = '',
    String? albumId,
    Map<String, dynamic>? poll,
    Map<String, dynamic>? contact,
  }) => _service.sendRoomMessage(
    roomId: roomId,
    senderId: senderId,
    senderName: senderName,
    senderGender: senderGender,
    text: text,
    type: type,
    imageData: imageData,
    durationMs: durationMs,
    repliedToId: repliedToId,
    repliedToText: repliedToText,
    repliedToSenderName: repliedToSenderName,
    repliedToMeta: repliedToMeta,
    isForwarded: isForwarded,
    mentions: mentions,
    videoPoster: videoPoster,
    albumId: albumId,
    poll: poll,
    contact: contact,
  );

  /// Perbarui payload lokasi live di room.
  Future<bool> updateRoomLocationMessage(String id, String payload) =>
      _service.updateLocationMessage(id, payload);

  Future<bool> deleteRoomMessage(String messageId) async {
    return _service.deleteRoomMessage(messageId);
  }

  /// ADMIN SAJA — hapus/undo pesan siapa pun di room (RPC security definer).
  Future<bool> adminDeleteRoomMessage(String messageId, {bool undelete = false}) {
    return _service.adminDeleteRoomMessage(messageId, undelete: undelete);
  }

  Future<bool> deletePrivateMessage(String messageId) async {
    return _service.deletePrivateMessage(messageId);
  }

  Future<bool> undeletePrivateMessage(String messageId) async {
    return _service.undeletePrivateMessage(messageId);
  }

  Future<bool> undeleteRoomMessage(String messageId) async {
    return _service.undeleteRoomMessage(messageId);
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

  /// Kirim hadiah di room (live) ke host (owner). Return {ok, points, qty}.
  Future<Map<String, dynamic>> sendRoomGift(
    String roomId,
    String giftId, {
    int qty = 1,
  }) {
    return _service.sendRoomGift(roomId, giftId, qty: qty);
  }

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

  /// last_seen satu user (untuk "terakhir dilihat" di header chat).
  Future<DateTime?> getUserLastSeen(String uid) =>
      _service.getUserLastSeen(uid);

  Stream<String> getTypingStream(String chatId) =>
      _service.getTypingStream(chatId);

  Stream<(String, int)> getTypingPulseStream(String chatId) =>
      _service.getTypingPulseStream(chatId);

  void sendTyping(String chatId, {String kind = 'typing'}) =>
      _service.sendTyping(chatId, kind: kind);

  Future<String?> sendPrivateMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
    String type = 'text',
    String imageData = '',
    int? durationMs,
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    Map<String, dynamic>? repliedToMeta,
    bool isForwarded = false,
    List<Mention> mentions = const [],
    String videoPoster = '',
    String? albumId,
    Map<String, dynamic>? poll,
    Map<String, dynamic>? contact,
  }) => _service.sendPrivateMessage(
    chatId: chatId,
    senderId: senderId,
    senderName: senderName,
    senderGender: senderGender,
    text: text,
    type: type,
    imageData: imageData,
    durationMs: durationMs,
    repliedToId: repliedToId,
    repliedToText: repliedToText,
    repliedToSenderName: repliedToSenderName,
    repliedToMeta: repliedToMeta,
    isForwarded: isForwarded,
    mentions: mentions,
    videoPoster: videoPoster,
    albumId: albumId,
    poll: poll,
    contact: contact,
  );

  Future<void> markAsRead(String chatId, String uid) async {
    await _service.markAsRead(chatId, uid);
  }

  /// Tandai SEMUA chat pribadi dibaca (menu ⋮ chat list). Return jumlah
  /// chat yang benar-benar berubah (skip yang sudah 0). RPC paralel per
  /// batch 10 (dulu serial; paralel tanpa batas = DB storm).
  Future<int> markAllChatsRead(String uid) async {
    final snapshot = _service.lastPrivateChatsSnapshot(uid) ?? const [];
    final targets = snapshot
        .where((c) => (c.unreadCounts[uid] ?? 0) > 0)
        .toList();
    for (var i = 0; i < targets.length; i += 10) {
      final chunk = targets.skip(i).take(10);
      await Future.wait(chunk.map((c) => _service.markAsRead(c.chatId, uid)));
    }
    return targets.length;
  }

  /// Tandai dibaca dari monitor admin (RPC SECURITY DEFINER khusus admin —
  /// mark_chat_read biasa kena RLS participant saat dipanggil akun admin).
  Future<void> markAsReadAdmin(String chatId, String uid) async {
    await _service.markAsReadAdmin(chatId, uid);
  }

  Future<void> clearViewOnceImage(
    String messageId, {
    bool isRoom = false,
    bool video = false,
    String? chatId,
  }) async {
    await _service.clearViewOnceImage(
      messageId,
      isRoom: isRoom,
      video: video,
      chatId: chatId,
    );
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
  /// Error gangguan jaringan (offline/DNS/timeout), bukan ditolak server —
  /// dipakai UI untuk memilih pesan gagal yang tepat.
  static bool isNetworkError(Object e) => OfflineOutbox.isNetworkError(e);

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

  Future<void> pinChat(String chatId, bool pin, {String? myUid}) async {
    await _service.pinPrivateChat(chatId, pin, myUidParam: myUid);
  }

  Future<void> muteChat(String chatId, bool mute, {String? myUid}) async {
    await _service.mutePrivateChat(chatId, mute, myUidParam: myUid);
  }

  /// Mute/unmute notifikasi room live — sync server + lokal (C1 audit).
  Future<void> muteRoom(String roomId, bool mute) {
    return _service.muteRoom(roomId, mute);
  }

  Future<void> archiveChat(String chatId, bool archive, {String? myUid}) async {
    await _service.archivePrivateChat(chatId, archive, myUidParam: myUid);
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

  Future<Map<String, dynamic>> reportRoomMessage(
    String messageId, {
    required String reasonCode,
    String note = '',
  }) =>
      _service.reportRoomMessage(messageId,
          reasonCode: reasonCode, note: note);

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
    _emit();
  }

  // ── Passthrough agar screen tidak import ChatService (Fase 9b) ──
  Future<bool> editPrivateMessage(String id, String text) =>
      _service.editPrivateMessage(id, text);

  /// Perbarui payload lokasi live (koordinat bergerak) — hanya `text`.
  Future<bool> updateLocationMessage(String id, String payload) =>
      _service.updateLocationMessage(id, payload);
  Future<bool> editRoomMessage(String id, String text) =>
      _service.editRoomMessage(id, text);
  Future<void> prefetchPrivateChat(String chatId) =>
      _service.prefetchPrivateChat(chatId);
  String privateChatId(String a, String b) => _service.privateChatId(a, b);
  static String effectiveStatusOf(String? raw, String? lastSeen) =>
      ChatService.effectiveStatusOf(raw, lastSeen);
  bool isBlocked(String uid) => _blockedUids.contains(uid);

  /// Boleh kirim media di room ini? (gate trust room publik)
  Future<bool?> canSendRoomMedia(String roomId) =>
      _service.canSendRoomMedia(roomId);

  Future<Map<String, dynamic>?> roomMediaGateState(String roomId) =>
      _service.roomMediaGateState(roomId);

  Future<String> checkContentSafety(String storagePath) =>
      _service.checkContentSafety(storagePath);

  Future<bool> flagMediaReview(String messageId) =>
      _service.flagMediaReview(messageId);

  Future<Map<String, dynamic>> adminSetHomeCountry(String uid, String? country) =>
      _service.adminSetHomeCountry(uid, country);

  Future<bool> moderatorResolveReview(String messageId, {required bool hide}) =>
      _service.moderatorResolveReview(messageId, hide: hide);

  Future<List<Map<String, dynamic>>> adminSearchUsers(String query) =>
      _service.adminSearchUsers(query);

  Future<Map<String, dynamic>?> moderatorConsole(String country) =>
      _service.moderatorConsole(country);

  Future<Map<String, dynamic>> decideModeratorApplication(
    int id, {
    required bool approve,
    String note = '',
  }) =>
      _service.decideModeratorApplication(id, approve: approve, note: note);

  Future<Map<String, dynamic>> decideCountryPermit(
    String uid,
    String country, {
    required bool approve,
    String note = '',
  }) =>
      _service.decideCountryPermit(uid, country,
          approve: approve, note: note);

  Future<Map<String, dynamic>> moderatorHideMessage(
    String messageId, {
    required bool hide,
  }) =>
      _service.moderatorHideMessage(messageId, hide: hide);

  Future<Map<String, dynamic>> resolveMessageReports(
    String messageId, {
    String action = 'actioned',
  }) =>
      _service.resolveMessageReports(messageId, action: action);

  Future<Map<String, dynamic>> applyCountryModerator(
    String country, {
    String reason = '',
  }) =>
      _service.applyCountryModerator(country, reason: reason);

  Future<List<String>> moderatorUids(List<String> uids) =>
      _service.moderatorUids(uids);

  Future<Map<String, dynamic>> setHomeCountry(String country) =>
      _service.setHomeCountry(country);

  Future<Map<String, dynamic>?> adminModerationOverview() =>
      _service.adminModerationOverview();

  Future<List<Map<String, dynamic>>> moderatorCandidates(String country) =>
      _service.moderatorCandidates(country);

  Future<Map<String, dynamic>> moderatorSetColleague(
    String country,
    String uid, {
    required bool grant,
  }) =>
      _service.moderatorSetColleague(country, uid, grant: grant);

  Future<Map<String, dynamic>?> myModerationState() =>
      _service.myModerationState();

  Future<Map<String, dynamic>> requestCountryPermit(
    String country, {
    String reason = '',
  }) =>
      _service.requestCountryPermit(country, reason: reason);

  /// Status blokir DUA ARAH (saya↔dia). Lihat
  /// `ChatService.getChatBlockState` — RLS `blocks` membuat klien tak bisa
  /// tahu bila dirinya diblokir, sehingga perlu RPC.
  Future<({bool iBlockedOther, bool otherBlockedMe, bool canSend})>
  chatBlockState(String otherUid) => _service.getChatBlockState(otherUid);

  /// Bersihkan semua data chat akun lama (logout). Urutan penting: timer
  /// save & antrean memori dibuang DULU, baru wipe disk — kalau terbalik,
  /// timer/flush yang tertunda menulis ulang data akun lama.
  Future<void> reset() async {
    _blockedUids = [];
    _service.clearCachedStreams();
    OfflineOutbox.instance.resetForLogout();
    _emit();
    await Future.wait<void>([
      _guard(MessageCache.instance.clearAll()),
      _guard(PhotoCache.instance.clearAll()),
      // Poster/aspek foto chat milik user lama — hanya di sini (logout),
      // BUKAN saat background (poster harus persisten untuk cold start).
      _guard(ChatPosterCache.instance.clear()),
      _guard(PhotoAspectCache.instance.clear()),
    ]);
    // Antrean bisa dimuat ulang dari disk selagi wipe berjalan → buang lagi.
    OfflineOutbox.instance.resetForLogout();
  }

  static Future<void> _guard(Future<void> f) =>
      f.catchError((Object e) => dlog('[CHAT] reset cache error: $e'));

  void _disposeAll() {
    _disposed = true;
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

/// ── Header private chat (per-chat) ──────────────────────────────────────
///
/// PERF (Prioritas 4): dulu header (status/last-seen/kota/umur/gender/read)
/// adalah FIELD di State layar chat → tiap update memanggil `setState()`
/// di ROOT layar → membangun ulang AppBar + Scaffold + PopScope + seluruh
/// list, padahal yang berubah hanya 1 baris subtitle/centang. Sekarang state
/// header dipisah ke provider per-chat → hanya subtree yang `watch` rebuild.
///
/// Immutable + `==` value-based supaya Riverpod skip notify saat tak berubah
/// (heartbeat presence yang emit nilai sama = nol rebuild).
class ChatHeader {
  final String otherStatus;
  final DateTime? otherLastSeen;
  final String otherCity;
  final String otherCountry;
  final int otherAge;
  final String otherGender;
  final bool otherRegistered;
  final bool otherDeleted;
  final DateTime? otherLastRead;
  final bool isBlocked;

  const ChatHeader({
    this.otherStatus = 'offline',
    this.otherLastSeen,
    this.otherCity = '',
    this.otherCountry = '',
    this.otherAge = 0,
    this.otherGender = '',
    this.otherRegistered = false,
    this.otherDeleted = false,
    this.otherLastRead,
    this.isBlocked = false,
  });

  ChatHeader copyWith({
    String? otherStatus,
    DateTime? otherLastSeen,
    bool clearLastSeen = false,
    String? otherCity,
    String? otherCountry,
    int? otherAge,
    String? otherGender,
    bool? otherRegistered,
    bool? otherDeleted,
    DateTime? otherLastRead,
    bool clearLastRead = false,
    bool? isBlocked,
  }) {
    return ChatHeader(
      otherStatus: otherStatus ?? this.otherStatus,
      otherLastSeen: clearLastSeen
          ? null
          : (otherLastSeen ?? this.otherLastSeen),
      otherCity: otherCity ?? this.otherCity,
      otherCountry: otherCountry ?? this.otherCountry,
      otherAge: otherAge ?? this.otherAge,
      otherGender: otherGender ?? this.otherGender,
      otherRegistered: otherRegistered ?? this.otherRegistered,
      otherDeleted: otherDeleted ?? this.otherDeleted,
      otherLastRead: clearLastRead
          ? null
          : (otherLastRead ?? this.otherLastRead),
      isBlocked: isBlocked ?? this.isBlocked,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatHeader &&
      other.otherStatus == otherStatus &&
      other.otherLastSeen == otherLastSeen &&
      other.otherCity == otherCity &&
      other.otherCountry == otherCountry &&
      other.otherAge == otherAge &&
      other.otherGender == otherGender &&
      other.otherRegistered == otherRegistered &&
      other.otherDeleted == otherDeleted &&
      other.otherLastRead == otherLastRead &&
      other.isBlocked == isBlocked;

  @override
  int get hashCode => Object.hash(
    otherStatus,
    otherLastSeen,
    otherCity,
    otherCountry,
    otherAge,
    otherGender,
    otherRegistered,
    otherDeleted,
    otherLastRead,
    isBlocked,
  );
}

/// Notifier header chat (per-chatId). Null-safe: `family` per chat, auto
/// dibuang saat tak ada listener (`autoDispose`).
class ChatHeaderNotifier extends AutoDisposeFamilyNotifier<ChatHeader, String> {
  @override
  ChatHeader build(String chatId) => const ChatHeader();

  /// Patch sebagian field — no-op bila hasilnya identik (skip notify).
  void patch(ChatHeader Function(ChatHeader) f) {
    final next = f(state);
    if (next == state) return;
    state = next;
  }
}

final chatHeaderProvider =
    AutoDisposeNotifierProviderFamily<ChatHeaderNotifier, ChatHeader, String>(
      ChatHeaderNotifier.new,
    );
