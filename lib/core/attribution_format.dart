/// Format & terjemahan string atribusi — MURNI (tanpa I/O, tanpa plugin).
///
/// Dipisah dari `services/attribution_service.dart` (yang bergantung plugin
/// Play Referrer + Firebase) supaya layer UI (screens/widgets) bisa memakai
/// fungsi murni ini lewat `core/` tanpa melanggar boundary import services/.
library;

/// Terjemahan "link apa yang membawa user ke sini" dari field atribusi mentah.
/// Murni (tanpa I/O) → mudah di-unit-test. Tidak mengubah data, hanya konteks.
///
/// Contoh keluaran:
///   `utm_source=google-play&utm_medium=organic`
///     → 'Install organik — cari sendiri di Play Store (bukan iklan)'
///   `gclid=CjwKCA...`
///     → 'Google Ads (klik iklan)'
///   `` (kosong) → 'Tidak ada referrer'
String describeAttributionSource({
  String referrerRaw = '',
  String source = '',
  String utmSource = '',
  String utmMedium = '',
  String utmCampaign = '',
}) {
  final raw = referrerRaw.trim().toLowerCase();
  final src = source.trim().toLowerCase();
  final us = utmSource.trim().toLowerCase();

  // Referrer default Play/Android = install organik (bukan iklan).
  if (us == 'google-play' || src == 'google-play') {
    return 'Install organik — cari sendiri di Play Store (bukan iklan)';
  }
  if (raw.contains('gclid=') || src == 'google') {
    return utmCampaign.isNotEmpty
        ? 'Google Ads — kampanye "$utmCampaign"'
        : 'Google Ads (klik iklan)';
  }
  if (raw.contains('fbclid=') || src == 'facebook') {
    return utmCampaign.isNotEmpty
        ? 'Facebook Ads — kampanye "$utmCampaign"'
        : 'Facebook Ads (klik iklan)';
  }
  if (src == 'instagram') {
    return utmCampaign.isNotEmpty
        ? 'Instagram Ads — kampanye "$utmCampaign"'
        : 'Instagram Ads (klik iklan)';
  }
  if (raw.contains('ttclid=') || src == 'tiktok') {
    return utmCampaign.isNotEmpty
        ? 'TikTok Ads — kampanye "$utmCampaign"'
        : 'TikTok Ads (klik iklan)';
  }
  if (src == 'referral') {
    return 'Referral — dari link share user lain';
  }
  if (src == 'organic' || (raw.isEmpty && us.isEmpty)) {
    return 'Organik / tanpa link iklan';
  }
  // Ada utm_source lain (twitter/x, snapchat, dst) — tampilkan apa adanya.
  if (us.isNotEmpty) {
    return 'Utm source: $us'
        '${utmMedium.isNotEmpty ? ' · medium: $utmMedium' : ''}';
  }
  return 'Kanal tidak dikenal — tidak ada data link';
}
