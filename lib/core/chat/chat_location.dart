import 'dart:convert';

/// Payload LOKASI untuk pesan `type='location'`.
///
/// Format: kolom `text` berisi JSON ringkas
/// `{"lat":..,"lng":..,"label":"..","caption":".."}`.
/// Tidak ada kolom DB baru — koordinat menumpang kolom teks (≤2000 char,
/// jauh di bawah batas). Murni & testable; TANPA ketergantungan Flutter.
class ChatLocation {
  final double lat;
  final double lng;
  /// Nama tempat (opsional; '' bila tidak ada).
  final String label;
  /// Caption dari kolom ketik saat kirim (opsional; '' = lokasi saja).
  final String caption;

  const ChatLocation({
    required this.lat,
    required this.lng,
    this.label = '',
    this.caption = '',
  });

  /// Encode ke string untuk kolom `text`.
  String encode() => jsonEncode({
    'lat': lat,
    'lng': lng,
    if (label.isNotEmpty) 'label': label,
    if (caption.isNotEmpty) 'caption': caption,
  });

  /// Tautan buka di Google Maps (universal link, Android/iOS).
  String get mapsUrl =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  @override
  bool operator ==(Object other) =>
      other is ChatLocation &&
      other.lat == lat &&
      other.lng == lng &&
      other.label == label &&
      other.caption == caption;

  @override
  int get hashCode => Object.hash(lat, lng, label, caption);
}

/// True bila [text] adalah payload lokasi yang valid (punya lat & lng angka).
///
/// Dipakai untuk: (a) memutuskan label preview di daftar chat, (b) mem-parse
/// bubble. Aman terhadap teks biasa/JSON lain (mis. GIF jsonb) — hanya lolos
/// bila kedua koordinat ada dan berupa angka.
bool isLocationPayload(String? text) => parseLocation(text) != null;

/// Parse payload lokasi; null bila bukan format lokasi yang valid.
ChatLocation? parseLocation(String? text) {
  if (text == null) return null;
  final t = text.trim();
  // Cepat: harus JSON objek. Hindari decode mahal untuk teks biasa.
  if (t.length < 9 || !t.startsWith('{') || !t.endsWith('}')) return null;
  if (!t.contains('"lat"') || !t.contains('"lng"')) return null;
  try {
    final m = jsonDecode(t);
    if (m is! Map) return null;
    final lat = m['lat'];
    final lng = m['lng'];
    if (lat is! num || lng is! num) return null;
    // Tolak koordinat mustahil (JSON lain yang kebetulan punya lat/lng).
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    final label = m['label'];
    final caption = m['caption'];
    return ChatLocation(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      label: label is String ? label : '',
      caption: caption is String ? caption : '',
    );
  } catch (_) {
    return null;
  }
}

/// Label ringkas untuk preview daftar chat (caption bila ada, jika tidak
/// label tempat, terakhir fallback mis. "[Lokasi]").
String locationPreviewLabel(String? text, String fallback) {
  final loc = parseLocation(text);
  if (loc == null) return fallback;
  if (loc.caption.isNotEmpty) return loc.caption;
  if (loc.label.isNotEmpty) return loc.label;
  return fallback;
}
