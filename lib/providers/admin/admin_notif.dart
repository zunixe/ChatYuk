part of '../admin_provider.dart';

/// Notifikasi admin (device baru / call video aktif).
/// State + _emit ada di [AdminBase]; detector pendatang baru tinggal di
/// mixin pemanggil (devices/calls) karena member antar-mixin tak terlihat.
mixin AdminNotifMx on AdminBase {
  /// Stream notifikasi admin — dipakai layar panel untuk menampilkan
  /// snackbar + notifikasi sistem (localNotifications).
  Stream<String> get notifications => _notifCtrl.stream;

  /// Arm notifikasi: muat dulu daftar device yang SUDAH pernah dinotifikasi
  /// (tersimpan di SharedPreferences, persist antar restart), baru aktif.
  Future<void> armNotifications() async {
    // 1) Muat device yang sudah pernah dinotifikasi (persist antar restart).
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(AdminBase._kSeenDevicesKey) ?? const [];
      _seenDeviceIds.addAll(saved);
    } catch (_) {}

    // 2) SEED diam-diam: semua device yang sudah ada SEKARANG dimasukkan ke
    // daftar seen TANPA notifikasi. Hanya device yang muncul SETELAH titik
    // ini yang akan dinotifikasi.
    try {
      final res = await _service.listDevices(limit: 1000, offset: 0);
      final items = (res['items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final d in items) {
        final id = '${d['install_id'] ?? ''}';
        if (id.isNotEmpty) _seenDeviceIds.add(id);
      }
      // Simpan gabungan supaya restart berikutnya punya baseline yang sama.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(AdminBase._kSeenDevicesKey, _seenDeviceIds.toList());
    } catch (e) {
      dlog('[ADMIN] arm seed devices error: $e');
    }

    _seenDevicesLoaded = true;
    _notifArmed = true;
  }
}
