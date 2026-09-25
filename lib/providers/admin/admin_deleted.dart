part of '../admin_provider.dart';

/// Arsip user terhapus (tab Terhapus) + hapus anon/batch.
mixin AdminDeletedMx on AdminBase {
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
          AdminBase.kAdminDeletedKey,
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
        MessageCache.instance.saveRawList(AdminBase.kAdminDeletedKey, _deleted);
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

  /// Riwayat GPS/IP user yang sudah dihapus (dari arsip).
  Future<List<Map<String, dynamic>>> getDeletedLocationHistory(
    String userId,
  ) async {
    if (userId.isEmpty) return const [];
    try {
      return await _service.getDeletedLocationHistory(userId);
    } catch (e) {
      dlog('[ADMIN] getDeletedLocationHistory error: $e');
      return const [];
    }
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
}
