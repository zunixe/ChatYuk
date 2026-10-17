import 'dart:typed_data';

import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/blurhash.dart';

/// Mengunci implementasi BlurHash (encode + decode) terhadap SPESIFIKASI resmi.
void main() {
  // Hash contoh resmi dari repo woltapp/blurhash (32×32, komponen 4×3).
  const canonical = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

  Uint8List solidRgba(int r, int g, int b, int w, int h) {
    final out = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      out[i * 4] = r;
      out[i * 4 + 1] = g;
      out[i * 4 + 2] = b;
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  group('validate', () {
    test('hash resmi valid', () => expect(BlurHashCodec.validate(canonical), isTrue));
    test('panjang salah → tidak valid', () {
      expect(BlurHashCodec.validate('LEHV6'), isFalse);
      expect(BlurHashCodec.validate('${canonical}x'), isFalse);
    });
    test('alfabet ilegal → tidak valid', () {
      expect(BlurHashCodec.validate('LEHV6nWB2yk8pyo0adR*.7kCMdn!'), isFalse);
    });
  });

  test('DECODER sesuai spek: hash resmi (4×3) didecode jadi gambar bervariasi',
      () {
    // size flag 'L' → 21 → numX=4, numY=3 (bukti indexing base83 benar).
    final sf = BlurHashCodec.alphabet.indexOf(canonical[0]);
    expect(sf, 21);
    expect(sf % 9 + 1, 4);
    expect(sf ~/ 9 + 1, 3);

    final decoded = BlurHashCodec.decode(canonical, width: 32, height: 32);
    expect(decoded.width, 32);
    expect(decoded.height, 32);
    var mn = 255, mx = 0;
    for (var i = 0; i < 32 * 32; i++) {
      final v = decoded.pixels[i * 4 + 1];
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    expect(mx - mn, greaterThan(10),
        reason: 'komponen AC harus menghasilkan variasi (bukan flat)');
  });

  test('ENCODER sesuai spek: hasil encode cocok dgn DECODER referensi '
      '(flutter_blurhash) — oracle independen', () async {
    const w = 32, h = 32;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = (x + y * w) * 4;
        rgba[idx] = 220;
        rgba[idx + 1] = 40 + (y * 180 ~/ (h - 1));
        rgba[idx + 2] = 60 + (x * 150 ~/ (w - 1));
        rgba[idx + 3] = 255;
      }
    }
    final hash = BlurHashCodec.encode(pixels: rgba, width: w, height: h);
    expect(BlurHashCodec.validate(hash), isTrue);

    // Oracle: decoder resmi (package) atas hash hasil encoder kita.
    final oracle = await blurHashDecode(width: w, height: h, blurHash: hash);
    final mine = BlurHashCodec.decode(hash, width: w, height: h);
    expect(oracle.length, mine.pixels.length);

    int mean(Uint8List p, int ch) {
      var s = 0;
      for (var i = 0; i < w * h; i++) {
        s += p[i * 4 + ch];
      }
      return s ~/ (w * h);
    }

    for (var ch = 0; ch < 3; ch++) {
      expect(mean(mine.pixels, ch), closeTo(mean(oracle, ch), 12),
          reason: 'decode kita ≈ decode referensi (kanal $ch)');
    }
  });

  test('warna solid → decode menghasilkan warna itu (~)', () {
    final rgba = solidRgba(200, 60, 30, 32, 32);
    final hash = BlurHashCodec.encode(
      pixels: rgba,
      width: 32,
      height: 32,
    );
    final back = BlurHashCodec.decode(hash, width: 32, height: 32);
    // Tengah gambar (hindari edge).
    final idx = (16 + 16 * 32) * 4;
    expect(back.pixels[idx], closeTo(200, 6));
    expect(back.pixels[idx + 1], closeTo(60, 6));
    expect(back.pixels[idx + 2], closeTo(30, 6));
  });

  test('gradien vertikal: rerata warna decode ≈ rerata asli', () {
    const w = 32, h = 32;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = (x + y * w) * 4;
        rgba[idx] = 20;
        rgba[idx + 1] = (y * 255 ~/ (h - 1));
        rgba[idx + 2] = 200;
        rgba[idx + 3] = 255;
      }
    }
    final hash = BlurHashCodec.encode(pixels: rgba, width: w, height: h);
    final back = BlurHashCodec.decode(hash, width: w, height: h);
    int avg(Uint8List p, int ch) {
      var s = 0;
      for (var i = 0; i < w * h; i++) {
        s += p[i * 4 + ch];
      }
      return s ~/ (w * h);
    }

    expect(avg(back.pixels, 1), closeTo(avg(rgba, 1), 10));
    expect(avg(back.pixels, 0), closeTo(avg(rgba, 0), 10));
    expect(avg(back.pixels, 2), closeTo(avg(rgba, 2), 10));
  });

  test('computeBlurHash dari JPEG → hash valid', () async {
    final im = img.Image(width: 64, height: 48);
    img.fill(im, color: img.ColorRgb8(10, 180, 90));
    final jpeg = Uint8List.fromList(img.encodeJpg(im, quality: 80));
    final hash = await computeBlurHash(jpeg);
    expect(hash, isNotNull);
    expect(BlurHashCodec.validate(hash!), isTrue,
        reason: 'hash hasil encode harus lolos validasi spek');
  });

  test('bytes bukan gambar → null (tidak melempar)', () async {
    final hash = await computeBlurHash(Uint8List.fromList([1, 2, 3, 4]));
    expect(hash, isNull);
  });
}
