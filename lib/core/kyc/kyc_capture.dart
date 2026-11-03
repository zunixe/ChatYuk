import 'image_quality.dart';
import 'ktp_ocr.dart';

/// Hasil kamera KTP: file foto + data yang terbaca + kualitas frame.
class KycDocCapture {
  final String path;
  final KtpOcrResult ocr;
  final FrameQuality? quality;

  /// true = dipotret otomatis setelah KTP terbaca & tajam.
  final bool auto;

  const KycDocCapture({
    required this.path,
    required this.ocr,
    this.quality,
    this.auto = false,
  });
}

/// Hasil kamera wajah: file selfie + bukti liveness.
class KycSelfieCapture {
  final String path;

  /// true = semua tantangan (kedip + toleh) lolos dengan wajah yang sama.
  final bool live;

  /// Tantangan yang diselesaikan, urut (mis. ['blink','turn']).
  final List<String> steps;

  const KycSelfieCapture({
    required this.path,
    required this.live,
    this.steps = const [],
  });
}
