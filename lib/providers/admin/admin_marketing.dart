part of '../admin_provider.dart';

/// Email Marketing (admin) — daftar campaign, composer, detail, kirim,
/// statistik. Semua akses lewat RPC admin-only (guard di SQL).
mixin AdminMarketingMx on AdminBase {
  List<Map<String, dynamic>> marketingCampaigns = [];
  Map<String, dynamic>? marketingStats;
  Map<String, dynamic>? marketingDetail;
  bool marketingLoading = false;
  AdminErrKind? _marketingError;

  AdminErrKind? get marketingError => _marketingError;

  /// Muat daftar campaign + statistik agregat.
  Future<void> fetchMarketing() async {
    marketingLoading = true;
    _marketingError = null;
    _notifyMarketing();
    try {
      final results = await Future.wait([
        _service.emailCampaignsPage(),
        _service.emailStats(),
      ]);
      marketingCampaigns = results[0] as List<Map<String, dynamic>>;
      marketingStats = results[1] as Map<String, dynamic>;
    } catch (e) {
      _marketingError = classifyAdminError(e);
    }
    marketingLoading = false;
    _notifyMarketing();
  }

  /// Estimasi jumlah penerima untuk sebuah segment.
  Future<int> estimateSegment(Map<String, dynamic> segment) async {
    try {
      final r = await _service.emailEstimateSegment(segment);
      return (r['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Simpan draft (insert kalau [id] null/0). Return id campaign.
  Future<int> saveCampaign({
    int? id,
    required String name,
    required String subject,
    required String html,
    required Map<String, dynamic> segment,
  }) async {
    final r = await _service.emailCampaignSave(
      id: id,
      name: name,
      subject: subject,
      html: html,
      segment: segment,
    );
    await fetchMarketing();
    return (r['id'] as num?)?.toInt() ?? 0;
  }

  Future<void> deleteCampaign(int id) async {
    await _service.emailCampaignDelete(id);
    await fetchMarketing();
  }

  /// Muat detail (campaign + daftar penerima).
  Future<void> fetchMarketingDetail(int id) async {
    marketingLoading = true;
    _marketingError = null;
    _notifyMarketing();
    try {
      marketingDetail = await _service.emailCampaignDetail(id);
    } catch (e) {
      _marketingError = classifyAdminError(e);
    }
    marketingLoading = false;
    _notifyMarketing();
  }

  /// Kirim (enqueue) campaign. Return kode: 'ok:<n>' | alasan gagal.
  Future<String> sendCampaign(int id) async {
    try {
      final r = await _service.emailEnqueue(id);
      await fetchMarketing();
      if (r['ok'] == true) {
        return 'ok:${(r['recipients'] as num?)?.toInt() ?? 0}';
      }
      return '${r['reason'] ?? 'failed'}';
    } catch (e) {
      return 'error';
    }
  }
}
