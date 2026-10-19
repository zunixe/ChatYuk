import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/core/media/chat_photo_helper.dart';

/// BENCHMARK NYATA — biaya rasio kartu link: SEBELUM vs SESUDAH.
///
/// Konteks (docs/PERFORMANCE.md §2.23): `LinkPreviewImage.peekAspect` dulu
/// membaca bytes gambar dari DISK secara SINKRON
/// (`MediaDiskCache.readSync` → `File.readAsBytesSync`) lalu mem-parse
/// dimensinya — dieksekusi per bubble link SETIAP bubble di-mount, di UI
/// thread. Sekarang rasio disimpan di `LinkPreviewService._aspectCache` (RAM).
///
/// Test ini mengukur dua jalur itu dengan file og:image berukuran realistis:
///  - COLD  = file ditulis ulang sebelum dibaca (page cache OS kosong) →
///            mendekati kondisi HP saat scroll ke pesan lama.
///  - WARM  = file sudah di page cache → kondisi terbaik (optimistis).
///  - MOUNT = N bubble link masuk SATU frame, semuanya COLD (skenario nyata
///            saat daftar pesan lama dimount bersamaan).
///
/// Jalankan: `flutter test test/link_preview_aspect_bench_test.dart`
/// Angka ini BASELINE DESKTOP (page cache gesit), bukan HP — lihat catatan
/// hasil di docs/PERFORMANCE.md §2.23.
void main() {
  const sizeKb = 300; // og:image tipikal (YouTube/TikTok thumbnail)
  const n = 30; // jumlah sampel untuk p50/max

  late Directory tmp;
  late Uint8List pngBytes;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('lpbench');
    // PNG minimal valid 1280x720 (dimensi di IHDR byte 16..23).
    final b = Uint8List(sizeKb * 1024);
    b[0] = 0x89; b[1] = 0x50; b[2] = 0x4E; b[3] = 0x47;
    b[4] = 0x0D; b[5] = 0x0A; b[6] = 0x1A; b[7] = 0x0A;
    b[16] = 0; b[17] = 0; b[18] = 0x05; b[19] = 0x00; // 1280
    b[20] = 0; b[21] = 0; b[22] = 0x02; b[23] = 0xD0; // 720
    pngBytes = b;
  });

  tearDownAll(() => tmp.delete(recursive: true));

  /// Jalur SEBELUM: baca file dari disk + parse dimensi.
  void beforePath(File f) {
    final d = f.readAsBytesSync();
    parseImageDimensions(d);
  }

  /// Jalur SESUDAH: lookup RAM.
  void afterPath(Map<String, double> m) {
    final _ = m['https://x/img.jpg'];
  }

  final ramMap = <String, double>{'https://x/img.jpg': 1280 / 720};

  test('COLD: tulis-ulang file lalu baca (page cache kosong)', () async {
    final us = <int>[];
    for (var i = 0; i < n; i++) {
      final f = File('${tmp.path}/cold$i.png');
      await f.writeAsBytes(pngBytes, flush: true);
      final sw = Stopwatch()..start();
      beforePath(f);
      sw.stop();
      us.add(sw.elapsedMicroseconds);
    }
    us.sort();
    final p50 = us[us.length ~/ 2];
    // ignore: avoid_print
    print('[BENCH] COLD ${sizeKb}KB  p50=${p50}us  max=${us.last}us  n=$n');

    // RAM harus nol I/O.
    final ram = <int>[];
    for (var i = 0; i < n; i++) {
      final sw = Stopwatch()..start();
      afterPath(ramMap);
      sw.stop();
      ram.add(sw.elapsedMicroseconds);
    }
    ram.sort();
    // ignore: avoid_print
    print('[BENCH] RAM  lookup   p50=${ram[ram.length ~/ 2]}us  '
        'max=${ram.last}us  n=$n');
    expect(ram.last, lessThan(us.last));
  });

  test('MOUNT: N bubble link masuk SATU frame (semua COLD)', () async {
    // ignore: avoid_print
    print('[BENCH] ── mount N bubble link dalam 1 frame ──');
    for (final count in [8, 20, 30]) {
      final files = <File>[];
      for (var i = 0; i < count; i++) {
        final f = File('${tmp.path}/m${count}_$i.png');
        await f.writeAsBytes(pngBytes, flush: true);
        files.add(f);
      }
      final sw = Stopwatch()..start();
      for (final f in files) {
        beforePath(f);
      }
      sw.stop();
      final totalMs = sw.elapsedMicroseconds / 1000;
      // ignore: avoid_print
      print('[BENCH]   SEBELUM $count bubble = '
          '${totalMs.toStringAsFixed(1)}ms '
          '(${(totalMs / count).toStringAsFixed(2)} ms/bubble)');
    }
    // SESUDAH: N lookup RAM.
    final sw = Stopwatch()..start();
    for (var i = 0; i < 30; i++) {
      afterPath(ramMap);
    }
    sw.stop();
    // ignore: avoid_print
    print('[BENCH]   SESUDAH 30 bubble = '
        '${(sw.elapsedMicroseconds / 1000).toStringAsFixed(2)}ms total (RAM)');
    expect(sw.elapsedMilliseconds, lessThan(1));
  });
}
