import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/cache/media_disk_cache.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../config/supabase_config.dart';
import 'realtime_hub.dart';
import '../config/gifts.dart';
import '../core/cache/message_cache.dart';
import '../core/cache/photo_cache.dart';
import '../services/storage_photo_service.dart';
import '../utils.dart';
import '../utils/mention.dart';
import '../core/perf/perf_probe.dart';
import 'notification_prefs_service.dart';
import 'chat_stream_session.dart';

export 'chat_stream_session.dart';


part 'chat_service_private.dart';
part 'chat_service_private_chatlist.dart';
part 'chat_service_room.dart';
part 'chat_service_typing.dart';
part 'chat_service_presence.dart';
part 'chat_service_gift.dart';

/// State instance + method privat BERSAMA lintas domain.
///
/// Mixin per-domain (file `part`) mengaksesnya — satu library via `part`,
/// jadi sah, dan interface `ChatService` tidak berubah (mock test aman).
abstract class ChatBase {
  final SupabaseClient _sb = SupabaseConfig.client;
  String? _ownCountryCache;
  String? _invisibleUidCache;
  DateTime? _invisibleFetchedAt;
  Set<String>? _dummyUidCache;
  DateTime? _dummyUidFetchedAt;
  final Map<String, RealtimeChannel> _privateBroadcastChannels = {};
  final Map<String, int> _privateBroadcastRefs = {};
  final Map<String, String> _onlinePathByUid = {};
  final Map<String, List<void Function()>> _chatReloaders = {};
  final Map<String, StreamController<List<PrivateChatInfo>>>
  _privateChatsStreams = {};
  final Map<String, List<PrivateChatInfo>> _privateChatsLast = {};
  final Map<String, Future<void>> _chatListFetchInFlight = {};
  final Map<String, Set<String>> _privateChatsHidden = {};
  final Map<String, DateTime> _lastChatReloadAt = {};
  final Map<String, Timer> _chatListSaveTimers = {};
  final Map<String, RealtimeChannel> _typingChannels = {};
  final Map<String, int> _typingRefs = {};
  final Map<String, Set<StreamController<(String, int)>>> _typingSubs = {};
  final Map<String, Timer> _typingGrace = {};
  final Map<String, int> _lastPingTyping = {};

  Future<String> _avatarB64(String path) async {
    final cached = ChatService._avatarCache[path];
    if (cached != null) {
      // LRU sejati: yang baru dibaca pindah ke ujung (tahan dari eviction).
      ChatService._avatarCache.remove(path);
      ChatService._avatarCache[path] = cached;
      return cached;
    }
    // DISK FIRST: baca dari cache lokal (instan, tanpa network).
    final disk = await MediaDiskCache.instance.read(path);
    if (disk != null && disk.isNotEmpty) {
      final b64 = base64Encode(disk);
      if (ChatService._avatarCache.length >= ChatService._avatarCacheMax) {
        ChatService._avatarCache.remove(ChatService._avatarCache.keys.first);
      }
      ChatService._avatarCache[path] = b64;
      return b64;
    }
    // Disk miss → download server → TULIS KE DISK (sumber lokal berikutnya).
    final b64 = await StoragePhotoService.instance.download(path) ?? '';
    if (b64.isNotEmpty) {
      try {
        await MediaDiskCache.instance
            .write(path, Uint8List.fromList(base64Decode(b64)));
      } catch (_) {}
      if (ChatService._avatarCache.length >= ChatService._avatarCacheMax) {
        ChatService._avatarCache.remove(ChatService._avatarCache.keys.first);
      }
      ChatService._avatarCache[path] = b64;
    }
    return b64;
  }
  /// Unduh audio voice message ke cache lokal (base64 via PhotoCache) —
  /// dipakai VoiceBubble untuk play offline tanpa fetch ulang.
  Future<void> _downloadVoiceToCache(String cacheKey, MessageModel msg) async {
    try {
      if (msg.imageData.isEmpty) return;
      if (!StoragePhotoService.instance.isVoicePath(msg.imageData)) return;
      final existing = await PhotoCache.instance.load(cacheKey, msg.id);
      if (existing != null && existing.isNotEmpty) {
        // Path sudah tercatat — pastikan bytes-nya juga ada di disk.
        unawaited(ChatService.prefetchVoiceBytes(msg.imageData));
        return;
      }
      await PhotoCache.instance.save(cacheKey, msg.id, msg.imageData);
      unawaited(ChatService.prefetchVoiceBytes(msg.imageData));
    } catch (e) {
      dlog('[ChatService] voice cache ${msg.id}: $e');
    }
  }
  /// - loadCache dan fetchServer jalan PARALEL untuk tampilan secepat mungkin.
  /// - INSERT event langsung di-append ke list tanpa refetch (0 network round-trip).
  /// - UPDATE/DELETE tetap refetch karena perlu reorder.
  /// - Poll fallback hanya jalan kalau realtime diam > 25s (event terlewat),
  ///   supaya tidak duplikasi pekerjaan realtime tiap 30 detik.
  ChatMessageStream _cachedMessagesStream({required String cacheKey}) {
    // Wrapper tipis — seluruh logika stream dipindah ke ChatStreamSession.
    return ChatStreamSession(
      sb: _sb,
      cacheKey: cacheKey,
      needsPhotoFill: ChatService._needsPhotoFill,
      downloadVoiceToCache: _downloadVoiceToCache,
      prefetchVoiceBytes: ChatService.prefetchVoiceBytes,
    ).start();
  }
  Future<void> unhideChat(String myUid, String chatId) async {
    final row = await _sb
        .from('private_chats')
        .select('hidden_by')
        .eq('chat_id', chatId)
        .maybeSingle();
    if (row == null) return;
    final hidden = List<String>.from(
      (row['hidden_by'] as List<dynamic>?) ?? [],
    );
    if (hidden.remove(myUid)) {
      await _sb
          .from('private_chats')
          .update({'hidden_by': hidden})
          .eq('chat_id', chatId);
    }
  }

}

