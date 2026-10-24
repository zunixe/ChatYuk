/// Daftar kata terlarang pada nickname — SATU sumber untuk seluruh app.
///
/// Latar (REVIEW_2026-10-24 BUG-05): daftar sebelumnya **hardcode di APK**
/// (`'zaini'`, `'hafid'`), sehingga (a) nama pribadi tersemat di aplikasi yang
/// bisa dibongkar, dan (b) mengubah daftar wajib rilis baru.
///
/// Sekarang daftar dibaca dari `app_settings.banned_nicknames` (text[]) saat
/// startup. Bila gagal dimuat (offline / kolom belum ada), dipakai daftar
/// bawaan yang SAMA — jadi guard anti-impersonasi tidak pernah "terbuka"
/// hanya karena jaringan bermasalah.
///
/// Normalisasi: lowercase, buang spasi/underscore/dash supaya
/// `ZAINI-HAFID`, `zaini_hafid`, `zainihafid` sama-sama tertangkap.
library;

class BannedNicknames {
  BannedNicknames._();

  /// Daftar bawaan (fallback). HARUS sama dengan default kolom di DB
  /// (`20261024180000_banned_nicknames_setting.sql`).
  static const List<String> defaults = <String>['zaini', 'hafid'];

  static Set<String> _flat = _flatten(defaults);

  /// True bila daftar sudah berasal dari server.
  static bool get loadedFromServer => _fromServer;
  static bool _fromServer = false;

  static Set<String> _flatten(Iterable<String> raw) {
    final out = <String>{};
    for (final r in raw) {
      final n = normalizeForBan(r);
      if (n.isNotEmpty) out.add(n);
    }
    return out;
  }

  /// Terapkan daftar dari server (dipanggil sekali saat startup).
  static void setFromServer(Iterable<String> raw) {
    final next = _flatten(raw);
    if (next.isEmpty) return; // daftar kosong = jangan buka guard
    _flat = next;
    _fromServer = true;
  }

  /// True bila [flat] (sudah dinormalisasi) mengandung salah satu kata.
  static bool matches(String flat) {
    if (flat.isEmpty) return false;
    for (final word in _flat) {
      if (flat.contains(word)) return true;
    }
    return false;
  }

  /// Muat dari `app_settings` (abaikan kegagalan — pakai fallback).
  static Future<void> loadFromServer(dynamic client) async {
    try {
      if (client == null) return;
      final map = await client
          .from('app_settings')
          .select('banned_nicknames')
          .eq('id', 'global')
          .maybeSingle();
      final raw = (map is Map) ? map['banned_nicknames'] : null;
      if (raw is List && raw.isNotEmpty) {
        setFromServer(raw.map((e) => '$e'));
      }
    } catch (_) {
      // Offline / kolom belum ada → fallback bawaan tetap aktif.
    }
  }
}

/// Normalisasi nickname untuk pencocokan kata terlarang.
String normalizeForBan(String nickname) {
  final lower = nickname.trim().toLowerCase();
  return lower.replaceAll(RegExp(r'[\s_\-]+'), '');
}
