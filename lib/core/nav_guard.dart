/// Guard anti double-push navigasi (dipakai jalur user DAN admin).
///
/// AKAR MASALAH (insiden berulang, lihat docs/PERFORMANCE.md §18):
/// tap 2× cepat saat transisi push belum selesai menumpuk 2 route identik.
/// 1× back hanya menutup route atas → layar tampak SAMA → user melaporkan
/// "tombol back mati" padahal scroll masih jalan (bukan freeze).
///
/// RUMUS: [tryClaimNav] menolak klaim kedua untuk `key` yang sama dalam
/// [window] (default 2 dtk). Klaim DILEPAS saat route di-pop ([releaseNav])
/// — jadi buka-ulang setelah back tetap langsung bisa.
///
/// ATURAN (JANGAN DIBALIK): setiap `Navigator.push` ke layar chat/room/user
/// WAJIB lewat guard ini + `.then((_) => releaseNav(key))`.
library;

/// Jendela default: tap kedua dalam rentang ini untuk key yang sama ditolak.
const Duration kNavClaimWindow = Duration(seconds: 2);

final Map<String, DateTime> _navClaim = {};

/// Kunci unik per jenis tujuan — hindari tabrakan antar-jenis.
String navKeyChat(String chatId) => 'chat:$chatId';
String navKeyRoom(String roomId) => 'room:$roomId';
String navKeyUser(String uid) => 'user:$uid';

/// True bila navigasi boleh jalan. [now] hanya untuk test.
///
/// [key] kosong → selalu boleh (tidak ada yang bisa didedupe).
/// Klaim pertama = true; klaim kedua dalam [window] = false.
bool tryClaimNav(
  String key, {
  DateTime? now,
  Duration window = kNavClaimWindow,
}) {
  if (key.isEmpty) return true;
  final at = (now ?? DateTime.now()).toUtc();
  final prev = _navClaim[key];
  if (prev != null && at.difference(prev) < window) {
    return false;
  }
  _navClaim[key] = at;
  return true;
}

/// Lepas klaim [tryClaimNav] — panggil saat route tujuan di-pop.
void releaseNav(String key) {
  if (key.isEmpty) return;
  _navClaim.remove(key);
}

/// Hanya untuk test: bersihkan seluruh klaim.
void resetNavClaims() => _navClaim.clear();
