import 'dart:async';
import 'package:flutter/foundation.dart';
import 'media_disk_cache.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../config/supabase_config.dart';
import 'realtime_hub.dart';
import '../config/gifts.dart';
import '../services/message_cache.dart';
import '../services/photo_cache.dart';
import '../services/storage_photo_service.dart';
import '../utils.dart';
import 'notification_prefs_service.dart';
import 'chat_stream_session.dart';

export 'chat_stream_session.dart';

class ChatService {
  final SupabaseClient _sb = SupabaseConfig.client;

  // Cache avatar (path → base64) — hindari download ulang tiap fetch online.
  static final Map<String, String> _avatarCache = {};
  static const _avatarCacheMax = 100;

  // Country user sendiri (sekali per sesi) — untuk shard merge online (K6).
  String? _ownCountryCache;
  // Setting invisible (sekali per sesi, TTL 5 mnt) — sync presence tidak
  // perlu fetch app_settings tiap tick.
  String? _invisibleUidCache;
  DateTime? _invisibleFetchedAt;
  Future<String?> _fetchInvisibleUid() async {
    final last = _invisibleFetchedAt;
    if (last != null &&
        DateTime.now().difference(last).inMinutes < 5) {
      return _invisibleUidCache;
    }
    try {
      final setting = await _sb
          .from('app_settings')
          .select('invisible_enabled,invisible_admin_uid')
          .eq('id', 'global')
          .maybeSingle()
          .timeout(const Duration(seconds: 2));
      _invisibleFetchedAt = DateTime.now();
      final enabled = setting?['invisible_enabled'];
      if (enabled == true) {
        final v = setting?['invisible_admin_uid'];
        _invisibleUidCache = v is String ? v : null;
      } else {
        _invisibleUidCache = null;
      }
    } catch (_) {}
    return _invisibleUidCache;
  }

  // UID dummy (TTL 5 mnt) — dummy tak punya socket presence, jadi filter
  // presence cross-reference butuh daftar ini supaya dummy idle tetap tampil.
  Set<String>? _dummyUidCache;
  DateTime? _dummyUidFetchedAt;
  Future<Set<String>> _fetchDummyUids() async {
    final last = _dummyUidFetchedAt;
    if (last != null &&
        DateTime.now().difference(last).inMinutes < 5 &&
        _dummyUidCache != null) {
      return _dummyUidCache!;
    }
    try {
      final rows = await _sb
          .from('dummy_accounts')
          .select('uid')
          .timeout(const Duration(seconds: 2));
      _dummyUidCache = {
        for (final r in rows as List) '${(r as Map)['uid'] ?? ''}',
      }..remove('');
      _dummyUidFetchedAt = DateTime.now();
    } catch (_) {}
    return _dummyUidCache ?? <String>{};
  }

