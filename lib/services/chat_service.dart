import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../config/supabase_config.dart';
import '../services/message_cache.dart';
import '../services/photo_cache.dart';
import '../utils.dart';

class ChatService {
  final SupabaseClient _sb = SupabaseConfig.client;

  // ── Room Chat ──

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

    // Private chat: cutoff waktu delete — pesan lama (<= cutoff) tidak
    // pernah ditampilkan lagi untuk user yang menghapus, meski ada di server.
    DateTime? _hiddenCutoff;

    // Kapan terakhir realtime "hidup" — poll skip kalau masih fresh.
    DateTime lastRealtime = DateTime.now();

    // Cache write di-debounce (2s) + skip kalau data tidak berubah,
    // supaya tidak encrypt & tulis SharedPreferences tiap pesan / tiap poll.
    Timer? saveDebounce;
    String? lastSavedSig;

    void scheduleCacheSave() {
      if (controller.isClosed || _current.isEmpty) return;
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

    // Kolom tanpa image_data — foto diambil terpisah (PhotoCache / download
    // lazy) supaya buka chat tetap cepat walau ada ratusan foto.
    const baseCols = 'id,sender_id,sender_name,sender_gender,text,type,is_registered,created_at';
    const replyCols = 'replied_to_id,replied_to_text,replied_to_sender_name';
    final cols = isPrivate ? '$baseCols,$replyCols' : baseCols;

    // Sync foto otomatis: server → file lokal terenkripsi. Download lazy
    // (2-3 paralel) hanya untuk pesan yang fotonya belum ada di lokal.
    final photoQueue = <MessageModel>[];
    var downloading = 0;
    const maxConcurrentPhotos = 3;

    Future<void> _drainPhotoQueue() async {
      while (photoQueue.isNotEmpty && downloading < maxConcurrentPhotos) {
        final m = photoQueue.removeAt(0);
        downloading++;
        try {
          final row = await _sb
              .from(table)
              .select('image_data')
              .eq('id', m.id)
              .maybeSingle();
          final data = row?['image_data'] as String? ?? '';
          if (data.isNotEmpty) {
            await PhotoCache.instance.save(cacheKey, m.id, data);
            if (controller.isClosed) return;
            final idx = _current.indexWhere((x) => x.id == m.id);
            if (idx >= 0 && _current[idx].imageData.isEmpty) {
              _current[idx] = _current[idx].copyWith(imageData: data);
              controller.add(List.unmodifiable(_current));
              scheduleCacheSave();
            }
          }
        } catch (e) {
          debugPrint('[photo download] ${m.id} error: $e');
        } finally {
          downloading--;
        }
      }
    }

    void queuePhotoDownload(MessageModel m) {
      if (photoQueue.any((q) => q.id == m.id)) return;
      photoQueue.add(m);
      _drainPhotoQueue();
    }

    // Isi imageData dari file lokal (paralel); yang belum ada → antri download.
    Future<List<MessageModel>> withLocalPhotos(List<MessageModel> models) async {
      return Future.wait(models.map((m) async {
        if (m.type != 'image' && m.type != 'view_once' && m.type != 'view_once_expired') return m;
        final cached = await PhotoCache.instance.load(cacheKey, m.id);
        if (cached != null) return m.copyWith(imageData: cached);
        queuePhotoDownload(m);
        return m.copyWith(imageData: '');
      }));
    }

    Future<List<MessageModel>> fetchServer() async {
      final rows = await _sb
          .from(table)
          .select(cols)
          .eq(filterKey, filterVal)
          .order('created_at', ascending: true)
          .limit(100);
      final models = rows
          .map((row) => MessageModel.fromMap('${row['id']}', snakeToCamel(row)))
          .toList();
      return withLocalPhotos(models);
    }

    // Ambil cutoff delete user ini (UTC → local). null = tidak pernah delete.
    Future<DateTime?> fetchHiddenCutoff() async {
      if (!isPrivate) return null;
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return null;
      try {
        final row = await _sb
            .from('private_chats')
            .select('hidden_at')
            .eq('chat_id', filterVal)
            .maybeSingle();
        if (row == null) return null;
        final map = (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {};
        final v = map[uid];
        if (v == null) return null;
        return DateTime.tryParse('$v')?.toLocal();
      } catch (_) {
        return null;
      }
    }

    Future<void> reload() async {
      try {
        final server = await fetchServer();
        if (controller.isClosed) return;
        if (isPrivate) {
          _hiddenCutoff = await fetchHiddenCutoff();
          if (_hiddenCutoff != null) {
            server.removeWhere((m) => !m.timestamp.isAfter(_hiddenCutoff!));
          }
        }
        _current = server;
        controller.add(_current);
        scheduleCacheSave();
      } catch (e) {
        debugPrint('[_cachedMessagesStream] fetch error: $e');
        // Fallback: tampilkan cache hanya kalau server gagal
        MessageCache.instance.loadMessages(cacheKey).then((cached) async {
          if (cached.isNotEmpty && !controller.isClosed && _current.isEmpty) {
            final filled = await withLocalPhotos(cached);
            if (controller.isClosed) return;
            _current = filled;
            controller.add(_current);
          }
        });
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
          if (_hiddenCutoff != null && !msg.timestamp.isAfter(_hiddenCutoff!)) return;
          // Foto dari realtime langsung di-sync ke file lokal (fire-and-forget)
          if (msg.imageData.isNotEmpty) {
            PhotoCache.instance.save(cacheKey, msg.id, msg.imageData).catchError((_) {});
          } else if (msg.type == 'image' || msg.type == 'view_once' || msg.type == 'view_once_expired') {
            queuePhotoDownload(msg);
          }
          _current = [..._current, msg];
          lastRealtime = DateTime.now();
          debugPrint('[DEBUG-READ] realtime INSERT table=$table msg=${msg.id} filter=$filterVal');
          controller.add(_current);
          scheduleCacheSave();
        } catch (_) {
          reload();
        }
      },
    );
    // UPDATE: parse payload untuk update partial (jangan refetch full)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: table,
      callback: (payload) {
        lastRealtime = DateTime.now();
        try {
          final newRecord = payload.newRecord;
          if (newRecord['id'] == null) { reload(); return; }
          final idx = _current.indexWhere((x) => x.id == newRecord['id']);
          if (idx < 0) { reload(); return; }
          final updated = _current[idx].copyWith(
            imageData: newRecord['image_data'] as String?,
          );
          _current[idx] = updated;
          controller.add(List.unmodifiable(_current));
          scheduleCacheSave();
        } catch (_) {
          reload();
        }
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

  /// Cek apakah user masih aktif (akun tidak dihapus).
  /// Dipakai sebelum startPrivateChat — policy RLS menolak insert chat
  /// kalau salah satu participant sudah tidak ada di profiles.
  Future<bool> isUserActive(String uid) async {
    try {
      final row = await _sb
          .from('profiles')
          .select('id')
          .eq('id', uid)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

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

    // Kirim pesan = chat muncul lagi di list (history lama tetap disembunyikan)
    await unhideChat(senderId, chatId);

    await _sb.from('private_messages').insert({
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_gender': senderGender,
      'text': text,
      'type': type,
      'image_data': imageData,
      if (repliedToId != null) 'replied_to_id': repliedToId,
      if (repliedToText != null) 'replied_to_text': repliedToText,
      if (repliedToSenderName != null) 'replied_to_sender_name': repliedToSenderName,
    });
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
  // Cache stream per myUid agar tidak buat channel baru tiap subscribe
  final Map<String, StreamController<List<PrivateChatInfo>>> _privateChatsStreams = {};

  Future<void> markAsRead(String chatId, String uid) async {
    try {
      await _sb.rpc('mark_chat_read', params: {'p_chat_id': chatId, 'p_uid': uid});
      debugPrint('[DEBUG-READ] RPC ok chat=$chatId uid=$uid');
      _refreshChatStreams(uid);
    } catch (e) {
      debugPrint('[DEBUG-READ] RPC FAIL chat=$chatId uid=$uid err=$e');
    }
  }

  // ── Typing Indicator ──
  // Pakai realtime broadcast (ephemeral, tanpa tabel DB). Event 'typing'
  // dikirim ke channel per-chat; penerima hanya menampilkan kalau pengirimnya
  // bukan diri sendiri (broadcast ikut ter-echo ke pengirim).

  final Map<String, RealtimeChannel> _typingChannels = {};

  RealtimeChannel _typingChannel(String chatId) {
    return _typingChannels.putIfAbsent(chatId, () {
      final ch = _sb.channel('typing-$chatId');
      ch.subscribe();
      return ch;
    });
  }

  /// Stream event typing lawan bicara di satu chat.
  Stream<void> getTypingStream(String chatId) {
    final controller = StreamController<void>.broadcast();
    final channel = _typingChannel(chatId);
    channel.onBroadcast(event: 'typing', callback: (payload) {
      final senderId = payload['sender_id'] as String?;
      if (senderId == null || senderId == _sb.auth.currentUser?.id) return;
      if (!controller.isClosed) controller.add(null);
    });
    controller.onCancel = () {
      _typingChannels.remove(chatId);
      _sb.removeChannel(channel);
    };
    return controller.stream;
  }

  /// Kirim sinyal typing (throttle dilakukan di screen).
  void sendTyping(String chatId) {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    _typingChannel(chatId).sendBroadcastMessage(
      event: 'typing',
      payload: {
        'sender_id': uid,
        'ts': DateTime.now().millisecondsSinceEpoch,
      },
    ).catchError((_) => ChannelResponse.error);
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
    for (final c in _privateChatsStreams.values) {
      if (!c.isClosed) c.close();
    }
    _privateChatsStreams.clear();
  }

  Stream<List<PrivateChatInfo>> getMyPrivateChats(String myUid) {
    // Cache: kembali stream yang sudah ada agar channel Supabase
    // tidak dilipatgandakan tiap subscribe/didChange berikutnya.
    final existing = _privateChatsStreams[myUid];
    if (existing != null && !existing.isClosed) return existing.stream;

    final controller = StreamController<List<PrivateChatInfo>>.broadcast();
    _privateChatsStreams[myUid] = controller;

    Future<List<PrivateChatInfo>> fetch() async {
      final rows = await _sb
          .from('private_chats')
          .select()
          .contains('participants', [myUid])
          .order('last_message_at', ascending: false)
          .limit(200);
      print('[DEBUG-CHATLIST] FETCH for $myUid, got ${rows.length} rows');
      for (final r in rows) {
        print('[DEBUG-CHATLIST]   chat=${r['chat_id']} last=${r['last_message']}');
      }
      Set<String> hiddenSet = {};
      try {
        hiddenSet = await getHiddenChats(myUid);
      } catch (_) {}
      return rows
          .where((row) => !hiddenSet.contains(row['chat_id']))
          .map((row) {
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
        debugPrint('[getMyPrivateChats] fetched ${rows.length} chats for $myUid');
        if (!controller.isClosed) controller.add(rows);
      } catch (e) {
        debugPrint('[getMyPrivateChats] fetch error for $myUid: $e');
      }
    }

    _chatReloaders.putIfAbsent(myUid, () => []).add(reload);

    // Nama channel harus UNIK per instance — getMyPrivateChats bisa disubscribe
    // dari 2 screen sekaligus (list chat + layar chat); nama sama = join gagal,
    // event realtime tidak pernah sampai (centang baca jadi tidak update).
    final instanceId = DateTime.now().microsecondsSinceEpoch;
    final channel = _sb.channel('private-chats-$myUid-$instanceId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'private_chats',
      callback: (_) => reload(),
    );
    channel.subscribe();

    // Pesan BARU masuk untuk chat yang aku hapus (hidden) → chat muncul lagi
    // di list, tapi hanya pesan setelah cutoff yang akan tampil isinya.
    final msgChannel = _sb.channel('private-chats-msg-$myUid-$instanceId');
    msgChannel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'private_messages',
      callback: (payload) async {
        final chatId = payload.newRecord['chat_id'] as String?;
        if (chatId == null) return;
        try {
          final row = await _sb
              .from('private_chats')
              .select('hidden_by,hidden_at')
              .eq('chat_id', chatId)
              .maybeSingle();
          if (row == null) return;
          final hidden = List<String>.from((row['hidden_by'] as List<dynamic>?) ?? []);
          if (!hidden.contains(myUid)) return;
          final hm = (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {};
          final cutoffStr = hm[myUid];
          final msgStr = payload.newRecord['created_at'] as String?;
          if (cutoffStr != null && msgStr != null) {
            final cutoff = DateTime.tryParse('$cutoffStr');
            final msgAt = DateTime.tryParse(msgStr);
            if (cutoff == null || msgAt == null || !msgAt.isAfter(cutoff)) return;
          }
          await unhideChat(myUid, chatId);
          reload();
        } catch (_) {}
      },
    );
    msgChannel.subscribe();

    reload();

    controller.onCancel = () {
      _chatReloaders[myUid]?.remove(reload);
      if (_chatReloaders[myUid]?.isEmpty == true) _chatReloaders.remove(myUid);
      _sb.removeChannel(channel);
      _sb.removeChannel(msgChannel);
      final cached = _privateChatsStreams[myUid];
      if (cached == controller) _privateChatsStreams.remove(myUid);
    };

    return controller.stream;
  }

  /// Stream status realtime satu user (online/idle/offline).
  /// Pakai channel postgres changes pada profiles — ringan, hanya 1 row.
  /// Status dihitung efektif: last_seen basi (> 15 menit) dianggap offline,
  /// supaya sinkron dengan daftar pengguna online di list chat.
  Stream<String> getUserStatus(String uid) {
    final controller = StreamController<String>.broadcast();
    String _current = 'offline';

    String effectiveStatus(String? rawStatus, String? lastSeenStr) {
      final s = rawStatus ?? 'offline';
      if (s == 'offline') return 'offline';
      final lastSeen = DateTime.tryParse(lastSeenStr ?? '');
      if (lastSeen == null) return 'offline';
      final stale = lastSeen.toUtc().isBefore(
            DateTime.now().toUtc().subtract(const Duration(minutes: 15)),
          );
      return stale ? 'offline' : s;
    }

    Future<void> fetchStatus() async {
      try {
        final row = await _sb
            .from('profiles')
            .select('status,last_seen')
            .eq('id', uid)
            .maybeSingle();
        if (row == null || controller.isClosed) return;
        final s = effectiveStatus(row['status'] as String?, row['last_seen'] as String?);
        if (s != _current) {
          _current = s;
          controller.add(_current);
        }
      } catch (e) {
        debugPrint('[chat] fetchStatus error: $e');
      }
    }

    final channel = _sb.channel('user-status-$uid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'profiles',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: uid),
      callback: (payload) {
        if (controller.isClosed) return;
        final s = effectiveStatus(
          payload.newRecord['status'] as String?,
          payload.newRecord['last_seen'] as String?,
        );
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

  // ── Hide Chat (soft-delete via server) ──
  // Chat ditandai hidden_by + hidden_at (cutoff) di DB, tidak dihapus.
  // Lawan bicara tetap melihat chat normal (tanpa cutoff).
  // History sebelum cutoff tidak pernah tampil lagi untuk user yang menghapus;
  // hanya pesan BARU setelah cutoff yang muncul saat chat terbuka lagi.

  Future<void> hideChat(String myUid, String chatId) async {
    final row = await _sb
        .from('private_chats')
        .select('hidden_by,hidden_at')
        .eq('chat_id', chatId)
        .maybeSingle();
    if (row == null) return;
    final hidden = List<String>.from((row['hidden_by'] as List<dynamic>?) ?? []);
    final hiddenAt =
        Map<String, dynamic>.from((row['hidden_at'] as Map<dynamic, dynamic>?) ?? {});
    if (!hidden.contains(myUid)) hidden.add(myUid);
    // Cutoff selalu di-refresh — pesan sebelum waktu delete terbaru
    // tetap tidak tampil walau chat sudah pernah muncul lagi sebelumnya.
    hiddenAt[myUid] = DateTime.now().toUtc().toIso8601String();
    await _sb
        .from('private_chats')
        .update({'hidden_by': hidden, 'hidden_at': hiddenAt})
        .eq('chat_id', chatId);
  }

  Future<void> unhideChat(String myUid, String chatId) async {
    final row = await _sb
        .from('private_chats')
        .select('hidden_by')
        .eq('chat_id', chatId)
        .maybeSingle();
    if (row == null) return;
    final hidden = List<String>.from((row['hidden_by'] as List<dynamic>?) ?? []);
    if (hidden.remove(myUid)) {
      await _sb
          .from('private_chats')
          .update({'hidden_by': hidden})
          .eq('chat_id', chatId);
    }
  }

  Future<Set<String>> getHiddenChats(String myUid) async {
    try {
      final rows = await _sb.from('private_chats').select('chat_id').contains('hidden_by', [myUid]);
      return rows.map((r) => r['chat_id'] as String).toSet();
    } catch (_) {
      return {};
    }
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
