/// Notifikasi pesan berisi LINK: pakai judul/deskripsi + gambar preview
/// (dikirim server di `data` oleh edge `send-push`) — bukan URL mentah.
///
/// Fungsi MURNI (mudah diuji): keputusan teks & kelayakan gambar.
library;

String _pick(Map data, List<String> keys) {
  for (final k in keys) {
    final v = data[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

/// Teks notifikasi: prioritas deskripsi → judul → teks pesan asli ([fallback]).
String notifBodyForLinkPreview(Map data, String fallback) {
  final desc = _pick(data, ['previewDesc', 'previewDescription']);
  if (desc.isNotEmpty) return desc;
  final title = _pick(data, ['previewTitle']);
  if (title.isNotEmpty) return title;
  return fallback;
}

/// Gambar preview layak dipakai sebagai BigPicture: hanya https (Android
/// memblokir cleartext) dan berupa URL.
bool isNotifPreviewImage(String? url) =>
    url != null && url.startsWith('https://');

/// Judul di dalam BigPicture (judul preview) — kosong = pakai default.
String notifPreviewImageTitle(Map data) => _pick(data, ['previewTitle']);