  Future<String?> _fetchOwnCountry() async {
    if (_ownCountryCache != null) return _ownCountryCache;
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) return null;
      final row = await _sb
          .from('profiles')
          .select('country')
          .eq('id', me)
          .maybeSingle()
          .timeout(const Duration(seconds: 2));
      final c = (row?['country'] as String?)?.trim();
      if (c != null && c.isNotEmpty) _ownCountryCache = c;
    } catch (_) {}
    return _ownCountryCache;
  }

  /// Salinan key cache avatar — dipakai unit test untuk mengunci batas
  /// [_avatarCacheMax] (dulu tumbuh tanpa batas per user yang pernah online).
  @visibleForTesting
  static Set<String> get avatarCacheKeys => _avatarCache.keys.toSet();

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

  Future<String> _avatarB64(String path) async {
    final cached = _avatarCache[path];
    if (cached != null) {
      // LRU sejati: yang baru dibaca pindah ke ujung (tahan dari eviction).
      _avatarCache.remove(path);
      _avatarCache[path] = cached;
      return cached;
    }
    // DISK FIRST: baca dari cache lokal (instan, tanpa network).
    final disk = await MediaDiskCache.instance.read(path);
    if (disk != null && disk.isNotEmpty) {
      final b64 = base64Encode(disk);
      if (_avatarCache.length >= _avatarCacheMax) {
        _avatarCache.remove(_avatarCache.keys.first);
      }
      _avatarCache[path] = b64;
      return b64;
    }
    // Disk miss → download server → TULIS KE DISK (sumber lokal berikutnya).
    final b64 = await StoragePhotoService.instance.download(path) ?? '';
    if (b64.isNotEmpty) {
      try {
        await MediaDiskCache.instance
            .write(path, Uint8List.fromList(base64Decode(b64)));
      } catch (_) {}
      if (_avatarCache.length >= _avatarCacheMax) {
        _avatarCache.remove(_avatarCache.keys.first);
      }
      _avatarCache[path] = b64;
    }
    return b64;
  }

  /// Foto masih perlu diisi: imageData kosong ATAU masih path storage
  /// (belum ter-download ke base64 lokal).
  static bool _needsPhotoFill(MessageModel m) {
    if (m.imageData.isEmpty) return true;
    return StoragePhotoService.instance.isPath(m.imageData) ||
        StoragePhotoService.instance.isVoicePath(m.imageData);
  }

  /// Path voice yang sedang diunduh — cegah dobel download (prefetch
  /// riwayat + realtime arrival + tap user bisa memicu bersamaan).
  static final Set<String> _voiceDownloadInflight = {};

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

  /// Unduh audio voice message ke cache lokal (base64 via PhotoCache) —
  /// dipakai VoiceBubble untuk play offline tanpa fetch ulang.
  Future<void> _downloadVoiceToCache(String cacheKey, MessageModel msg) async {
    try {
      if (msg.imageData.isEmpty) return;
      if (!StoragePhotoService.instance.isVoicePath(msg.imageData)) return;
      final existing = await PhotoCache.instance.load(cacheKey, msg.id);
      if (existing != null && existing.isNotEmpty) {
        // Path sudah tercatat — pastikan bytes-nya juga ada di disk.
        unawaited(prefetchVoiceBytes(msg.imageData));
        return;
      }
      await PhotoCache.instance.save(cacheKey, msg.id, msg.imageData);
      unawaited(prefetchVoiceBytes(msg.imageData));
    } catch (e) {
      dlog('[ChatService] voice cache ${msg.id}: $e');
    }
  }

  // ── Room Chat ──

  ChatMessageStream getRoomMessages(String roomId) {
    return _cachedMessagesStream(cacheKey: 'room_$roomId');
  }

  Future<void> sendRoomMessage({
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
    bool isForwarded = false,
  }) async {
    // Validasi tipe pesan
    if (!['text', 'image', 'view_once', 'voice'].contains(type)) {
      throw Exception('Invalid message type');
    }
    // Validasi image/voice data jika ada — boleh base64 (lama) ATAU path storage (baru)
    if (imageData.isNotEmpty &&
        !isValidImageBase64(imageData) &&
        !StoragePhotoService.instance.isPath(imageData) &&
        !StoragePhotoService.instance.isVoicePath(imageData)) {
      throw Exception('Invalid image data');
    }
    if (type == 'text' && (text.isEmpty || text.length > 2000)) return;
    await _sb.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_gender': senderGender,
      'text': text,
      'type': type,
      'image_data': type == 'voice' ? '' : imageData,
      if (type == 'voice') 'voice_path': imageData,
      if (type == 'voice' && durationMs != null) 'duration_ms': durationMs,
      if (type == 'image' && imageData.isNotEmpty) 'image_path': imageData,
      if (repliedToId != null) 'replied_to_id': repliedToId,
      if (repliedToText != null) 'replied_to_text': repliedToText,
      if (repliedToSenderName != null) 'replied_to_sender_name': repliedToSenderName,
      if (isForwarded) 'is_forwarded': true,
    });
  }

  Future<bool> deleteRoomMessage(String messageId) async {
    try {
      await _sb.from('messages').update({'is_deleted': true}).eq('id', messageId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Edit teks pesan sendiri di room (global & private room). RLS menjamin
  /// hanya sender_id (auth.uid) yang boleh mengubah pesannya. `edited`
  /// ditandai bila kolom migrasi ada; kalau belum, fallback hanya ubah text.
  Future<bool> editRoomMessage(String messageId, String newText) async {
    try {
      await _sb
          .from('messages')
          .update({'text': newText, 'edited': true})
          .eq('id', messageId);
      return true;
    } catch (e) {
      dlog('[ChatService] editRoomMessage (with edited) error: $e');
      try {
        await _sb
            .from('messages')
            .update({'text': newText})
            .eq('id', messageId);
        return true;
      } catch (e2) {
        dlog('[ChatService] editRoomMessage (text only) error: $e2');
        return false;
      }
    }
  }

  // ── Private Chat ──

  /// Id chat 1:1 deterministik — urutan uid di-sort. Bisa dipanggil tanpa
  /// DB (fallback saat upsert gagal), hasilnya selalu sama dgn sisi lain.
  String privateChatId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  String _chatId(String uid1, String uid2) => privateChatId(uid1, uid2);

  /// Kunci cache pesan private chat (dipakai stream + prefetch). Konsisten
  /// supaya prefetch saat tap di list mengisi key yang sama dengan stream.
  static String privateCacheKey(String chatId) => 'private_$chatId';

  ChatMessageStream getPrivateChatMessages(String chatId) {
    return _cachedMessagesStream(cacheKey: privateCacheKey(chatId));
  }

  /// Prefetch pesan ke memori (fire-and-forget) — dipanggil saat user TAP
  /// item chat di list, supaya saat PrivateChatScreen mount cache sudah
  /// panas → emit frame-pertama instan (tanpa "loading pesan").
  void prefetchPrivateChat(String chatId) {
    unawaited(
      MessageCache.instance.preloadMessages(privateCacheKey(chatId)),
    );
  }

  /// Edit teks pesan sendiri di private chat. RLS menjamin hanya sender_id
  /// (auth.uid) yang boleh mengubah pesannya. `edited` ditandai true bila
  /// kolom migrasi sudah ada; kalau belum, fallback hanya ubah `text`.
  Future<bool> editPrivateMessage(String messageId, String newText) async {
    try {
      await _sb
          .from('private_messages')
          .update({'text': newText, 'edited': true})
          .eq('id', messageId);
      return true;
    } catch (e) {
      dlog('[ChatService] editPrivateMessage (with edited) error: $e');
      try {
        await _sb
            .from('private_messages')
            .update({'text': newText})
            .eq('id', messageId);
        return true;
      } catch (e2) {
        dlog('[ChatService] editPrivateMessage (text only) error: $e2');
        return false;
      }
    }
  }

  /// Hapus pesan sendiri (soft delete) — tandai is_deleted = true.
  /// RLS menjamin hanya sender_id (auth.uid) yang boleh mengubah pesannya.
  Future<bool> deletePrivateMessage(String messageId) async {
    try {
      await _sb
          .from('private_messages')
          .update({'is_deleted': true})
          .eq('id', messageId);
      return true;
    } catch (e) {
      dlog('[ChatService] deletePrivateMessage error: $e');
      return false;
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
      needsPhotoFill: _needsPhotoFill,
      downloadVoiceToCache: _downloadVoiceToCache,
      prefetchVoiceBytes: prefetchVoiceBytes,
    ).start();
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
    await _sb
        .from('private_chats')
        .upsert(
          {
            'chat_id': chatId,
            'participants': [myUid, otherUid],
            'participant_names': {myUid: myName, otherUid: otherName},
            'participant_genders': {myUid: myGender, otherUid: otherGender},
            'participant_locations': {myUid: myCountry, otherUid: otherCountry},
            'participant_ages': {myUid: myAge, otherUid: otherAge},
            'last_message': '',
            'last_message_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'chat_id',
          ignoreDuplicates: true,
        );
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
    int? durationMs,
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    bool isForwarded = false,
  }) async {
    // Validasi tipe pesan
    if (!['text', 'image', 'view_once', 'call', 'voice'].contains(type)) {
      throw Exception('Invalid message type');
    }
    // Validasi image/voice data jika ada — boleh base64 (lama) ATAU path storage (baru)
    if (type != 'call' &&
        imageData.isNotEmpty &&
        !isValidImageBase64(imageData) &&
        !StoragePhotoService.instance.isPath(imageData) &&
        !StoragePhotoService.instance.isVoicePath(imageData)) {
      throw Exception('Invalid image data');
    }
    // Batasi panjang teks pesan
    if (text.length > 2000) {
      throw Exception('Message too long (max 2000 chars)');
    }

    // Kirim pesan = chat muncul lagi di list (history lama tetap disembunyikan).
    // Optimasi: chat yang sudah tampil di list pasti tidak hidden — skip
    // unhideChat supaya kirim cukup 1 round-trip.
    final visibleInList =
        _privateChatsLast[senderId]?.any((c) => c.chatId == chatId) ?? false;
    if (!visibleInList) {
      await unhideChat(senderId, chatId);
    }

    final inserted = await _sb.from('private_messages').insert({
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_gender': senderGender,
      'text': text,
      'type': type,
      'image_data': type == 'voice' ? '' : imageData,
      if (type == 'voice') 'voice_path': imageData,
      if (type == 'voice' && durationMs != null) 'duration_ms': durationMs,
      if (type == 'image' && imageData.isNotEmpty) 'image_path': imageData,
      if (repliedToId != null) 'replied_to_id': repliedToId,
      if (repliedToText != null) 'replied_to_text': repliedToText,
      if (repliedToSenderName != null)
        'replied_to_sender_name': repliedToSenderName,
      if (isForwarded) 'is_forwarded': true,
    }).select('id').maybeSingle();
    // Pemicu AI LANGSUNG (tanpa nunggu antrean pg_net trigger yang lambat —
    // terbukti delay ~1 menit): panggil edge function fire-and-forget.
    // Trigger DB tetap jadi backup bila ini gagal; claim cegah balasan dobel.
    final insertedId = (inserted as Map?)?['id'];
    // trigger_msg_id null = invokasi melewati claim & dedupe di edge
    // function (potensi dobel-balas) — biarkan trigger DB yang menangani.
    if (insertedId != null) _invokeAiReply(chatId, senderId, insertedId);
    // Broadcast untuk skala (tanpa postgres realtime) — fire-and-forget.
    // Channel REUSE per chat (putIfAbsent) — dulu: channel baru per pesan
    // menumpuk di memori + traffic realtime makin berat di chat panjang.
    try {
      await _sendBroadcastOnce(chatId, 'new_message', {
        'chat_id': chatId,
        'sender_id': senderId,
        'sender_name': senderName,
        'sender_gender': senderGender,
        'text': text,
        'type': type,
        'image_data': type == 'voice' ? '' : imageData,
        'voice_path': type == 'voice' ? imageData : '',
        'duration_ms': durationMs ?? 0,
      });
    } catch (_) {}
  }

  /// Panggil edge function ai-reply langsung seusai kirim (fire-and-forget).
  /// Kalau lawan bicara bukan dummy AI, function langsung skip (murah).
  /// Kalau dummy AI, balasan mulai ~1-2 detik (bukan nunggu antrean pg_net).
  /// Fallback berlapis saat cache list belum hangat (mis. pesan pertama di
  /// chat baru): fetch participants server, lalu parse chat_id — JANGAN
  /// silent-skip, karena itu bikin pesan tak dibaca & tak dibalas.
  Future<void> _invokeAiReply(
    String chatId,
    String senderId,
    dynamic triggerId,
  ) async {
    try {
      String? other;
      final chats = _privateChatsLast[senderId];
      if (chats != null) {
        for (final c in chats) {
          if (c.chatId != chatId) continue;
          for (final p in c.participants) {
            if (p != senderId) {
              other = p;
              break;
            }
          }
          break;
        }
      }
      // Fallback 1: ambil participants langsung dari server.
      if (other == null) {
        try {
          final row = await _sb
              .from('private_chats')
              .select('participants')
              .eq('chat_id', chatId)
              .maybeSingle();
          final parts = (row as Map?)?['participants'];
          if (parts is List) {
            for (final p in parts) {
              if ('$p' != senderId) {
                other = '$p';
                break;
              }
            }
          }
        } catch (_) {}
      }
      // Fallback 2: chat_id 1-1 selalu format "uid1_uid2".
      if (other == null) {
        for (final p in chatId.split('_')) {
          if (p != senderId && p.isNotEmpty) {
            other = p;
            break;
          }
        }
      }
      if (other == null) return;
      await _sb.functions.invoke(
        'ai-reply',
        body: {
          'chat_id': chatId,
          'trigger_msg_id': triggerId,
          'sender_id': senderId,
          'dummy_uid': other,
        },
      );
    } catch (_) {}
  }

  final Map<String, RealtimeChannel> _privateBroadcastChannels = {};
  final Map<String, int> _privateBroadcastRefs = {};
  // uid → server path avatar (untuk kv disk cache list online; bytes ada
  // di MediaDiskCache per path — cold start memuat foto dari disk).
  final Map<String, String> _onlinePathByUid = {};

  RealtimeChannel _privateBroadcastChannel(String chatId) {
    final ch = _privateBroadcastChannels.putIfAbsent(chatId, () {
      final c = _sb.channel('private_$chatId');
      c.subscribe();
      return c;
    });
    _privateBroadcastRefs[chatId] = (_privateBroadcastRefs[chatId] ?? 0) + 1;
    return ch;
  }

  /// Kirim broadcast sekali pakai channel refcounted — acquire + release
  /// langsung supaya tidak bocor (dulu NoRef tanpa jalur release menumpuk
  /// 1 channel per chat selamanya).
  Future<void> _sendBroadcastOnce(
    String chatId,
    String event,
    Map<String, dynamic> payload,
  ) async {
    final ch = _privateBroadcastChannel(chatId);
    try {
      await ch.sendBroadcastMessage(event: event, payload: payload);
    } catch (_) {
    } finally {
      releasePrivateChannel(chatId);
    }
  }

  /// Lepas satu pemakai channel broadcast; hapus channel saat tak dipakai.
  void releasePrivateChannel(String chatId) {
    final n = (_privateBroadcastRefs[chatId] ?? 1) - 1;
    if (n <= 0) {
      _privateBroadcastRefs.remove(chatId);
      final ch = _privateBroadcastChannels.remove(chatId);
      if (ch != null) _sb.removeChannel(ch);
    } else {
      _privateBroadcastRefs[chatId] = n;
    }
  }

  /// Kirim koin ke lawan bicara. Server yang memvalidasi & memotong koin.
  /// Return {ok, points}. Lempar PostgrestException bila gagal.
  Future<Map<String, dynamic>> sendCoins(
    String chatId,
    String receiverId,
    int amount,
  ) async {
    final res = await _sb.rpc(
      'send_coins',
      params: {
        'p_chat_id': chatId,
        'p_receiver_id': receiverId,
        'p_amount': amount,
      },
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Kirim hadiah (gift) ke lawan bicara. Server memotong koin pengirim,
  /// ambil platform cut, kredit net ke penerima. Return {ok, points, net, cut}.
  Future<Map<String, dynamic>> sendGift(
    String chatId,
    String receiverId,
    String giftId,
  ) async {
    final res = await _sb.rpc(
      'send_gift',
      params: {
        'p_chat_id': chatId,
        'p_receiver_id': receiverId,
        'p_gift_id': giftId,
      },
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Kirim hadiah di room (live) ke host/owner. Server memotong koin
  /// pengirim (bucket bonus→topup→earned), ambil platform cut, kredit
  /// net ke owner, lalu insert pesan bukti type='gift' di room feed.
  /// Return {ok, points, gift, qty, gross, net, cut}.
  Future<Map<String, dynamic>> sendRoomGift(
    String roomId,
    String giftId, {
    int qty = 1,
  }) async {
    final res = await _sb.rpc(
      'send_room_gift',
      params: {
        'p_room_id': roomId,
        'p_gift_id': giftId,
        'p_qty': qty,
      },
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Daftar hadiah dari server (fallback ke katalog lokal bila gagal).
  Future<List<Map<String, dynamic>>> listGifts() async {
    try {
      final res = await _sb.rpc('list_gifts');
      if (res is List) return res.cast<Map<String, dynamic>>();
    } catch (e) {
      dlog('[ChatService] listGifts fallback local: $e');
    }
    return kGiftCatalog
        .map(
          (g) => {
            'id': g.id,
            'emoji': g.emoji,
            'name_id': g.nameId,
            'name_en': g.nameEn,
            'coins': g.coins,
          },
        )
        .toList();
  }

  /// Tandai view_once message sebagai expired setelah dilihat.
  /// image_data DIKEEP di DB (admin masih bisa melihat) — hanya type yang
  /// diubah. Kontrol "boleh lihat/tidak" dilakukan di sisi UI.
  Future<void> clearViewOnceImage(
    String messageId, {
    bool isRoom = false,
  }) async {
    try {
      await _sb
          .from(isRoom ? 'messages' : 'private_messages')
          .update({'type': 'view_once_expired'})
          .eq('id', messageId);
    } catch (e) {
      dlog('[ChatService] expireViewOnce error: $e');
    }
  }

  // Map: userId -> list of reload callbacks untuk getMyPrivateChats streams
  final Map<String, List<void Function()>> _chatReloaders = {};
  // Cache stream per myUid agar tidak buat channel baru tiap subscribe
  final Map<String, StreamController<List<PrivateChatInfo>>>
  _privateChatsStreams = {};
  // Snapshot terakhir per myUid — dikirim ke subscriber baru (mis. balik ke
  // sub-tab Pesan) supaya list langsung tampil tanpa spinner broadcast-miss.
  final Map<String, List<PrivateChatInfo>> _privateChatsLast = {};
  // Chat yang di-hide per myUid — dipakai pesan masuk untuk skip query.
  final Map<String, Set<String>> _privateChatsHidden = {};
  // Waktu reload terakhir per myUid — dipakai untuk skip refetch 500 row
  // saat sub-tab Pesan di-mount ulang dan snapshot realtime masih fresh.
  final Map<String, DateTime> _lastChatReloadAt = {};

  Future<void> markAsRead(String chatId, String uid) async {
    try {
      await _sb.rpc(
        'mark_chat_read',
        params: {'p_chat_id': chatId, 'p_uid': uid},
      );
      // Update snapshot lokal langsung (tanpa refetch 500 row) — event
      // realtime dari RPC ini menyusul dan menyinkronkan via _applyChatEvent.
      _applyLocalRead(uid, chatId);
    } catch (e) {
      dlog('[DEBUG-READ] RPC FAIL chat=$chatId uid=$uid err=$e');
    }
  }

  /// Tandai dibaca atas nama peserta dari monitor admin. Pakai RPC khusus
  /// (SECURITY DEFINER + guard admin) karena akun admin bukan participant,
  /// sehingga mark_chat_read biasa (RLS participants) tidak mengubah apa-apa.
  Future<void> markAsReadAdmin(String chatId, String uid) async {
    try {
      await _sb.rpc(
        'admin_mark_chat_read',
        params: {'p_chat_id': chatId, 'p_uid': uid},
      );
      _applyLocalRead(uid, chatId);
    } catch (e) {
      dlog('[DEBUG-READ-ADMIN] RPC FAIL chat=$chatId uid=$uid err=$e');
    }
  }

  /// Persist list chat (debounced) — supaya setelah app ditutup lalu dibuka
  /// lagi, list tampil instan dari cache sebelum fetch server menyusul.
  final Map<String, Timer> _chatListSaveTimers = {};

  void _scheduleChatListSave(String myUid) {
    _chatListSaveTimers[myUid]?.cancel();
    _chatListSaveTimers[myUid] = Timer(const Duration(seconds: 2), () {
      final rows = _privateChatsLast[myUid];
      if (rows == null || rows.isEmpty) return;
      MessageCache.instance
          .saveRawList(myUid, rows.map((c) => c.toMap()).toList());
    });
  }

  /// Update unread/lastRead di snapshot lokal list chat — UI instan tanpa
  /// refetch. Snapshot tetap akurat karena realtime mengirim row lengkap.
  void _applyLocalRead(String myUid, String chatId) {
    final last = _privateChatsLast[myUid];
    if (last == null) return;
    final idx = last.indexWhere((c) => c.chatId == chatId);
    if (idx < 0) return;
    final chat = last[idx];
    if ((chat.unreadCounts[myUid] ?? 0) == 0) return;
    final updated = chat.copyWith(
      unreadCounts: {...chat.unreadCounts, myUid: 0},
      lastReadAt: {...chat.lastReadAt, myUid: DateTime.now()},
    );
    final list = List.of(last)..[idx] = updated;
    _privateChatsLast[myUid] = list;
    _lastChatReloadAt[myUid] = DateTime.now();
    _scheduleChatListSave(myUid);
    final controller = _privateChatsStreams[myUid];
    if (controller != null && !controller.isClosed) controller.add(list);
  }

  /// Terapkan row private_chats dari payload realtime ke snapshot lokal —
  /// tanpa query tambahan. Row dikirim lengkap oleh Supabase Realtime.
  void _applyChatEvent(String myUid, Map<String, dynamic> row) {
    final chat = _rowToPrivateChat(row);
    final hiddenBy = List<String>.from(
      (row['hidden_by'] as List<dynamic>?) ?? [],
    );
    if (hiddenBy.contains(myUid)) {
      _privateChatsHidden.putIfAbsent(myUid, () => {}).add(chat.chatId);
      _removeLocalChat(myUid, chat.chatId);
      return;
    }
    _privateChatsHidden[myUid]?.remove(chat.chatId);
    if (chat.messageCount <= 0) {
      _removeLocalChat(myUid, chat.chatId);
      return;
    }
    final last = _privateChatsLast[myUid] ?? [];
    final idx = last.indexWhere((c) => c.chatId == chat.chatId);
    final List<PrivateChatInfo> list;
    if (idx >= 0) {
      list = List.of(last)..[idx] = chat;
    } else {
      list = [chat, ...last];
    }
    // Jaga urutan: pinned dulu (by pinnedAt), baru lastMessageAt
    list.sort((a, b) => _comparePinned(a, b, myUid));
    _privateChatsLast[myUid] = list;
    _lastChatReloadAt[myUid] = DateTime.now();
    _scheduleChatListSave(myUid);
    final controller = _privateChatsStreams[myUid];
    if (controller != null && !controller.isClosed) controller.add(list);
  }

  void _removeLocalChat(String myUid, String chatId) {
    // Hard delete (mis. admin hapus chat di monitor) harus ikut menguap
    // dari disk user — kalau tidak, pesan lama bangkit lagi dari cache
    // saat buka offline. Fire-and-forget: jangan tahan stream list.
    final cacheKey = 'private_$chatId';
    MessageCache.instance.saveMessages(cacheKey, []).catchError((_) {});
    PhotoCache.instance.clearChat(cacheKey).catchError((_) {});
    final last = _privateChatsLast[myUid];
    if (last == null) return;
    final idx = last.indexWhere((c) => c.chatId == chatId);
    if (idx < 0) return;
    final list = List.of(last)..removeAt(idx);
    _privateChatsLast[myUid] = list;
    _lastChatReloadAt[myUid] = DateTime.now();
    _scheduleChatListSave(myUid);
    final controller = _privateChatsStreams[myUid];
    if (controller != null && !controller.isClosed) controller.add(list);
  }

  // ── Typing Indicator ──
  // Pakai realtime broadcast (ephemeral, tanpa tabel DB). Event 'typing'
  // dikirim ke channel per-chat; penerima hanya menampilkan kalau pengirimnya
  // bukan diri sendiri (broadcast ikut ter-echo ke pengirim).

  final Map<String, RealtimeChannel> _typingChannels = {};
  final Map<String, int> _typingRefs = {};
  // Fan-out: SATU onBroadcast per channel → semua controller subscriber.
  // Dulu tiap getTypingPulseStream daftar callback baru ke channel yang sama
  // (resubscribe tiap pesan = callback menumpuk).
  final Map<String, Set<StreamController<(String, int)>>> _typingSubs = {};

  RealtimeChannel _typingChannel(String chatId) {
    // Batalkan grace-removal bila subscribe lagi sebelum timer jalan.
    _typingGrace[chatId]?.cancel();
    _typingGrace.remove(chatId);
    final ch = _typingChannelRaw(chatId);
    _typingRefs[chatId] = (_typingRefs[chatId] ?? 0) + 1;
    return ch;
  }

  void _fanoutTyping(String chatId, Map<String, dynamic> raw) {
    // Struktur callback bisa NESTED ({event, payload:{...}, type}) atau
    // FLAT ({sender_id, kind, ts}) tergantung versi realtime_client —
    // handle keduanya. Dulu: selalu baca top-level → sender_id null →
    // indikator typing TIDAK PERNAH tampil (AI & manusia).
    final Map<String, dynamic> data;
    if (raw['payload'] is Map) {
      data = Map<String, dynamic>.from(raw['payload'] as Map);
    } else {
      data = Map<String, dynamic>.from(raw);
    }
    final senderId = data['sender_id'] as String?;
    final myId = _sb.auth.currentUser?.id;
    if (senderId == null || senderId == myId) {
      debugPrint('[TYPING] fanout drop chat=$chatId sender=$senderId me=$myId keys=${data.keys.toList()}');
      return;
    }
    final ts = (data['ts'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final subs = _typingSubs[chatId];
    if (subs == null || subs.isEmpty) {
      debugPrint('[TYPING] fanout no-subs chat=$chatId (bubble tak bisa tampil)');
      return;
    }
    debugPrint('[TYPING] fanout ok chat=$chatId subs=${subs.length}');
    for (final c in subs.toList()) {
      if (!c.isClosed) c.add(((data['kind'] as String?) ?? 'typing', ts));
    }
  }

  /// Channel typing untuk kirim fire-and-forget (tanpa refcount).
  /// PENTING: harus memakai jalur yang SAMA dengan [_typingChannel] supaya
  /// channel selalu punya handler onBroadcast — kalau tidak, channel "buta"
  /// yang terbuat di sini akan dipakai ulang oleh subscriber dan bubble
  /// "titik 3" tak pernah tampil (bug: putIfAbsent ke map yang sama).
  RealtimeChannel _typingChannelNoRef(String chatId) {
    return _typingChannelRaw(chatId);
  }

  /// Buat/ambil channel typing TANPA menyentuh refcount. Selalu memasang
  /// handler + subscribe dengan urutan yang benar (handler dulu).
  RealtimeChannel _typingChannelRaw(String chatId) {
    final existing = _typingChannels[chatId];
    if (existing != null) return existing;
    final c = _sb.channel('typing-$chatId');
    c.onBroadcast(
      event: 'typing',
      callback: (raw) {
        debugPrint('[TYPING] onBroadcast chat=$chatId raw=$raw');
        _fanoutTyping(chatId, raw);
      },
    );
    c.subscribe((status, error) {
      debugPrint('[TYPING] subscribe $chatId -> $status err=$error');
    });
    _typingChannels[chatId] = c;
    return c;
  }

  /// Lepas satu pemakai channel typing; hapus channel saat tak dipakai.
  /// Grace 3 dtk — resubscribe cepat (cancel lama selesai setelah subscribe
  /// baru) tidak membunuh channel yang masih dipakai.
  final Map<String, Timer> _typingGrace = {};

  void releaseTypingChannel(String chatId) {
    final n = (_typingRefs[chatId] ?? 1) - 1;
    if (n <= 0) {
      _typingRefs.remove(chatId);
      _typingGrace[chatId]?.cancel();
      _typingGrace[chatId] = Timer(const Duration(seconds: 3), () {
        _typingGrace.remove(chatId);
        if ((_typingRefs[chatId] ?? 0) > 0) return;
        final ch = _typingChannels.remove(chatId);
        if (ch != null) _sb.removeChannel(ch);
      });
    } else {
      _typingRefs[chatId] = n;
    }
  }

  /// Stream event typing/recording lawan bicara di satu chat.
  /// Emit kind: 'typing' | 'recording' (dari payload event).
  Stream<String> getTypingStream(String chatId) {
    return getTypingPulseStream(chatId).map((e) => e.$1);
  }

  /// Stream pulse typing mentah (kind + timestamp server ms).
  /// Dipakai layar chat untuk mengabaikan pulse basi dari invokasi lama
  /// yang masih jalan setelah balasannya sudah masuk.
  Stream<(String, int)> getTypingPulseStream(String chatId) {
    final controller = StreamController<(String, int)>.broadcast();
    _typingChannel(chatId);
    debugPrint('[TYPING] subscriber registered for $chatId');
    _typingSubs.putIfAbsent(chatId, () => {}).add(controller);
    controller.onCancel = () {
      _typingSubs[chatId]?.remove(controller);
      if (_typingSubs[chatId]?.isEmpty == true) _typingSubs.remove(chatId);
      releaseTypingChannel(chatId);
    };
    return controller.stream;
  }

  /// Kirim sinyal typing/recording (throttle dilakukan di screen).
  /// Ping DB di-throttle 10 dtk per chat (broadcast realtime tetap tiap
  /// sinyal — murah; yang mahal write ping_typing-nya).
  final Map<String, int> _lastPingTyping = {};
  void sendTyping(String chatId, {String kind = 'typing'}) {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    _typingChannelNoRef(chatId)
        .sendBroadcastMessage(
          event: 'typing',
          payload: {
            'sender_id': uid,
            'kind': kind,
            'ts': DateTime.now().millisecondsSinceEpoch,
          },
        )
        .catchError((_) => ChannelResponse.error);
    // Ping DB untuk ai-reply: AI menunggu selama user masih mengetik.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_lastPingTyping[chatId] ?? 0) < 10000) return;
    _lastPingTyping[chatId] = now;
    _sb
        .rpc('ping_typing', params: {'p_chat_id': chatId})
        .catchError((_) {});
  }

  void _refreshChatStreams(String myUid) {
    final callbacks = _chatReloaders[myUid];
    if (callbacks == null) return;
    for (final cb in List.of(callbacks)) {
      cb();
    }
  }

  /// Refresh paksa list private chat (dipanggil saat screen list di-mount
  /// ulang — broadcast stream tidak menyimpan data terakhir, jadi tanpa ini
  /// StreamBuilder bisa stuck spinner setelah tab di-switch).
  void refreshMyPrivateChats(String myUid) => _refreshChatStreams(myUid);

  void clearCachedStreams() {
    _chatReloaders.clear();
    for (final c in _privateChatsStreams.values) {
      if (!c.isClosed) c.close();
    }
    _privateChatsStreams.clear();
  }

  /// Fetch rows private_chats untuk user — dipakai getMyPrivateChats dan
  /// refresh saat stream cached di-subscribe ulang.
  Future<List<PrivateChatInfo>> _fetchPrivateChatRows(String myUid) async {
    final rows = await _sb
        .from('private_chats')
        .select()
        .contains('participants', [myUid])
        .order('last_message_at', ascending: false)
        .limit(50);
    Set<String> hiddenSet = {};
    try {
      hiddenSet = await getHiddenChats(myUid);
    } catch (e) {
      dlog('[ChatService] fetchHiddenChats error: $e');
    }
    _privateChatsHidden[myUid] = hiddenSet;
    final list = rows
        .where((row) => !hiddenSet.contains(row['chat_id']))
        .map(_rowToPrivateChat)
        .where((c) => c.messageCount > 0)
        .toList();
    list.sort((a, b) => _comparePinned(a, b, myUid));
    return list;
  }

  PrivateChatInfo _rowToPrivateChat(Map<String, dynamic> row) {
    final d = snakeToCamel(row);
    return PrivateChatInfo(
      chatId: d['chatId'] ?? '',
      participants: List<String>.from(d['participants'] ?? []),
      participantNames: Map<String, String>.from(d['participantNames'] ?? {}),
      participantGenders: Map<String, String>.from(
        d['participantGenders'] ?? {},
      ),
      participantLocations: Map<String, String>.from(
        d['participantLocations'] ?? {},
      ),
      participantAges: (d['participantAges'] as Map<dynamic, dynamic>? ?? {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      participantRegistered:
          (d['participantRegistered'] as Map<dynamic, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k.toString(), v == true),
          ),
      lastMessage: d['lastMessage'] ?? '',
      lastMessageAt: parseDate(d['lastMessageAt']),
      messageCount: (d['messageCount'] as num?)?.toInt() ?? 0,
      unreadCounts: (d['unreadCounts'] as Map<dynamic, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      ),
      lastReadAt: (d['lastReadAt'] as Map<dynamic, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k.toString(), parseDate(v)),
      ),
      pinnedBy: List<String>.from(d['pinnedBy'] ?? const []),
      pinnedAt: (d['pinnedAt'] as Map<dynamic, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k.toString(), parseDate(v)),
      ),
      mutedBy: List<String>.from(d['mutedBy'] ?? const []),
      archivedBy: List<String>.from(d['archivedBy'] ?? const []),
    );
  }

  Future<void> pinPrivateChat(String chatId, bool pin, {String? myUidParam}) async {
    // Optimistic update biar UI langsung pindah ke atas tanpa tunggu network
    final myUid = myUidParam ?? _sb.auth.currentUser?.id;
    if (myUid != null) {
      final last = _privateChatsLast[myUid];
      if (last != null) {
        final idx = last.indexWhere((c) => c.chatId == chatId);
        if (idx >= 0) {
          final old = last[idx];
          final newPinnedBy = pin
              ? (old.pinnedBy.contains(myUid) ? old.pinnedBy : [...old.pinnedBy, myUid])
              : old.pinnedBy.where((id) => id != myUid).toList();
          final newPinnedAt = Map<String, DateTime>.from(old.pinnedAt);
          if (pin) {
            newPinnedAt[myUid] = DateTime.now();
          } else {
            newPinnedAt.remove(myUid);
          }
          final updated = old.copyWith(pinnedBy: newPinnedBy, pinnedAt: newPinnedAt);
          final list = List<PrivateChatInfo>.from(last)..[idx] = updated;
          list.sort((a, b) => _comparePinned(a, b, myUid));
          _privateChatsLast[myUid] = list;
          _privateChatsStreams[myUid]?.add(List.unmodifiable(list));
          _scheduleChatListSave(myUid);
        }
      }
    }
    await _sb.rpc('pin_private_chat', params: {'p_chat_id': chatId, 'p_pin': pin});
  }

  /// Mute/unmute notifikasi chat — pola sama seperti pin: optimistic
  /// update cache + cermin lokal (dipakai gate notif di main.dart) + RPC.
  /// RPC butuh migrasi 20260909000000_mute_archive_chats.sql.
  Future<void> mutePrivateChat(String chatId, bool mute, {String? myUidParam}) async {
    final myUid = myUidParam ?? _sb.auth.currentUser?.id;
    if (myUid != null) {
      final last = _privateChatsLast[myUid];
      if (last != null) {
        final idx = last.indexWhere((c) => c.chatId == chatId);
        if (idx >= 0) {
          final old = last[idx];
          final next = mute
              ? (old.mutedBy.contains(myUid) ? old.mutedBy : [...old.mutedBy, myUid])
              : old.mutedBy.where((id) => id != myUid).toList();
          final list = List<PrivateChatInfo>.from(last)..[idx] = old.copyWith(mutedBy: next);
          _privateChatsLast[myUid] = list;
          _privateChatsStreams[myUid]?.add(List.unmodifiable(list));
          _scheduleChatListSave(myUid);
        }
      }
    }
    await NotificationPrefsService.setChatMuted(chatId, mute);
    await _sb.rpc('mute_private_chat', params: {'p_chat_id': chatId, 'p_mute': mute});
  }

  /// Mute/unmute notifikasi ROOM live — server sebagai sumber kebenaran
  /// (kolom rooms.muted_by via RPC mute_room) + cermin lokal untuk
  /// offline-first. Menyamakan model dengan private chat (C1 audit).
  Future<void> muteRoom(String roomId, bool mute) async {
    await NotificationPrefsService.setChatMuted(roomId, mute);
    try {
      await _sb.rpc('mute_room', params: {'p_room_id': roomId, 'p_mute': mute});
    } catch (e) {
      // Server gagal (offline) → tetap tersimpan lokal; sinkron lain waktu.
      dlog('[chat] muteRoom server gagal (lokal tersimpan): $e');
    }
  }

  /// Archive/unarchive chat — optimistic update + RPC.
  /// Chat terarsip difilter di layar (tidak di service) agar daftar
  /// arsip bisa ditampilkan dari cache yang sama.
  Future<void> archivePrivateChat(String chatId, bool archive, {String? myUidParam}) async {
    final myUid = myUidParam ?? _sb.auth.currentUser?.id;
    if (myUid != null) {
      final last = _privateChatsLast[myUid];
      if (last != null) {
        final idx = last.indexWhere((c) => c.chatId == chatId);
        if (idx >= 0) {
          final old = last[idx];
          final next = archive
              ? (old.archivedBy.contains(myUid) ? old.archivedBy : [...old.archivedBy, myUid])
              : old.archivedBy.where((id) => id != myUid).toList();
          final list = List<PrivateChatInfo>.from(last)..[idx] = old.copyWith(archivedBy: next);
          _privateChatsLast[myUid] = list;
          _privateChatsStreams[myUid]?.add(List.unmodifiable(list));
          _scheduleChatListSave(myUid);
        }
      }
    }
    await _sb.rpc('archive_private_chat', params: {'p_chat_id': chatId, 'p_archive': archive});
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

  /// Snapshot terakhir list private chat — dipakai initialData StreamBuilder
  /// supaya tab Pesan tidak spinner saat di-mount ulang (broadcast stream
  /// tidak me-replay event yang di-add sebelum subscriber terpasang).
  List<PrivateChatInfo>? lastPrivateChatsSnapshot(String myUid) =>
      _privateChatsLast[myUid];

  Stream<List<PrivateChatInfo>> getMyPrivateChats(String myUid) {
    // Cache: kembali stream yang sudah ada agar channel Supabase
    // tidak dilipatgandakan tiap subscribe/didChange berikutnya.
    final existing = _privateChatsStreams[myUid];
    if (existing != null && !existing.isClosed) {
      // Subscriber baru (mis. balik ke sub-tab Pesan setelah buka Room):
      // broadcast stream tidak me-replay event lama, jadi kirim snapshot
      // terakhir dulu supaya list langsung tampil tanpa spinner.
      final last = _privateChatsLast[myUid];
      if (last != null) existing.add(last);
      // Snapshot sudah dijaga fresh oleh realtime (payload row lengkap) —
      // refetch 500 row cuma perlu kalau snapshot sudah lama / belum ada.
      final lastReload = _lastChatReloadAt[myUid];
      if (lastReload == null ||
          DateTime.now().difference(lastReload) > const Duration(seconds: 30)) {
        _refreshChatStreams(myUid);
      }
      return existing.stream;
    }

    final controller = StreamController<List<PrivateChatInfo>>.broadcast();
    _privateChatsStreams[myUid] = controller;

    Future<void> reload() async {
      try {
        final rows = await _fetchPrivateChatRows(myUid);
        _privateChatsLast[myUid] = rows;
        _lastChatReloadAt[myUid] = DateTime.now();
        dlog(
          '[getMyPrivateChats] fetched ${rows.length} chats for $myUid',
        );
        if (!controller.isClosed) controller.add(rows);
        if (rows.isNotEmpty) {
          MessageCache.instance
              .saveRawList(myUid, rows.map((c) => c.toMap()).toList());
        }
      } catch (e) {
        dlog('[getMyPrivateChats] fetch error for $myUid: $e');
      }
    }

    _chatReloaders.putIfAbsent(myUid, () => []).add(reload);

    // Cold start (app baru dibuka): tampilkan list dari cache disk DULU
    // tanpa spinner — fetch server menyusul dan mengkoreksi.
    MessageCache.instance.loadRawList(myUid).then((cachedRows) {
      if (cachedRows.isEmpty) return;
      final cached =
          cachedRows.map(PrivateChatInfo.fromMap).toList()
            ..sort((a, b) => _comparePinned(a, b, myUid));
      if (_privateChatsLast[myUid] != null &&
          _privateChatsLast[myUid]!.isNotEmpty) {
        return; // sudah ada data lebih baru — jangan timpa
      }
      _privateChatsLast[myUid] = cached;
      if (!controller.isClosed) controller.add(cached);
    });

    // Nama channel harus UNIK per instance — getMyPrivateChats bisa disubscribe
    // dari 2 screen sekaligus (list chat + layar chat); nama sama = join gagal,
    // event realtime tidak pernah sampai (centang baca jadi tidak update).
    final instanceId = DateTime.now().microsecondsSinceEpoch;
    final channel = _sb.channel('private-chats-$myUid-$instanceId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'private_chats',
      callback: (payload) {
        // Update snapshot langsung dari payload (row lengkap) — tanpa
        // refetch 500 row untuk setiap centang baca / pesan baru.
        if (controller.isClosed) return;
        if (payload.eventType == PostgresChangeEvent.delete) {
          final chatId = payload.oldRecord['chat_id'] as String?;
          if (chatId != null) _removeLocalChat(myUid, chatId);
        } else {
          _applyChatEvent(myUid, payload.newRecord);
        }
      },
    );
    channel.subscribe();

    // Pesan BARU masuk untuk chat yang aku hapus (hidden) → chat muncul lagi
    // di list, tapi hanya pesan setelah cutoff yang akan tampil isinya.
    // Chat yang tidak hidden tidak perlu dicek — row private_chats sudah
    // di-update trigger dan dikirim channel di atas (tanpa query tambahan).
    final msgChannel = _sb.channel('private-chats-msg-$myUid-$instanceId');
    msgChannel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'private_messages',
      callback: (payload) async {
        final chatId = payload.newRecord['chat_id'] as String?;
        if (chatId == null || controller.isClosed) return;
        if (!(_privateChatsHidden[myUid]?.contains(chatId) ?? false)) return;
        try {
          final row = await _sb
              .from('private_chats')
              .select('hidden_by,hidden_at')
              .eq('chat_id', chatId)
              .maybeSingle();
          if (row == null) return;
          final hidden = List<String>.from(
            (row['hidden_by'] as List<dynamic>?) ?? [],
          );
          if (!hidden.contains(myUid)) return;
          final hm = (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {};
          final cutoffStr = hm[myUid];
          final msgStr = payload.newRecord['created_at'] as String?;
          if (cutoffStr != null && msgStr != null) {
            final cutoff = DateTime.tryParse('$cutoffStr');
            final msgAt = DateTime.tryParse(msgStr);
            if (cutoff == null || msgAt == null || !msgAt.isAfter(cutoff))
              return;
          }
          await unhideChat(myUid, chatId);
          // Row private_chats berubah → channel di atas yang apply ke list.
        } catch (e) {
          dlog('[ChatService] autoUnhideOnMessage error: $e');
        }
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
      if (cached == controller) {
        _privateChatsStreams.remove(myUid);
        _privateChatsLast.remove(myUid);
        _privateChatsHidden.remove(myUid);
        _lastChatReloadAt.remove(myUid);
      }
    };

    return controller.stream;
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
      if (presenceUids.contains(id)) return true;
      if (st == 'online') return true;
      if (dummyUids.contains(id)) return true;
      return false;
    }).toList();
    return filtered.isEmpty ? rpcRows : filtered;
  }

  /// Stream status realtime satu user (online/idle/offline).
  /// Pakai channel postgres changes pada profiles — ringan, hanya 1 row.
  /// Status dihitung efektif: last_seen basi (> 30 menit) dianggap offline,
  /// supaya sinkron dengan daftar pengguna online di list chat.
  /// [initialStatus] membuat stream langsung emit status yang sudah diketahui
  /// (misal dari profil yang baru di-fetch) tanpa query DB tambahan.
  Stream<String> getUserStatus(String uid, {String? initialStatus}) {
    final controller = StreamController<String>.broadcast();
    String _current = initialStatus ?? 'offline';
    if (initialStatus != null && initialStatus != 'offline') {
      Future.microtask(() {
        if (!controller.isClosed) controller.add(_current);
      });
    }

    Future<void> fetchStatus() async {
      try {
        final row = await _sb
            .from('profiles')
            .select('status,last_seen')
            .eq('id', uid)
            .maybeSingle();
        if (row == null || controller.isClosed) return;
        final s = ChatService.effectiveStatusOf(
          row['status'] as String?,
          row['last_seen'] as String?,
        );
        if (s != _current) {
          _current = s;
          controller.add(_current);
        }
      } catch (e) {
        dlog('[chat] fetchStatus error: $e');
      }
    }

    // Nama channel harus UNIK per instance — 2 screen bisa menonton user
    // yang sama bersamaan (nama sama = join gagal, status mati sebelah).
    final instanceId = DateTime.now().microsecondsSinceEpoch;
    final channel = _sb.channel('user-status-$uid-$instanceId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'profiles',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: uid,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        final s = ChatService.effectiveStatusOf(
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
    if (initialStatus == null) fetchStatus();

    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }

  /// Ambil last_seen satu user (untuk "terakhir dilihat" di header chat).
  Future<DateTime?> getUserLastSeen(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final row = await _sb
          .from('profiles')
          .select('last_seen')
          .eq('id', uid)
          .maybeSingle();
      final v = row?['last_seen'] as String?;
      return v == null ? null : DateTime.tryParse(v)?.toLocal();
    } catch (e) {
      dlog('[chat] getUserLastSeen error: $e');
      return null;
    }
  }

  Stream<List<UserModel>> getOnlineUsers() {
    final controller = StreamController<List<UserModel>>.broadcast();
    List<UserModel> cached = [];
    Timer? debounce;
    // Map uid→path dibangun ulang tiap stream dibuka — tanpa clear, tumbuh
    // seumur instance (1 entry per user yang pernah online).
    _onlinePathByUid.clear();
    // Coalesce fallback: kapan sync terakhir jalan (sumber mana pun).
    DateTime? lastSyncAt;

    Future<void> syncFromPresence() async {
      lastSyncAt = DateTime.now();
      dlog('[ONLINE-EMIT] sync start t=${DateTime.now().millisecondsSinceEpoch % 100000}');
      try {
        final state = RealtimeHub.instance.onlinePresenceState;
        dlog('[ONLINE-EMIT] presence state keys=${state.keys.length}');
        // Fast path per-country shard: ambil max 50 uid tanpa expand full O(N) (jangan values.expand untuk 1M)
        List<String> firstNPresenceUids(int n) {
          final out = <String>[];
          for (final list in state.values) {
            for (final m in list as List) {
              final uid = '${(m as Map)['uid'] ?? ''}';
              if (uid.isEmpty) continue;
              out.add(uid);
              if (out.length >= n) return out;
            }
            if (out.length >= n) break;
          }
          return out;
        }

        final presenceUidsFast = firstNPresenceUids(50);
        dlog('[ONLINE-EMIT] presenceUidsFast=${presenceUidsFast.length}');
        if (presenceUidsFast.isNotEmpty) {
          try {
            const colsFast = 'id,nickname,gender,age,country,city,status,avatar,is_registered,last_seen';
            final fastRows = await _sb.from('profiles').select(colsFast).inFilter('id', presenceUidsFast).limit(50).timeout(const Duration(seconds: 2));
            if (fastRows.isNotEmpty && !controller.isClosed) {
              // Emit cepat dari presence
              final seenFast = <String>{};
              final pendingFast = <UserModel>[];
              for (final row in fastRows) {
                try {
                  var u = UserModel.fromMap('${row['id']}', snakeToCamel(row));
                  if (!seenFast.add(u.uid)) continue;
                  if (u.avatar.isNotEmpty &&
                      StoragePhotoService.instance.isAvatarPath(u.avatar)) {
                    _onlinePathByUid[u.uid] = u.avatar;
                  }
                  if (u.avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(u.avatar)) {
                    final cachedB64 = _avatarCache[u.avatar];
                    if (cachedB64 != null && cachedB64.isNotEmpty) {
                      u = u.copyWith(avatar: cachedB64);
                    } else {
                      // Belum ada b64 di cache: pakai avatar dari emission
                      // sebelumnya (per uid) — string avatar tidak berubah
                      // antar-emission → tidak memicu decode ulang/blink.
                      final prev = cached.where((c) => c.uid == u.uid).firstOrNull;
                      if (prev != null && prev.avatar.isNotEmpty &&
                          !StoragePhotoService.instance.isAvatarPath(prev.avatar)) {
                        u = u.copyWith(avatar: prev.avatar);
                      }
                    }
                  } else if (u.avatar.isEmpty) {
                    final prev = cached.where((c) => c.uid == u.uid).firstOrNull;
                    if (prev != null && prev.avatar.isNotEmpty &&
                        !StoragePhotoService.instance.isAvatarPath(prev.avatar)) {
                      u = u.copyWith(avatar: prev.avatar);
                    }
                  }
                  pendingFast.add(u);
                } catch (_) {}
              }
              if (pendingFast.isNotEmpty) {
                // Urutan SAMA dengan RPC (last_seen desc) — emission awal dan
                // emission RPC tidak memindahkan posisi card di layar.
                pendingFast.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
                cached = List.of(pendingFast);
                if (!controller.isClosed) controller.add(List.unmodifiable(cached));
                // Background download avatar batch (sama seperti slow path).
                // Lewati path yang sudah ada di _avatarCache (tidak download
                // ulang tiap tick); index via Map biar O(1), bukan indexWhere.
                const avatarBatch = 20;
                bool avatarUpdated = false;
                final cachedIdx = <String, int>{
                  for (var k = 0; k < cached.length; k++) cached[k].uid: k,
                };
                for (var i = 0; i < pendingFast.length; i += avatarBatch) {
                  final chunk = pendingFast.skip(i).take(avatarBatch).toList();
                  final results = await Future.wait(chunk.map((u) async {
                    if (u.avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(u.avatar)) {
                      final hit = _avatarCache[u.avatar];
                      if (hit != null && hit.isNotEmpty) {
                        return u.copyWith(avatar: hit);
                      }
                      final b64 = await _avatarB64(u.avatar);
                      if (b64.isNotEmpty) return u.copyWith(avatar: b64);
                    }
                    return u;
                  }));
                  for (var j = 0; j < chunk.length; j++) {
                    final idx = cachedIdx[chunk[j].uid] ?? -1;
                    if (idx >= 0 && results[j].avatar != cached[idx].avatar) {
                      cached[idx] = results[j];
                      avatarUpdated = true;
                    }
                  }
                }
                if (avatarUpdated) {
                  dlog('[ONLINE-EMIT] avatar batch updated t=${DateTime.now().millisecondsSinceEpoch}');
                  if (!controller.isClosed) controller.add(List.unmodifiable(cached));
                }
              }
            }
          } catch (_) {}
        }
        // Coba RPC ringan dulu (1 RTT, server-side, tanpa IN 500).
        // K6 skala: global limit 200 + merge shard country sendiri
        // (index per-country) — user sekota selalu terlihat walau
        // >200 online global bersamaan; user baru online (last_seen
        // terbaru) selalu masuk top list.
        List<dynamic> rpcRows = [];
        bool usedRpc = false;
        try {
          dlog('[ONLINE-EMIT] calling RPC get_online_users');
          final data = await _sb.rpc('get_online_users', params: {'p_limit': 200}).timeout(const Duration(seconds: 2));
          dlog('[ONLINE-EMIT] RPC done rows=${data is List ? data.length : 0}');
          if (data is List && data.isNotEmpty) {
            rpcRows = data;
            usedRpc = true;
          }
        } catch (_) {}
        // Merge shard country sendiri (ringan, index per-country) — menutup
        // celah user yang tidak masuk top-200 global.
        try {
          final ownCountry = await _fetchOwnCountry();
          if (ownCountry != null && ownCountry.isNotEmpty) {
            final local = await _sb.rpc('get_online_users', params: {
              'p_country': ownCountry,
              'p_limit': 100,
            }).timeout(const Duration(seconds: 2));
            if (local is List && local.isNotEmpty) {
              final ids = rpcRows.map((r) => '${r['id'] ?? ''}').toSet();
              for (final r in local) {
                if (!ids.contains('${r['id'] ?? ''}')) rpcRows.add(r);
              }
              if (rpcRows.isNotEmpty) usedRpc = true;
            }
          }
        } catch (_) {}
        List<dynamic> rows;
        if (usedRpc) {
          // ── PRESENCE CROSS-REFERENCE ────────────────────────────────────
          // RPC return user berdasarkan DB (status + last_seen). Kalau app
          // di-kill tanpa lifecycle event, profiles.status tetap 'online'/
          // 'idle' dan last_seen masih fresh → user zombie muncul di list.
          final presenceUids = <String>{};
          for (final list in state.values) {
            for (final m in list) {
              final uid = '${(m as Map)['uid'] ?? ''}';
              if (uid.isNotEmpty) presenceUids.add(uid);
            }
          }
          final dummyUids = await _fetchDummyUids();
          rows = ChatService.filterRpcOnlineRows(
            rpcRows,
            presenceUids,
            dummyUids: dummyUids,
          );
        } else {
          // Fallback hybrid lama jika RPC belum deploy / gagal — tetap batasi O(50)
          final presenceUids = firstNPresenceUids(50);
          Set<String> dbUids = {};
          try {
            final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 30)).toIso8601String();
            final dbRows = await _sb.from('profiles').select('id').neq('status', 'offline').neq('status', 'invisible').gte('last_seen', cutoff).limit(100).timeout(const Duration(seconds: 2));
            for (final r in dbRows) {
              final id = '${r['id'] ?? ''}';
              if (id.isNotEmpty) dbUids.add(id);
            }
          } catch (_) {}
          final uids = {...presenceUids, ...dbUids}.toList();
          if (uids.isEmpty) {
            // Jangan kosongkan list yang sudah tampil (emit kosong bikin
            // list online kedip hilang-muncul) — biarkan fallback tick
            // yang mengoreksi kalau memang sepi sungguhan.
            return;
          }
          String? invisibleUid2 = await _fetchInvisibleUid();
          final filtered2 = invisibleUid2 == null ? uids : uids.where((id) => id != invisibleUid2).toList();
          if (filtered2.isEmpty) {
            // Sama: skip emit kosong, jangan timpa list terisi.
            return;
          }
          const cols2 = 'id,nickname,gender,age,country,city,status,avatar,is_registered,last_seen';
          rows = await _sb.from('profiles').select(cols2).inFilter('id', filtered2).limit(1000).timeout(const Duration(seconds: 6));
        }
        // Invisible filter untuk path RPC juga (cache 5 mnt, bukan per tick)
        String? invisibleUid = await _fetchInvisibleUid();
        if (invisibleUid != null) {
          rows = rows.where((r) => '${(r as Map)['id']}' != invisibleUid).toList();
        }
        final seen = <String>{};
        final pending = <UserModel>[];
        for (final row in rows) {
          try {
            var u = UserModel.fromMap('${row['id']}', snakeToCamel(row));
            if (!seen.add(u.uid)) continue;
            if (u.avatar.isNotEmpty &&
                StoragePhotoService.instance.isAvatarPath(u.avatar)) {
              _onlinePathByUid[u.uid] = u.avatar;
            }
            if (u.avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(u.avatar)) {
              final cachedB64 = _avatarCache[u.avatar];
              if (cachedB64 != null && cachedB64.isNotEmpty) {
                u = u.copyWith(avatar: cachedB64);
              } else {
                final prev = cached.where((c) => c.uid == u.uid).firstOrNull;
                if (prev != null && prev.avatar.isNotEmpty &&
                    !StoragePhotoService.instance.isAvatarPath(prev.avatar)) {
                  u = u.copyWith(avatar: prev.avatar);
                }
              }
            } else if (u.avatar.isEmpty) {
              final prev = cached.where((c) => c.uid == u.uid).firstOrNull;
              if (prev != null && prev.avatar.isNotEmpty &&
                  !StoragePhotoService.instance.isAvatarPath(prev.avatar)) {
                u = u.copyWith(avatar: prev.avatar);
              }
            }
            pending.add(u);
          } catch (e) {
            dlog('[getOnlineUsers] skip bad row: $e');
          }
        }
        // Progressive: emit dulu tanpa avatar (instant), avatar nyusul background
        pending.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
        // Anti-hilang-semua: hasil slow path KOSONG saat cache sebelumnya
        // terisi → jangan timpa (kemungkinan network blip), biarkan
        // fallback tick retry. Timer grace di provider sebagai lapis 2.
        if (pending.isEmpty && cached.isNotEmpty) {
          return;
        }
        cached = List.of(pending);
        // Simpan kv list online: avatar = SERVER PATH (ringan). Bytes foto
        // sudah ada di MediaDiskCache per path — cold start berikutnya
        // memuat foto dari disk, tanpa network.
        try {
          final rows = pending
              .map((u) => {'uid': u.uid, ...u.toMap(), 'avatar': _onlinePathByUid[u.uid] ?? ''})
              .toList();
          if (rows.isNotEmpty) {
            MessageCache.instance.saveRawList('online_users', rows);
          }
        } catch (_) {}
        dlog('[ONLINE-EMIT] slow path n=${pending.length} withAvatar=${pending.where((u) => u.avatar.isNotEmpty && !StoragePhotoService.instance.isAvatarPath(u.avatar)).length} t=${DateTime.now().millisecondsSinceEpoch}');
        if (!controller.isClosed) controller.add(List.unmodifiable(cached));
        // Background download avatar batch 20 (index Map O(1)).
        const avatarBatch = 20;
        bool avatarUpdated = false;
        final cachedIdx2 = <String, int>{
          for (var k = 0; k < cached.length; k++) cached[k].uid: k,
        };
        for (var i = 0; i < pending.length; i += avatarBatch) {
          final chunk = pending.skip(i).take(avatarBatch).toList();
          final results = await Future.wait(chunk.map((u) async {
            if (u.avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(u.avatar)) {
              final b64 = await _avatarB64(u.avatar);
              if (b64.isNotEmpty) return u.copyWith(avatar: b64);
            }
            return u;
          }));
          for (var j = 0; j < chunk.length; j++) {
            final idx = cachedIdx2[chunk[j].uid] ?? -1;
            if (idx >= 0 && results[j].avatar != cached[idx].avatar) {
              cached[idx] = results[j];
              avatarUpdated = true;
            }
          }
        }
        if (avatarUpdated && !controller.isClosed) controller.add(List.unmodifiable(cached));
      } catch (e) {
        dlog('[getOnlineUsers] presence fetch error: $e');
        if (!controller.isClosed) controller.addError(e);
      }
    }

    final sub = RealtimeHub.instance.onlinePresence.listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 1200), syncFromPresence);
    });
    // Realtime profiles UPDATE: user lain yang baru online (termasuk dummy
    // yang di-set dari admin panel — tanpa device/presence) harus langsung
    // muncul di daftar. Dulu: sync hanya via presence event sendiri +
    // fallback saat list kosong → perubahan status dari admin terlihat
    // sangat terlambat.
    final profileSyncSub = _sb
        .channel('online-list-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            if (controller.isClosed) return;
            final st = payload.newRecord['status'] as String?;
            final changedUid = '${payload.newRecord['id'] ?? ''}';
            // Realtime OFFLINE: user (termasuk dummy tanpa presence socket
            // yang di-offline-kan tick server) langsung dibuang dari list
            // tayang — tanpa menunggu full resync. Idempoten: uid yang
            // memang tak ada di list = no-op. Event online/idle di bawah
            // tetap full resync seperti semula.
            if (ChatService.shouldDropOnlineUid(st)) {
              if (changedUid.isNotEmpty &&
                  cached.any((c) => c.uid == changedUid)) {
                cached = cached.where((c) => c.uid != changedUid).toList();
                dlog('[ONLINE-EMIT] profile $st event → drop $changedUid');
                if (!controller.isClosed) {
                  controller.add(List.unmodifiable(cached));
                }
              }
              return;
            }
            // Hanya re-sync saat ada yang masuk jadi online/idle.
            if (st != 'online' && st != 'idle') return;
            final ls = DateTime.tryParse(
              '${payload.newRecord['last_seen'] ?? ''}',
            );
            if (ls == null) return;
            if (ls.toUtc().isBefore(
              DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
            )) {
              return;
            }
            dlog('[ONLINE-EMIT] profile online event → resync');
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 1200), syncFromPresence);
          },
        )
        .subscribe();
    // initial sync
    syncFromPresence();
    // also periodic fallback if presence empty (cold start before track)
    // + TRUTH-CHECK berkala: socket realtime bisa mati diam-diam (blip
    // jaringan) sehingga event join/update tidak pernah sampai — dulu
    // tick hanya jalan saat cache kosong → user baru online tidak muncul
    // sampai restart app. Sekarang sync tetap jalan tiap 30s (RPC 1 RTT,
    // murah; provider anti-kedip mencegah flicker).
    // Coalesce: tick dilewati bila sync baru jalan <45 dtk (dari event
    // presence/profile) — fallback hanya untuk socket mati (tak ada event
    // = tak ada sync = tick tetap jalan tiap ~60 dtk).
    final fallbackTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (lastSyncAt != null &&
          DateTime.now().difference(lastSyncAt!).inSeconds < 45) {
        return; // baru sync — hemat 1 RPC.
      }
      dlog('[ONLINE-EMIT] fallback 30s tick cachedEmpty=${cached.isEmpty}');
      syncFromPresence();
    });
    controller.onCancel = () {
      debounce?.cancel();
      fallbackTimer.cancel();
      sub.cancel();
      _sb.removeChannel(profileSyncSub);
    };
    return controller.stream;
  }

  Stream<List<UserModel>> getOnlineUsersInRoom(String roomId) {
    return _sb
        .from('room_presence')
        .stream(primaryKey: ['room_id', 'user_id'])
        .eq('room_id', roomId)
        .map((rows) {
          // Presensi basi (joined_at > 5 menit, heartbeat 60 detik tidak jalan
          // lagi karena app di-kill/background) dianggap sudah keluar room.
          final cutoff = DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          );
          return rows
              .where((row) {
                final joined = DateTime.tryParse('${row['joined_at']}');
                return joined != null && joined.toUtc().isAfter(cutoff);
              })
              .map((row) {
                final d = snakeToCamel(row);
                return UserModel(
                  uid: d['userId'] ?? '',
                  nickname: d['nickname'] ?? 'Anon',
                  gender: d['gender'] ?? 'other',
                  age: (d['age'] as num?)?.toInt() ?? 0,
                  // room_presence tidak menyimpan lokasi (hanya profil); biarkan
                  // kosong agar tidak query kolom nir-skema.
                  country: '',
                  city: '',
                  ipAddress: '',
                  status: 'online',
                  avatar: '',
                  isRegistered: d['isRegistered'] == true,
                  loginAt: DateTime.now(),
                  createdAt: DateTime.now(),
                  lastSeen: parseDate(d['joinedAt']),
                );
              })
              // Dedupe by uid — update event dari supabase stream bisa
              // menduplikasi row (bug stream multi-column PK) sehingga
              // "Kamu" muncul 2x setelah keluar-masuk room.
              .fold<Map<String, UserModel>>({}, (acc, u) {
                acc[u.uid] = u;
                return acc;
              })
              .values
              .toList();
        });
  }

  Future<void> joinRoom(String roomId, UserModel user) async {
    // nickname, gender, age di-set oleh trigger DB dari profiles
    // tidak dikirim dari client untuk mencegah impersonasi
    // joined_at di-refresh setiap heartbeat (60 detik) — row presence
    // yang basi (app di-kill/force-stop) otomatis difilter dari daftar
    // online room oleh getOnlineUsersInRoom / getRoomOnlineCounts.
    await _sb.from('room_presence').upsert({
      'room_id': roomId,
      'user_id': user.uid,
      'joined_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'room_id,user_id');
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    await _sb
        .from('room_presence')
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
    final hidden = List<String>.from(
      (row['hidden_by'] as List<dynamic>?) ?? [],
    );
    final hiddenAt = Map<String, dynamic>.from(
      (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {},
    );
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

  Future<Set<String>> getHiddenChats(String myUid) async {
    try {
      final rows = await _sb.from('private_chats').select('chat_id').contains(
        'hidden_by',
        [myUid],
      );
      return rows.map((r) => r['chat_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  Stream<Map<String, int>> getRoomOnlineCounts({String? country}) {
    final controller = StreamController<Map<String, int>>.broadcast();
    Timer? timer;
    bool closed = false;
    Future<void> fetch() async {
      if (closed || controller.isClosed) return;
      try {
        final c = (country == null || country.trim().isEmpty) ? null : country.trim();
        final res = await _sb.rpc('count_room_presence_by_country', params: {'p_country': c});
        final map = <String, int>{};
        if (res is Map) {
          res.forEach((k, v) => map['$k'] = (v as num).toInt());
        }
        if (!controller.isClosed) controller.add(map);
      } catch (e) {
        dlog('[getRoomOnlineCounts] rpc error country=$country: $e');
      }
    }

    fetch();
    // 30 detik cukup untuk badge jumlah online per room — realtime
    // presence list tab Online adalah jalur utama; 15s seumur sesi
    // terlalu boros RPC hanya untuk angka.
    timer = Timer.periodic(const Duration(seconds: 30), (_) => fetch());
    // Cleanup stale presence di background (idempotent)
    _sb.rpc('cleanup_room_presence', params: {'p_minutes': 10}).catchError((_) {});
    controller.onCancel = () {
      closed = true;
      timer?.cancel();
    };
    return controller.stream;
  }

  // ── Block / Report ──

  Future<void> blockUser(String myUid, String blockedUid) async {
    await _sb.from('blocks').upsert({
      'blocker_id': myUid,
      'blocked_id': blockedUid,
    }, onConflict: 'blocker_id,blocked_id');
  }

  Future<void> unblockUser(String myUid, String blockedUid) async {
    await _sb
        .from('blocks')
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
    final res = await _sb
        .from('blocks')
        .select('blocker_id')
        .eq('blocker_id', myUid)
        .eq('blocked_id', otherUid)
        .maybeSingle();
    return res != null;
  }

  Future<List<String>> getBlockedUids(String myUid) async {
    final res = await _sb
        .from('blocks')
        .select('blocked_id')
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
