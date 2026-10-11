// Daftar negara dan kota lengkap
// Data dikurasi dari sumber publik

import 'dart:math' as math;
import 'city_coords.dart';

part 'regions_data.dart';
part 'regions_data_a.dart';
part 'regions_data_b.dart';
part 'regions_data_c.dart';
part 'regions_countries.dart';

/// Mendapatkan list kota untuk negara tertentu
List<String> getCitiesForCountry(String country) => kotaByNegara[country] ?? [];

/// Mendapatkan nama negara (kompatibilitas dengan entry_screen)
String negaraLabel(String key, bool isId) => key;

/// Mendapatkan list negara yang punya data kota
List<String> getNegaraKeys() => kotaByNegara.keys.toList();

// ── Pencocokan kota hasil deteksi geo (IP/GPS) ──────────────────────────────

/// Normalisasi nama kota: lowercase, buang diacritic & prefix "Kota "/"Kab.".
String normalizeCity(String s) {
  var out = s.trim().toLowerCase();
  final sb = StringBuffer();
  for (final ch in out.runes) {
    final de = String.fromCharCode(ch).trim();
    if (de.isEmpty) continue; // buang combining marks hasil NFKD-ish manual
    sb.write(de);
  }
  out = sb.toString();
  out = out.replaceAll(RegExp(r'^kota\s+'), '');
  out = out.replaceAll(RegExp(r'^kab(?:upaten)?\.?\s+'), '');
  return out;
}

/// Cari kota kurasi yang cocok dengan nama hasil deteksi.
/// Urutan: exact normalized -> prefix -> contains dua arah. Null kalau tak ada.
String? matchCity(String detected, List<String> cities) {
  final d = normalizeCity(detected);
  if (d.isEmpty || cities.isEmpty) return null;
  final normalized = {for (final c in cities) normalizeCity(c): c};
  if (normalized[d] != null) return normalized[d];
  for (final e in normalized.entries) {
    if (e.key.startsWith(d)) return e.value;
  }
  for (final e in normalized.entries) {
    if (e.key.contains(d) || d.contains(e.key)) return e.value;
  }
  return null;
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180.0;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
}

/// Kota kurasi terdekat dari koordinat deteksi (IP/GPS).
/// Hanya bandingkan kota di [cities] yang punya koordinat di kotaCoords.
/// Return null kalau koordinat kosong / tak ada kota berkordinat.
String? nearestCity(
  double lat,
  double lon,
  String country,
  List<String> cities,
) {
  String? best;
  var bestDist = double.infinity;
  for (final c in cities) {
    final coord = kotaCoords['$country|$c'];
    if (coord == null || coord.length < 2) continue;
    final dist = _haversineKm(lat, lon, coord[0], coord[1]);
    if (dist < bestDist) {
      bestDist = dist;
      best = c;
    }
  }
  return best;
}
