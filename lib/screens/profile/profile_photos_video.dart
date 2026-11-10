part of '../profile_screen.dart';

/// Upload VIDEO galeri profil ("Foto Saya") — mixin terpisah supaya
/// `profile_photos.dart` tetap di bawah gate 1000 baris.
///
/// Alur: pilih (kamera/galeri) → validasi durasi 30 dtk → cek wajah
/// (khusus female: mayoritas frame sampel memuat tepat satu wajah) →
/// kompres 720p → poster + preview blur → upload.
mixin _ProfilePhotosVideoMx on _ProfileBase {
  Future<void> _addGalleryVideo(ImageSource source) async {
    final scope = ProviderScope.containerOf(context, listen: false);
    final s = scope.read(localeProvider).s;
    final storage = scope.read(storageProvider);

    String? path;
    if (source == ImageSource.camera && _isFemaleAccount) {
      // Female: kamera DALAM-APP — verifikasi wajah tampil DI LAYAR REKAM
      // (hint live di preview, tombol rekam aktif hanya saat 1 wajah,
      // hasil dicek cepat di layar yang sama). Bukan di layar lain.
      path = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              FaceCaptureVideoScreen(maxMs: storage.galleryVideoMaxMs),
        ),
      );
      if (path == null || !mounted) return;
    } else {
      XFile? picked;
      try {
        picked = await ImagePicker().pickVideo(
          source: source,
          preferredCameraDevice: CameraDevice.front,
          maxDuration: Duration(milliseconds: storage.galleryVideoMaxMs),
        );
      } catch (e) {
        dlog('[PROFILE] pickVideo error: $e');
        _videoSnack(s.errPhotoPermission);
        return;
      }
      if (picked == null || !mounted) return;
      path = picked.path;
    }

    // 1) Durasi ASLI — tolak >30 dtk SEBELUM kompres (jangan buang waktu).
    final rawMs = await storage.videoDurationMs(path);
    if (!mounted) return;
    if (rawMs > storage.galleryVideoMaxMs) {
      _videoSnack(s.galleryVideoHint);
      return;
    }

    // 2) Female + GALERI: video WAJIB memuat wajah (sampling frame + ML Kit).
    //    Rekaman KAMERA in-app sudah diverifikasi LIVE di layar rekam →
    //    tidak perlu cek ulang di sini. `failed` (detektor tak tersedia)
    //    diloloskan — pola sama foto.
    if (_isFemaleAccount && source != ImageSource.camera) {
      final check = await FaceCheck.checkVideo(path, durationMs: rawMs);
      if (!mounted) return;
      if (check == FaceCheckResult.noFace) {
        final retry = await _confirmVideoFaceRetry(s);
        if (!mounted) return;
        if (retry) await _addGalleryVideo(source);
        return;
      }
    }

    // 3) Kompres 720p/24fps — gagal = tolak (jangan upload mentah).
    setState(() => _uploading = true);
    _videoSnack(s.videoCompressing);
    try {
      final out = await storage.compressGalleryVideo(path);
      if (!mounted) return;
      if (out == null || !await out.exists()) {
        _videoSnack(s.videoCompressFail);
        return;
      }
      // Durasi HASIL — metadata file asli bisa tak terbaca (0).
      final outMs = await storage.videoDurationMs(out.path);
      if (!mounted) return;
      if (outMs > storage.galleryVideoMaxMs) {
        _videoSnack(s.galleryVideoHint);
        return;
      }
      final bytes = await out.readAsBytes();
      if (bytes.length > storage.galleryVideoMaxBytes) {
        _videoSnack(s.videoTooLarge);
        return;
      }
      // 4) Poster: thumbnail kartu + preview blur untuk paywall.
      final poster = await storage.storyVideoPoster(out.path);
      if (!mounted) return;
      if (poster == null || poster.isEmpty) {
        _videoSnack(s.videoCompressFail);
        return;
      }
      final processed = await NativeImage.processGalleryPhoto(poster);
      await scope
          .read(authProvider.notifier)
          .uploadVideo(
            videoBytes: bytes,
            posterBytes: poster,
            preview: processed?.preview ?? '',
            faceVerified: _isFemaleAccount,
          );
      await _loadPhotos();
    } catch (e) {
      dlog('[PROFILE] uploadVideo error: $e');
      _videoSnack(s.errPhotoSave);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _videoSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Wajah tidak terdeteksi di video → tawarkan pilih ulang (pola sama foto).
  Future<bool> _confirmVideoFaceRetry(S s) async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.photoVerifyDialogTitle),
        content: Text(s.galleryVideoNoFace),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.photoVerifyRetry),
          ),
        ],
      ),
    );
    return retry == true;
  }
}
