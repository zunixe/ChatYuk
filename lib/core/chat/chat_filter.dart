/// Filter daftar chat (tab Pesan) — helper MURNI agar bisa di-unit-test
/// tanpa widget/screen, dan operasi yang sama dipakai layar.
///
/// Empat pilihan (permintaan user, gaya tab "Terhapus" di admin):
/// - `all`        — semua chat
/// - `unread`     — ada pesan belum dibaca
/// - `anon`       — lawan bicara belum terdaftar (guest)
/// - `registered` — lawan bicara sudah terdaftar (punya email)
enum ChatFilter {
  all,
  unread,
  anon,
  registered;

  /// Nilai key yang dipakai UI (`_chatFilter`).
  String get key => name;

  static ChatFilter fromKey(String? k) =>
      ChatFilter.values.firstWhere(
        (f) => f.name == k,
        orElse: () => ChatFilter.all,
      );
}

class ChatFilterLogic {
  ChatFilterLogic._();

  /// Cocokkah satu chat dengan filter?
  /// [unread] = jumlah pesan belum dibaca utk saya; [otherRegistered] =
  /// status pendaftaran lawan bicara (false = anon).
  static bool matches(
    ChatFilter filter, {
    required int unread,
    required bool otherRegistered,
  }) {
    switch (filter) {
      case ChatFilter.all:
        return true;
      case ChatFilter.unread:
        return unread > 0;
      case ChatFilter.anon:
        return !otherRegistered;
      case ChatFilter.registered:
        return otherRegistered;
    }
  }

  /// Hitung jumlah chat per filter dari daftar item yang sudah lolos
  /// arsip + query. Dipakai untuk label chip "(n)".
  ///
  /// [items] = daftar ringkas (unread, registered) per chat.
  static ({int all, int unread, int anon, int registered}) counts(
    Iterable<({int unread, bool registered})> items,
  ) {
    var all = 0, unread = 0, anon = 0, registered = 0;
    for (final i in items) {
      all++;
      if (i.unread > 0) unread++;
      if (!i.registered) {
        anon++;
      } else {
        registered++;
      }
    }
    return (all: all, unread: unread, anon: anon, registered: registered);
  }
}
