import 'package:flutter/foundation.dart';

import 'message_cache.dart';

/// Sematan (pin) GRUP/Room di daftar Pesan.
///
/// Disimpan LOKAL per perangkat (kv `gpins` lewat [MessageCache]) karena tabel
/// grup belum punya kolom pinned per-user (beda dengan chat private yang
/// menyimpan `pinned_by`/`pinned_at` di server). Urutan: terbaru disematkan
/// dulu, lalu grup dengan aktivitas terbaru.
class GroupPinStore {
  GroupPinStore._();

  static const String _key = 'gpins';

  /// Nama kunci tombstone: kv `saveRawObj` mengabaikan map kosong, jadi saat
  /// semua sematan dilepas kita tulis penanda ini agar perubahan ikut ke disk.
  static const String _tombstone = '__none__';

  static final Map<String, DateTime> _pins = {};
  static bool _loaded = false;

  @visibleForTesting
  static Map<String, DateTime> get pinsForTest => _pins;

  static bool isPinned(String id) => _pins.containsKey(id);

  static DateTime? pinnedAt(String id) => _pins[id];

  /// Muat sematan (sinkron dari RAM bila sesi ini sudah pernah menulis).
  static void load() {
    if (_loaded) return;
    final mem = MessageCache.instance.peekRawObj(_key);
    if (mem.isNotEmpty) {
      _apply(mem);
      _loaded = true;
      return;
    }
    _loaded = true;
    _loadDisk();
  }

  static Future<void> _loadDisk() async {
    try {
      final obj = await MessageCache.instance.loadRawObj(_key);
      if (obj.isNotEmpty && _pins.isEmpty) _apply(obj);
    } catch (_) {}
  }

  static void _apply(Map<String, dynamic> obj) {
    _pins.clear();
    obj.forEach((k, v) {
      if (k.isEmpty || k == _tombstone) return;
      final t = v is String ? DateTime.tryParse(v) : null;
      if (t != null) _pins[k] = t;
    });
  }

  /// Balik status sematan grup; mengembalikan status BARU (true = tersemat).
  static bool toggle(String id) {
    final removed = _pins.remove(id) != null;
    if (!removed) _pins[id] = DateTime.now();
    _persist();
    return !removed;
  }

  static void remove(String id) {
    if (_pins.remove(id) != null) _persist();
  }

  static void _persist() {
    final map = <String, dynamic>{
      for (final e in _pins.entries) e.key: e.value.toIso8601String(),
    };
    if (map.isEmpty) map[_tombstone] = DateTime.now().toIso8601String();
    MessageCache.instance.saveRawObj(_key, map);
  }

  /// Urutan grup di daftar Pesan: tersemat paling atas (terbaru dulu), lalu
  /// grup dengan [lastAt] terbaru. Fungsi MURNI (mudah diuji).
  static int compareGroups(
    String aId,
    DateTime? aLast,
    String bId,
    DateTime? bLast,
  ) {
    final ap = _pins[aId];
    final bp = _pins[bId];
    if (ap != null && bp == null) return -1;
    if (ap == null && bp != null) return 1;
    if (ap != null && bp != null) {
      final c = bp.compareTo(ap);
      if (c != 0) return c;
    }
    final al = aLast ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bl = bLast ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bl.compareTo(al);
  }

  @visibleForTesting
  static void resetForTest() {
    _pins.clear();
    _loaded = false;
  }
}
