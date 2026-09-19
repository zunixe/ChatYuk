part of 'chat_service.dart';

/// Domain **gift** — pisah dari monolit ChatService (Fase 4).
/// Satu library (`part`): field privat `ChatBase` tetap bisa diakses,
/// member mixin jadi bagian interface `ChatService` (mock aman).
mixin ChatServiceGiftMx on ChatBase {
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
}
