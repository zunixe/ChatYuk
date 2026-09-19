part of 'chat_service.dart';

/// Domain **private** — pisah dari monolit ChatService (Fase 4).
/// Satu library (`part`): field privat `ChatBase` tetap bisa diakses,
/// member mixin jadi bagian interface `ChatService` (mock aman).
mixin ChatServicePrivateMx on ChatBase {
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
    List<Mention> mentions = const [],
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
      if (mentions.isNotEmpty) 'mentions': Mention.listTo(mentions),
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
        if (mentions.isNotEmpty) 'mentions': Mention.listTo(mentions),
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

}
