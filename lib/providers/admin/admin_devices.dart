part of '../admin_provider.dart';

/// Device tracking (tab Perangkat) + detail user.
mixin AdminDevicesMx on AdminBase {
  // ── Device tracking (tab Perangkat) ──
  static const int _devicePageSize = 100;
  List<Map<String, dynamic>> _devices = [];
  bool _devicesLoading = false;
  bool _devicesHasMore = true;
  int _devicesTotal = 0;
  bool _devicesFetchingMore = false;
  AdminErrKind? _devicesError;

  List<Map<String, dynamic>> get devices => _devices;
  bool get devicesLoading => _devicesLoading;
  bool get devicesHasMore => _devicesHasMore;
  int get devicesTotal => _devicesTotal;
  AdminErrKind? get devicesError => _devicesError;

Future<void> fetchDevices() async {
    _devicesLoading = true;
    _devicesError = null;
    if (!_disposed) notifyListeners();
    // Cold start / tab baru → cache disk dulu (tahan offline).
    if (_devices.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(
          AdminBase.kAdminDevicesKey,
        );
        if (cached.isNotEmpty && _devices.isEmpty) {
          _devices = cached;
          _devicesTotal = cached.length;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final res = await _service.listDevices(
        limit: _devicePageSize,
        offset: 0,
      );
      final fresh = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      if (fresh.isNotEmpty || _devices.isEmpty) {
        _devices = fresh;
        _devicesTotal = (res['total'] as num?)?.toInt() ?? 0;
        _devicesHasMore = _devices.length < _devicesTotal;
      }
      if (_devices.isNotEmpty) {
        MessageCache.instance.saveRawList(AdminBase.kAdminDevicesKey, _devices);
      }
      await _detectNewDevices(_devices);
    } catch (e) {
      _devicesError = classifyAdminError(e);
      dlog('[ADMIN] fetchDevices error: $e');
    }
    _devicesLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Refresh periodic tanpa spinner & tanpa menimpa list saat error.
  Future<void> refreshDevicesSilent() async {
    try {
      final res = await _service.listDevices(
        limit: _devicePageSize,
        offset: 0,
      );
      _devices = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _devicesTotal = (res['total'] as num?)?.toInt() ?? 0;
      _devicesHasMore = _devices.length < _devicesTotal;
      _devicesError = null;
    } catch (e) {
      dlog('[ADMIN] refreshDevicesSilent error: $e');
      if (_devices.isEmpty) _devicesError = classifyAdminError(e);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> fetchMoreDevices() async {
    if (_devicesFetchingMore || !_devicesHasMore || _devicesLoading) return;
    _devicesFetchingMore = true;
    try {
      final res = await _service.listDevices(
        limit: _devicePageSize,
        offset: _devices.length,
      );
      final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      if (more.isNotEmpty) _devices.addAll(more);
      _devicesHasMore = _devices.length < _devicesTotal;
    } catch (e) {
      dlog('[ADMIN] fetchMoreDevices error: $e');
    }
    _devicesFetchingMore = false;
    if (!_disposed) notifyListeners();
  }

  /// Detail lengkap satu user (profil + device + chat + lokasi).
  Future<Map<String, dynamic>> getUserDetail(String uid) async {
    return _service.getUserDetail(uid);
  }

  /// Notifikasi device baru — daftar install_id yang sudah dinotifikasi
  /// PERSIST di SharedPreferences, jadi tidak dobel antar restart app.
  /// Device yang di-exclude admin (app_settings.excluded_devices) tidak
  /// memicu notifikasi — daftar diambil ringan dari server sekali sesi.
  Future<void> _detectNewDevices(List<Map<String, dynamic>> devices) async {
    if (!_seenDevicesLoaded || _disposed) return; // tunggu armNotifications
    var excluded = <String>{};
    try {
      excluded = await _service.getExcludedDevices();
    } catch (_) {}
    for (final d in devices) {
      final installId = '${d['install_id'] ?? ''}';
      if (installId.isEmpty) continue;
      if (_seenDeviceIds.contains(installId)) continue;
      _seenDeviceIds.add(installId);
      await _persistSeenDevice(installId);
      if (excluded.contains(installId)) continue; // jangan notif excluded
      final nick = '${d['nickname'] ?? '?'}';
      final brand = '${d['brand'] ?? ''}';
      final model = '${d['model'] ?? ''}';
      final device = [brand, model].where((e) => e.isNotEmpty).join(' ');
      _emit('Device baru: $nick · ${device.isEmpty ? 'unknown' : device}');
    }
  }
}
