import 'dart:convert';

/// Payload LOKASI untuk pesan `type='location'`.
///
/// Format: kolom `text` berisi JSON ringkas `{"lat":..,"lng":..,"label":".."}`.
/// Tidak ada kolom DB baru — koordinat menumpang kolom teks (≤2000 char,
/// jauh di bawah batas). Murni & testable; TANPA ketergantungan Flutter.
class ChatLocation {
  final double lat;
  final double lng;
  /// Nama tempat (opsional; '' bila tidak ada).
  final String label;

  const ChatLocation({required this.lat, required this.lng, this.label = ''});

  /// Encode ke string untuk kolom `text`.
  String encode() => jsonEncode({
    'lat': lat,
    'lng': lng,
    if (label.isNotEmpty) 'label': label,
  });

  /// Tautan buka di Google Maps (universal link, Android/iOS).
  String get mapsUrl =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  @override
  bool operator ==(Object other) =>
      other is ChatLocation &&
      other.lat == lat &&
      other.lng == lng &&
      other.label == label;

  @override
  int get hashCode => Object.hash(lat, lng, label);
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
    return ChatLocation(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      label: label is String ? label : '',
    );
  } catch (_) {
    return null;
  }
}

/// Label ringkas untuk preview daftar chat (mis. "[Lokasi]" / "📍 Lokasi").
/// [fallback] dipakai bila [text] tidak bisa di-parse.
String locationPreviewLabel(String? text, String fallback) {
  final loc = parseLocation(text);
  if (loc == null) return fallback;
  if (loc.label.isNotEmpty) return loc.label;
  return fallback;
}
