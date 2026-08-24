import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/active_call_model.dart';
import '../services/admin_service.dart';
import '../services/storage_photo_service.dart';

class AdminProvider extends ChangeNotifier {
  final AdminService _service = AdminService(Supabase.instance.client);
  Map<String, dynamic>? _stats;
  bool _loading = false;
  String? _error;
  bool _pointsEnabled = true;
  bool _disposed = false;

  Map<String, dynamic>? get stats => _stats;
  bool get loading => _loading;
  String? get error => _error;
  bool get pointsEnabled => _pointsEnabled;

  Future<void> fetchStats() async {
    _loading = true;
    _error = null;
    if (!_disposed) notifyListeners();
    try {
      _stats = await _service.getStats();
      _pointsEnabled = _stats?['points_enabled'] == true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[ADMIN] fetchStats error: $e');
    }
    _loading = false;
    if (!_disposed) notifyListeners();
  }

  /// Refresh statistik tanpa memicu state "loading" (untuk timer/polling).
  Future<void> refreshStats() async {
    try {
      _stats = await _service.getStats();
      _pointsEnabled = _stats?['points_enabled'] == true;
    } catch (e) {
      debugPrint('[ADMIN] refreshStats error: $e');
    }
    if (!_disposed) notifyListeners();
  }

  /// Ambil detail data card Overview (list user/room per kategori).
  /// Di-cache 60 detik: peta user & bottom sheet stat memanggil ini di
  /// saat bersamaan — hindari double fetch payload besar.
  Map<String, dynamic>? _detailCache;
  DateTime? _detailCacheAt;
  static const _detailTtl = Duration(seconds: 60);

  Future<Map<String, dynamic>> fetchStatsDetail() async {
    if (_detailCache != null &&
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
      debugPrint('[ADMIN] fetchStatsDetail error: $e');
      return {};
    }
  }

  // ── Bar chart registrasi email per hari ──
  Map<int, int> _regDaily = {};
  bool _regLoading = false;

  Map<int, int> get regDaily => _regDaily;
  bool get regLoading => _regLoading;

  Future<void> fetchRegistrationsDaily(int year, int month) async {
    _regLoading = true;
    if (!_disposed) notifyListeners();
    try {
      _regDaily = await _service.fetchRegistrationsDaily(year, month);
    } catch (e) {
      debugPrint('[ADMIN] fetchRegistrationsDaily error: $e');
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
      debugPrint('[ADMIN] massBonus error: $e');
      return null;
    }
  }

  Future<int?> resetAllPoints() async {
    try {
      final count = await _service.resetAllPoints();
      await fetchStats();
      return count;
    } catch (e) {
      debugPrint('[ADMIN] resetAllPoints error: $e');
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
      debugPrint('[ADMIN] togglePointsSystem error: $e');
      return false;
    }
  }

  Future<void> forceLogout(String targetUid) async {
    try {
      await _service.forceLogout(targetUid);
    } catch (e) {
      debugPrint('[ADMIN] forceLogout error: $e');
      rethrow;
    }
  }

  // ── Admin Chat Monitor ──
  static const int chatPageSize = 50;
  static const int messagePageSize = 100;

  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _chatMessages = [];
  List<String> _adminUids = [];
  bool _chatsLoading = false;
  bool _chatsHasMore = true;
  int _chatsTotal = 0;
  bool _chatsFetchingMore = false;
  String? _chatsError;

  List<Map<String, dynamic>> get chats => _chats;
  List<Map<String, dynamic>> get chatMessages => _chatMessages;
  List<String> get adminUids => _adminUids;
  bool get chatsLoading => _chatsLoading;
  bool get chatsHasMore => _chatsHasMore;
  int get chatsTotal => _chatsTotal;
  String? get chatsError => _chatsError;

  Future<void> fetchChats() async {
    _chatsLoading = true;
    _chatsError = null;
    if (!_disposed) notifyListeners();
    try {
      final res = await _service.listChats(limit: chatPageSize, offset: 0);
      _chats = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _chatsTotal = (res['total'] as num?)?.toInt() ?? 0;
      _chatsHasMore = _chats.length < _chatsTotal;
      _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .toList();
    } catch (e) {
      _chatsError = e.toString();
      debugPrint('[ADMIN] fetchChats error: $e');
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
      debugPrint('[ADMIN] fetchMoreChats error: $e');
    }
    _chatsFetchingMore = false;
    if (!_disposed) notifyListeners();
  }

