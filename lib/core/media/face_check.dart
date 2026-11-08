import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../utils.dart';

/// Hasil cek wajah pada sebuah file gambar.
enum FaceCheckResult {
  /// Tepat satu wajah — lolos.
  ok,

  /// Tidak ada wajah — tolak (bukan foto muka).
  noFace,

  /// Lebih dari satu wajah — tolak (selfie harus sendiri).
  multiple,

  /// Detektor gagal (device tak mendukung / ML Kit error) — jangan blokir
  /// user karena keterbatasan device (pola sama dengan `KycScreen.faceChecker`).
  failed,
}

/// Deteksi wajah pada file gambar (ML Kit, native).
///
/// Dipakai verifikasi foto profil female: gambar yang dipilih (kamera/galeri)
/// WAJIB memuat wajah — dicek SEBELUM upload supaya user langsung tahu dan
/// bisa langsung mengganti fotonya.
class FaceCheck {
  FaceCheck._();

  /// Opsi detektor TUNGGAL — dipakai semua jalur (kamera live & cek file)
  /// supaya hasil identifikasi konsisten: foto yang lolos di kamera juga
  /// lolos saat dicek dari galeri, dan sebaliknya.
  static FaceDetectorOptions get options => FaceDetectorOptions(
    performanceMode: FaceDetectorMode.fast,
    enableClassification: true,
    enableTracking: true,
    minFaceSize: 0.2,
  );

  /// Hitung wajah; -1 = detektor gagal.
  static Future<int> countInFile(String path) async {
    final d = FaceDetector(options: options);
    try {
      final faces = await d.processImage(InputImage.fromFilePath(path));
      return faces.length;
    } catch (e) {
      dlog('[FACE-CHECK] detect error: $e');
      return -1;
    } finally {
      try {
        await d.close();
      } catch (e) {
        dlog('[FACE-CHECK] close error: $e');
      }
    }
  }

  /// Klasifikasikan file → [FaceCheckResult].
  static Future<FaceCheckResult> checkFile(String path) async {
    final n = await countInFile(path);
    if (n < 0) return FaceCheckResult.failed;
    if (n == 0) return FaceCheckResult.noFace;
    if (n > 1) return FaceCheckResult.multiple;
    return FaceCheckResult.ok;
  }
}
