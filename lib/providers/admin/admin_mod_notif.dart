part of '../admin_provider.dart';

/// Notifikasi aktivitas MODERASI untuk admin panel: permohonan izin kirim
/// media, laporan, pesan perlu ditinjau, dan perubahan moderator.
///
/// RPC `admin_moderation_activity()` ringan (hitungan + timestamp terakhir,
/// TANPA daftar penuh) — aman untuk polling 180s. Baseline: fetch pertama
/// setelah arm disimpan diam-diam (pola sama dengan detector device baru)
/// supaya membuka panel tidak memicu notifikasi palsu; setelah itu tiap
/// timestamp yang lebih BARU dari nilai tersimpan dianggap aktivitas baru.
mixin AdminModNotifMx on AdminBase {
  /// Timestamp terakhir yang SUDAH dinotifikasi, per sumber aktivitas
  /// (`permits` / `applications` / `reports` / `reviews` / `mods`).
  final Map<String, String> _modSeenAt = {};
  bool _modSeenLoaded = false;

  static const String _kModSeenKey = 'admin_mod_seen_at';

  // ── Realtime aktivitas moderasi ──
  // Dengarkan INSERT/UPDATE tabel sumber aktivitas (RLS SELECT
  // authenticated / admin sudah dibuka + tabel didaftarkan di publication
  // supabase_realtime oleh migrasi 20261027162000) → bump → cek RPC ringan
  // → notifikasi seketika. Polling 180s tetap jalan sebagai fallback.
  RealtimeChannel? _modChannel;
  Timer? _modBumpTimer;

  static const List<String> _kModTables = [
    'moderator_applications',
    'moderator_actions',
    'country_send_permits',
    'reports',
  ];

  /// Mulai watcher realtime (idempoten). Dipanggil bersama arm.
  void startModerationRealtime() {
    if (_modChannel != null || _disposed) return;
    try {
      final ch = _sb.channel('admin-mod-notif');
      for (final table in _kModTables) {
        ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_, [__]) => _modBump(),
        );
      }
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'needs_review',
          value: 'true',
        ),
        callback: (_, [__]) => _modBump(),
      );
      ch.subscribe((status, err) {
        if (err != null) dlog('[ADMIN] mod realtime error: $err');
      });
      _modChannel = ch;
    } catch (e) {
      dlog('[ADMIN] startModerationRealtime error: $e');
    }
  }

  void _modBump() {
    _modBumpTimer?.cancel();
    _modBumpTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!_disposed) unawaited(checkModerationActivity());
    });
  }

  /// Poll satu kali — dipanggil timer 180s panel admin, setelah arm.
  Future<void> checkModerationActivity() async {
    if (!_notifArmed || _disposed) return;
    try {
      final act = await _service.moderationActivity();
      if (act == null) return;

      if (!_modSeenLoaded) {
        _modSeenLoaded = true;
        try {
          final prefs = await SharedPreferences.getInstance();
          final saved = prefs.getString(_kModSeenKey);
          if (saved != null) {
            final map = jsonDecode(saved);
            if (map is Map) {
              for (final e in map.entries) {
                _modSeenAt['${e.key}'] = '${e.value}';
              }
            }
          }
        } catch (_) {}
      }

      // Baseline pertama setelah arm: catat tanpa mengganggu.
      if (!_modBaselineDone) {
        _modBaselineDone = true;
        _modMarkAll(act);
        await _modPersistSeen();
        return;
      }

      final s = AppLocale.s;
      final parts = <String>[];

      if (_modIsNew('permits', '${act['permits_at'] ?? ''}')) {
        final n = (act['permits'] as num?)?.toInt() ?? 0;
        if (n > 0) parts.add(s.adminModNotifPermits(n));
      }
      if (_modIsNew('applications', '${act['applications_at'] ?? ''}')) {
        final n = (act['applications'] as num?)?.toInt() ?? 0;
        if (n > 0) parts.add(s.adminModNotifApplications(n));
      }
      if (_modIsNew('reports', '${act['reports_at'] ?? ''}')) {
        final n = (act['reports'] as num?)?.toInt() ?? 0;
        if (n > 0) parts.add(s.adminModNotifReports(n));
      }
      if (_modIsNew('reviews', '${act['reviews_at'] ?? ''}')) {
        final n = (act['reviews'] as num?)?.toInt() ?? 0;
        if (n > 0) parts.add(s.adminModNotifReviews(n));
      }
      if (_modIsNew('mods', '${act['mods_at'] ?? ''}')) {
        final last = act['mods_last'];
        if (last is Map) {
          final granted = '${last['action']}' == 'grant_permit';
          final nick = '${last['nickname']}';
          final country = '${last['country']}';
          parts.add(granted
              ? s.adminModNotifModGranted(nick, country)
              : s.adminModNotifModRevoked(nick, country));
        }
      }

      _modMarkAll(act);
      await _modPersistSeen();

      if (parts.isNotEmpty && !_disposed) {
        _emit('${s.adminModNotifPrefix}${parts.join(' · ')}');
      }
    } catch (_) {}
  }

  bool _modIsNew(String key, String iso) {
    final at = DateTime.tryParse(iso);
    if (at == null) return false;
    final prev = DateTime.tryParse(_modSeenAt[key] ?? '');
    return prev == null || at.isAfter(prev);
  }

  void _modMarkAll(Map<String, dynamic> act) {
    final permitsAt = '${act['permits_at'] ?? ''}';
    final appsAt = '${act['applications_at'] ?? ''}';
    final reportsAt = '${act['reports_at'] ?? ''}';
    final reviewsAt = '${act['reviews_at'] ?? ''}';
    final modsAt = '${act['mods_at'] ?? ''}';
    if (permitsAt.isNotEmpty) _modSeenAt['permits'] = permitsAt;
    if (appsAt.isNotEmpty) _modSeenAt['applications'] = appsAt;
    if (reportsAt.isNotEmpty) _modSeenAt['reports'] = reportsAt;
    if (reviewsAt.isNotEmpty) _modSeenAt['reviews'] = reviewsAt;
    if (modsAt.isNotEmpty) _modSeenAt['mods'] = modsAt;
  }

  Future<void> _modPersistSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kModSeenKey, jsonEncode(_modSeenAt));
    } catch (_) {}
  }

  /// Tutup watcher realtime (dipanggil saat dispose).
  void stopModerationRealtime() {
    final ch = _modChannel;
    _modChannel = null;
    _modBumpTimer?.cancel();
    _modBumpTimer = null;
    try {
      if (ch != null) _sb.removeChannel(ch);
    } catch (_) {}
  }
}
