part of '../admin_provider.dart';

/// Atribusi sumber user (tab Atribusi): ringkasan per kanal + daftar user.
mixin AdminAttributionMx on AdminBase {
  Map<String, dynamic>? _attrSummary;
  bool _attrLoading = false;
  AdminErrKind? _attrError;
  int _attrDays = 0; // 0 = semua waktu

  List<Map<String, dynamic>> _attrUsers = [];
  bool _attrUsersLoading = false;
  bool _attrUsersHasMore = true;
  int _attrUsersTotal = 0;
  bool _attrUsersFetchingMore = false;
  AdminErrKind? _attrUsersError;
  String _attrSource = ''; // '' = semua kanal
  static const int _attrPageSize = 100;

  Map<String, dynamic>? get attrSummary => _attrSummary;
  bool get attrLoading => _attrLoading;
  AdminErrKind? get attrError => _attrError;
  int get attrDays => _attrDays;

  List<Map<String, dynamic>> get attrUsers => _attrUsers;
  bool get attrUsersLoading => _attrUsersLoading;
  bool get attrUsersHasMore => _attrUsersHasMore;
  AdminErrKind? get attrUsersError => _attrUsersError;
  String get attrSource => _attrSource;
  int get attrUsersTotal => _attrUsersTotal;

  /// Muat ringkasan atribusi (jumlah per kanal + kampanye). Cache disk untuk
  /// tampilan offline.
  Future<void> fetchAttribution({int? days, bool force = false}) async {
    if (days != null) _attrDays = days;
    _attrLoading = true;
    _attrError = null;
    _notifyAttribution();
    if (_attrSummary == null) {
      try {
        final cached = await MessageCache.instance.loadRawObj(
          AdminBase.kAdminAttributionKey,
        );
        if (cached.isNotEmpty && _attrSummary == null) {
          _attrSummary = cached;
          _notifyAttribution();
        }
      } catch (_) {}
    }
    try {
      final fresh = await _service.getAttributionSummary(days: _attrDays);
      _attrSummary = fresh;
      if (fresh.isNotEmpty) {
        MessageCache.instance.saveRawObj(
          AdminBase.kAdminAttributionKey,
          fresh,
        );
      }
    } catch (e) {
      _attrError = classifyAdminError(e);
      dlog('[ADMIN] fetchAttribution error: $e');
    }
    _attrLoading = false;
    _notifyAttribution();
  }

  /// Muat halaman-1 daftar user untuk 1 kanal ([source] kosong = semua).
  Future<void> fetchAttributionUsers({String? source}) async {
    if (source != null) _attrSource = source;
    _attrUsersLoading = true;
    _attrUsersError = null;
    _attrUsersHasMore = true;
    _notifyAttribution();
    try {
      final res = await _service.listAttributionUsers(
        source: _attrSource,
        limit: _attrPageSize,
        offset: 0,
      );
      _attrUsers = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _attrUsersTotal = (res['total'] as num?)?.toInt() ?? _attrUsers.length;
      _attrUsersHasMore = _attrUsers.length < _attrUsersTotal;
    } catch (e) {
      _attrUsersError = classifyAdminError(e);
      dlog('[ADMIN] fetchAttributionUsers error: $e');
    }
    _attrUsersLoading = false;
    _notifyAttribution();
  }

  /// Muat halaman berikutnya (infinite scroll).
  Future<void> loadMoreAttributionUsers() async {
    if (_attrUsersLoading ||
        _attrUsersFetchingMore ||
        !_attrUsersHasMore) {
      return;
    }
    _attrUsersFetchingMore = true;
    _notifyAttribution();
    try {
      final res = await _service.listAttributionUsers(
        source: _attrSource,
        limit: _attrPageSize,
        offset: _attrUsers.length,
      );
      final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      if (more.isNotEmpty) {
        _attrUsers = [..._attrUsers, ...more];
      }
      _attrUsersTotal = (res['total'] as num?)?.toInt() ?? _attrUsers.length;
      _attrUsersHasMore = _attrUsers.length < _attrUsersTotal;
    } catch (e) {
      dlog('[ADMIN] loadMoreAttributionUsers error: $e');
    }
    _attrUsersFetchingMore = false;
    _notifyAttribution();
  }
}
