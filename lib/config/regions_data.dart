part of 'regions.dart';

/// Gabungan peta negara→kota (dipecah 3 part demi batas ukuran file).
Map<String, List<String>> get kotaByNegara => {
  ...kotaByNegaraA,
  ...kotaByNegaraB,
  ...kotaByNegaraC,
};
