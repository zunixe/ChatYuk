part of 'chat_service.dart';

/// Domain **room** — pisah dari monolit ChatService (Fase 4).
/// Satu library (`part`): field privat `ChatBase` tetap bisa diakses,
/// member mixin jadi bagian interface `ChatService` (mock aman).
mixin ChatServiceRoomMx on ChatBase {
  ChatMessageStream getRoomMessages(String roomId) {
    return _cachedMessagesStream(cacheKey: 'room_$roomId');
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
    /// Metadata kutipan (jenis media, dimensi, path video) — JSON.
    Map<String, dynamic>? repliedToMeta,
    bool isForwarded = false,
    List<Mention> mentions = const [],
    String videoPoster = '',
    /// Bundle multi-foto: semua pesan batch berbagi id yang sama.
    String? albumId,
    /// Definisi poll (type 'poll'): {"q":..., "o":[...], "m":bool}.
    Map<String, dynamic>? poll,
    /// Kontak dibagikan (type 'contact') — payload sama dengan private.
    Map<String, dynamic>? contact,
  }) async {
    // Validasi tipe pesan
    if (![
      'text',
      'image',
      'view_once',
      'voice',
      'location',
      // Video (termasuk sekali lihat) — lihat catatan di sender private.
      'video',
      'video_once',
      'video_once_expired',
      // Stiker (ala Telegram) — sama seperti private.
      'sticker',
      // File/dokumen: text = nama file, image_path = path, duration_ms = ukuran.
      'file',
      // Poll (grup & global room; paritas private chat).
      'poll',
      // Kontak (grup & global room; paritas private chat).
      'contact',
    ].contains(type)) {
      throw Exception('Invalid message type');
    }
    // Validasi image/voice data jika ada — boleh base64 (lama) ATAU path storage (baru)
    if (imageData.isNotEmpty &&
        !isValidImageBase64(imageData) &&
        !StoragePhotoService.instance.isPath(imageData) &&
        !StoragePhotoService.instance.isVoicePath(imageData) &&
        !(type == 'file' &&
            StoragePhotoService.instance.isChatFilePath(imageData))) {
      throw Exception('Invalid image data');
    }
    if (type == 'text' && text.isEmpty) return null;
    if (text.length > 2000) {
      throw Exception('Message too long (max 2000 chars)');
    }
    final inserted = await _sb.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_gender': senderGender,
      'text': text,
      'type': type,
      'image_data': (type == 'voice' || type == 'location') ? '' : imageData,
      if (albumId != null && albumId.isNotEmpty) 'album_id': albumId,
      if (type == 'voice') 'voice_path': imageData,
      if (type == 'voice' && durationMs != null) 'duration_ms': durationMs,
      // Durasi view-once (detik; 0 = sampai ditutup). Voice pakai ms.
      if (type == 'view_once' && durationMs != null)
        'duration_ms': durationMs,
      if (type == 'image' && imageData.isNotEmpty) 'image_path': imageData,
      // FILE: image_path = path storage, duration_ms = ukuran (byte).
      if (type == 'file' && imageData.isNotEmpty) 'image_path': imageData,
      if (type == 'file' && durationMs != null) 'duration_ms': durationMs,
      // VIDEO: duration_ms = panjang video; image_path = path .mp4.
      if ((type == 'video' ||
              type == 'video_once' ||
              type == 'video_once_expired') &&
          durationMs != null)
        'duration_ms': durationMs,
      if ((type == 'video' ||
              type == 'video_once' ||
              type == 'video_once_expired') &&
          imageData.isNotEmpty)
        'image_path': imageData,
      if ((type == 'video' ||
              type == 'video_once' ||
              type == 'video_once_expired') &&
          videoPoster.isNotEmpty)
        'video_poster': videoPoster,
      if (repliedToId != null) 'replied_to_id': repliedToId,
      if (repliedToText != null) 'replied_to_text': repliedToText,
      if (repliedToSenderName != null) 'replied_to_sender_name': repliedToSenderName,
      if (repliedToMeta != null && repliedToMeta.isNotEmpty)
        'replied_to_meta': repliedToMeta,
      if (isForwarded) 'is_forwarded': true,
      if (mentions.isNotEmpty) 'mentions': Mention.listTo(mentions),
      if (poll != null) 'poll': poll,
      if (contact != null) 'contact': contact,
    }).select('id').maybeSingle();
    return (inserted as Map?)?['id']?.toString();
  }

  /// Perbarui payload lokasi LIVE di room (koordinat bergerak) — hanya `text`.
  Future<bool> updateLocationMessage(String messageId, String newPayload) async {
    try {
      await _sb
          .from('messages')
          .update({'text': newPayload})
          .eq('id', messageId);
      return true;
    } catch (e) {
      dlog('[ChatService] updateRoomLocationMessage error: $e');
      return false;
    }
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

  /// ADMIN SAJA: hapus (soft-delete) pesan SIAPA PUN di room — global maupun
  /// grup. RLS `messages_update_own` hanya mengizinkan sender_id = auth.uid,
  /// jadi jalur ini lewat RPC SECURITY DEFINER `admin_delete_room_message`
  /// yang menegakkan gate email admin (zunixe@gmail.com) di server. User biasa
  /// yang memanggil RPC ini ditolak ('Unauthorized') → UI tidak menampilkannya.
  /// [undelete] = true untuk UNDO di snackbar.
  Future<bool> adminDeleteRoomMessage(String messageId, {bool undelete = false}) async {
    try {
      final res = await _sb.rpc(
        'admin_delete_room_message',
        params: {'p_message_id': int.tryParse(messageId), 'p_deleted': !undelete},
      );
      if (res is Map && res['ok'] == true) return true;
      dlog('[ChatService] adminDeleteRoomMessage not ok: $messageId -> $res');
      return false;
    } catch (e) {
      dlog('[ChatService] adminDeleteRoomMessage error: $e');
      return false;
    }
  }

  /// Batalkan hapus (aksi UNDO di snackbar): kembalikan is_deleted=false.
  /// RLS update milik-sendiri mengizinkan (policy sama seperti delete).
  Future<bool> undeleteRoomMessage(String messageId) async {
    try {
      final rows = await _sb
          .from('messages')
          .update({'is_deleted': false})
          .eq('id', messageId)
          .select('id');
      if (rows.isEmpty) {
        dlog('[ChatService] undeleteRoomMessage 0 rows: $messageId');
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
    final res = await measuredRpc(_sb, 
      'send_room_gift',
      params: {
        'p_room_id': roomId,
        'p_gift_id': giftId,
        'p_qty': qty,
      },
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Broadcast ringan `view_once_seen` ke kanal STREAM penerima chat/room —
  /// dipakai sebagai penanda realtime ke PENGIRIM tanpa menunggu event UPDATE
  /// postgres (yang bisa telat/terlewat di MIUI/Doze).
  ///
  /// Topik diambil dari `viewOnceSeenTopic` — SATU sumber dengan subscriber
  /// `ChatStreamSession.viewOnceSeenTopic` (dulu memakai `private_<chatId>`
  /// sehingga tidak pernah sampai ke subscriber di `msg-<cacheKey>`, 2026-10-20).
  Future<void> _sendViewOnceSeen(
    String chatId,
    Map<String, dynamic> payload, {
    required bool isRoom,
  }) async {
    RealtimeChannel? ch;
    try {
      final topic = viewOnceSeenTopic(isRoom: isRoom, id: chatId);
      dlog('[VO-SEEN] send topic=$topic id=${payload['message_id']}');
      ch = _sb.channel(topic);
      var ok = false;
      ch.subscribe((st, err) {
        dlog('[VO-SEEN] subscribe st=$st err=$err topic=$topic');
        if (st == RealtimeSubscribeStatus.subscribed) ok = true;
      });
      // Tunggu subscribe singkat (maks 2 dtk) sebelum kirim.
      for (var i = 0; i < 20 && !ok; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (ok) {
        await ch.sendBroadcastMessage(
          event: 'view_once_seen',
          payload: payload,
        );
        dlog('[VO-SEEN] terkirim topic=$topic id=${payload['message_id']}');
      } else {
        dlog('[VO-SEEN] GAGAL subscribe (timeout 2s) topic=$topic');
      }
    } catch (e) {
      dlog('[ChatService] viewOnceSeen broadcast error: $e');
    } finally {
      if (ch != null) {
        try {
          await _sb.removeChannel(ch);
        } catch (_) {} // cleanup best-effort
      }
    }
  }

  /// Tandai view_once message sebagai expired setelah dilihat.
  /// image_data DIKEEP di DB (admin masih bisa melihat) — hanya type yang
  /// diubah. Kontrol "boleh lihat/tidak" dilakukan di sisi UI.
  ///
  /// [video] = true untuk video "sekali lihat" → type jadi
  /// `video_once_expired` (video punya type sendiri karena duration_ms
  /// dipakai untuk panjang video, bukan timer).
  Future<void> clearViewOnceImage(
    String messageId, {
    bool isRoom = false,
    bool video = false,
    String? chatId,
  }) async {
    final newType = video ? 'video_once_expired' : 'view_once_expired';
    try {
      await _sb
          .from(isRoom ? 'messages' : 'private_messages')
          .update({'type': newType})
          .eq('id', messageId);
    } catch (e) {
      dlog('[ChatService] expireViewOnce error: $e');
    }
    // REALTIME PENANDA "SUDAH DILIHAT" untuk PENGIRIM.
    //
    // Kenapa perlu broadcast: event `UPDATE` postgres hanya sampai ke klien
    // yang sedang berlangganan channel tabel itu, dan pada beberapa device
    // (MIUI/Doze) event-nya telat. Pengirim jadi tetap melihat kartu foto
    // sekali-lihat walau penerima sudah membukanya. Broadcast ringan ini
    // langsung dikirim setelah UPDATE sukses → pengirim mengunci kartu
    // seketika (tanpa menunggu refetch).
    if (chatId != null && chatId.isNotEmpty) {
      try {
        await _sendViewOnceSeen(chatId, {
          'chat_id': chatId,
          'message_id': messageId,
          'type': newType,
          'is_room': isRoom,
        }, isRoom: isRoom);
      } catch (e) { dlog('[CHAT-ROOM]: $e'); }
    }
  }

  /// Mute/unmute notifikasi ROOM live — server sebagai sumber kebenaran
  /// (kolom rooms.muted_by via RPC mute_room) + cermin lokal untuk
  /// offline-first. Menyamakan model dengan private chat (C1 audit).
  Future<void> muteRoom(String roomId, bool mute) async {
    await NotificationPrefsService.setChatMuted(roomId, mute);
    try {
      await measuredRpc(_sb, 'mute_room', params: {'p_room_id': roomId, 'p_mute': mute});
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
    // Guard in-flight: di koneksi lambat, RPC ini bisa 1.5-2.3s; tanpa guard
    // tick 30s bisa menumpuk antrean RPC berat. Skip bila masih jalan.
    bool inFlight = false;
    Future<void> fetch() async {
      if (closed || controller.isClosed || inFlight) return;
      inFlight = true;
      try {
        final c = (country == null || country.trim().isEmpty) ? null : country.trim();
        final res = await measuredRpc(_sb, 'count_room_presence_by_country', params: {'p_country': c});
        final map = <String, int>{};
        if (res is Map) {
          res.forEach((k, v) => map['$k'] = (v as num).toInt());
        }
        if (!controller.isClosed) controller.add(map);
      } catch (e) {
        dlog('[getRoomOnlineCounts] rpc error country=$country: $e');
      } finally {
        inFlight = false;
      }
    }

    // PERF: jangan tembak RPC berat (count_room_presence_by_country bisa
    // ~1.5s) TEPAT saat stream dibuka (frame transisi/boot). Tunda sedikit
    // agar frame pertama layar bersih; badge jumlah menyusul.
    Timer(const Duration(milliseconds: 600), () => fetch());
    // 60 detik: badge angka online per room cukup; RPC berat ini jangan
    // bersaing dengan jalur realtime (presence list tab Online).
    timer = Timer.periodic(const Duration(seconds: 60), (_) => fetch());
    // Cleanup stale presence di background (idempotent) — DEFER supaya tidak
    // bersaing dengan RPC frame pertama (dulu langsung saat buka).
    Timer(const Duration(seconds: 2), () {
      measuredRpc(_sb, 'cleanup_room_presence', params: {'p_minutes': 10})
          .catchError((_) {});
    });
    controller.onCancel = () {
      closed = true;
      timer?.cancel();
    };
    return controller.stream;
  }
}
