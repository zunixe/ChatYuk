part of '../admin_provider.dart';

/// Statistik overview + poin + storage/tabel/registrasi/CF usage.
mixin AdminStatsMx on AdminBase {
  Map<String, dynamic>? _stats;
  bool _loading = false;
  AdminErrKind? _error;
  bool _pointsEnabled = true;

  Map<String, dynamic>? get stats => _stats;
  bool get loading => _loading;
  AdminErrKind? get error => _error;
  bool get pointsEnabled => _pointsEnabled;

  /// True bila kegagalan terakhir karena koneksi (dipakai banner "data terakhir").
  bool get hasData => _stats != null && _stats!.isNotEmpty;


  /// Muat statistik. Urutan: memori → cache disk (instan, tahan offline) →
  /// network. Kegagalan TIDAK mengosongkan data lama; hanya menandai error
  /// agar UI bisa menampilkan banner "data terakhir".
  Future<void> fetchStats({bool force = false}) async {
    _loading = true;
    _error = null;
    if (!_disposed) notifyListeners();
    // Cold start / data kosong: tampilkan cache disk dulu (instan, tanpa
    // network) supaya panel tidak kosong saat offline.
    if (_stats == null) {
      try {
        final cached = await MessageCache.instance.loadRawObj(AdminBase.kAdminStatsKey);
        if (cached.isNotEmpty && _stats == null) {
          _stats = cached;
          _pointsEnabled = _stats?['points_enabled'] == true;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {}
    }
    try {
      _stats = force
          ? await _service.getStatsForce()
          : await _service.getStats();
      _pointsEnabled = _stats?['points_enabled'] == true;
      if (_stats != null && _stats!.isNotEmpty) {
        MessageCache.instance.saveRawObj(AdminBase.kAdminStatsKey, _stats!);
      }
    } catch (e) {
      // Data lama dipertahankan; error hanya ditandai (kategori, bukan teks
      // mentah — detail asli tetap ke dlog).
      _error = classifyAdminError(e);
      dlog('[ADMIN] fetchStats error: $e');
    }
    _loading = false;
    if (!_disposed) notifyListeners();
  }

  /// Refresh statistik tanpa memicu state "loading" (untuk timer/polling).
  /// Server meng-cache hasil 5 menit — polling ini jadi O(1) di DB.
  /// Gagal = data lama dipertahankan (tanpa error banner; polling diam-diam).
  Future<void> refreshStats({bool force = false}) async {
    try {
      final fresh = force
          ? await _service.getStatsForce()
          : await _service.getStats();
      if (fresh.isEmpty) return; // jangan timpa data baik dengan kosong
      _stats = fresh;
      _pointsEnabled = _stats?['points_enabled'] == true;
      MessageCache.instance.saveRawObj(AdminBase.kAdminStatsKey, fresh);
    } catch (e) {
      dlog('[ADMIN] refreshStats error: $e');
    }
    if (!_disposed) notifyListeners();
  }

  /// Ambil detail data card Overview (list user/room per kategori).
  /// Di-cache 60 detik: peta user & bottom sheet stat memanggil ini di
  /// saat bersamaan — hindari double fetch payload besar.
  Map<String, dynamic>? _detailCache;
  DateTime? _detailCacheAt;
  static const _detailTtl = Duration(seconds: 60);

  Future<Map<String, dynamic>> fetchStatsDetail({bool force = false}) async {
    if (!force &&
        _detailCache != null &&
        _detailCacheAt != null &&
        DateTime.now().difference(_detailCacheAt!) < _detailTtl) {
      return _detailCache!;
    }
    try {
      final d = await _service.getStatsDetail();
      _detailCache = d;
      _detailCacheAt = DateTime.now();
      return d;
    } catch (e) {
      dlog('[ADMIN] fetchStatsDetail error: $e');
      return {};
    }
  }

  /// Buang cache detail 60 detik — dipakai saat daftar device exclude
  /// berubah supaya card Overview langsung menampilkan data segar
  /// (device yang di-unexclude muncul lagi tanpa nunggu cache kadaluarsa).
  void invalidateStatsDetail() {
    _detailCache = null;
    _detailCacheAt = null;
  }

  // ── UID tersembunyi (dummy + device-ter-exclude) untuk filter peta ──
  Set<String> _hiddenUids = {};
  Set<String> get hiddenUids => _hiddenUids;
  bool isHiddenUid(String id) => id.isNotEmpty && _hiddenUids.contains(id);

  Future<void> fetchHiddenUids() async {
    try {
      _hiddenUids = await _service.fetchHiddenUids();
    } catch (e) {
      dlog('[ADMIN] fetchHiddenUids error: $e');
    }
  }

  // ── Bar chart registrasi email per hari ──
  Map<int, int> _regDaily = {};
  bool _regLoading = false;
  final Map<String, Map<int, int>> _regDailyCache = {};

  Map<int, int> get regDaily => _regDaily;
  bool get regLoading => _regLoading;

  Future<void> fetchRegistrationsDaily(int year, int month) async {
    final cacheKey = '${year}_$month';
    // Bulan lampau tidak berubah lagi → cache permanen; bulan berjalan
    // di-refetch tiap kali dibuka.
    final isCurrentMonth =
        year == DateTime.now().year && month == DateTime.now().month;
    if (!isCurrentMonth && _regDailyCache.containsKey(cacheKey)) {
      if (_regDaily == _regDailyCache[cacheKey]) return;
      _regDaily = _regDailyCache[cacheKey]!;
      if (!_disposed) notifyListeners();
      return;
    }
    _regLoading = true;
    if (!_disposed) notifyListeners();
    try {
      _regDaily = await _service.fetchRegistrationsDaily(year, month);
      _regDailyCache[cacheKey] = _regDaily;
    } catch (e) {
      dlog('[ADMIN] fetchRegistrationsDaily error: $e');
      _regDaily = {};
    }
    _regLoading = false;
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>?> massBonus(int bonus) async {
    try {
      final result = await _service.massBonus(bonus);
      await fetchStats();
      return result;
    } catch (e) {
      dlog('[ADMIN] massBonus error: $e');
      return null;
    }
  }

  Future<int?> resetAllPoints() async {
    try {
      final count = await _service.resetAllPoints();
      await fetchStats();
      return count;
    } catch (e) {
      dlog('[ADMIN] resetAllPoints error: $e');
      return null;
    }
  }

  Future<bool> togglePointsSystem(bool enabled) async {
    try {
      final result = await _service.togglePointsSystem(enabled);
      _pointsEnabled = result;
      if (!_disposed) notifyListeners();
      return result;
    } catch (e) {
      dlog('[ADMIN] togglePointsSystem error: $e');
      return false;
    }
  }

  Future<void> forceLogout(String targetUid) async {
    try {
      await _service.forceLogout(targetUid);
    } catch (e) {
      dlog('[ADMIN] forceLogout error: $e');
      rethrow;
    }
  }

  // ── Statistik penggunaan data Supabase ──
  Map<String, dynamic>? _storageStats;
  bool _storageStatsLoading = false;
  DateTime? _storageStatsAt;
  static const _storageTtl = Duration(minutes: 10);

  Map<String, dynamic>? get storageStats => _storageStats;
  bool get storageStatsLoading => _storageStatsLoading;

  /// TTL 10 menit — kartu Overview remount tidak menembak RPC berulang.
  Future<void> fetchStorageStats({bool force = false}) async {
    if (!force &&
        _storageStats != null &&
        _storageStatsAt != null &&
        DateTime.now().difference(_storageStatsAt!) < _storageTtl) {
      return;
    }
    _storageStatsLoading = true;
    if (!_disposed) notifyListeners();
    try {
      _storageStats = await _service.getStorageStats();
      _storageStatsAt = DateTime.now();
    } catch (e) {
      dlog('[ADMIN] fetchStorageStats error: $e');
    }
    _storageStatsLoading = false;
    if (!_disposed) notifyListeners();
  }

  // ── Breakdown ukuran tabel (sheet dari kartu Database) ──
  List<Map<String, dynamic>> _tableSizes = [];
  bool _tableSizesLoading = false;

  List<Map<String, dynamic>> get tableSizes => _tableSizes;
  bool get tableSizesLoading => _tableSizesLoading;

  /// Selalu fetch fresh saat sheet dibuka (tanpa TTL — angka ukuran
  /// berubah tiap ada tulis; RPC hanya baca katalog, murah).
  Future<void> fetchTableSizes() async {
    _tableSizesLoading = true;
    if (!_disposed) notifyListeners();
    try {
      final res = await _service.getTableSizes();
      _tableSizes =
          List<Map<String, dynamic>>.from(res['tables'] ?? const []);
    } catch (e) {
      dlog('[ADMIN] fetchTableSizes error: $e');
    }
    _tableSizesLoading = false;
    if (!_disposed) notifyListeners();
  }

  // ── Daftar registrasi email ──
  List<Map<String, dynamic>> _registrations = [];
  bool _registrationsLoading = false;

  List<Map<String, dynamic>> get registrations => _registrations;
  bool get registrationsLoading => _registrationsLoading;

  Future<void> fetchRegistrations() async {
    _registrationsLoading = true;
    if (!_disposed) notifyListeners();
    try {
      final res = await _service.listRegistrations(limit: 200, offset: 0);
      _registrations =
          List<Map<String, dynamic>>.from(res['items'] ?? const []);
    } catch (e) {
      dlog('[ADMIN] fetchRegistrations error: $e');
    }
    _registrationsLoading = false;
    if (!_disposed) notifyListeners();
  }

  // ── Cloudflare Realtime TURN usage ──
  Map<String, dynamic>? _cfUsage;

  Map<String, dynamic>? get cfUsage => _cfUsage;

  Future<void> fetchCfUsage() async {
    try {
      _cfUsage = await _service.getCfUsage();
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[ADMIN] fetchCfUsage error: $e');
    }
  }
}
