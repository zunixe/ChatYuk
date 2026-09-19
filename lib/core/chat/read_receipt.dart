/// Logika read-receipt (centang-2) — helper MURNI agar bisa di-unit-test
/// tanpa screen. Perilaku dipindah apa adanya dari `private_chat_screen.dart`.
///
/// Aturan yang TIDAK boleh dilanggar (sumber: docs/FEATURE_MAP.md §3a):
/// 1. **Monoton maju** — nilai lebih tua / `null` tidak boleh menurunkan
///    status; kalau dilanggar, centang-2 kedip/balik ke centang-1.
/// 2. **Batas inklusif** — pesan yang timestamp-nya PERSIS sama dengan waktu
///    baca ikut centang-2 (`!isAfter` = `<=`), bukan `<` ketat.
class ReadReceipt {
  ReadReceipt._();

  /// Gabungkan nilai tersimpan dengan nilai masuk. Mengembalikan yang
  /// LEBIH BARU; `incoming` null/tidak maju → kembalikan `current`.
  static DateTime? merge(DateTime? current, DateTime? incoming) {
    if (incoming == null) return current;
    if (current == null) return incoming;
    return incoming.isAfter(current) ? incoming : current;
  }

  /// Terbaru dari banyak kandidat (mis. snapshot live + `peekRawList`).
  /// Null semua → null.
  static DateTime? best(Iterable<DateTime?> candidates) {
    DateTime? out;
    for (final c in candidates) {
      out = merge(out, c);
    }
    return out;
  }

  /// True bila pesan [messageTs] sudah dibaca lawan ([otherLastRead]).
  /// Inklusif: `messageTs <= otherLastRead`. `otherLastRead` null → false.
  static bool isRead(DateTime messageTs, DateTime? otherLastRead) {
    if (otherLastRead == null) return false;
    return !messageTs.isAfter(otherLastRead);
  }

  /// Parse nilai last-read dari sumber apa pun (DateTime, ISO string, null).
  /// Nilai tak terparse → null (jangan dianggap epoch).
  static DateTime? parse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse('$value');
  }
}
