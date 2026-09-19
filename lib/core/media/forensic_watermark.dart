import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Hasil deteksi watermark untuk satu kandidat seed.
class WatermarkDetect {
  final String seed;
  final double rho;
  final double z;
  final bool matched;
  const WatermarkDetect({
    required this.seed,
    required this.rho,
    required this.z,
    required this.matched,
  });
}

/// Forensic watermark untuk foto view-once.
///
/// Spread-spectrum di domain DCT kanal luminance:
/// - Kode pseudo-random ±1 diturunkan dari seed (UID penerima) dengan hash
///   FNV-1a yang STABIL lintas platform/run (bukan String.hashCode).
/// - Kode SAMA untuk semua blok (global code) + averaging saat ekstraksi,
///   supaya tahan terhadap sedikit misalignment crop & noise gambar.
/// - Koefisien DCT frekuensi rendah dipilih supaya tahan terhadap downscale
///   (foto tampil ~200px) dan recapture layar kamera HP kedua.
/// - Gambar di-resize proporsional (sisi terpanjang = [size]) agar rasio asli
///   tetap; blok 64px disusun mengikuti dimensi sebenarnya (grid 16 blok).
class ForensicWatermark {
  ForensicWatermark._();

  static const int size = 1200;
  static const int blockSize = 64;
  static const int coeffsPerBlock = 32;
  static const double alpha = 50.0;

  /// Ambang z-score antar-seed untuk verdict "matched". Seed benar adalah
  /// outlier jauh di atas distribusi seed lain (dalam uji: victim z≈2.8,
  /// seed salah ≤1.6). Disetel saat validasi recapture lapangan.
  static const double threshold = 2.0;

  static final List<(int, int)> _positions = _zigzagLow(coeffsPerBlock);

  // ── Hash stabil FNV-1a 32-bit ───────────────────────────────
  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Kode ±1 deterministik per seed, SEIMBANG (6×+1, 6×−1) sehingga mean-nya
  /// persis nol. Centering per-blok saat ekstraksi hanya menyisakan sinyal.
  static Float64List _code(String seed) {
    final c = Float64List(coeffsPerBlock);
    final half = coeffsPerBlock ~/ 2;
    for (int p = 0; p < coeffsPerBlock; p++) {
      c[p] = p < half ? 1 : -1;
    }
    // Fisher–Yates deterministik dari hash seed.
    final rng = math.Random(_fnv1a(seed));
    for (int p = coeffsPerBlock - 1; p > 0; p--) {
      final j = rng.nextInt(p + 1);
      final t = c[p];
      c[p] = c[j];
      c[j] = t;
    }
    return c;
  }

  // ── Posisi zigzag frekuensi rendah (tanpa DC) ────────────────
  static List<(int, int)> _zigzagLow(int count) {
    final out = <(int, int)>[];
    var sum = 1;
    while (out.length < count) {
      for (var r = 0; r <= sum; r++) {
        final c = sum - r;
        final pair = sum.isEven ? (r, c) : (c, r);
        out.add(pair);
        if (out.length >= count) break;
      }
      sum++;
    }
    return out;
  }

  // ── DCT 1D / 2D (orthonormal DCT-II) ─────────────────────────
  static double _cos(int k, int i, int n) =>
      math.cos((math.pi * (2 * i + 1) * k) / (2 * n));

  static Float64List _dct1d(Float64List x) {
    final n = x.length;
    final out = Float64List(n);
    final scale = math.sqrt(2.0 / n);
    for (int k = 0; k < n; k++) {
      double sum = 0;
      for (int i = 0; i < n; i++) {
        sum += x[i] * _cos(k, i, n);
      }
      out[k] = (k == 0 ? scale / math.sqrt(2.0) : scale) * sum;
    }
    return out;
  }

  static Float64List _idct1d(Float64List y) {
    final n = y.length;
    final out = Float64List(n);
    final scale = math.sqrt(2.0 / n);
    for (int i = 0; i < n; i++) {
      double sum = 0;
      for (int k = 0; k < n; k++) {
        final ck = k == 0 ? scale / math.sqrt(2.0) : scale;
        sum += ck * y[k] * _cos(k, i, n);
      }
      out[i] = sum;
    }
    return out;
  }

  static Float64List _dct2d(Float64List block, int n) =>
      _transform2d(block, n, _dct1d);

  static Float64List _idct2d(Float64List block, int n) =>
      _transform2d(block, n, _idct1d);

