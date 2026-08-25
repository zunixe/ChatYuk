import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/config/regions.dart';

void main() {
  final id = getCitiesForCountry('Indonesia');
  final fiji = getCitiesForCountry('Fiji');

  group('matchCity', () {
    test('exact match', () {
      expect(matchCity('Bandung', id), 'Bandung');
    });

    test('prefix Kota dibuang', () {
      expect(matchCity('Kota Bandung', id), 'Bandung');
      expect(matchCity('Kota  Surabaya', id), 'Surabaya');
    });

    test('nama lebih spesifik dari deteksi -> contains', () {
      expect(matchCity('South Tangerang', id), 'Tangerang');
      expect(matchCity('Jakarta Selatan', id), 'Jakarta');
    });

    test('tidak ada yang cocok -> null', () {
      expect(matchCity('Nausori', fiji), isNull);
      expect(matchCity('', id), isNull);
    });
  });

  group('nearestCity', () {
    test('koordinat tepat di kota kurasi', () {
      // Denpasar ~ -8.65, 115.22
      final r = nearestCity(-8.65, 115.22, 'Indonesia', id);
      expect(r, 'Denpasar');
    });

    test('kota tanpa koordinat sendiri -> tetangga terdekat', () {
      // Nausori (Fiji, tak ada di daftar) dekat Suva
      final r = nearestCity(-18.14, 178.44, 'Fiji', fiji);
      expect(r, 'Suva');
    });

    test('null kalau negara tak punya koordinat sama sekali', () {
      // Semua kota Fiji mungkin punya; pakai negara kosong
      expect(nearestCity(0, 0, 'Negara Ngawur', ['Kota X']), isNull);
    });
  });
}
