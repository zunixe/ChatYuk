part of 'chat_service.dart';

/// Domain **room** — pisah dari monolit ChatService (Fase 4).
/// Satu library (`part`): field privat `ChatBase` tetap bisa diakses,
/// member mixin jadi bagian interface `ChatService` (mock aman).
mixin ChatServiceRoomMx on ChatBase {
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
    List<Mention> mentions = const [],
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
    if (type == 'text' && text.isEmpty) return;
    if (text.length > 2000) {
      throw Exception('Message too long (max 2000 chars)');
    }
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
      if (mentions.isNotEmpty) 'mentions': Mention.listTo(mentions),
    });
  }

  Future<bool> deleteRoomMessage(String messageId) async {
    try {
      final rows = await _sb
          .from('messages')
          .update({'is_deleted': true})
          .eq('id', messageId)
          .select('id');
      if (rows.isEmpty) {
        dlog('[ChatService] deleteRoomMessage 0 rows: $messageId');
        return false;
      }
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
}
