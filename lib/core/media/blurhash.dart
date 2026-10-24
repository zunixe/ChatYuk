import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// BlurHash (encode + decode) — implementasi murni Dart sesuai spesifikasi
/// resmi (https://github.com/woltapp/blurhash). Dipakai untuk menghasilkan
/// placeholder instan foto post di Timeline (ala Threads/Instagram) sehingga
/// tidak ada kedipan/layout shift sebelum thumbnail tiba.
///
/// Catatan: `flutter_blurhash` (dipakai untuk MENAMPILKAN) hanya menyediakan
/// decode. Encoder di sini menutup celah itu tanpa dependensi tambahan selain
/// `package:image` yang SUDAH dipakai proyek.
class BlurHashCodec {
  BlurHashCodec._();

  /// Alfabet base83 sesuai spesifikasi BlurHash.
  static const String alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
      '#\$%*+,-.:;=?@[]^_{|}~';

  static double _srgbToLinear(int value) {
    final v = value / 255.0;
    if (v <= 0.04045) return v / 12.92;
    return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  static int _linearToSrgb(double value) {
    final v = value.clamp(0.0, 1.0);
    if (v <= 0.0031308) return (v * 12.92 * 255 + 0.5).toInt();
    return ((1.055 * math.pow(v, 1 / 2.4) - 0.055) * 255 + 0.5).toInt();
  }

  static double _signPow(double value, double exp) =>
      (math.pow(value.abs(), exp) * value.sign).toDouble();

  static int _encodeDC(double r, double g, double b) =>
      (_linearToSrgb(r) << 16) + (_linearToSrgb(g) << 8) + _linearToSrgb(b);

  static List<double> _decodeDC(int value) {
    final intR = value >> 16;
    final intG = (value >> 8) & 255;
    final intB = value & 255;
    return [
      _srgbToLinear(intR),
      _srgbToLinear(intG),
      _srgbToLinear(intB),
    ];
  }

  static int _encodeAC(double r, double g, double b, double maximumValue) {
    int quant(double value) {
      final v = _signPow(value / maximumValue, 0.5) * 9 + 9.5;
      return v.floor().clamp(0, 18);
    }

    return quant(r) * 19 * 19 + quant(g) * 19 + quant(b);
  }

  static List<double> _decodeAC(int value, double maximumValue) {
    final quantR = value ~/ (19 * 19);
    final quantG = (value ~/ 19) % 19;
    final quantB = value % 19;
    return [
      _signPow((quantR - 9) / 9.0, 2.0) * maximumValue,
      _signPow((quantG - 9) / 9.0, 2.0) * maximumValue,
      _signPow((quantB - 9) / 9.0, 2.0) * maximumValue,
    ];
  }

  static String _encode83(int value, int length) {
    final result = StringBuffer();
    for (var i = 1; i <= length; i++) {
      final digit = (value ~/ math.pow(83, length - i).toInt()) % 83;
      result.write(alphabet[digit]);
    }
    return result.toString();
  }

  static int _decode83(String str) {
    var value = 0;
    for (var i = 0; i < str.length; i++) {
      final digit = alphabet.indexOf(str[i]);
      if (digit < 0) return -1;
      value = value * 83 + digit;
    }
    return value;
  }

  /// Bentuk hash valid? (panjang & alfabet sesuai)
  static bool validate(String hash) {
    if (hash.length < 6) return false;
    for (var i = 0; i < hash.length; i++) {
      if (!alphabet.contains(hash[i])) return false;
    }
    final sizeFlag = _decode83(hash.substring(0, 1));
    final numY = (sizeFlag ~/ 9) + 1;
    final numX = (sizeFlag % 9) + 1;
    if (numX < 1 || numX > 9 || numY < 1 || numY > 9) return false;
    return hash.length == 4 + 2 * numX * numY;
  }

  /// Encode [pixels] (RGBA, stride 4, panjang = width*height*4) → hash.
  static String encode({
    required List<int> pixels,
    required int width,
    required int height,
    int componentX = 4,
    int componentY = 3,
  }) {
    assert(pixels.length >= width * height * 4, 'pixels kurang dari w*h*4');
    final factorsR = <double>[];
    final factorsG = <double>[];
    final factorsB = <double>[];

    for (var y = 0; y < componentY; y++) {
      for (var x = 0; x < componentX; x++) {
        final normalisation = (x == 0 && y == 0) ? 1.0 : 2.0;
        var r = 0.0, g = 0.0, b = 0.0;
        for (var i = 0; i < width; i++) {
          final cosX = math.cos(math.pi * x * i / width);
          for (var j = 0; j < height; j++) {
            final basis = cosX * math.cos(math.pi * y * j / height);
            final idx = (i + j * width) * 4;
            r += basis * _srgbToLinear(pixels[idx]);
            g += basis * _srgbToLinear(pixels[idx + 1]);
            b += basis * _srgbToLinear(pixels[idx + 2]);
          }
        }
        final scale = normalisation / (width * height);
        factorsR.add(r * scale);
        factorsG.add(g * scale);
        factorsB.add(b * scale);
      }
    }

    final sizeFlag = (componentX - 1) + (componentY - 1) * 9;
    final hash = StringBuffer(_encode83(sizeFlag, 1));

    double maximumValue;
    if (factorsR.length > 1) {
      var actualMaximumValue = 0.0;
      for (var i = 1; i < factorsR.length; i++) {
        actualMaximumValue = math.max(
          actualMaximumValue,
          math.max(
            factorsR[i].abs(),
            math.max(factorsG[i].abs(), factorsB[i].abs()),
          ),
        );
      }
      final quantisedMaximumValue = (actualMaximumValue * 166 - 0.5)
          .floor()
          .clamp(0, 82);
      maximumValue = (quantisedMaximumValue + 1) / 166.0;
      hash.write(_encode83(quantisedMaximumValue, 1));
    } else {
      maximumValue = 1.0;
      hash.write(_encode83(0, 1));
    }

    hash.write(
      _encode83(_encodeDC(factorsR[0], factorsG[0], factorsB[0]), 4),
    );
    for (var i = 1; i < factorsR.length; i++) {
      hash.write(
        _encode83(
          _encodeAC(factorsR[i], factorsG[i], factorsB[i], maximumValue),
          2,
        ),
      );
    }
    return hash.toString();
  }

  /// Decode [hash] → RGBA (stride 4) pada ukuran [width]×[height].
  /// Dipakai untuk test round-trip & (opsional) render manual.
  static ({Uint8List pixels, int width, int height}) decode(
    String hash, {
    int width = 32,
    int height = 32,
  }) {
    if (!validate(hash)) {
      throw ArgumentError('BlurHash tidak valid: $hash');
    }
    final sizeFlag = _decode83(hash.substring(0, 1));
    final numY = (sizeFlag ~/ 9) + 1;
    final numX = (sizeFlag % 9) + 1;
    final quantisedMaximumValue = _decode83(hash.substring(1, 2));
    final maximumValue = (quantisedMaximumValue + 1) / 166.0;

    final colors = List<List<double>>.generate(numX * numY, (i) {
      if (i == 0) return _decodeDC(_decode83(hash.substring(2, 6)));
      return _decodeAC(
        _decode83(hash.substring(4 + i * 2, 6 + i * 2)),
        maximumValue,
      );
    });

    final out = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var r = 0.0, g = 0.0, b = 0.0;
        for (var j = 0; j < numY; j++) {
          for (var i = 0; i < numX; i++) {
            final basis =
                math.cos(math.pi * x * i / width) *
                math.cos(math.pi * y * j / height);
            final color = colors[i + j * numX];
            r += color[0] * basis;
            g += color[1] * basis;
            b += color[2] * basis;
          }
        }
        final idx = (x + y * width) * 4;
        out[idx] = _linearToSrgb(r);
        out[idx + 1] = _linearToSrgb(g);
        out[idx + 2] = _linearToSrgb(b);
        out[idx + 3] = 255;
      }
    }
    return (pixels: out, width: width, height: height);
  }
}

