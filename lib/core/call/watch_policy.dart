/// Kebijakan negosiasi "watch" (admin memantau call 1:1).
///
/// Masalah nyata (2026-09-28, call audio): admin mengirim `watch_request`
/// tiap 3 dtk; tiap ~8 dtk throttle peserta habis → peserta MENUTUP pc
/// watch lama & membuat yang baru → audio peserta putus sesaat lalu
/// tersambung lagi ("suara sempat hilang, muncul lagi"). Terbukti di DB:
/// 5 `watch_request` + 3 `watch_offer` dalam 9 dtk untuk satu call.
///
/// Fungsi murni di sini supaya keputusan bisa dikunci unit test tanpa
/// plugin WebRTC.

/// Aksi sisi PESERTA saat menerima `watch_request` dari admin.
enum WatchReplyAction {
  /// Abaikan: bukan untuk kita / belum ada media / bukan admin / baru saja
  /// dijawab (< throttle).
  ignore,

  /// Kirim ulang status mic/kamera — pc watch masih sehat, JANGAN rebuild.
  sendState,

  /// Buat pc watch baru + kirim offer (pc belum ada / sudah mati).
  rebuildOffer,
}

/// Keputusan peserta. [hasHealthyPc] = pc watch untuk watcher ini ada dan
/// state-nya bukan `failed`/`closed` (connecting/connected/disconnected
/// dianggap sehat — `disconnected` bisa pulih sendiri). Pemanggil
/// menghitung bool ini dari enum flutter_webrtc (core tetap bebas plugin).
WatchReplyAction decideWatchReply({
  required bool isForMe,
  required bool hasLocalMedia,
  required bool isAdminWatcher,
  required bool alreadyRepliedRecently,
  required bool hasHealthyPc,
}) {
  if (!isForMe || !hasLocalMedia || !isAdminWatcher) {
    return WatchReplyAction.ignore;
  }
  if (hasHealthyPc) return WatchReplyAction.sendState;
  if (alreadyRepliedRecently) return WatchReplyAction.ignore;
  return WatchReplyAction.rebuildOffer;
}

/// Keputusan sisi ADMIN: kirim `watch_request` ke peserta ini?
///
/// [negotiating] = sudah ada offer masuk tetapi belum selesai connect
/// (beri waktu handshake; jangan minta ulang → peserta tidak rebuild).
bool shouldRequestWatch({
  required bool connected,
  required bool negotiating,
}) {
  if (connected) return false;
  if (negotiating) return false;
  return true;
}
