// AUTO-GENERATED oleh scripts/gen_city_coords.py — jangan edit manual.
// Sumber koordinat: GeoNames cities15000 (CC-BY 4.0 / ODbL),
// https://www.geonames.org/export/
// Key: 'Negara|Kota' (harus cocok dengan kotaByNegara di regions.dart).

part 'city_coords_a.dart';
part 'city_coords_b.dart';
part 'city_coords_c.dart';

/// Koordinat kota (dipecah 3 part demi batas ukuran file).
Map<String, List<double>> get kotaCoords => {
  ...kotaCoordsA,
  ...kotaCoordsB,
  ...kotaCoordsC,
};
