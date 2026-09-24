import 'dart:async';

import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/active_call_model.dart';
import '../services/admin_service.dart';
import '../services/admin_call_watch_service.dart';
export '../services/admin_call_watch_service.dart' show WatchSession;
import '../core/cache/message_cache.dart';
import '../core/cache/photo_cache.dart';
import '../core/admin_err.dart';
import '../services/storage_photo_service.dart';

class AdminProvider extends ChangeNotifier {
  /// Service disuntik dari luar (default produksi) — pola sama dengan
  /// `ChatProvider`/`RoomProvider`. Test: `AdminProvider(service: mock)`.
  final AdminService _service;

  /// Client Supabase untuk realtime monitor (bisa disuntik di test).
  /// LAZY: tidak menyentuh `Supabase.instance` saat konstruksi.
  final SupabaseClient? _injectedSb;
  SupabaseClient get _sb => _injectedSb ?? Supabase.instance.client;

  AdminProvider({AdminService? service, SupabaseClient? sb})
      : _service = service ?? AdminService(),
        _injectedSb = sb;

  // ── Notifikasi admin (device baru / call video aktif) ──
  final StreamController<String> _notifCtrl =
      StreamController<String>.broadcast();
  final Set<String> _seenDeviceIds = {};
  final Set<String> _seenCallIds = {};
  bool _notifArmed = false;
  bool _seenDevicesLoaded = false;
  static const String _kSeenDevicesKey = 'admin_seen_device_ids';

  /// Stream notifikasi admin — dipakai layar panel untuk menampilkan
  /// snackbar + notifikasi sistem (localNotifications).
  Stream<String> get notifications => _notifCtrl.stream;

  void _emit(String msg) {
    if (_disposed) return;
    try {
      if (!_notifCtrl.isClosed) _notifCtrl.add(msg);
    } catch (_) {}
  }

