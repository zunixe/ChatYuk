import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chatyuk/services/forensic_watermark.dart';
import 'package:image/image.dart' as img;

void main() {
  const victim = '279f6944-0fa8-4f15-a9e5-e94d09773359';
  final wrongSeeds = List.generate(
      20, (i) => 'xxxx-yyyy-zzzz-wwww-${i.toString().padLeft(12, '0')}');

  final rng = _Rng(100);
  final source = img.Image(width: 1200, height: 900);
  for (final p in source) {
    final gradient = (p.x * 255 ~/ source.width) * 0.5 +
        (p.y * 255 ~/ source.height) * 0.3 +
        rng.next(30);
    p
      ..r = (gradient + rng.next(20)).clamp(0, 255)
      ..g = (gradient * 0.9 + rng.next(20)).clamp(0, 255)
      ..b = (gradient * 0.7 + rng.next(20)).clamp(0, 255);
  }
  final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 90));
  final embedded = ForensicWatermark.embedToBase64(bytes, victim)!;
  final embeddedBytes = base64Decode(embedded);
  final decoded = img.decodeImage(embeddedBytes)!;

  // A: recode q70 same-size (transmisi/pembukaan penuh)
  final aBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 70));
  // B: tampil penuh di fullscreen (~400px) lalu di-foto ulang
  final big = img.copyResize(decoded, width: 400);
  final bBytes = Uint8List.fromList(img.encodeJpg(big, quality: 70));

  var pass = true;
  for (final (label, b) in [('A q70 512', aBytes), ('B fullscreen 400', bBytes)]) {
    final res = ForensicWatermark.detect(b, [victim, ...wrongSeeds]);
    final v = res.firstWhere((r) => r.seed == victim);
    final wrongMax = res
        .where((r) => r.seed != victim)
        .map((r) => r.rho)
        .reduce((a, b) => a > b ? a : b);
    final rank = res.indexOf(v) + 1;
    final ok = rank == 1 && v.matched;
    if (!ok) pass = false;
    stdout.writeln(
        '$label: victim rho=${v.rho.toStringAsFixed(3)} z=${v.z.toStringAsFixed(2)}  '
        'wrongMax rho=${wrongMax.toStringAsFixed(3)}  rank=$rank  '
        '${ok ? 'OK' : 'BAD'}');
    final wrongZs = res.where((r) => r.seed != victim).map((r) => r.z).toList()
      ..sort();
    final wmin = wrongZs.first, wmax = wrongZs.last;
    stdout.writeln(
        '    wrong z: min=${wmin.toStringAsFixed(2)} max=${wmax.toStringAsFixed(2)}');
  }
  stdout.writeln(pass ? 'ALL PASS' : 'SOME FAIL');
  exit(pass ? 0 : 1);
}

class _Rng {
  _Rng(int seed) : _s = seed;
  int _s;
  int next(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return _s % max;
  }
}
