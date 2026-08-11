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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
