/// Cache STATUS BROADCAST per room (grant + live_uid) — memori dulu,
/// disk opsional.
///
/// Kenapa: dulu `_broadcastReady`/`_isGrantedBroadcast` baru terisi setelah
/// RPC `myBroadcastGranted` selesai → tombol kamera & banner "Mulai
/// Broadcast" MUNCUL belakangan (terlihat "ngeblink") tiap buka grup.
/// Dengan cache ini nilai terakhir bisa dibaca SINKRON di initState →
/// kontrol tampil sejak frame pertama, lalu direkonsiliasi RPC.
class BroadcastStateCache {
  BroadcastStateCache._();

  /// roomId → (granted, liveUid). liveUid null = tidak ada yang live.
  static final Map<String, _Entry> _mem = <String, _Entry>{};

  /// Simpan status terbaru (dipanggil setelah RPC init / refresh).
  static void save(String roomId, {required bool granted, String? liveUid}) {
    _mem[roomId] = _Entry(granted, liveUid);
    // Cap ringan: room yang dibuka seumur sesi biasanya sedikit; buang
    // entri terlama bila > 60 supaya tidak tumbuh tanpa batas.
    while (_mem.length > 60) {
      _mem.remove(_mem.keys.first);
    }
  }

  /// Status tersimpan (null = belum pernah dibuka di sesi ini).
  static ({bool granted, String? liveUid})? peek(String roomId) {
    final e = _mem[roomId];
    if (e == null) return null;
    return (granted: e.granted, liveUid: e.liveUid);
  }

  /// Hapus (mis. user keluar room / logout) — kontrol kembali menunggu RPC.
  static void clear(String roomId) => _mem.remove(roomId);
}

class _Entry {
  _Entry(this.granted, this.liveUid);
  bool granted;
  String? liveUid;
}
