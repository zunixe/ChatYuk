import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../core/cache/offline_outbox.dart';
import '../core/chat/chat_location.dart';
import '../utils.dart' show capitalizeFirst;
import '../utils/mention.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../widgets/chat_info_snack.dart';
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
  /// Path video lokal yang sedang di-preview (null = tidak ada).
  /// Room mengembalikan null (fitur video belum aktif di sana).
  String? get sendPendingVideoPath => null;

  /// Lokasi yang sedang di-preview (null = tidak ada).
  ChatLocation? get sendPendingLocation => null;
  set sendPendingLocation(ChatLocation? v) {}

  /// Kirim lokasi yang SUDAH ditangkap pemanggil (+ caption & balasan).
  /// Lokasi dioper sebagai argumen (bukan dibaca ulang dari field) karena
  /// `sendMessage` membersihkan preview via `setState` sebelum memanggil ini.
  /// Implementasi nyata di layar (private: sendPrivateMessage; room:
  /// sendRoomMessage + dialog konfirmasi).
  Future<void> sendLocationFromPreviewAt(
    ChatLocation location, {
    String text = '',
    MessageModel? reply,
  });

  /// Kirim video dari preview. Default: delegasi ke implementasi nyata di
  /// `ChatPhotoSendMixin` (`sendVideoFromPreviewImpl`) — video TIDAK diaktifkan
  /// di sana (`videoSendEnabled=false`) sehingga aman untuk room (no-op).
  ///
  /// Layar BOLEH meng-override method ini (mis. tes/varian lain).
  Future<void> sendVideoFromPreview({
    String text = '',
    MessageModel? reply,
  }) => sendVideoFromPreviewImpl(text: text, reply: reply);

  /// Implementasi nyata di `ChatPhotoSendMixin`. Dipisah agar nama publik
  /// `sendVideoFromPreview` bebas di-override tanpa kalah linearisasi mixin.
  Future<void> sendVideoFromPreviewImpl({
    String text = '',
    MessageModel? reply,
  });

  /// Kandidat mention untuk layar ini.
  List<Mention> sendMentionCandidates();

  /// Cek tambahan sebelum kirim. Return false = batalkan (pesan sudah
  /// ditampilkan sendiri oleh implementor).
  /// - private: tolak bila lawan memblokir (`chat.isBlocked`)
  /// - room: cek role private-room (bukan member → ajak join)
  Future<bool> sendPreCheck();

  /// Batalkan mode edit (kosongkan state edit di layar).
  void sendCancelEdit();

  /// Kosongkan composer dengan nilai VALID (selection offset 0, composing
  /// range kosong). `TextEditingController.clear()` memakai
  /// `TextEditingValue.empty` yang selection-nya offset -1 (INVALID) → saat
  /// IME Android masih aktif/meng-compose, engine bisa mengirim balik nilai
  /// lama sehingga teks "muncul lagi" setelah terkirim. Setel eksplisit agar
  /// benar-benar bersih.
  void sendClearComposer() {
    sendMsgCtrl.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );
  }

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
    // Media (foto ATAU video) boleh dikirim tanpa caption. Tanpa
    // `hasVideo` di guard ini, kirim video tanpa teks BERHENTI di sini
    // (early return) sebelum cabang video sempat jalan.
    final hasVideo =
        sendPendingVideoPath != null && sendPendingVideoPath!.isNotEmpty;
    final hasLocation = sendPendingLocation != null;
    if (text.isEmpty && !hasPhoto && !hasVideo && !hasLocation) return;
    if (sendIsSending) return;


    // Soft gate anon: fitur anon OFF → tawarkan daftar, jangan kirim.
    if (ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).anonBlocked) {
      if (!mounted) return;
      final ls = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
      showAnonPromptDialog(
        context,
        title: ls.promptCompleteEmailChatTitle,
        message: ls.promptCompleteEmailChatMsg,
        icon: Icons.chat_bubble_outline,
      );
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
      sendClearComposer();
      setState(() => sendEditingMessage = null);
      sendIsSending = true;
      try {
        final ok = await sendEditPersist(editing, raw);
        if (mounted) {
          final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
          showChatSnack(context, ok ? s.msgEdited : s.errSendFailed);
        }
      } finally {
        sendIsSending = false;
      }
      return;
    }

    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;

    // Jika ada VIDEO preview → kirim video (+ caption & balasan).
    // Dicek SEBELUM foto: video & foto tidak boleh tampil bareng, tapi
    // video diprioritaskan bila keduanya sempat terisi.
    if (sendPendingVideoPath != null &&
        sendPendingVideoPath!.isNotEmpty) {
      final reply = sendReplyingTo;
      final text = sendMsgCtrl.text.trim();
      sendClearComposer();
      setState(() {
        sendReplyingTo = null;
      });
      sendIsSending = true;
      try {
        await sendVideoFromPreview(text: text, reply: reply);
      } finally {
        sendIsSending = false;
      }
      return;
    }

    // Jika ada LOKASI preview → kirim lokasi (+ caption & balasan bila ada).
    // Dicek SEBELUM video & foto: preview lokasi & media lain tidak bisa
    // tampil bareng, lokasi paling eksplisit.
    if (hasLocation) {
      // Tangkap lokasi SEBELUM clear: `setState` menjalankan callback-nya
      // sinkron, jadi `sendPendingLocation` sudah null saat
      // sendLocationFromPreview membaca field lagi (bug: lokasi tak pernah
      // terkirim — preview hilang tapi insert tak jalan).
      final loc = sendPendingLocation!;
      final reply = sendReplyingTo;
      final caption = sendMsgCtrl.text.trim();
      sendClearComposer();
      setState(() {
        sendPendingLocation = null;
        sendReplyingTo = null;
      });
      sendIsSending = true;
      try {
        await sendLocationFromPreviewAt(loc, text: caption, reply: reply);
      } finally {
        sendIsSending = false;
      }
      return;
    }

    // Jika ada foto preview → kirim foto (+ caption & balasan bila ada).
    if (hasPhoto) {
      final photoB64 = sendPendingPhotoBase64!;
      final reply = sendReplyingTo;
      sendClearComposer();
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
    sendClearComposer();
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

    final pp = ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier);
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
      final ss = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
      if (remaining == -1) {
        pp.showOutOfPointsDialog(context, ss.isId);
      } else {
        showChatSnack(context, ss.errSendFailed);
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
          final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
          final blockedByOther =
              e.toString().contains('42501') ||
              e.toString().toLowerCase().contains('insufficient_privilege') ||
              e.toString().toLowerCase().contains('policy');
          showChatSnack(
            context,
            blockedByOther ? s.msgBlockedByOther : s.errSendFailed,
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
