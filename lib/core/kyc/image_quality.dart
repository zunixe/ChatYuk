import 'dart:typed_data';

/// Kualitas frame kamera untuk foto dokumen — dihitung dari kanal
/// luminans (Y) di area tengah, disampling (stride) supaya murah per frame.
class FrameQuality {
  /// Varians Laplacian — makin besar makin tajam. < [minSharpness] = blur.
  final double sharpness;

  /// Porsi piksel nyaris putih (≥ 250) — pantulan lampu di laminasi KTP.
  final double glareRatio;

  /// Rata-rata kecerahan 0..255.
  final double brightness;

  const FrameQuality(this.sharpness, this.glareRatio, this.brightness);

  static const double minSharpness = 60;
  static const double maxGlare = 0.04;
  static const double minBrightness = 50;

  bool get sharp => sharpness >= minSharpness;
  bool get glare => glareRatio > maxGlare;
  bool get dark => brightness < minBrightness;
  bool get ok => sharp && !glare && !dark;

  Map<String, dynamic> toJson() => {
        'sharpness': double.parse(sharpness.toStringAsFixed(1)),
        'glare': double.parse(glareRatio.toStringAsFixed(3)),
        'brightness': double.parse(brightness.toStringAsFixed(1)),
      };

  /// [lum] diakses lewat [at] (x, y) → 0..255 supaya bisa dipakai untuk
  /// plane Y (nv21) maupun BGRA. Area: tengah [region] × [region] frame.
  static FrameQuality measure({
    required int width,
    required int height,
    required int Function(int x, int y) at,
    double region = 0.6,
    int step = 2,
  }) {
    final rw = (width * region).round();
    final rh = (height * region).round();
    final x0 = (width - rw) ~/ 2;
    final y0 = (height - rh) ~/ 2;
    var n = 0;
    var sum = 0.0;
    var sumSq = 0.0;
    var bright = 0;
    var lumSum = 0.0;
    for (var y = y0 + step; y < y0 + rh - step; y += step) {
      for (var x = x0 + step; x < x0 + rw - step; x += step) {
        final c = at(x, y);
        final lap = at(x - step, y) +
            at(x + step, y) +
            at(x, y - step) +
            at(x, y + step) -
            4 * c;
        sum += lap;
        sumSq += lap * lap;
        lumSum += c;
        if (c >= 250) bright++;
        n++;
      }
    }
    if (n == 0) return const FrameQuality(0, 0, 0);
    final mean = sum / n;
    return FrameQuality(sumSq / n - mean * mean, bright / n, lumSum / n);
  }

  /// Plane Y (nv21 / yuv420 plane 0).
  static FrameQuality fromLuma(
    Uint8List y,
    int width,
    int height,
    int bytesPerRow,
  ) =>
      measure(
        width: width,
        height: height,
        at: (x, yy) => y[yy * bytesPerRow + x],
      );

  /// Plane BGRA8888 (iOS) — luminans dari rata-rata kanal.
  static FrameQuality fromBgra(
    Uint8List p,
    int width,
    int height,
    int bytesPerRow,
  ) =>
      measure(
        width: width,
        height: height,
        at: (x, y) {
          final i = y * bytesPerRow + x * 4;
          return (p[i] * 29 + p[i + 1] * 150 + p[i + 2] * 77) >> 8;
        },
      );
}
