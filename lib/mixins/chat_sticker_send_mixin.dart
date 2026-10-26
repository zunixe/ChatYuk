import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../widgets/chat_info_snack.dart';
import '../widgets/sticker_bubble.dart';
import 'chat_send_mixin.dart';

/// Kirim STIKER (private & room) — instan ala WhatsApp.
///
/// Dulu: sheet menunggu upload/unduh + insert selesai BARU tertutup, dan
/// stiker baru tampil setelah gema server → "sudah ke-klik belum?" + lama.
/// Sekarang: bubble PENDING muncul seketika (stiker koleksi = path yang
/// bytes-nya sudah di cache sheet; stiker baru = base64 lokal), kirim di
/// latar. Stiker koleksi TIDAK diunduh ulang sebelum kirim.
mixin ChatStickerSendMixin<T extends StatefulWidget> on ChatSendMixin<T> {
  /// Insert pesan `type='sticker'` dengan path storage (private / room).
  /// Dispatch stiker; mengembalikan id pesan server (null bila gagal).
  Future<String?> stickerDispatch(String path);

  MessageModel? _pendingSticker(String data) {
    final auth = ProviderScope.containerOf(context, listen: false)
        .read(authProvider.notifier);
    final uid = auth.uid;
    final p = auth.profile;
    if (uid == null || p == null) return null;
    return MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: p.nickname,
      senderGender: p.gender,
      isRegistered: p.isRegistered,
      text: '',
      type: 'sticker',
      imageData: data,
      timestamp: DateTime.now(),
    );
  }

  /// Gagal kirim: BLOKIR → bubble tetap centang-1 (senyap); lainnya → buang
  /// bubble + snackbar.
  Future<void> _failPending(MessageModel m, Object e) async {
    if (isSilentBlock(e)) {
      await keepBlocked(m);
      return;
    }
    _dropPending(m);
  }

  void _dropPending(MessageModel m) {
    if (!mounted) return;
    setState(() => outboxPending.removeWhere((x) => x.id == m.id));
    showChatSnack(
      context,
      ProviderScope.containerOf(context, listen: false)
          .read(localeProvider)
          .s
          .stickerSendFail,
    );
  }

  /// Stiker BARU (bytes; png / gif / webp dari GIPHY): bubble base64 instan
  /// → upload → kirim path.
  Future<void> sendStickerBytes(Uint8List png, {String ext = 'png'}) async {
    if (png.isEmpty || !mounted) return;
    final pending = _pendingSticker(base64Encode(png));
    if (pending == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => outboxPending.add(pending));
    outboxScrollToBottom();
    try {
      final path = await container.read(storageProvider).uploadSticker(
            uid: pending.senderId,
            base64: pending.imageData,
            ext: ext,
          );
      if (path == null || path.isEmpty) throw Exception('upload failed');
      // NSFW/trust: stiker bisa GIF/WebP/MP4 — periksa sebelum dikirim.
      if (!await contentSafetyAllowsMedia(path)) {
        throw Exception('sticker_rejected');
      }
      // Pengirim langsung lihat versi server tanpa unduh.
      StickerBubble.seedCache(path, png);
      final stickerId = await stickerDispatch(path);
      if (mediaReviewNeeded) {
        mediaReviewNeeded = false;
        await mediaReviewFlag(stickerId);
      }
    } catch (e) {
      await _failPending(pending, e);
    }
  }

  /// Stiker KOLEKSI (sudah di server): bubble instan → langsung kirim.
  Future<void> sendStickerPath(String path) async {
    if (path.isEmpty || !mounted) return;
    final pending = _pendingSticker(path);
    if (pending == null) return;
    setState(() => outboxPending.add(pending));
    outboxScrollToBottom();
    try {
      // Stiker dari KOLEKSI: periksa konten sebelum kirim.
      if (!await contentSafetyAllowsMedia(path)) {
        throw Exception('sticker_rejected');
      }
      await stickerDispatch(path);
    } catch (e) {
      await _failPending(pending, e);
    }
  }
}