class ChatService extends ChatBase with ChatServicePrivateMx, ChatServicePrivateChatListMx, ChatServiceRoomMx, ChatServiceTypingMx, ChatServicePresenceMx, ChatServiceGiftMx {
  static final Map<String, String> _avatarCache = {};
  static const _avatarCacheMax = 100;
  @visibleForTesting
  static Set<String> get avatarCacheKeys => _avatarCache.keys.toSet();
  static final Set<String> _voiceDownloadInflight = {};
  static void clearAvatarCacheForPath(String path) {
    _avatarCache.remove(path);
  }
  static void clearAvatarCacheForUid(String uid) {
    _avatarCache.remove('avatars/$uid.jpg');
  }
  static void setAvatarCacheForUid(String uid, String base64) {
    if (base64.isEmpty) {
      _avatarCache.remove('avatars/$uid.jpg');
      return;
    }
    if (_avatarCache.length >= _avatarCacheMax) {
      _avatarCache.remove(_avatarCache.keys.first);
    }
    _avatarCache['avatars/$uid.jpg'] = base64;
  }
  static void setAvatarCacheForPath(String path, String base64) {
    if (path.isEmpty) return;
    if (base64.isEmpty) {
      _avatarCache.remove(path);
      return;
    }
    if (_avatarCache.length >= _avatarCacheMax) {
      _avatarCache.remove(_avatarCache.keys.first);
    }
    _avatarCache[path] = base64;
  }
  /// Foto masih perlu diisi: imageData kosong ATAU masih path storage
  /// (belum ter-download ke base64 lokal).
  static bool _needsPhotoFill(MessageModel m) {
    if (m.imageData.isEmpty) return true;
    return StoragePhotoService.instance.isPath(m.imageData) ||
        StoragePhotoService.instance.isVoicePath(m.imageData);
  }
  /// Pastikan audio voice ada di MediaDiskCache (cache yang dibaca
  /// VoiceBubble saat play). Fire-and-forget; skip kalau sudah di disk;
  /// aman dipanggil berulang dari jalur mana pun.
  static Future<void> prefetchVoiceBytes(String path) async {
    if (path.isEmpty || !StoragePhotoService.instance.isVoicePath(path)) {
      return;
    }
    if (_voiceDownloadInflight.contains(path)) return;
    try {
      final f = await MediaDiskCache.instance.fileFor(path);
      if (f != null) return; // sudah di disk — tap play instan
      _voiceDownloadInflight.add(path);
      final bytes = await StoragePhotoService.instance.downloadBytes(path);
      if (bytes != null && bytes.isNotEmpty) {
        await MediaDiskCache.instance.write(path, bytes);
      }
    } catch (e) {
      dlog('[ChatService] voice prefetch: $e');
    } finally {
      _voiceDownloadInflight.remove(path);
    }
  }
  static int _comparePinned(PrivateChatInfo a, PrivateChatInfo b, String myUid) {
    final aPinned = a.isPinnedFor(myUid);
    final bPinned = b.isPinnedFor(myUid);
    if (aPinned && !bPinned) return -1;
    if (!aPinned && bPinned) return 1;
    if (aPinned && bPinned) {
      final aTime = a.pinnedAtFor(myUid) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.pinnedAtFor(myUid) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final c = bTime.compareTo(aTime);
      if (c != 0) return c;
    }
    return b.lastMessageAt.compareTo(a.lastMessageAt);
  }
  /// Hitung status efektif: last_seen basi (> 30 menit) dianggap offline.
  /// Status 'invisible' (admin) dianggap offline bagi user lain.
  /// Dipakai getUserStatus & UserInfoScreen agar logikanya seragam.
  static String effectiveStatusOf(String? rawStatus, String? lastSeenStr) {
    final s = rawStatus ?? 'offline';
    if (s == 'offline' || s == 'invisible') return 'offline';
    final lastSeen = DateTime.tryParse(lastSeenStr ?? '');
    if (lastSeen == null) return 'offline';
    final stale = lastSeen.toUtc().isBefore(
      DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
    );
    return stale ? 'offline' : s;
  }
  /// True bila event status profil harus langsung membuang user dari
  /// daftar online tayang (tanpa menunggu full resync).
  static bool shouldDropOnlineUid(String? status) {
    return status == 'offline' || status == 'invisible';
  }
  /// True bila status mentah layak tampil di daftar Online: hanya
  /// 'online'/'idle'. 'offline'/'invisible'/lainnya selalu gugur — socket
  /// presence yang hidup tidak mengalahkan pilihan invisible manual.
  static bool isVisibleOnlineStatus(String? rawStatus) {
    final s = rawStatus ?? 'offline';
    return s == 'online' || s == 'idle';
  }
  /// True bila user layak tampil di daftar Online: status terlihat +
  /// last_seen segar (≤ 30 menit, sama seperti RPC + effectiveStatusOf).
  /// Dipakai menyaring cache disk basi & emission berstatus basi supaya
  /// akun invisible/offline tidak nempel di daftar Online.
  static bool isVisibleOnline(String? rawStatus, DateTime lastSeen) {
    if (!isVisibleOnlineStatus(rawStatus)) return false;
    final stale = lastSeen.toUtc().isBefore(
      DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
    );
    return !stale;
  }
  /// Filter hasil RPC daftar online terhadap presence WebSocket.
  /// - Ada di presence → WebSocket hidup, tampil apa pun statusnya.
  /// - Status 'online' tapi belum di-presence → baru connect, tampil
  ///   (presence butuh ~1 detik untuk track).
  /// - Dummy (tanpa socket presence, status dikelola cron/tick) → selalu
  ///   tampil sesuai status DB (idle dummy tetap tampil).
  /// - Status selain 'online' tanpa presence dan bukan dummy (mis. 'idle'
  ///   zombie karena app di-kill) → buang.
  /// Safety net: kalau filter membuang semua, kembalikan RPC asli
  /// (kemungkinan presence belum sync — cold start).
  static List<dynamic> filterRpcOnlineRows(
    List<dynamic> rpcRows,
    Set<String> presenceUids, {
    Set<String> dummyUids = const {},
  }) {
    final filtered = rpcRows.where((r) {
      final m = r as Map;
      final id = '${m['id'] ?? ''}';
      final st = '${m['status'] ?? ''}';
      // Offline/invisible selalu gugur — walau socket presence-nya hidup
      // (invisible manual harus menang).
      if (!isVisibleOnlineStatus(st)) return false;
      if (presenceUids.contains(id)) return true;
      if (st == 'online') return true;
      if (dummyUids.contains(id)) return true;
      return false;
    }).toList();
    return filtered.isEmpty ? rpcRows : filtered;
  }
}

