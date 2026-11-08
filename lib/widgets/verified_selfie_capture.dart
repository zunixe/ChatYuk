import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/media/face_check.dart';
import '../providers/riverpod/locale_provider.dart';
import '../utils.dart';
import 'face_capture_camera.dart';

/// Pilih foto + VALIDASI WAJAH — untuk upload foto profil.
///
/// KAMERA → kamera dalam-app ([FaceCaptureCameraScreen]): hint "bukan
/// wajah" tampil LANGSUNG di layar kamera (dulu kamera sistem + snackbar
/// yang tertutup layar kamera).
/// GALERI → picker sistem; hasil dicek setelah dipilih.
///
/// Keduanya: bukan wajah → dialog penjelasan → "Pilih Foto Lagi" membuka
/// lagi (user langsung ganti), "Batal" menghentikan.
///
/// [crop] opsional (avatar 1:1): validasi dijalankan pada HASIL CROP —
/// yang diupload harus benar-benar memuat wajah, bukan file aslinya.
///
/// Return path file final yang lolos, atau null bila batal.
/// Detektor gagal (-1) → diloloskan (jangan blokir karena keterbatasan
/// device; pola sama dengan alur KYC).
Future<String?> pickVerifiedFacePhoto(
  BuildContext context, {
  required ImageSource source,
  double? maxWidth,
  int? imageQuality,
  Future<String?> Function(String path)? crop,
}) async {
  final s = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(localeProvider).s;
  while (true) {
    if (!context.mounted) return null;
    String path;
    if (source == ImageSource.camera) {
      final shot = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const FaceCaptureCameraScreen(),
        ),
      );
      if (shot == null || !context.mounted) return null;
      path = shot;
    } else {
      final XFile? picked;
      try {
        picked = await ImagePicker().pickImage(
          source: source,
          maxWidth: maxWidth,
          imageQuality: imageQuality,
        );
      } catch (e) {
        dlog('[PHOTO-VERIFY] pickImage error: $e');
        if (context.mounted) _snack(context, s.errPhotoPermission);
        return null;
      }
      if (picked == null) return null; // user batal
      path = picked.path;
    }
    if (crop != null) {
      final cropped = await crop(path);
      if (cropped == null) return null; // batal di cropper
      path = cropped;
    }
    final r = await FaceCheck.checkFile(path);
    if (r == FaceCheckResult.ok || r == FaceCheckResult.failed) return path;
    if (!context.mounted) return null;
    // LAYAR penolakan (bukan dialog/snackbar): foto yang ditolak tampil
    // penuh + alasannya, jadi tidak mungkin tertutup layar lain.
    final retry = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FaceRejectPreviewScreen(path: path, result: r),
      ),
    );
    if (retry != true || !context.mounted) return null;
    // Tidak return → sumber dibuka lagi: user langsung ganti foto.
  }
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
