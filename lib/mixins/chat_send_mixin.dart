import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../core/cache/offline_outbox.dart';
import '../utils.dart' show capitalizeFirst;
import '../utils/mention.dart';
import '../widgets/anon_prompt_dialog.dart';
import 'chat_outbox_mixin.dart';
import 'chat_photo_send_mixin.dart';

/// Modul BERSAMA alur kirim pesan (private ↔ room) — teks, caption foto,
/// edit, balas, poin, antrean offline.
///
/// Dulu `_send` disalin 288 baris (private) vs 292 baris (room) dan mulai
/// divergen. Sekarang satu kerangka; kekhasan tiap produk lewat hook.
///
/// **Acuan = `private_chat_screen`.** Dua pengecualian yang DISEPAKATI
/// (bukan asal timpa):
/// - edit-mode: ikut private (senyap, tanpa guard/snackbar)
/// - foto + balas: dukung `repliedTo` (superset) supaya fitur room tidak hilang
///
/// Wajib dipakai bersama [ChatOutboxMixin] + [ChatPhotoSendMixin].
mixin ChatSendMixin<T extends StatefulWidget>
    on ChatOutboxMixin<T>, ChatPhotoSendMixin<T> {
  // ── Kontrak ──
  TextEditingController get sendMsgCtrl;
  bool get sendIsSending;
  set sendIsSending(bool v);
  MessageModel? get sendEditingMessage;
  set sendEditingMessage(MessageModel? v);
  MessageModel? get sendReplyingTo;
  set sendReplyingTo(MessageModel? v);
  String? get sendPendingPhotoBase64;
  set sendPendingPhotoBase64(String? v);

  /// Kandidat mention untuk layar ini.
  List<Mention> sendMentionCandidates();

  /// Cek tambahan sebelum kirim. Return false = batalkan (pesan sudah
  /// ditampilkan sendiri oleh implementor).
  /// - private: tolak bila lawan memblokir (`chat.isBlocked`)
  /// - room: cek role private-room (bukan member → ajak join)
  Future<bool> sendPreCheck();

  /// Batalkan mode edit (kosongkan state edit di layar).
  void sendCancelEdit();

  /// Simpan perubahan pesan yang sedang diedit (private: editPrivateMessage,
  /// room: editRoomMessage). Return true bila server menerima.
  Future<bool> sendEditPersist(MessageModel editing, String raw);

  /// Kirim pesan teks (private: sendPrivateMessage, room: sendRoomMessage).
  Future<void> sendDispatchText({
    required String text,
    required MessageModel? reply,
    required List<Mention> mentions,
  });

  /// Efek setelah pesan teks sukses terkirim.
  /// - private: bonus chat baru + fallback konfirmasi pending
  /// - room: toast potong poin + counter bonus 5 pesan
  void sendOnSentText();

  /// Alur kirim tunggal.
  Future<void> sendMessage() async {
    final raw = sendMsgCtrl.text.trim();
    // Kapitalkan huruf pertama saat kirim PESAN BARU (gaya WhatsApp).
    final text = capitalizeFirst(raw);
    final hasPhoto = sendPendingPhotoBase64 != null;
    if (text.isEmpty && !hasPhoto) return;
    if (sendIsSending) return;

    // Soft gate anon: fitur anon OFF → tawarkan daftar, jangan kirim.
    if (context.read<AuthProvider>().anonBlocked) {
      if (!mounted) return;
      showAnonPromptDialog(context);
      return;
    }

    // Cek kekhasan layar (blokir / role private-room).
    if (!await sendPreCheck()) return;
    if (!mounted) return;

    // Mode edit: kirim langsung mengubah pesan lama (bukan pesan baru).
    // Pakai versi ROOM (lebih aman): guard `_isSending` (anti double-tap) +
    // snackbar hasil (user tahu edit berhasil/gagal).
    final editing = sendEditingMessage;
    if (editing != null && !hasPhoto) {
      if (raw.isEmpty || raw == editing.text) {
        sendCancelEdit();
        return;
      }
      sendMsgCtrl.clear();
      setState(() => sendEditingMessage = null);
      sendIsSending = true;
      try {
        final ok = await sendEditPersist(editing, raw);
        if (mounted) {
          final s = context.read<LocaleProvider>().s;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? s.msgEdited : s.errSendFailed)),
          );
        }
      } finally {
        sendIsSending = false;
      }
      return;
    }

    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;

    // Jika ada foto preview → kirim foto (+ caption & balasan bila ada).
    if (hasPhoto) {
      final photoB64 = sendPendingPhotoBase64!;
      final reply = sendReplyingTo;
      sendMsgCtrl.clear();
      setState(() {
        sendPendingPhotoBase64 = null;
        sendReplyingTo = null;
      });
      sendIsSending = true;
      try {
        await sendPhotoBase64(photoB64, text: text, reply: reply);
      } finally {
        sendIsSending = false;
      }
      return;
    }

    // ── Pesan teks ──
    sendMsgCtrl.clear();
    sendIsSending = true;
    final reply = sendReplyingTo;
    final mentions = parseMentions(text, candidates: sendMentionCandidates());
    final pending = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: text,
      type: 'text',
      imageData: '',
      timestamp: DateTime.now(),
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
      mentions: mentions,
    );
    setState(() {
      outboxPending.add(pending);
      sendReplyingTo = null;
    });
    outboxScrollToBottom();

    // Tanpa koneksi: antrekan (poin dipotong saat benar-benar terkirim).
    if (!outboxIsOnline) {
      await queueOffline(
        pending: pending,
        pointsKind: 'text',
        pointsDeducted: false,
        repliedToId: reply?.id,
        repliedToText: reply?.text,
        repliedToSenderName: reply?.senderName,
        mentions: mentions,
      );
      sendIsSending = false;
      return;
    }

    final pp = context.read<PointsProvider>();
    final remaining = await pp.deductBeforeSend('text');
    if (remaining < 0) {
      if (remaining == -2) {
        await queueOffline(
          pending: pending,
          pointsKind: 'text',
          pointsDeducted: false,
          repliedToId: reply?.id,
          repliedToText: reply?.text,
          repliedToSenderName: reply?.senderName,
          mentions: mentions,
        );
        sendIsSending = false;
        return;
      }
      setState(() => outboxPending.remove(pending));
      sendIsSending = false;
      if (!mounted) return;
      final ss = context.read<LocaleProvider>().s;
      if (remaining == -1) {
        pp.showOutOfPointsDialog(context, ss.isId);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ss.errSendFailed)));
      }
      return;
    }

    try {
      await sendDispatchText(text: text, reply: reply, mentions: mentions);
      sendOnSentText();
    } catch (e) {
      if (OfflineOutbox.isNetworkError(e)) {
        // Poin sudah dipotong, jangan refund — dipakai saat flush.
        await queueOffline(
          pending: pending,
          pointsKind: 'text',
          pointsDeducted: true,
          repliedToId: reply?.id,
          repliedToText: reply?.text,
          repliedToSenderName: reply?.senderName,
          mentions: mentions,
        );
      } else {
        safeUnawaited(pp.refundChatPoint('text'));
        if (mounted) {
          setState(() => outboxPending.remove(pending));
          final s = context.read<LocaleProvider>().s;
          final blockedByOther =
              e.toString().contains('42501') ||
              e.toString().toLowerCase().contains('insufficient_privilege') ||
              e.toString().toLowerCase().contains('policy');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                blockedByOther ? s.msgBlockedByOther : s.errSendFailed,
              ),
            ),
          );
        }
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      sendIsSending = false;
    }
    if (mounted) outboxScrollToBottom();
  }
}