class PrivateChatInfo {
  final String chatId;
  final List<String> participants;
  final Map<String, String> participantNames;
  final Map<String, String> participantGenders;
  final Map<String, String> participantLocations;
  final Map<String, int> participantAges;
  final Map<String, bool> participantRegistered;
  final String lastMessage;
  final DateTime lastMessageAt;
  final String lastSenderId;
  final int messageCount;
  final Map<String, int> unreadCounts;
  final Map<String, DateTime> lastReadAt;
  final List<String> pinnedBy;
  final Map<String, DateTime> pinnedAt;
  final List<String> mutedBy;
  final List<String> archivedBy;

  PrivateChatInfo({
    required this.chatId,
    required this.participants,
    required this.participantNames,
    this.participantGenders = const {},
    this.participantLocations = const {},
    this.participantAges = const {},
    this.participantRegistered = const {},
    required this.lastMessage,
    required this.lastMessageAt,
    this.lastSenderId = '',
    this.messageCount = 0,
    this.unreadCounts = const {},
    this.lastReadAt = const {},
    this.pinnedBy = const [],
    this.pinnedAt = const {},
    this.mutedBy = const [],
    this.archivedBy = const [],
  });

  bool isPinnedFor(String uid) => pinnedBy.contains(uid);
  DateTime? pinnedAtFor(String uid) => pinnedAt[uid];
  bool isMutedFor(String uid) => mutedBy.contains(uid);
  bool isArchivedFor(String uid) => archivedBy.contains(uid);