  /// Refresh daftar chat tanpa loading spinner (untuk polling berkala).
  Future<void> refreshChats() async {
    try {
      final res = await _service.listChats(limit: chatPageSize, offset: 0);
      _chats = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _chatsTotal = (res['total'] as num?)?.toInt() ?? 0;
      _chatsHasMore = _chats.length < _chatsTotal;
      _adminUids = (res['admin_uids'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .toList();
    } catch (e) {
      debugPrint('[ADMIN] refreshChats error: $e');
    }
    if (!_disposed) notifyListeners();
  }

  // ── Call aktif (badge monitor + pantau call) ──
  List<ActiveCallInfo> _activeCalls = [];
  bool _activeCallsLoading = false;
  RealtimeChannel? _callChannel;
  Timer? _callRealtimeDebounce;

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
      // Bersihkan zombie dulu (app dipaksa tutup saat call → row menggantung),
      // lalu ambil daftar aktif. Hasil sweep juga memicu realtime UPDATE.
      try {
        await _service.sweepStaleCalls();
      } catch (_) {}
      _activeCalls = await _service.getActiveCalls();
    } catch (e) {
      debugPrint('[ADMIN] fetchActiveCalls error: $e');
    }
    _activeCallsLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Realtime: dengarkan tabel calls — INSERT/UPDATE apapun langsung
  /// menyegarkan daftar call aktif tanpa menunggu polling.
  void ensureCallRealtime() {
    if (_callChannel != null || _disposed) return;
    final ch = Supabase.instance.client.channel('admin-calls-monitor');
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
  String? _contactError;

  List<Map<String, dynamic>> get contactMessages => _contactMessages;
  bool get contactLoading => _contactLoading;
  bool get contactHasMore => _contactHasMore;
  int get contactTotal => _contactTotal;
  String? get contactError => _contactError;

  Future<void> fetchContactMessages() async {
    _contactLoading = true;
    _contactError = null;
    if (!_disposed) notifyListeners();
    try {
      final res = await _service.listContactMessages(
        limit: chatPageSize,
        offset: 0,
      );
      _contactMessages = List<Map<String, dynamic>>.from(
        res['items'] ?? const [],
      );
      _contactTotal = (res['total'] as num?)?.toInt() ?? 0;
      _contactHasMore = _contactMessages.length < _contactTotal;
    } catch (e) {
      _contactError = e.toString();
      debugPrint('[ADMIN] fetchContactMessages error: $e');
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
      debugPrint('[ADMIN] fetchMoreContactMessages error: $e');
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
      debugPrint('[ADMIN] setContactRead error: $e');
    }
  }

  Future<void> deleteContactMessage(String id) async {
    try {
      await _service.deleteContactMessage(id);
      _contactMessages.removeWhere((m) => m['id'] == id);
      if (_contactTotal > 0) _contactTotal--;
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[ADMIN] deleteContactMessage error: $e');
    }
  }

  bool _chatMessagesHasMore = true;
  bool _chatMessagesFetchingMore = false;
  bool get chatMessagesHasMore => _chatMessagesHasMore;

  Future<bool> fetchChatMessages(String chatId) async {
    _chatMessages = [];
    _chatMessagesHasMore = true;
    if (!_disposed) notifyListeners();
    try {
      _chatMessages = await _service.getChatMessages(
        chatId,
        limit: messagePageSize,
        offset: 0,
      );
      _chatMessagesHasMore = _chatMessages.length >= messagePageSize;
      return true;
    } catch (e) {
      debugPrint('[ADMIN] fetchChatMessages error: $e');
      return false;
    } finally {
      if (!_disposed) notifyListeners();
    }
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
      debugPrint('[ADMIN] fetchMoreChatMessages error: $e');
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
      debugPrint('[ADMIN] refreshChatMessages error: $e');
    }
    if (!_disposed) notifyListeners();
  }

  /// Fetch image_data untuk satu foto (retry / thumb).
  Future<String> fetchMessageImage(int messageId) async {
    try {
      return await _service.getMessageImage(messageId);
    } catch (e) {
      debugPrint('[ADMIN] fetchMessageImage error: $e');
      return '';
    }
  }

  /// Hapus chat + (opsional) user. Return true jika sukses.
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
      return res['ok'] == true;
    } catch (e) {
      debugPrint('[ADMIN] deleteChat error: $e');
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
      Supabase.instance.client.removeChannel(_callChannel!);
    } catch (_) {}
    _callChannel = null;
    super.dispose();
  }
}
