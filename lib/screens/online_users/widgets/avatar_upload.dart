import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme.dart';
import '../../../core/media/native_image.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/online_users_provider.dart';
import '../../../providers/riverpod/timeline_provider.dart';
import '../../../utils.dart';

/// Pilih → crop 1:1 → proses native → upload avatar sendiri (dari halaman
/// Online). Setelah sukses, patch list Online & Timeline langsung supaya foto
/// baru terlihat tanpa pindah halaman / tunggu stream.
///
/// [onUploadingChanged] dipanggil true saat mulai proses & false saat selesai
/// (untuk state spinner di UI). Bila widget hilang (unmounted) saat proses,
/// callback TIDAK dipanggil lagi — pemanggil menangani lewat `mounted`.
Future<void> pickAndUploadAvatarFromOnline(
  BuildContext context, {
  required void Function(bool uploading) onUploadingChanged,
}) async {
  final s = ProviderScope.containerOf(context, listen: false)
      .read(localeProvider).s;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(s.avatarGallery),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(s.menuTakePhoto),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;

  final picker = ImagePicker();
  final XFile? picked;
  try {
    // TANPA maxWidth/imageQuality — foto asli utuh diteruskan ke cropper
    // (kompresi cukup 1x di akhir proses) — sama dengan profile_screen.
    picked = await picker.pickImage(source: source);
  } catch (e) {
    dlog('[ONLINE] pickImage error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errPhotoPermission)));
    }
    return;
  }
  if (picked == null || !context.mounted) return;

  // Crop interaktif 1:1 — geser/zoom pilih bagian yang masuk avatar.
  // Apa yang dilihat user di lingkaran = persis yang tersimpan.
  final CroppedFile? cropped;
  try {
    cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      maxWidth: 1024,
      maxHeight: 1024,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: s.avatarCamera,
          toolbarColor: AppTheme.bgScreen,
          toolbarWidgetColor: Colors.white,
          backgroundColor: Colors.black,
          activeControlsWidgetColor: AppTheme.primary,
          lockAspectRatio: true,
          // Edge-to-edge Android 15+: ikon status bar ikut terang/gelap
          // toolbar (jangan isi warna bar — API deprecated, ditolak Play).
          statusBarLight: !AppTheme.isDark,
        ),
        IOSUiSettings(title: s.avatarCamera, aspectRatioLockEnabled: true),
      ],
    );
  } catch (e) {
    dlog('[ONLINE] crop error: $e');
    return;
  }
  if (cropped == null || !context.mounted) return;

  onUploadingChanged(true);
  try {
    final bytes = await cropped.readAsBytes();
    if (!context.mounted) {
      onUploadingChanged(false);
      return;
    }

    final processed = await NativeImage.processSquare(bytes);
    if (processed == null || !context.mounted) {
      onUploadingChanged(false);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoProcess)));
      }
      return;
    }

    final pp = ProviderScope.containerOf(context, listen: false)
        .read(authProvider.notifier);
    await pp.updateAvatar(processed);
    if (context.mounted) {
      // Langsung patch list online & timeline supaya foto baru terlihat
      // tanpa pindah halaman / tunggu stream 30s
      try {
        final uid = pp.profile?.uid ?? '';
        if (uid.isNotEmpty) {
          ProviderScope.containerOf(context, listen: false)
              .read(onlineUsersProvider.notifier)
              .updateAvatarForUid(uid, processed);
          ProviderScope.containerOf(context, listen: false)
              .read(timelineProvider.notifier)
              .refreshAvatarForUid(uid, processed);
        }
      } catch (_) {}
      onUploadingChanged(false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.msgProfileSaved)));
    }
  } catch (e) {
    if (context.mounted) {
      onUploadingChanged(false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errPhotoUpload)));
    }
  }
}
