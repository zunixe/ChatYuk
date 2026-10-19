import 'package:flutter_map/flutter_map.dart';

/// Tile OpenStreetMap dasar untuk seluruh app (bubble lokasi & pemilih).
///
/// Sebelumnya URL template diduplikasi di `location_bubble.dart` dan
/// `location_picker_sheet.dart`, dan keduanya memakai provider default
/// TANPA cache → setiap buka sheet / scroll ulang histori chat mengunduh
/// ulang tile yang sama. Satu instance provider + cache disk 200 MB di
/// bawah membuat peta kedua kalinya tampil instan (dan hemat kuota).
const String osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Provider dipakai BERSAMA: cache-nya jadi lintas widget & lintas buka.
/// `abortObsoleteRequests` memutus unduhan tile yang sudah ter-scroll
/// keluar layar (flutter_map ≥ 8.2), menghemat bandwidth saat geser peta.
///
/// CATATAN: `headers` WAJIB map biasa (bukan `const`/unmodifiable) —
/// konstruktor `TileLayer` memanggil `putIfAbsent('User-Agent')` pada map
/// ini, dan itu melempar `UnsupportedError` bila map-nya unmodifiable.
final TileProvider basicMapTiles = NetworkTileProvider(
  headers: <String, String>{'User-Agent': 'com.chatyuk.chatyuk'},
  abortObsoleteRequests: true,
  cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
    // 200 MB: cukup untuk ratusan ribu tile kota, tanpa mengganggu
    // penyimpanan (cache ini boleh dibersihkan OS kapan saja).
    maxCacheSize: 200 * 1000 * 1000,
  ),
);
