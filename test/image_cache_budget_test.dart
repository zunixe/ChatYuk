import 'package:chatyuk/core/media/image_cache_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;

  test('cap byte mengikuti kelas RAM (RAM/128, clamp 16-48MB)', () {
    expect(imageCacheBytesForRam(2 * gb), 16 * mb); // 2GB→16MB
    expect(imageCacheBytesForRam(3 * gb), 24 * mb); // 3GB→24MB
    expect(imageCacheBytesForRam(4 * gb), 32 * mb); // 4GB→32MB
    expect(imageCacheBytesForRam(6 * gb), 48 * mb); // 6GB→48MB
    expect(imageCacheBytesForRam(16 * gb), 48 * mb); // clamp atas
  });

  test('cap entri mengikuti kelas RAM (RAM/32MB, clamp 60-160)', () {
    expect(imageCacheEntriesForRam(2 * gb), 64); // 2GB/32MB
    expect(imageCacheEntriesForRam(4 * gb), 128);
    expect(imageCacheEntriesForRam(16 * gb), 160); // clamp atas
    expect(imageCacheEntriesForRam(1 * gb), 60); // 32 → clamp bawah
  });

  test('RAM tak valid (0/negatif, physicalRamSize bug ROM) → fallback 4GB', () {
    expect(imageCacheBytesForRam(0), 32 * mb);
    expect(imageCacheEntriesForRam(-1), 128);
  });

  test('HP RAM besar (physicalRamSize 0 → fallback) tak turun ke 16MB', () {
    // Regresi: dulu ramBytes=0 → clamp(0)=16MB (paling kecil) di HP RAM besar.
    // Fallback 4GB → 32MB; device 11GB valid → 48MB. Keduanya > 16MB.
    expect(imageCacheBytesForRam(kImageCacheFallbackRamBytes), 32 * mb);
    expect(imageCacheBytesForRam(11 * gb), 48 * mb);
  });
}
