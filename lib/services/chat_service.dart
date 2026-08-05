import 'dart:async';
import 'package:flutter/foundation.dart';
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

  /// Gabungan cache lokal (dulu, instan) + realtime server (setelahnya).
  /// Menggunakan explicit fetch + postgres changes channel (lebih reliable dari .stream()).
  Stream<List<MessageModel>> _cachedMessagesStream({
    required String cacheKey,
  }) {
    final controller = StreamController<List<MessageModel>>.broadcast();

    // Fetch langsung dari server (bukan .stream() realtime yang bermasalah)
    Future<List<MessageModel>> fetchServer() async {
      final rows = await _sb
          .from(cacheKey.startsWith('private_') ? 'private_messages' : 'messages')
          .select()
          .eq(cacheKey.startsWith('private_') ? 'chat_id' : 'room_id',
              cacheKey.split('_').skip(1).join('_'))
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
        controller.add(server);
        MessageCache.instance.saveMessages(cacheKey, server);
      } catch (e) {
        debugPrint('[_cachedMessagesStream] fetch error: $e');
      }
    }

    Future<void> loadCache() async {
      final cached = await MessageCache.instance.loadMessages(cacheKey);
      if (cached.isNotEmpty && !controller.isClosed) {
        controller.add(cached);
      }
      reload();
    }

    // Subscribe postgres changes ke table yang relevan
    final table = cacheKey.startsWith('private_') ? 'private_messages' : 'messages';
    final channelName = 'msg-${cacheKey.hashCode}';
    final channel = _sb.channel(channelName);
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) => reload(),
    );
    channel.subscribe();

    loadCache();

    controller.onCancel = () {
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
    await _sb.from('private_chats').upsert({
      'chat_id': chatId,
      'participants': [myUid, otherUid],
      'participant_names': {myUid: myName, otherUid: otherName},
      'participant_genders': {myUid: myGender, otherUid: otherGender},
      'participant_locations': {myUid: myCountry, otherUid: otherCountry},
      'participant_ages': {myUid: myAge, otherUid: otherAge},
      'last_message': '',
      'last_message_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'chat_id');
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
      'last_message': type == 'image' ? '[Foto]' : text,
      'last_message_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _sb.from('private_chats').update(update).eq('chat_id', chatId);
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

  Stream<List<UserModel>> getOnlineUsers() {
    return _sb
        .from('profiles')
        .stream(primaryKey: ['id'])
        .neq('status', 'offline')
        .order('last_seen', ascending: false)
        .limit(200)
        .map((rows) => rows
            .map((row) => UserModel.fromMap('${row['id']}', snakeToCamel(row)))
            .toList());
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
                loginAt: DateTime.now(),
                createdAt: DateTime.now(),
                lastSeen: parseDate(d['joinedAt']),
              );
            }).toList());
  }

  Future<void> joinRoom(String roomId, UserModel user) async {
    await _sb.from('room_presence').upsert({
      'room_id': roomId,
      'user_id': user.uid,
      'nickname': user.nickname,
      'gender': user.gender,
      'age': user.age,
    }, onConflict: 'room_id,user_id');
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    await _sb.from('room_presence')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', uid);
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
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCounts = const {},
    this.lastReadAt = const {},
  });
}
