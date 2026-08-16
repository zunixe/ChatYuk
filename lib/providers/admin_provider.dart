import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    super.dispose();
  }
}