  static Float64List _transform2d(
    Float64List block,
    int n,
    Float64List Function(Float64List) axis,
  ) {
    final tmp = Float64List(n * n);
    for (int r = 0; r < n; r++) {
      final row = Float64List(n);
      for (int c = 0; c < n; c++) {
        row[c] = block[r * n + c];
      }
      final d = axis(row);
      for (int c = 0; c < n; c++) {
        tmp[r * n + c] = d[c];
      }
    }
    final out = Float64List(n * n);
    for (int c = 0; c < n; c++) {
      final col = Float64List(n);
      for (int r = 0; r < n; r++) {
        col[r] = tmp[r * n + c];
      }
      final d = axis(col);
      for (int r = 0; r < n; r++) {
        out[r * n + c] = d[r];
      }
    }
    return out;
  }

  // ── Kanal luminance (Rec.601) ────────────────────────────────
  static double _luma(num r, num g, num b) => 0.299 * r + 0.587 * g + 0.114 * b;

  static Float64List _luminance(img.Image im) {
    final w = im.width;
    final h = im.height;
    final y = Float64List(w * h);
    for (int yy = 0; yy < h; yy++) {
      for (int x = 0; x < w; x++) {
        final p = im.getPixel(x, yy);
        y[yy * w + x] = _luma(p.r, p.g, p.b);
      }
    }
    return y;
  }

  static double _blockVariance(Float64List block) {
    double mean = 0;
    for (final v in block) {
      mean += v;
    }
    mean /= block.length;
    double varSum = 0;
    for (final v in block) {
      final d = v - mean;
      varSum += d * d;
    }
    return varSum / block.length;
  }

