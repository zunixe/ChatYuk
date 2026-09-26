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
  /// SEED dilakukan malas (lazy) di _detectNewDevices: fetchDevices pertama
  /// setelah arm menjadi baseline diam-diam — TANPA fetch limit-1000 khusus
  /// (dulu 1 RPC besar tiap buka panel, penyebab utama lag buka panel).
  Future<void> armNotifications() async {
    // Muat device yang sudah pernah dinotifikasi (persist antar restart).
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(AdminBase._kSeenDevicesKey) ?? const [];
      _seenDeviceIds.addAll(saved);
    } catch (_) {}

    _seedDone = false;
    _seenDevicesLoaded = true;
    _notifArmed = true;
  }
}