  /// Arm notifikasi: muat dulu daftar device yang SUDAH pernah dinotifikasi
  /// (tersimpan di SharedPreferences, persist antar restart), baru aktif.
  Future<void> armNotifications() async {
    // 1) Muat device yang sudah pernah dinotifikasi (persist antar restart).
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kSeenDevicesKey) ?? const [];
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
      await prefs.setStringList(_kSeenDevicesKey, _seenDeviceIds.toList());
    } catch (e) {
      dlog('[ADMIN] arm seed devices error: $e');
    }

    _seenDevicesLoaded = true;
    _notifArmed = true;
  }

  Future<void> _persistSeenDevice(String installId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kSeenDevicesKey) ?? <String>[];
      if (!list.contains(installId)) {
        list.add(installId);
        // Batasi ukuran list (simpan 500 terbaru).
        while (list.length > 500) {
          list.removeAt(0);
        }
        await prefs.setStringList(_kSeenDevicesKey, list);
      }
    } catch (_) {}
  }
  Map<String, dynamic>? _stats;
  bool _loading = false;
  AdminErrKind? _error;
  bool _pointsEnabled = true;
  bool _disposed = false;

  Map<String, dynamic>? get stats => _stats;
  bool get loading => _loading;
  AdminErrKind? get error => _error;
  bool get pointsEnabled => _pointsEnabled;

  // ── Cache disk data admin ──
  // Data admin disimpan terenkripsi (MessageCache → SQLCipher + Keystore)
  // supaya saat OFFLINE panel tetap menampilkan data terakhir, bukan layar
  // error. Kunci `admin_*` supaya tombol "bersihkan cache admin" bisa
  // menghapusnya selektif (lihat clearAdminCache()).
  static const kAdminStatsKey = 'admin_stats';
  static const kAdminChatsKey = 'admin_chats';
  static const kAdminDevicesKey = 'admin_devices';
  static const kAdminDeletedKey = 'admin_deleted';
  static const kAdminContactKey = 'admin_contact';
  static String adminDummyKey(String myUid) => 'admin_dummy_$myUid';
  static String adminChatMsgKey(String chatId) => 'admin_chatmsg_$chatId';

  /// Kunci cache yang dibersihkan tombol "Bersihkan cache admin".
  static const List<String> adminCacheKeys = [
    kAdminStatsKey,
    kAdminChatsKey,
    kAdminDevicesKey,
    kAdminDeletedKey,
    kAdminContactKey,
  ];

  /// True bila kegagalan terakhir karena koneksi (dipakai banner "data terakhir").
  bool get hasData => _stats != null && _stats!.isNotEmpty;


  // ── Passthrough (Fase 9b) — screen admin tidak import AdminService ──
  Future<void> setDummyAi(
    String uid,
    bool enabled,
    Map<String, dynamic> persona, {
    bool? scheduleAuto,
    bool? guardEnabled,
    bool? noRateLimit,
    int? maxReplies,
    int? minInterval,
    List<int>? activeHours,
    String? model,
    bool? photosEnabled,
  }) =>
      _service.setDummyAi(
        uid, enabled, persona,
        scheduleAuto: scheduleAuto,
        guardEnabled: guardEnabled,
        noRateLimit: noRateLimit,
        maxReplies: maxReplies,
        minInterval: minInterval,
        activeHours: activeHours,
        model: model,
        photosEnabled: photosEnabled,
      );
  Future<List<int>> autoScheduleAi(String uid) => _service.autoScheduleAi(uid);
  /// Buat sesi pantau panggilan (admin) — di-dispose oleh screen.
  WatchSession createWatchSession(ActiveCallInfo call) => WatchSession(call);

  /// Popup update aplikasi (app_settings) — dibaca/disimpan dari tab
  /// Global Setting. Screen admin tidak import AdminService.
  Future<Map<String, dynamic>?> getUpdateConfig() =>
      _service.getUpdateConfig();
  Future<void> saveUpdateConfig({
    required bool enabled,
    required String latestVersion,
    required String minVersion,
    required String notes,
  }) =>
      _service.saveUpdateConfig(
        enabled: enabled,
        latestVersion: latestVersion,
        minVersion: minVersion,
        notes: notes,
      );

  Future<Map<String, dynamic>> getPointSettings() => _service.getPointSettings();
  Future<Map<String, dynamic>> updatePointSettings(Map<String, dynamic> p) =>
      _service.updatePointSettings(p);
  Future<Map<String, dynamic>> getAiSettings() => _service.getAiSettings();
  Future<Map<String, dynamic>> setAiSettings({
    bool? globalEnabled,
    int? maxReplies,
    int? minInterval,
    bool? guardEnabled,
    bool? aiAiEnabled,
    String? apiBase,
    String? apiKey,
    String? defaultModel,
  }) =>
      _service.setAiSettings(
        globalEnabled: globalEnabled,
        maxReplies: maxReplies,
        minInterval: minInterval,
        guardEnabled: guardEnabled,
        aiAiEnabled: aiAiEnabled,
        apiBase: apiBase,
        apiKey: apiKey,
        defaultModel: defaultModel,
      );
  Future<List<Map<String, dynamic>>> getAiProviders() =>
      _service.getAiProviders();
  Future<Map<String, dynamic>> saveAiProvider({
    String? id,
    String? label,
    String? apiBase,
    String? apiKey,
    String? defaultModel,
    String? storyModel,
    String? fallbackModel,
  }) =>
      _service.saveAiProvider(
        id: id,
        label: label,
        apiBase: apiBase,
        apiKey: apiKey,
        defaultModel: defaultModel,
        storyModel: storyModel,
        fallbackModel: fallbackModel,
      );
  Future<void> deleteAiProvider(String id) => _service.deleteAiProvider(id);
  Future<void> activateAiProvider(String id) => _service.activateAiProvider(id);
  Future<Map<String, dynamic>> registerDummy({
    required String nickname,
    String gender = 'male',
    int age = 25,
    String country = 'Indonesia',
    String city = 'Jakarta',
  }) =>
      _service.registerDummy(
        nickname: nickname,
        gender: gender,
        age: age,
        country: country,
        city: city,
      );
  Future<Map<String, dynamic>> listDummiesPage({int limit = 50, int offset = 0}) =>
      _service.listDummiesPage(limit: limit, offset: offset);
  Future<Map<String, dynamic>> getDummyStories(String uid, {int days = 14}) =>
      _service.getDummyStories(uid, days: days);
  Future<Map<String, dynamic>> generateDummyStory(
    String uid, {
    required String storyDate,
  }) =>
      _service.generateDummyStory(uid, storyDate: storyDate);
  Future<Map<String, dynamic>> deleteDummy(String uid) => _service.deleteDummy(uid);
  Future<void> updateDummyProfile({
    required String uid,
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
  }) =>
      _service.updateDummyProfile(
        uid: uid, nickname: nickname, gender: gender, age: age,
        country: country, city: city,
      );
  Future<bool> isNicknameAvailable(String nickname, {String? excludeUid}) =>
      _service.isNicknameAvailable(nickname, excludeUid: excludeUid);
  Future<void> setDummyStatus(String uid, String status) =>
      _service.setDummyStatus(uid, status);
  Future<void> wakeDummy(String uid, {int minutes = 30}) =>
      _service.wakeDummy(uid, minutes: minutes);

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
        final cached = await MessageCache.instance.loadRawObj(kAdminStatsKey);
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
        MessageCache.instance.saveRawObj(kAdminStatsKey, _stats!);
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
      MessageCache.instance.saveRawObj(kAdminStatsKey, fresh);
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

  // ── Admin Chat Monitor ──
  static const int chatPageSize = 50;
  // 40 (dulu 100): buka chat ringan — 100 pesan + view_once base64 berat
  // di-serialize sekaligus bikin lambat. Sisanya dimuat saat scroll ke atas.
  static const int messagePageSize = 40;

  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _chatMessages = [];
  List<String> _adminUids = [];
  bool _chatsLoading = false;
  bool _chatsHasMore = true;
  int _chatsTotal = 0;
  bool _chatsFetchingMore = false;
  AdminErrKind? _chatsError;

  List<Map<String, dynamic>> get chats => _chats;
  List<Map<String, dynamic>> get chatMessages => _chatMessages;
  List<String> get adminUids => _adminUids;
  bool get chatsLoading => _chatsLoading;
  bool get chatsHasMore => _chatsHasMore;
  int get chatsTotal => _chatsTotal;
  AdminErrKind? get chatsError => _chatsError;

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
          kAdminDevicesKey,
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
        MessageCache.instance.saveRawList(kAdminDevicesKey, _devices);
      }
      await _detectNewDevices(_devices);
    } catch (e) {
      _devicesError = classifyAdminError(e);
      dlog('[ADMIN] fetchDevices error: $e');
    }
    _devicesLoading = false;
    if (!_disposed) notifyListeners();
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

  // ── Arsip user terhapus (tab Terhapus) ──
  static const int _deletedPageSize = 100;
  List<Map<String, dynamic>> _deleted = [];
  bool _deletedLoading = false;
  bool _deletedHasMore = true;
  int _deletedTotal = 0;
  bool _deletedFetchingMore = false;
  AdminErrKind? _deletedError;

  List<Map<String, dynamic>> get deleted => _deleted;
  bool get deletedLoading => _deletedLoading;
  bool get deletedHasMore => _deletedHasMore;
  int get deletedTotal => _deletedTotal;
  AdminErrKind? get deletedError => _deletedError;

  Future<void> fetchDeleted() async {
    _deletedLoading = true;
    _deletedError = null;
    if (!_disposed) notifyListeners();
    // Cold start / tab baru → cache disk dulu (tahan offline).
    if (_deleted.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(
          kAdminDeletedKey,
        );
        if (cached.isNotEmpty && _deleted.isEmpty) {
          _deleted = cached;
          _deletedTotal = cached.length;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final res = await _service.listDeleted(
        limit: _deletedPageSize,
        offset: 0,
      );
      final fresh = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      if (fresh.isNotEmpty || _deleted.isEmpty) {
        _deleted = fresh;
        _deletedTotal = (res['total'] as num?)?.toInt() ?? 0;
        _deletedHasMore = _deleted.length < _deletedTotal;
      }
      if (_deleted.isNotEmpty) {
        MessageCache.instance.saveRawList(kAdminDeletedKey, _deleted);
      }
    } catch (e) {
      _deletedError = classifyAdminError(e);
      dlog('[ADMIN] fetchDeleted error: $e');
    }
    _deletedLoading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> fetchMoreDeleted() async {
    if (_deletedFetchingMore || !_deletedHasMore || _deletedLoading) return;
    _deletedFetchingMore = true;
    try {
      final res = await _service.listDeleted(
        limit: _deletedPageSize,
        offset: _deleted.length,
      );
      final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      if (more.isNotEmpty) _deleted.addAll(more);
      _deletedHasMore = _deleted.length < _deletedTotal;
    } catch (e) {
      dlog('[ADMIN] fetchMoreDeleted error: $e');
    }
    _deletedFetchingMore = false;
    if (!_disposed) notifyListeners();
  }

  /// Riwayat device user yang sudah dihapus.
  Future<List<Map<String, dynamic>>> getDeletedDeviceHistory(String nick) async {
    return _service.getDeletedDeviceHistory(nick);
  }

  /// Hapus user ANON yang belum terdaftar (membebaskan nickname).
  /// Return `{ok, error?}`. Refresh daftar setelah sukses.
  Future<Map<String, dynamic>> deleteAnonUser(String uid) async {
    final res = await _service.deleteAnonUser(uid);
    if (res['ok'] == true) {
      await fetchDeleted();
    }
    return res;
  }

  /// Hapus batch user terpilih (bisa arsip `deleted_users` atau pending anon).
  /// Mengembalikan jumlah user yang berhasil dihapus.
  Future<int> deleteBatchUsers(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return 0;
    final anonUids = <String>[];
    final archiveUids = <String>[];
    for (final item in items) {
      final uid = '${item['user_id'] ?? ''}';
      if (uid.isEmpty) continue;
      if (item['pending'] == true) {
        anonUids.add(uid);
      } else {
        archiveUids.add(uid);
      }
    }
    int count = 0;
    if (archiveUids.isNotEmpty) {
      try {
        await _service.deleteArchivedUsers(archiveUids);
        count += archiveUids.length;
      } catch (e) {
        dlog('[ADMIN] deleteArchivedUsers error: $e');
      }
    }
    for (final uid in anonUids) {
      try {
        final res = await _service.deleteAnonUser(uid);
        if (res['ok'] == true) count++;
      } catch (e) {
        dlog('[ADMIN] deleteAnonUser error: $e');
      }
    }
    await fetchDeleted();
    return count;
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

  Future<void> fetchChats() async {
    _chatsLoading = true;
    _chatsError = null;
    if (!_disposed) notifyListeners();
    // Data kosong (cold start / tab baru) → tampilkan cache disk dulu.
    if (_chats.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(kAdminChatsKey);
        if (cached.isNotEmpty && _chats.isEmpty) {
          _chats = cached;
          _chatsTotal = cached.length;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final res = await _service.listChats(limit: chatPageSize, offset: 0);
      final fresh = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      // Jangan timpa data baik dengan hasil kosong (bisa karena server
      // mengembalikan kosong sesaat) — kecuali memang belum ada data.
      if (fresh.isNotEmpty || _chats.isEmpty) {
        _chats = fresh;
        _chatsTotal = (res['total'] as num?)?.toInt() ?? 0;
        _chatsHasMore = _chats.length < _chatsTotal;
      }
      _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .toList();
      if (_chats.isNotEmpty) {
        MessageCache.instance.saveRawList(kAdminChatsKey, _chats);
      }
    } catch (e) {
      // Data lama dipertahankan → banner "data terakhir" di UI.
      _chatsError = classifyAdminError(e);
      dlog('[ADMIN] fetchChats error: $e');
    }
    _chatsLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Muat halaman berikutnya (infinite scroll list chat).
  Future<void> fetchMoreChats() async {
    if (_chatsFetchingMore || !_chatsHasMore || _chatsLoading) return;
    _chatsFetchingMore = true;
    try {
      final res = await _service.listChats(
        limit: chatPageSize,
        offset: _chats.length,
      );
      final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _chatsTotal = (res['total'] as num?)?.toInt() ?? _chatsTotal;
      _chats = [..._chats, ...more];
      _chatsHasMore = _chats.length < _chatsTotal;
      _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .toList();
    } catch (e) {
      dlog('[ADMIN] fetchMoreChats error: $e');
    }
    _chatsFetchingMore = false;
    if (!_disposed) notifyListeners();
  }

  /// Refresh daftar chat tanpa loading spinner (untuk polling berkala).
  /// MERGE dengan list existing: server bisa return subset (race/filter),
  /// jangan memangkas balik → gejala "kadang muncul kadang ilang".
  Future<void> refreshChats() async {
    try {
      final want = _chats.length > chatPageSize ? _chats.length : chatPageSize;
      final res = await _service.listChats(limit: want, offset: 0);
      final fresh =
          List<Map<String, dynamic>>.from(res['items'] ?? const []);
      final merged = List<Map<String, dynamic>>.from(_chats);
      // Update existing / add new
      for (final f in fresh) {
        final id = '${f['chat_id']}';
        final idx = merged.indexWhere((c) => '${c['chat_id']}' == id);
        if (idx >= 0) {
          merged[idx] = f;
        } else {
          merged.insert(0, f); // terbaru di depan
        }
      }
      // JANGAN hapus item yang tidak ada di fresh (bisa filter/race).
      // Hanya jika server return LEBIH BANYAK → refresh total/hasMore.
      if (fresh.length > _chats.length) {
        _chatsTotal = (res['total'] as num?)?.toInt() ?? _chatsTotal;
        _chatsHasMore = merged.length < _chatsTotal;
      }
      _chats = merged;
      _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .toList();
    } catch (e) {
      dlog('[ADMIN] refreshChats error: $e');
    }
    if (!_disposed) notifyListeners();
  }

  // ── Call aktif (badge monitor + pantau call) ──
  List<ActiveCallInfo> _activeCalls = [];
  bool _activeCallsLoading = false;
  RealtimeChannel? _callChannel;
  Timer? _callRealtimeDebounce;
  int _sweepCounter = 0;

  List<ActiveCallInfo> get activeCalls => _activeCalls;
  bool get activeCallsLoading => _activeCallsLoading;

  /// Peta chatId → call aktif, untuk badge di kartu list monitor.
  Map<String, ActiveCallInfo> get activeCallsByChat => {
    for (final c in _activeCalls) c.chatId: c,
  };

  Future<void> fetchActiveCalls() async {
    ensureCallRealtime();
    if (_activeCallsLoading) return;
    _activeCallsLoading = true;
    try {
      // Sweep zombie hanya tiap panggilan ke-12 (fallback ~12 menit pada
      // polling 60 dtk) — realtime UPDATE sudah memicu refresh instan.
      if (_sweepCounter++ % 12 == 0) {
        try {
          await _service.sweepStaleCalls();
        } catch (_) {}
      }
      _activeCalls = await _service.getActiveCalls();
      _detectNewCalls(_activeCalls);
    } catch (e) {
      dlog('[ADMIN] fetchActiveCalls error: $e');
    }
    _activeCallsLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Notifikasi video call baru di monitor chat.
  void _detectNewCalls(List<ActiveCallInfo> calls) {
    for (final c in calls) {
      if (_seenCallIds.contains(c.id)) continue;
      _seenCallIds.add(c.id);
      if (!_notifArmed) continue;
      if (c.status == 'ringing' || c.status == 'answered') {
        _emit('Video call: ${c.callerName} ↔ ${c.calleeName}');
      }
    }
  }

  /// Realtime: dengarkan tabel calls — INSERT/UPDATE apapun langsung
  /// menyegarkan daftar call aktif tanpa menunggu polling.
  void ensureCallRealtime() {
    if (_callChannel != null || _disposed) return;
    final ch = _sb.channel('admin-calls-monitor');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'calls',
      callback: (_) => _debouncedRefreshActiveCalls(),
    );
    ch.subscribe();
    _callChannel = ch;
  }

  void _debouncedRefreshActiveCalls() {
    _callRealtimeDebounce?.cancel();
    _callRealtimeDebounce = Timer(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      fetchActiveCalls();
    });
  }

  // ── Pesan Kontak (Hubungi Kami) ──
  List<Map<String, dynamic>> _contactMessages = [];
  bool _contactLoading = false;
  bool _contactHasMore = true;
  bool _contactFetchingMore = false;
  int _contactTotal = 0;
  AdminErrKind? _contactError;

  List<Map<String, dynamic>> get contactMessages => _contactMessages;
  bool get contactLoading => _contactLoading;
  bool get contactHasMore => _contactHasMore;
  int get contactTotal => _contactTotal;
  AdminErrKind? get contactError => _contactError;

  Future<void> fetchContactMessages() async {
    _contactLoading = true;
    _contactError = null;
    if (!_disposed) notifyListeners();
    // Cold start / tab baru → cache disk dulu (tahan offline).
    if (_contactMessages.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(
          kAdminContactKey,
        );
        if (cached.isNotEmpty && _contactMessages.isEmpty) {
          _contactMessages = cached;
          _contactTotal = cached.length;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final res = await _service.listContactMessages(
        limit: chatPageSize,
        offset: 0,
      );
      final fresh = List<Map<String, dynamic>>.from(
        res['items'] ?? const [],
      );
      if (fresh.isNotEmpty || _contactMessages.isEmpty) {
        _contactMessages = fresh;
        _contactTotal = (res['total'] as num?)?.toInt() ?? 0;
        _contactHasMore = _contactMessages.length < _contactTotal;
      }
      if (_contactMessages.isNotEmpty) {
        MessageCache.instance.saveRawList(kAdminContactKey, _contactMessages);
      }
    } catch (e) {
      _contactError = classifyAdminError(e);
      dlog('[ADMIN] fetchContactMessages error: $e');
    }
    _contactLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Muat halaman berikutnya (infinite scroll list pesan kontak).
  Future<void> fetchMoreContactMessages() async {
    if (_contactFetchingMore || !_contactHasMore || _contactLoading) return;
    _contactFetchingMore = true;
    try {
      final res = await _service.listContactMessages(
        limit: chatPageSize,
        offset: _contactMessages.length,
      );
      final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _contactTotal = (res['total'] as num?)?.toInt() ?? _contactTotal;
      _contactMessages = [..._contactMessages, ...more];
      _contactHasMore = _contactMessages.length < _contactTotal;
    } catch (e) {
      dlog('[ADMIN] fetchMoreContactMessages error: $e');
    }
    _contactFetchingMore = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> setContactRead(String id, {bool read = true}) async {
    try {
      await _service.setContactRead(id, read: read);
      final i = _contactMessages.indexWhere((m) => m['id'] == id);
      if (i >= 0) {
        _contactMessages[i] = {..._contactMessages[i], 'is_read': read};
        if (!_disposed) notifyListeners();
      }
    } catch (e) {
      dlog('[ADMIN] setContactRead error: $e');
    }
  }

  Future<void> deleteContactMessage(String id) async {
    try {
      await _service.deleteContactMessage(id);
      _contactMessages.removeWhere((m) => m['id'] == id);
      if (_contactTotal > 0) _contactTotal--;
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[ADMIN] deleteContactMessage error: $e');
    }
  }

  bool _chatMessagesHasMore = true;
  bool _chatMessagesFetchingMore = false;
  bool get chatMessagesHasMore => _chatMessagesHasMore;

  Future<bool> fetchChatMessages(String chatId) async {
    // JANGAN kosongkan list dulu — biar pesan lama tetap tampil selama fetch
    // (anti-blink: dulu _chatMessages=[] → layar kosong → isi ulang, ikut
    // terulang tiap poll 5s).
    _chatMessagesHasMore = true;
    // Chat berbeda → muat cache disk chat itu dulu (tahan offline).
    if (_chatMsgCacheFor != chatId) {
      _chatMsgCacheFor = chatId;
      _chatMessages = const [];
      try {
        final cached = await MessageCache.instance.loadRawList(
          adminChatMsgKey(chatId),
        );
        if (cached.isNotEmpty && _chatMsgCacheFor == chatId) {
          _chatMessages = cached;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final fresh = await _service.getChatMessages(
        chatId,
        limit: messagePageSize,
        offset: 0,
      );
      if (fresh.isNotEmpty) {
        _chatMessages = fresh;
        MessageCache.instance.saveRawList(adminChatMsgKey(chatId), fresh);
      }
      _chatMessagesHasMore = fresh.length >= messagePageSize;
      return true;
    } catch (e) {
      // Data lama (memori/disk) dipertahankan — layar tetap ada isinya.
      dlog('[ADMIN] fetchChatMessages error: $e');
      return false;
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  /// Chat yang sedang ditampilkan di monitor (untuk tahu kapan cache disk
  /// perlu dimuat ulang saat pindah chat).
  String? _chatMsgCacheFor;

  /// Hapus SEMUA cache data admin di perangkat ini (tombol di tab Global
  /// Setting). Dipakai bila HP bergantian dipakai orang lain — data admin
  /// memuat PII user (email/IP/device).
  Future<void> clearAdminCache() async {
    for (final k in adminCacheKeys) {
      try {
        await MessageCache.instance.removeRawList(k);
        await MessageCache.instance.removeRawObj(k);
      } catch (_) {}
    }
    // Pesan monitor per-chat: kunci dinamis, bersihkan yang sedang terbuka.
    final cur = _chatMsgCacheFor;
    if (cur != null) {
      try {
        await MessageCache.instance.removeRawList(adminChatMsgKey(cur));
      } catch (_) {}
    }
    // Kosongkan state memori supaya UI tidak menampilkan data basi.
    _stats = null;
    _chats = const [];
    _devices = const [];
    _deleted = const [];
    _contactMessages = const [];
    _chatMessages = const [];
    _chatMsgCacheFor = null;
    if (!_disposed) notifyListeners();
  }

  /// Muat pesan lebih lama (pagination, dipanggil saat scroll ke atas).
  Future<void> fetchMoreChatMessages(String chatId) async {
    if (_chatMessagesFetchingMore || !_chatMessagesHasMore) return;
    _chatMessagesFetchingMore = true;
    try {
      final older = await _service.getChatMessages(
        chatId,
        limit: messagePageSize,
        offset: _chatMessages.length,
      );
      _chatMessages = [..._chatMessages, ...older];
      _chatMessagesHasMore = older.length >= messagePageSize;
    } catch (e) {
      dlog('[ADMIN] fetchMoreChatMessages error: $e');
    }
    _chatMessagesFetchingMore = false;
    if (!_disposed) notifyListeners();
  }

  /// Refresh pesan terbaru tanpa reset pagination — merge dengan yang sudah
  /// dimuat supaya scroll history tidak hilang saat ada pesan baru masuk.
  Future<void> refreshChatMessages(String chatId) async {
    try {
      final latest = await _service.getChatMessages(
        chatId,
        limit: messagePageSize,
        offset: 0,
      );
      final knownIds = _chatMessages.map((m) => '${m['id']}').toSet();
      final merged = List<Map<String, dynamic>>.from(_chatMessages);
      // Pesan baru (belum ada) ditambahkan di depan (terbaru duluan).
      for (final m in latest) {
        if (!knownIds.contains('${m['id']}')) {
          merged.insert(0, m);
        }
      }
      _chatMessages = merged;
    } catch (e) {
      dlog('[ADMIN] refreshChatMessages error: $e');
    }
    if (!_disposed) notifyListeners();
  }

  /// last_read_at chat (uid → ISO) untuk hitung centang-2 monitor.
  Future<Map<String, String>> fetchChatLastRead(String chatId) async {
    try {
      return await _service.getChatLastRead(chatId);
    } catch (e) {
      dlog('[ADMIN] fetchChatLastRead error: $e');
      return {};
    }
  }

  /// Fetch image_data untuk satu foto (retry / thumb).
  Future<String> fetchMessageImage(int messageId) async {
    try {
      return await _service.getMessageImage(messageId);
    } catch (e) {
      dlog('[ADMIN] fetchMessageImage error: $e');
      return '';
    }
  }

  /// Hapus chat (hard delete server) + (opsional) user.
  /// Cache lokal HP admin untuk chat itu ikut dihapus supaya monitor tidak
  /// menampilkan pesan hantu dari disk. HP peserta dibersihkan lewat
  /// realtime DELETE di ChatService._removeLocalChat. Return true jika sukses.
  Future<bool> deleteChat(String chatId, List<String> deleteUserIds) async {
    try {
      final res = await _service.deleteChat(chatId, deleteUserIds);
      final paths = (res['photo_paths'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList();
      // Cleanup foto di bucket storage (best-effort, tidak blokir).
      for (final p in paths) {
        if (StoragePhotoService.instance.isPath(p)) {
          await StoragePhotoService.instance.delete(p);
        }
      }
      if (res['ok'] == true) {
        final cacheKey = 'private_$chatId';
        try {
          await MessageCache.instance.saveMessages(cacheKey, []);
        } catch (_) {}
        try {
          await PhotoCache.instance.clearChat(cacheKey);
        } catch (_) {}
      }
      return res['ok'] == true;
    } catch (e) {
      dlog('[ADMIN] deleteChat error: $e');
      return false;
    }
  }

  void clearChatMessages() {
    _chatMessages = [];
    _chatMessagesHasMore = true;
    _chatMessagesFetchingMore = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _callRealtimeDebounce?.cancel();
    try {
      _callChannel?.unsubscribe();
      _sb.removeChannel(_callChannel!);
    } catch (_) {}
    _callChannel = null;
    try {
      _notifCtrl.close();
    } catch (_) {}
    super.dispose();
  }
}