  // ── EMBED ────────────────────────────────────────────────────
  /// Decode → resize 1024 → embed watermark → encode JPEG → base64.
  /// `seed` = UID penerima (satu-satunya pihak yang akan melihat foto).
  static String? embedToBase64(Uint8List bytes, String seed) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // Resize proporsional: sisi terpanjang = size, rasio asli dipertahankan.
    final resized = _resizeMaxSide(decoded, size);
    _embedInto(resized, seed);
    final jpg = img.encodeJpg(resized, quality: 82);
    return base64Encode(jpg);
  }

  static img.Image _resizeMaxSide(img.Image src, int maxSide) {
    final w = src.width;
    final h = src.height;
    if (w <= maxSide && h <= maxSide) return src;
    final scale = maxSide / (w > h ? w : h);
    final nw = (w * scale).round();
    final nh = (h * scale).round();
    return img.copyResize(
      src,
      width: nw,
      height: nh,
      interpolation: img.Interpolation.linear,
    );
  }

  static void _embedInto(img.Image im, String seed) {
    final n = blockSize;
    final w = im.width;
    final h = im.height;
    final gridX = w ~/ n;
    final gridY = h ~/ n;
    final y = _luminance(im);
    final code = _code(seed);

    for (int by = 0; by < gridY; by++) {
      for (int bx = 0; bx < gridX; bx++) {
        final block = Float64List(n * n);
        for (int i = 0; i < n; i++) {
          for (int j = 0; j < n; j++) {
            block[i * n + j] = y[(by * n + i) * w + bx * n + j];
          }
        }
        final dct = _dct2d(block, n);
        final varb = _blockVariance(block);
        final alphaB = alpha * (0.5 + 0.5 * math.min(varb / 400.0, 1.0));
        for (int p = 0; p < coeffsPerBlock; p++) {
          final (r, c) = _positions[p];
          dct[r * n + c] += alphaB * code[p];
        }
        final back = _idct2d(dct, n);
        for (int i = 0; i < n; i++) {
          for (int j = 0; j < n; j++) {
            y[(by * n + i) * w + bx * n + j] = back[i * n + j];
          }
        }
      }
    }

    // Tulis balik Y, pertahankan Cb/Cr agar warna tidak berubah.
    for (int yy = 0; yy < h; yy++) {
      for (int x = 0; x < w; x++) {
        final p = im.getPixel(x, yy);
        final cb = (p.b.toDouble() - _luma(p.r, p.g, p.b)) * 0.564 + 128.0;
        final cr = (p.r.toDouble() - _luma(p.r, p.g, p.b)) * 0.713 + 128.0;
        final ny = y[yy * w + x].round().clamp(0, 255);
        final rr = (ny + 1.402 * (cr - 128.0)).round().clamp(0, 255);
        final gg = (ny - 0.344136 * (cb - 128.0) - 0.714136 * (cr - 128.0))
            .round()
            .clamp(0, 255);
        final bb = (ny + 1.772 * (cb - 128.0)).round().clamp(0, 255);
        im.setPixelRgb(x, yy, rr, gg, bb);
      }
    }
  }

  // ── EXTRACT ──────────────────────────────────────────────────
  /// Deteksi watermark pada gambar (mis. foto bocor yang sudah di-crop).
  /// Kembalikan skor korelasi untuk tiap kandidat seed, urut menurun.
  static List<WatermarkDetect> detect(
    Uint8List bytes,
    List<String> candidates,
  ) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const [];

    // Multi-skala: recapture mengubah ukuran tampil. Embed selalu membuat
    // grid = size/blockSize = 16 blok pada sisi terpanjang. Saat ekstraksi,
    // blockSize harus mengikuti ukuran gambar agar grid tetap 16 blok.
    const gridBlocks = 16;
    const scales = [1600, 1024, 768, 512, 448, 384, 320, 256, 224, 192];
    const shifts = [0, -8, 8, -16, 16];

    // Kumpulkan SEMUA ekstraksi (tiap skala × shift) untuk evaluasi per seed.
    final means = <List<double>>[];
    for (final target in scales) {
      final resized = _resizeMaxSide(decoded, target);
      final n = (target / gridBlocks).round();
      final y = _luminance(resized);
      for (final dx in shifts) {
        for (final dy in shifts) {
          final mean = _extractMean(
            y,
            resized.width,
            resized.height,
            n,
            dx,
            dy,
          );
          means.add(mean);
        }
      }
    }

    // Untuk tiap seed: maxRho atas semua offset (pencarian alignment/skala).
    final rhos = <double>[];
    for (final seed in candidates) {
      final code = _code(seed);
      var maxRho = double.negativeInfinity;
      for (final mean in means) {
        final r = _correlate(mean, code);
        if (r > maxRho) maxRho = r;
      }
      rhos.add(maxRho);
    }

    // Z-score ANTAR-SEED: seed benar adalah outlier — maxRho-nya jauh di atas
    // distribusi maxRho seed lain. Seed salah berkumpul di tingkat noise.
    final n = rhos.length;
    final mu = rhos.reduce((a, b) => a + b) / n;
    final variance =
        rhos.map((r) => (r - mu) * (r - mu)).reduce((a, b) => a + b) / (n - 1);
    final sigma = math.sqrt(variance) + 1e-6;

    final results = <WatermarkDetect>[];
    for (int i = 0; i < candidates.length; i++) {
      final z = (rhos[i] - mu) / sigma;
      results.add(
        WatermarkDetect(
          seed: candidates[i],
          rho: rhos[i],
          z: z,
          matched: z > threshold,
        ),
      );
    }
    results.sort((a, b) => b.rho.compareTo(a.rho));
    return results;
  }

  static List<double> _extractMean(
    Float64List y,
    int w,
    int h,
    int n,
    int dx,
    int dy,
  ) {
    final gridX = w ~/ n;
    final gridY = h ~/ n;
    final acc = Float64List(coeffsPerBlock);
    final cnt = Float64List(coeffsPerBlock);
    for (int by = 0; by < gridY; by++) {
      for (int bx = 0; bx < gridX; bx++) {
        final ox = bx * n + dx;
        final oy = by * n + dy;
        if (ox < 0 || oy < 0 || ox + n > w || oy + n > h) continue;
        final block = Float64List(n * n);
        for (int i = 0; i < n; i++) {
          for (int j = 0; j < n; j++) {
            block[i * n + j] = y[(oy + i) * w + ox + j];
          }
        }
        final dct = _dct2d(block, n);
        // Center-kan koefisien terpilih: buang offset konten gambar sehingga
        // hanya sinyal watermark (code ±1, mean 0) yang tersisa per-blok.
        var meanP = 0.0;
        for (int p = 0; p < coeffsPerBlock; p++) {
          final (r, c) = _positions[p];
          meanP += dct[r * n + c];
        }
        meanP /= coeffsPerBlock;
        var ss = 0.0;
        final vals = Float64List(coeffsPerBlock);
        for (int p = 0; p < coeffsPerBlock; p++) {
          final (r, c) = _positions[p];
          vals[p] = dct[r * n + c] - meanP;
          ss += vals[p] * vals[p];
        }
        final std = math.sqrt(ss / coeffsPerBlock) + 1e-6;
        for (int p = 0; p < coeffsPerBlock; p++) {
          acc[p] += vals[p] / std;
          cnt[p] += 1;
        }
      }
    }
    final mean = List<double>.filled(coeffsPerBlock, 0);
    for (int p = 0; p < coeffsPerBlock; p++) {
      if (cnt[p] > 0) mean[p] = acc[p] / cnt[p];
    }
    return mean;
  }

  static double _correlate(List<double> c, Float64List code) {
    // Cosine similarity: bounded [-1,1], tahan amplitudo/energi gambar.
    double num = 0, denC = 0, denCode = 0;
    for (int p = 0; p < code.length; p++) {
      num += c[p] * code[p];
      denC += c[p] * c[p];
      denCode += code[p] * code[p];
    }
    return num / (math.sqrt(denC) * math.sqrt(denCode) + 1e-9);
  }
}