  Map<String, dynamic> toMap() => {
    'chatId': chatId,
    'participants': participants,
    'participantNames': participantNames,
    'participantGenders': participantGenders,
    'participantLocations': participantLocations,
    'participantAges': participantAges,
    'participantRegistered': participantRegistered,
    'lastMessage': lastMessage,
    'lastMessageAt': lastMessageAt.toIso8601String(),
    'lastSenderId': lastSenderId,
    'messageCount': messageCount,
    'unreadCounts': unreadCounts,
    'lastReadAt': lastReadAt.map((k, v) => MapEntry(k, v.toIso8601String())),
    'pinnedBy': pinnedBy,
    'pinnedAt': pinnedAt.map((k, v) => MapEntry(k, v.toIso8601String())),
    'mutedBy': mutedBy,
    'archivedBy': archivedBy,
  };

  static Map<String, String> _strMap(dynamic v) =>
      ((v as Map?) ?? {}).map((k, e) => MapEntry('$k', '$e'));

  factory PrivateChatInfo.fromMap(Map<String, dynamic> d) {
    return PrivateChatInfo(
      chatId: '${d['chatId'] ?? ''}',
      participants: List<String>.from(d['participants'] ?? const []),
      participantNames: _strMap(d['participantNames']),
      participantGenders: _strMap(d['participantGenders']),
      participantLocations: _strMap(d['participantLocations']),
      participantAges: ((d['participantAges'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', (v as num).toInt()),
      ),
      participantRegistered: ((d['participantRegistered'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', v == true),
      ),
      lastMessage: '${d['lastMessage'] ?? ''}',
      lastMessageAt:
          DateTime.tryParse('${d['lastMessageAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastSenderId: '${d['lastSenderId'] ?? ''}',
      messageCount: (d['messageCount'] as num?)?.toInt() ?? 0,
      unreadCounts: ((d['unreadCounts'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', (v as num).toInt()),
      ),
      lastReadAt: ((d['lastReadAt'] as Map?) ?? {}).map(
        (k, v) =>
            MapEntry('$k', DateTime.tryParse('$v') ?? DateTime(2000)),
      ),
      pinnedBy: List<String>.from(d['pinnedBy'] ?? const []),
      pinnedAt: ((d['pinnedAt'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', DateTime.tryParse('$v') ?? DateTime(2000)),
      ),
      mutedBy: List<String>.from(d['mutedBy'] ?? const []),
      archivedBy: List<String>.from(d['archivedBy'] ?? const []),
    );
  }

  PrivateChatInfo copyWith({
    String? chatId,
    List<String>? participants,
    Map<String, String>? participantNames,
    Map<String, String>? participantGenders,
    Map<String, String>? participantLocations,
    Map<String, int>? participantAges,
    Map<String, bool>? participantRegistered,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastSenderId,
    int? messageCount,
    Map<String, int>? unreadCounts,
    Map<String, DateTime>? lastReadAt,
    List<String>? pinnedBy,
    Map<String, DateTime>? pinnedAt,
    List<String>? mutedBy,
    List<String>? archivedBy,
  }) {
    return PrivateChatInfo(
      chatId: chatId ?? this.chatId,
      participants: participants ?? this.participants,
      participantNames: participantNames ?? this.participantNames,
      participantGenders: participantGenders ?? this.participantGenders,
      participantLocations: participantLocations ?? this.participantLocations,
      participantAges: participantAges ?? this.participantAges,
      participantRegistered:
          participantRegistered ?? this.participantRegistered,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      messageCount: messageCount ?? this.messageCount,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      pinnedBy: pinnedBy ?? this.pinnedBy,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      mutedBy: mutedBy ?? this.mutedBy,
      archivedBy: archivedBy ?? this.archivedBy,
    );
  }
}