/// Sisi terpanjang maksimum saat mengekstrak piksel untuk encode (ringan).
const int kBlurHashSmallSide = 32;

/// Komponen default: 4×3 (kualitas bagus, hash tetap pendek).
const int kBlurHashComponentsX = 4;
const int kBlurHashComponentsY = 3;

/// Top-level untuk `compute()`: decode JPEG → kecilkan (sisi terpanjang
/// [kBlurHashSmallSide], proporsional) → encode BlurHash. Return null bila
/// bukan gambar yang bisa didecode (jangan melempar).
String? blurHashFromJpegTask((Uint8List, int, int) args) {
  final (bytes, cx, cy) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) return null;
  final longest = math.max(decoded.width, decoded.height);
  final small = longest <= kBlurHashSmallSide
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height
              ? kBlurHashSmallSide
              : null,
          height: decoded.height > decoded.width
              ? kBlurHashSmallSide
              : null,
          interpolation: img.Interpolation.average,
        );
  try {
    final rgba = small.getBytes(order: img.ChannelOrder.rgba);
    return BlurHashCodec.encode(
      pixels: rgba,
      width: small.width,
      height: small.height,
      componentX: cx,
      componentY: cy,
    );
  } catch (_) {
    return null;
  }
}

/// Hitung BlurHash dari bytes JPEG di isolate. Null bila gagal (pemanggil
/// menyimpan string kosong — placeholder jatuh ke alas #1E1E1E).
Future<String?> computeBlurHash(
  Uint8List jpeg, {
  int componentX = kBlurHashComponentsX,
  int componentY = kBlurHashComponentsY,
}) async {
  if (jpeg.isEmpty) return null;
  try {
    return await compute(blurHashFromJpegTask, (jpeg, componentX, componentY));
  } catch (_) {
    return null;
  }
}
