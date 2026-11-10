import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:video_compress/video_compress.dart';

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

  /// Frame video pada posisi [positionMs] → FILE (JPEG) untuk deteksi.
  /// [video_compress] dipakai karena `video_thumbnail` terpisah merusak
  /// build AGP 9 (lihat StoragePhotoService.storyVideoPoster).
  static Future<File?> _defaultFrameAt(String videoPath, int positionMs) async {
    try {
      return await VideoCompress.getFileThumbnail(
        videoPath,
        quality: 70,
        position: positionMs,
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      dlog('[FACE-CHECK] frame extract error: $e');
      return null;
    }
  }

  /// Cek wajah pada VIDEO (galeri profil female): sampling 4 frame
  /// (15/40/65/90% durasi) → lolos bila MAYORITAS frame yang berhasil
  /// diekstrak memuat TEPAT satu wajah.
  ///
  /// Ini verifikasi "ada wajah" per-frame, BUKAN liveness (kedip/toleh) —
  /// lebih longgar dari selfie liveness, tapi mencegah video tanpa wajah /
  /// video orang banyak dipakai sebagai konten profil.
  ///
  /// [frameAt] & [countFaces] dapat diinjeksi untuk unit test (tanpa plugin
  /// native). Semua frame gagal diekstrak / detektor error →
  /// [FaceCheckResult.failed] (jangan blokir user karena keterbatasan device
  /// — pola sama foto).
  static Future<FaceCheckResult> checkVideo(
    String videoPath, {
    required int durationMs,
    Future<File?> Function(String videoPath, int positionMs)? frameAt,
    Future<int> Function(String framePath)? countFaces,
  }) async {
    final extract = frameAt ?? _defaultFrameAt;
    final count = countFaces ?? countInFile;
    final d = durationMs > 0 ? durationMs : 6000;
    final positions = <int>[
      (d * 0.15).round(),
      (d * 0.40).round(),
      (d * 0.65).round(),
      (d * 0.90).round(),
    ];
    var samples = 0;
    var okFrames = 0;
    final tempFiles = <File>[];
    try {
      for (final pos in positions) {
        final f = await extract(videoPath, pos);
        if (f == null) continue;
        tempFiles.add(f);
        final n = await count(f.path);
        if (n < 0) continue; // detektor error → sampel diabaikan
        samples++;
        if (n == 1) okFrames++;
      }
    } finally {
      // Dedupe path: extractor bisa mengembalikan file yang sama.
      final seen = <String>{};
      for (final f in tempFiles) {
        if (!seen.add(f.path)) continue;
        try {
          await f.delete();
        } catch (e) {
          dlog('[FACE-CHECK] temp delete error: $e');
        }
      }
    }
    if (samples == 0) return FaceCheckResult.failed;
    return okFrames * 2 >= samples ? FaceCheckResult.ok : FaceCheckResult.noFace;
  }
}
