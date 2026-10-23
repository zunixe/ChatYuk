import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/chat/chat_file.dart';
import '../models/message_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../widgets/chat_info_snack.dart';
import 'chat_send_mixin.dart';

/// Kirim FILE/dokumen (ala WhatsApp) — private & room memakai mixin ini.
///
/// Alur: pilih file → validasi ukuran → bubble optimistik (spinner) →
/// potong poin (sama foto) → upload storage → dispatch `type='file'`
/// (text = nama file, durationMs = ukuran byte). Offline / gagal → bubble
/// dibuang + snackbar + refund poin (tanpa antrean offline: file bisa
/// puluhan MB, tidak disimpan di outbox).
mixin ChatFileSendMixin<T extends StatefulWidget> on ChatSendMixin<T> {
  Future<void> pickAndSendFile() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final s = container.read(localeProvider).s;
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(withData: false);
    } catch (_) {
      return;
    }
    final f = res?.files.single;
    final path = f?.path;
    if (f == null || path == null || !mounted) return;
    if (f.size > ChatFile.maxBytes) {
      showChatSnack(context, s.errFileTooLarge(ChatFile.maxBytes ~/ 1048576));
      return;
    }
    await sendFileFromPath(path: path, name: f.name, size: f.size);
  }

  Future<void> sendFileFromPath({
    required String path,
    required String name,
    required int size,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final s = container.read(localeProvider).s;
    final reply = sendReplyingTo;

    void fail() {
      if (!mounted) return;
      showChatSnack(context, s.errSendFile);
    }

    if (!outboxIsOnline) {
      fail();
      return;
    }

    final pending = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: name,
      type: 'file',
      imageData: '',
      timestamp: DateTime.now(),
      durationMs: size,
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
      repliedToMeta: sendReplyMeta(reply),
    );
    ChatFile.rememberLocal(pending.id, path);
    setState(() {
      outboxPending.add(pending);
      sendReplyingTo = null;
    });
    outboxScrollToBottom();

    void dropPending() {
      ChatFile.forgetLocal(pending.id);
      if (mounted) {
        setState(() => outboxPending.removeWhere((m) => m.id == pending.id));
      }
    }

    final pp = container.read(pointsProvider.notifier);
    final r = await pp.deductBeforeSend('image');
    if (r < 0) {
      dropPending();
      if (!mounted) return;
      if (r == -1) {
        pp.showOutOfPointsDialog(context, s.isId);
      } else {
        fail();
      }
      return;
    }

    try {
      // STREAMING dari disk — JANGAN `readAsBytes()` (file ≤50MB → RAM spike).
      final storagePath = await container
          .read(storageProvider)
          .uploadChatFileFromPath(
            chatId: photoUploadChatId,
            fileName: name,
            filePath: path,
            contentType: ChatFile.mimeOf(name),
          );
      if (storagePath == null || storagePath.isEmpty) {
        throw Exception('upload failed');
      }
      // Simpan path lokal juga untuk path storage (pesan versi server).
      ChatFile.rememberLocal(storagePath, path);
      await photoDispatch(
        imageData: storagePath,
        type: 'file',
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: name,
        repliedToId: reply?.id,
        repliedToText: reply?.text,
        repliedToSenderName: reply?.senderName,
        repliedToMeta: sendReplyMeta(reply),
        videoDurationMs: size,
      );
      photoOnSent('file');
      outboxScrollToBottom();
    } catch (e) {
      unawaited(pp.refundChatPoint('image'));
      // BLOKIR: kartu file tetap centang-1 (path lokal masih diingat),
      // tanpa snackbar (senyap).
      if (isSilentBlock(e)) {
        await keepBlocked(pending);
        return;
      }
      dropPending();
      fail();
    }
  }
}
