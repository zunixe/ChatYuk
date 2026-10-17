import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/riverpod/locale_provider.dart';
import '../widgets/gallery_picker_sheet.dart';
import 'chat_send_mixin.dart';

/// Tombol "Gallery" ala WhatsApp — private & room memakai mixin ini.
///
/// - 1 foto  → jalur preview lama (caption, HD, timer sekali-lihat).
/// - ≥2 foto → LANGSUNG terkirim sebagai satu ALBUM (tanpa preview),
///   HD mengikuti toggle di pemilih. Balasan aktif ditempel ke foto pertama.
/// - Tombol folder → pemilih sistem (alur lama, multi + preview).
mixin ChatGallerySendMixin<T extends StatefulWidget> on ChatSendMixin<T> {
  static const int galleryMaxPhotos = 10;

  Future<void> openGalleryPicker() async {
    final s = ProviderScope.containerOf(context, listen: false)
        .read(localeProvider)
        .s;
    final res = await GalleryPickerSheet.show(
      context,
      s: s,
      maxSelect: galleryMaxPhotos,
    );
    if (res == null || !mounted) return;
    if (res.useSystemPicker) {
      await photoPickFromGalleryToPreview();
      return;
    }
    final bytes = await res.readBytes();
    if (!mounted) return;
    await sendGalleryBytes(bytes, hd: res.hd);
  }

  /// Kirim hasil pilihan galeri (urut pilih). Dipisah agar bisa diuji.
  Future<void> sendGalleryBytes(List<Uint8List> bytes, {required bool hd}) async {
    if (bytes.isEmpty) return;
    if (bytes.length == 1) {
      await photoFromFileToPreview(bytes.first);
      if (mounted && pendingPhotoOriginal != null) {
        setState(() => photoHd = hd);
      }
      return;
    }
    albumExtraB64.clear();
    albumExtraOriginal.clear();
    String? first;
    Uint8List? firstOrig;
    for (final b in bytes) {
      final processed = await photoProcess(b);
      if (processed == null) continue;
      if (first == null) {
        first = processed;
        firstOrig = b;
      } else {
        albumExtraB64.add(processed);
        albumExtraOriginal.add(b);
      }
    }
    if (first == null || !mounted) return;
    pendingPhotoOriginal = firstOrig;
    photoHd = hd;
    final reply = sendReplyingTo;
    if (reply != null) setState(() => sendReplyingTo = null);
    await sendPhotoBase64(first, reply: reply);
  }
}
