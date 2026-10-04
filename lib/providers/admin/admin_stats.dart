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

  /// Muat statistik. Urutan: memori → cache disk (instan, tahan offline) →
  /// network. Kegagalan TIDAK mengosongkan data lama; hanya menandai error
  /// agar UI bisa menampilkan banner "data terakhir".
  Future<void> fetchStats({bool force = false}) async {
    _loading = true;
    _error = null;
    _notifyStats();
    // Cold start / data kosong: tampilkan cache disk dulu (instan, tanpa
    // network) supaya panel tidak kosong saat offline.
    if (_stats == null) {
      try {
        final cached = await MessageCache.instance.loadRawObj(AdminBase.kAdminStatsKey);
        if (cached.isNotEmpty && _stats == null) {
          _stats = cached;
          _pointsEnabled = _stats?['points_enabled'] == true;
          _notifyStats();
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
    _notifyStats();
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
    _notifyStats();
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

  /// Halaman daftar user statistik (RPC ber-paginasi — ganti list full dari
  /// detail untuk 4 kunci user). Return {'items': [...], 'total': n}.
  Future<Map<String, dynamic>> listStatsUsers(
    String kind, {
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      return await _service.listStatsUsers(kind, limit: limit, offset: offset);
    } catch (e) {
      dlog('[ADMIN] listStatsUsers error: $e');
      return {'items': const [], 'total': 0};
    }
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

  // ── Insight registrasi (KPI + tren bulanan + sumber) ──
  Map<String, dynamic> _regKpis = {};
  List<Map<String, dynamic>> _regMonthly = [];
  bool _regInsightLoading = false;
  bool _regInsightLoaded = false;

  Map<String, dynamic> get regKpis => _regKpis;
  List<Map<String, dynamic>> get regMonthly => _regMonthly;
  bool get regInsightLoading => _regInsightLoading;
  bool get regInsightLoaded => _regInsightLoaded;

  /// Muat KPI + tren bulanan sekali (dipanggil saat kartu dibuka).
  Future<void> fetchRegistrationInsights({bool force = false}) async {
    if (_regInsightLoaded && !force) return;
    _regInsightLoading = true;
    _notifyStats();
    try {
      final results = await Future.wait([
        _service.fetchRegistrationKpis(),
        _service.fetchRegistrationsMonthly(12),
      ]);
      _regKpis = results[0] as Map<String, dynamic>;
      _regMonthly = results[1] as List<Map<String, dynamic>>;
      _regInsightLoaded = true;
    } catch (e) {
      dlog('[ADMIN] fetchRegistrationInsights error: $e');
    }
    _regInsightLoading = false;
    _notifyStats();
  }

  // ── Sebaran geografis (negara → kota) ──
  List<Map<String, dynamic>> _countryStats = const [];
  final Map<String, List<Map<String, dynamic>>> _cityStatsCache = {};
  bool _geoLoading = false;
  bool _geoLoaded = false;

  List<Map<String, dynamic>> get countryStats => _countryStats;
  bool get geoLoading => _geoLoading;
  bool get geoLoaded => _geoLoaded;

  /// Muat sebaran user per negara (sekali, cache per sesi).
  Future<void> fetchCountryStats({bool force = false}) async {
    if (_geoLoaded && !force) return;
    _geoLoading = true;
    _notifyStats();
    try {
      _countryStats = await _service.fetchCountryStats();
      _geoLoaded = true;
    } catch (e) {
      dlog('[ADMIN] fetchCountryStats error: $e');
    }
    _geoLoading = false;
    _notifyStats();
  }

  /// Muat sebaran kota untuk satu negara (cache per negara).
  Future<List<Map<String, dynamic>>> fetchCityStats(
    String country, {
    bool force = false,
  }) async {
    if (!force && _cityStatsCache.containsKey(country)) {
      return _cityStatsCache[country]!;
    }
    try {
      final list = await _service.fetchCityStats(country);
      _cityStatsCache[country] = list;
      return list;
    } catch (e) {
      dlog('[ADMIN] fetchCityStats error: $e');
      return const [];
    }
  }

  Future<void> fetchRegistrationsDaily(int year, int month) async {
    final cacheKey = '${year}_$month';
    // Bulan lampau tidak berubah lagi → cache permanen; bulan berjalan
    // di-refetch tiap kali dibuka.
    final isCurrentMonth =
        year == DateTime.now().year && month == DateTime.now().month;
    if (!isCurrentMonth && _regDailyCache.containsKey(cacheKey)) {
      if (_regDaily == _regDailyCache[cacheKey]) return;
      _regDaily = _regDailyCache[cacheKey]!;
      _notifyStats();
      return;
    }
    _regLoading = true;
    _notifyStats();
    try {
      _regDaily = await _service.fetchRegistrationsDaily(year, month);
      _regDailyCache[cacheKey] = _regDaily;
    } catch (e) {
      dlog('[ADMIN] fetchRegistrationsDaily error: $e');
      _regDaily = {};
    }
    _regLoading = false;
    _notifyStats();
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
      _notifyStats();
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
  bool _storageStatsError = false;
  DateTime? _storageStatsAt;
  static const _storageTtl = Duration(minutes: 10);

  Map<String, dynamic>? get storageStats => _storageStats;
  bool get storageStatsLoading => _storageStatsLoading;
  bool get storageStatsError => _storageStatsError;

  /// TTL 10 menit — kartu Overview remount tidak menembak RPC berulang.
  /// Gagal = data lama dipertahankan + flag error (UI tampil retry,
  /// bukan spinner/0 diam).
  Future<void> fetchStorageStats({bool force = false}) async {
    if (!force &&
        _storageStats != null &&
        _storageStatsAt != null &&
        DateTime.now().difference(_storageStatsAt!) < _storageTtl) {
      return;
    }
    _storageStatsLoading = true;
    _storageStatsError = false;
    _notifyStats();
    try {
      final fresh = await _service.getStorageStats();
      if (fresh.isEmpty) {
        // Kosong = RPC gagal diam-diam — jangan timpa data baik.
        if (_storageStats == null) _storageStatsError = true;
      } else {
        _storageStats = fresh;
        _storageStatsAt = DateTime.now();
      }
    } catch (e) {
      dlog('[ADMIN] fetchStorageStats error: $e');
      if (_storageStats == null) _storageStatsError = true;
    }
    _storageStatsLoading = false;
    _notifyStats();
  }

  // ── Breakdown ukuran tabel (sheet dari kartu Database) ──
  List<Map<String, dynamic>> _tableSizes = [];
  bool _tableSizesLoading = false;
  bool _tableSizesError = false;

  List<Map<String, dynamic>> get tableSizes => _tableSizes;
  bool get tableSizesLoading => _tableSizesLoading;
  bool get tableSizesError => _tableSizesError;

  /// Selalu fetch fresh saat sheet dibuka (tanpa TTL — angka ukuran
  /// berubah tiap ada tulis; RPC hanya baca katalog, murah).
  /// Gagal = data lama dipertahankan + flag error (UI tampil retry).
  Future<void> fetchTableSizes() async {
    _tableSizesLoading = true;
    _tableSizesError = false;
    _notifyStats();
    try {
      final res = await _service.getTableSizes();
      final rows =
          List<Map<String, dynamic>>.from(res['tables'] ?? const []);
      if (rows.isEmpty && _tableSizes.isEmpty) {
        _tableSizesError = true;
      } else if (rows.isNotEmpty) {
        _tableSizes = rows;
      }
    } catch (e) {
      dlog('[ADMIN] fetchTableSizes error: $e');
      if (_tableSizes.isEmpty) _tableSizesError = true;
    }
    _tableSizesLoading = false;
    _notifyStats();
  }

  // ── Daftar registrasi email ──
  List<Map<String, dynamic>> _registrations = [];
  bool _registrationsLoading = false;

  List<Map<String, dynamic>> get registrations => _registrations;
  bool get registrationsLoading => _registrationsLoading;

  Future<void> fetchRegistrations() async {
    _registrationsLoading = true;
    _notifyStats();
    try {
      final res = await _service.listRegistrations(limit: 200, offset: 0);
      _registrations =
          List<Map<String, dynamic>>.from(res['items'] ?? const []);
    } catch (e) {
      dlog('[ADMIN] fetchRegistrations error: $e');
    }
    _registrationsLoading = false;
    _notifyStats();
  }

  // ── Cloudflare Realtime TURN usage ──
  Map<String, dynamic>? _cfUsage;

  Map<String, dynamic>? get cfUsage => _cfUsage;

  Future<void> fetchCfUsage() async {
    try {
      _cfUsage = await _service.getCfUsage();
      _notifyStats();
    } catch (e) {
      dlog('[ADMIN] fetchCfUsage error: $e');
    }
  }
}
