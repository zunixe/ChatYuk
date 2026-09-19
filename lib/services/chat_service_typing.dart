part of 'chat_service.dart';

/// Domain **typing** — pisah dari monolit ChatService (Fase 4).
/// Satu library (`part`): field privat `ChatBase` tetap bisa diakses,
/// member mixin jadi bagian interface `ChatService` (mock aman).
mixin ChatServiceTypingMx on ChatBase {
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
      dlog('[TYPING] fanout drop chat=$chatId sender=$senderId me=$myId keys=${data.keys.toList()}');
      return;
    }
    final ts = (data['ts'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final subs = _typingSubs[chatId];
    if (subs == null || subs.isEmpty) {
      dlog('[TYPING] fanout no-subs chat=$chatId (bubble tak bisa tampil)');
      return;
    }
    dlog('[TYPING] fanout ok chat=$chatId subs=${subs.length}');
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
        dlog('[TYPING] onBroadcast chat=$chatId raw=$raw');
        _fanoutTyping(chatId, raw);
      },
    );
    c.subscribe((status, error) {
      dlog('[TYPING] subscribe $chatId -> $status err=$error');
    });
    _typingChannels[chatId] = c;
    return c;
  }

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
    dlog('[TYPING] subscriber registered for $chatId');
    _typingSubs.putIfAbsent(chatId, () => {}).add(controller);
    controller.onCancel = () {
      _typingSubs[chatId]?.remove(controller);
      if (_typingSubs[chatId]?.isEmpty == true) _typingSubs.remove(chatId);
      releaseTypingChannel(chatId);
    };
    return controller.stream;
  }

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
}
