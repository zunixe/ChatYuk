import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/admin_service.dart';

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
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _chatMessages = [];
  bool _chatsLoading = false;
  String? _chatsError;

  List<Map<String, dynamic>> get chats => _chats;
  List<Map<String, dynamic>> get chatMessages => _chatMessages;
  bool get chatsLoading => _chatsLoading;
  String? get chatsError => _chatsError;

  Future<void> fetchChats() async {
    _chatsLoading = true;
    _chatsError = null;
    if (!_disposed) notifyListeners();
    try {
      _chats = await _service.listChats();
    } catch (e) {
      _chatsError = e.toString();
      debugPrint('[ADMIN] fetchChats error: $e');
    }
    _chatsLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Refresh daftar chat tanpa loading spinner (untuk polling berkala).
  Future<void> refreshChats() async {
    try {
      _chats = await _service.listChats();
    } catch (e) {
      debugPrint('[ADMIN] refreshChats error: $e');
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> fetchChatMessages(String chatId) async {
    _chatMessages = [];
    if (!_disposed) notifyListeners();
    try {
      _chatMessages = await _service.getChatMessages(chatId);
      return true;
    } catch (e) {
      debugPrint('[ADMIN] fetchChatMessages error: $e');
      return false;
    } finally {
      if (!_disposed) notifyListeners();
    }
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

  void clearChatMessages() {
    _chatMessages = [];
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
