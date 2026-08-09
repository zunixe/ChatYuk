import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../config/supabase_config.dart';
import '../services/message_cache.dart';
import '../utils.dart';

class ChatService {
  final SupabaseClient _sb = SupabaseConfig.client;

  // ── Room Chat ──

  Stream<List<MessageModel>> getRoomMessages(String roomId) {
    return _sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: true)
        .limit(100)
        .map((rows) => rows
            .map((row) => MessageModel.fromMap('${row['id']}', snakeToCamel(row)))
            .toList());
  }

  /// Stream pesan room dengan cache lokal (instan) + realtime server.
  Stream<List<MessageModel>> getRoomMessagesCached(String roomId) {
    return _cachedMessagesStream(cacheKey: 'room_$roomId');
  }

  Future<void> sendRoomMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
  }) async {
    // Batasi panjang teks
    if (text.isEmpty || text.length > 2000) return;
    await _sb.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_gender': senderGender,
      'text': text,
      'type': 'text',
      'image_data': '',
    });
  }

  // ── Private Chat ──

  String _chatId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  Stream<List<MessageModel>> getPrivateChatMessages(String chatId) {
    return _cachedMessagesStream(cacheKey: 'private_$chatId');
  }

  /// Gabungan cache lokal (instan) + realtime server.
  /// - loadCache dan fetchServer jalan PARALEL untuk tampilan secepat mungkin.
  /// - INSERT event langsung di-append ke list tanpa refetch (0 network round-trip).
  /// - UPDATE/DELETE tetap refetch karena perlu reorder.
  /// - Poll fallback hanya jalan kalau realtime diam > 25s (event terlewat),
  ///   supaya tidak duplikasi pekerjaan realtime tiap 30 detik.
  Stream<List<MessageModel>> _cachedMessagesStream({
    required String cacheKey,
  }) {
    final isPrivate = cacheKey.startsWith('private_');
    final table = isPrivate ? 'private_messages' : 'messages';
    final filterKey = isPrivate ? 'chat_id' : 'room_id';
    final filterVal = cacheKey.split('_').skip(1).join('_');

    final controller = StreamController<List<MessageModel>>.broadcast();
    var _current = <MessageModel>[];

    // Kapan terakhir realtime "hidup" — poll skip kalau masih fresh.
    DateTime lastRealtime = DateTime.now();

    // Cache write di-debounce (2s) + skip kalau data tidak berubah,
    // supaya tidak encrypt & tulis SharedPreferences tiap pesan / tiap poll.
    Timer? saveDebounce;
    String? lastSavedSig;

    void scheduleCacheSave() {
      if (controller.isClosed) return;
      saveDebounce?.cancel();
      saveDebounce = Timer(const Duration(seconds: 2), () async {
        if (controller.isClosed) return;
        final sig = _current.isEmpty ? '' : '${_current.length}:${_current.last.id}';
        if (sig == lastSavedSig) return;
        lastSavedSig = sig;
        try {
          await MessageCache.instance.saveMessages(cacheKey, _current);
        } catch (_) {}
      });
    }

    Future<List<MessageModel>> fetchServer() async {
      final rows = await _sb
          .from(table)
          .select()
          .eq(filterKey, filterVal)
          .order('created_at', ascending: true)
          .limit(100);
      return rows
          .map((row) => MessageModel.fromMap('${row['id']}', snakeToCamel(row)))
          .toList();
    }

    Future<void> reload() async {
      try {
        final server = await fetchServer();
        if (controller.isClosed) return;
        _current = server;
        controller.add(_current);
        scheduleCacheSave();
      } catch (e) {
        debugPrint('[_cachedMessagesStream] fetch error: $e');
      }
    }

    final channelName = 'msg-${cacheKey.hashCode}';
    final channel = _sb.channel(channelName);

    // INSERT: append langsung dari payload — tidak perlu round-trip ke server
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: table,
      callback: (payload) {
        if (controller.isClosed) return;
        try {
          final row = payload.newRecord;
          if (row[filterKey]?.toString() != filterVal) return;
          final msg = MessageModel.fromMap('${row['id']}', snakeToCamel(row));
          if (_current.any((m) => m.id == msg.id)) return; // dedupe
          _current = [..._current, msg];
          lastRealtime = DateTime.now();
          controller.add(_current);
          scheduleCacheSave();
        } catch (_) {
          reload();
        }
      },
    );
    // UPDATE/DELETE: refetch karena perlu reorder
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: table,
      callback: (_) {
        lastRealtime = DateTime.now();
        reload();
      },
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: table,
      callback: (_) {
        lastRealtime = DateTime.now();
        reload();
      },
    );
    channel.subscribe();

    // loadCache dan reload jalan paralel
    MessageCache.instance.loadMessages(cacheKey).then((cached) {
      if (cached.isNotEmpty && !controller.isClosed && _current.isEmpty) {
        _current = cached;
        controller.add(_current);
      }
    });
    reload();

    // Fallback polling: hanya jalan kalau realtime diam > 25s.
    // Saat realtime sehat (tangkap INSERT/UPDATE/DELETE), tidak ada
    // fetch redundant tiap 30 detik.
    final pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (DateTime.now().difference(lastRealtime).inSeconds < 25) return;
      reload();
    });

    controller.onCancel = () {
      pollTimer.cancel();
      saveDebounce?.cancel();
      // Flush cache pending kalau ada data yang belum tersimpan.
      if (_current.isNotEmpty) {
        final sig = _current.isEmpty ? '' : '${_current.length}:${_current.last.id}';
        if (sig != lastSavedSig) {
          MessageCache.instance.saveMessages(cacheKey, _current).catchError((_) {});
        }
      }
      _sb.removeChannel(channel);
    };

    return controller.stream;
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
    final chatId = _chatId(myUid, otherUid);
    // ignoreDuplicates: chat yang sudah ada tidak di-update.
    // Kalau di-upsert, trigger DB 'Cannot modify participants' akan menolak
    // karena kolom participants tidak boleh berubah setelah chat dibuat.
    await _sb.from('private_chats').upsert({
      'chat_id': chatId,
      'participants': [myUid, otherUid],
      'participant_names': {myUid: myName, otherUid: otherName},
      'participant_genders': {myUid: myGender, otherUid: otherGender},
      'participant_locations': {myUid: myCountry, otherUid: otherCountry},
      'participant_ages': {myUid: myAge, otherUid: otherAge},
      'last_message': '',
      'last_message_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'chat_id', ignoreDuplicates: true);
    return chatId;
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
    // Validasi tipe pesan
    if (!['text', 'image', 'view_once'].contains(type)) {
      throw Exception('Invalid message type');
    }
    // Validasi image data jika ada
    if (imageData.isNotEmpty && !isValidImageBase64(imageData)) {
      throw Exception('Invalid image data');
    }
    // Batasi panjang teks pesan
    if (text.length > 2000) {
      throw Exception('Message too long (max 2000 chars)');
    }

    await _sb.from('private_messages').insert({
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_gender': senderGender,
      'text': text,
      'type': type,
      'image_data': imageData,
    });

    final update = <String, dynamic>{
      'last_message': type == 'image' || type == 'view_once' ? '[Foto]' : text,
      'last_message_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _sb.from('private_chats').update(update).eq('chat_id', chatId);
  }

  /// Hapus image_data dari view_once message setelah dilihat.
  /// Data foto dihapus dari DB — hanya metadata yang tersisa.
  Future<void> clearViewOnceImage(String messageId) async {
    try {
      await _sb.from('private_messages')
          .update({'image_data': '', 'type': 'view_once_expired'})
          .eq('id', messageId);
    } catch (_) {}
  }

  // Map: userId -> list of reload callbacks untuk getMyPrivateChats streams
  final Map<String, List<void Function()>> _chatReloaders = {};

  Future<void> markAsRead(String chatId, String uid) async {
    try {
      final chat = await _sb.from('private_chats').select('unread_counts,last_read_at')
          .eq('chat_id', chatId).maybeSingle();
      if (chat == null) return;
      final unread = Map<String, dynamic>.from(chat['unread_counts'] ?? {});
      unread[uid] = 0;
      final lastRead = Map<String, dynamic>.from(chat['last_read_at'] ?? {});
      lastRead[uid] = DateTime.now().toUtc().toIso8601String();
      await _sb.from('private_chats').update({
        'unread_counts': unread,
        'last_read_at': lastRead,
      }).eq('chat_id', chatId);
      _refreshChatStreams(uid);
    } catch (_) {}
  }

  void _refreshChatStreams(String myUid) {
    final callbacks = _chatReloaders[myUid];
    if (callbacks == null) return;
    for (final cb in List.of(callbacks)) {
      cb();
    }
  }

  void clearCachedStreams() {
    _chatReloaders.clear();
  }

  Stream<List<PrivateChatInfo>> getMyPrivateChats(String myUid) {
    final controller = StreamController<List<PrivateChatInfo>>.broadcast();

    Future<List<PrivateChatInfo>> fetch() async {
      final rows = await _sb
          .from('private_chats')
          .select()
          .contains('participants', [myUid])
          .order('last_message_at', ascending: false);
      return rows.map((row) {
        final d = snakeToCamel(row);
        return PrivateChatInfo(
          chatId: d['chatId'] ?? '',
          participants: List<String>.from(d['participants'] ?? []),
          participantNames: Map<String, String>.from(d['participantNames'] ?? {}),
          participantGenders: Map<String, String>.from(d['participantGenders'] ?? {}),
          participantLocations: Map<String, String>.from(d['participantLocations'] ?? {}),
          participantAges: (d['participantAges'] as Map<dynamic, dynamic>? ?? {})
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
          participantRegistered: (d['participantRegistered'] as Map<dynamic, dynamic>? ?? {})
              .map((k, v) => MapEntry(k.toString(), v == true)),
          lastMessage: d['lastMessage'] ?? '',
          lastMessageAt: parseDate(d['lastMessageAt']),
          unreadCounts: (d['unreadCounts'] as Map<dynamic, dynamic>? ?? {})
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
          lastReadAt: (d['lastReadAt'] as Map<dynamic, dynamic>? ?? {})
              .map((k, v) => MapEntry(k.toString(), parseDate(v))),
        );
      }).toList();
    }

    Future<void> reload() async {
      try {
        final rows = await fetch();
        if (!controller.isClosed) controller.add(rows);
      } catch (e) {
        debugPrint('[getMyPrivateChats] fetch error: $e');
      }
    }

    _chatReloaders.putIfAbsent(myUid, () => []).add(reload);

    final channel = _sb.channel('private-chats-$myUid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'private_chats',
      callback: (_) => reload(),
    );
    channel.subscribe();

    reload();

    controller.onCancel = () {
      _chatReloaders[myUid]?.remove(reload);
      _sb.removeChannel(channel);
    };

    return controller.stream;
  }

  /// Stream status realtime satu user (online/idle/offline).
  /// Pakai channel postgres changes pada profiles — ringan, hanya 1 row.
  Stream<String> getUserStatus(String uid) {
    final controller = StreamController<String>.broadcast();
    String _current = 'offline';

    Future<void> fetchStatus() async {
      try {
        final row = await _sb.from('profiles').select('status').eq('id', uid).maybeSingle();
        if (row == null || controller.isClosed) return;
        final s = row['status'] as String? ?? 'offline';
        if (s != _current) {
          _current = s;
          controller.add(_current);
        }
      } catch (_) {}
    }

    final channel = _sb.channel('user-status-$uid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'profiles',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: uid),
      callback: (payload) {
        if (controller.isClosed) return;
        final s = payload.newRecord['status'] as String? ?? 'offline';
        if (s != _current) {
          _current = s;
          controller.add(_current);
        }
      },
    );
    channel.subscribe();
    fetchStatus();

    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }

  Stream<List<UserModel>> getOnlineUsers() {
    final controller = StreamController<List<UserModel>>.broadcast();
    List<UserModel> cached = [];

    Future<void> fetchOnline() async {
      try {
        // Exclude kolom sensitif: fcm_token, ip_address
        const cols = 'id,nickname,gender,age,country,city,status,avatar,is_registered,last_seen';
        // Hanya user yang masih aktif: last_seen dalam 15 menit terakhir.
        // User yang uninstall app / akunnya hilang last_seen-nya tidak pernah
        // di-update lagi sehingga otomatis hilang dari daftar online.
        final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 15)).toIso8601String();
        final rows = await _sb
            .from('profiles')
            .select(cols)
            .neq('status', 'offline')
            .gte('last_seen', cutoff)
            .order('last_seen', ascending: false)
            .limit(200);
        cached = rows
            .map((row) => UserModel.fromMap('${row['id']}', snakeToCamel(row)))
            .toList();
        if (!controller.isClosed) controller.add(List.unmodifiable(cached));
      } catch (e) {
        debugPrint('[getOnlineUsers] fetch error: $e');
      }
    }

    // Realtime: update status user yang sudah ada di cache secara instan,
    // supaya status di list chat sinkron dengan status di private chat.
    final channel = _sb.channel('online-users-status');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'profiles',
      callback: (payload) {
        final newStatus = payload.newRecord['status'] as String?;
        final id = payload.newRecord['id'] as String?;
        final lastSeenStr = payload.newRecord['last_seen'] as String?;
        if (id == null || newStatus == null || controller.isClosed) return;
        DateTime? lastSeen;
        try {
          lastSeen = DateTime.tryParse(lastSeenStr ?? '');
        } catch (_) {}
        final idx = cached.indexWhere((u) => u.uid == id);
        if (idx >= 0) {
          cached[idx] = cached[idx].copyWith(status: newStatus, lastSeen: lastSeen);
          controller.add(List.unmodifiable(cached));
        }
      },
    );
    channel.subscribe();

    // Poll setiap 30 detik — cukup responsif untuk status online/idle/offline
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => fetchOnline());
    fetchOnline();

    controller.onCancel = () {
      timer.cancel();
      _sb.removeChannel(channel);
    };
    return controller.stream;
  }

  Stream<List<UserModel>> getOnlineUsersInRoom(String roomId) {
    return _sb
        .from('room_presence')
        .stream(primaryKey: ['room_id', 'user_id'])
        .eq('room_id', roomId)
        .map((rows) => rows.map((row) {
              final d = snakeToCamel(row);
              return UserModel(
                uid: d['userId'] ?? '',
                nickname: d['nickname'] ?? 'Anon',
                gender: d['gender'] ?? 'other',
                age: (d['age'] as num?)?.toInt() ?? 0,
                country: d['country'] ?? '',
                city: d['city'] ?? '',
                ipAddress: '',
                status: 'online',
                avatar: '',
                isRegistered: d['isRegistered'] == true,
                loginAt: DateTime.now(),
                createdAt: DateTime.now(),
                lastSeen: parseDate(d['joinedAt']),
              );
            }).toList());
  }

  Future<void> joinRoom(String roomId, UserModel user) async {
    // nickname, gender, age di-set oleh trigger DB dari profiles
    // tidak dikirim dari client untuk mencegah impersonasi
    await _sb.from('room_presence').upsert({
      'room_id': roomId,
      'user_id': user.uid,
    }, onConflict: 'room_id,user_id');
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    await _sb.from('room_presence')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', uid);
  }

  // ── Hide Chat (client-side, hanya untuk user yang menghapus) ──
  // Chat tidak dihapus dari DB, hanya disembunyikan di device ini.
  // Lawan bicara tetap melihat chat normal.

  Future<Set<String>> getHiddenChats(String myUid) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('hidden_chats_$myUid') ?? [];
    return list.toSet();
  }

  Future<void> hideChat(String myUid, String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'hidden_chats_$myUid';
    final list = prefs.getStringList(key) ?? [];
    if (!list.contains(chatId)) {
      list.add(chatId);
      await prefs.setStringList(key, list);
    }
    // Hapus cache pesan lokal untuk chat ini
    await MessageCache.instance.saveMessages('private_$chatId', []);
  }

  Stream<Map<String, int>> getRoomOnlineCounts() {
    return _sb
        .from('room_presence')
        .stream(primaryKey: ['room_id', 'user_id'])
        .map((rows) {
          final counts = <String, int>{};
          for (final row in rows) {
            final roomId = '${row['room_id']}';
            counts[roomId] = (counts[roomId] ?? 0) + 1;
          }
          return counts;
        });
  }

  // ── Block / Report ──

  Future<void> blockUser(String myUid, String blockedUid) async {
    await _sb.from('blocks').upsert({
      'blocker_id': myUid,
      'blocked_id': blockedUid,
    }, onConflict: 'blocker_id,blocked_id');
  }

  Future<void> unblockUser(String myUid, String blockedUid) async {
    await _sb.from('blocks')
        .delete()
        .eq('blocker_id', myUid)
        .eq('blocked_id', blockedUid);
  }

  Future<void> reportUser({
    required String reporterId,
    required String reportedId,
    required String reason,
  }) async {
    await _sb.from('reports').insert({
      'reporter_id': reporterId,
      'reported_id': reportedId,
      'reason': reason,
    });
  }

  Future<bool> isUserBlocked(String myUid, String otherUid) async {
    final res = await _sb.from('blocks').select('blocker_id')
        .eq('blocker_id', myUid)
        .eq('blocked_id', otherUid)
        .maybeSingle();
    return res != null;
  }

  Future<List<String>> getBlockedUids(String myUid) async {
    final res = await _sb.from('blocks').select('blocked_id')
        .eq('blocker_id', myUid);
    return res.map((r) => '${r['blocked_id']}').toList();
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
  final Map<String, int> unreadCounts;
  final Map<String, DateTime> lastReadAt;

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
    this.unreadCounts = const {},
    this.lastReadAt = const {},
  });
}
