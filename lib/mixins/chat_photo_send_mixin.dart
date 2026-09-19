import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../services/chat_photo_helper.dart';
import '../services/offline_outbox.dart';
import '../services/storage_photo_service.dart';
import '../widgets/chat_ui_shared.dart' show processChatImage;
import 'chat_outbox_mixin.dart';

/// Modul BERSAMA kirim foto & view-once (private ↔ room).
///
/// Dulu logika ini hidup dua kali: private sudah pakai optimistic + antrean
/// offline; room masih 79 baris mandiri TANPA outbox. Sekarang satu jalur —
/// room ikut dapat centang-1 + kirim otomatis saat koneksi pulih.
///
/// Acuan = `private_chat_screen`. Perbedaan produk dijaga lewat hook
/// ([photoDispatch] beda private/room, [photoFirstBonus] hanya private).
///
/// Wajib dipakai bersama [ChatOutboxMixin].
mixin ChatPhotoSendMixin<T extends StatefulWidget> on ChatOutboxMixin<T> {
  // ── Kontrak ──
  /// Kirim pesan gambar (private: sendPrivateMessage; room: sendRoomMessage).
  Future<void> photoDispatch({
    required String imageData,
    required String type,
    required String senderId,
    required String senderName,
    required String senderGender,
  });

  /// Folder upload storage (private: chatId; room: `room_<id>`).
  String get photoUploadChatId;

  /// Seed watermark view-once (private: uid lawan; room: id room).
  String get photoSeed;

  /// Efek setelah foto sukses terkirim (private: bonus + fallback; room: no-op).
  void photoOnSent(String kind);

  /// Bonus sekali pakai khusus private (`first_photo`); room = no-op.
  void photoFirstBonus(PointsProvider pp);

  /// Set preview foto di composer (private: + fokus & scroll; room: set saja).
  void photoSetPreview(String base64);

  final ImagePicker _photoPicker = ImagePicker();

  ImagePicker get photoPicker => _photoPicker;

  /// Tombol kamera: ambil → proses → taruh di preview composer.
  Future<void> photoTakeToPreview() async {
    final picked = await _photoPicker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return;
    final processed = await photoProcess(await picked.readAsBytes());
    if (processed != null && mounted) photoSetPreview(processed);
  }

  /// Tombol galeri: ambil → proses → langsung kirim.
  Future<void> photoPickFromGalleryAndSend() async {
    final picked = await _photoPicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await sendPhotoBytes(await picked.readAsBytes());
  }

  /// Validasi ukuran + resize isolate. Return base64, null bila gagal
  /// (pesan error sudah tampil).
  Future<String?> photoProcess(Uint8List bytes) async {
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgFileTooLarge)));
      }
      return null;
    }
    final base64 = await compute(processChatImage, bytes);
    if (base64 == null && mounted) {
      final s = context.read<LocaleProvider>().s;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errPhotoRead)));
    }
    return base64;
  }

  /// Kirim foto biasa (optimistic + poin + upload + antre offline).
  Future<void> sendPhotoBytes(Uint8List bytes) async {
    final base64 = await photoProcess(bytes);
    if (base64 == null || !mounted) return;
    await _sendImageLike(base64: base64, kind: 'image', type: 'image');
  }

  /// Kirim view-once (watermark bila aktif).
  Future<void> sendViewOnceFromPicker() async {
    final picked = await _photoPicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final base64 = await (auth.watermarkEnabled
        ? compute(processViewOnceImage, (bytes, photoSeed))
        : compute(processChatPhoto, bytes));
    if (base64 == null) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoRead)));
      }
      return;
    }
    if (!mounted) return;
    await _sendImageLike(base64: base64, kind: 'view_once', type: 'view_once');
  }

  Future<void> _sendImageLike({
    required String base64,
    required String kind,
    required String type,
  }) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;

    final pendingPhoto = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: '',
      type: type,
      imageData: base64,
      timestamp: DateTime.now(),
    );
    setState(() => outboxPending.add(pendingPhoto));
    outboxScrollToBottom();

    // Offline: bubble tetap tampil (centang-1) + antre.
    if (!outboxIsOnline) {
      await queueOffline(
        pending: pendingPhoto,
        pointsKind: kind,
        pointsDeducted: false,
        imagePayload: base64,
        needsUpload: true,
        uploadKind: 'image',
      );
      return;
    }

    final pp = context.read<PointsProvider>();
    final r = await pp.deductBeforeSend(kind);
    if (r < 0) {
      setState(() => outboxPending.removeWhere((m) => m.id == pendingPhoto.id));
      if (!mounted) return;
      final s = context.read<LocaleProvider>().s;
      if (r == -1) {
        pp.showOutOfPointsDialog(context, s.isId);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
      }
      return;
    }

    try {
      final path = await StoragePhotoService.instance.upload(
        chatId: photoUploadChatId,
        base64: base64,
      );
      if (path == null || path.isEmpty) {
        if (!outboxIsOnline) throw const SocketException('photo upload failed');
        safeUnawaited(pp.refundChatPoint(kind));
        if (mounted) {
          final s = context.read<LocaleProvider>().s;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
          setState(
            () => outboxPending.removeWhere((m) => m.id == pendingPhoto.id),
          );
        }
        return;
      }
      await photoDispatch(
        imageData: path,
        type: type,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
      );
      if (kind == 'image') photoFirstBonus(pp);
      photoOnSent(kind);
      outboxScrollToBottom();
    } catch (e) {
      if (OfflineOutbox.isNetworkError(e) || !outboxIsOnline) {
        // Poin sudah dipotong, jangan refund — dipakai saat flush.
        await queueOffline(
          pending: pendingPhoto,
          pointsKind: kind,
          pointsDeducted: true,
          imagePayload: base64,
          needsUpload: true,
          uploadKind: 'image',
        );
      } else {
        safeUnawaited(pp.refundChatPoint(kind));
        if (mounted) {
          setState(
            () => outboxPending.removeWhere((m) => m.id == pendingPhoto.id),
          );
          final s = context.read<LocaleProvider>().s;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
        }
      }
    }
  }
}
