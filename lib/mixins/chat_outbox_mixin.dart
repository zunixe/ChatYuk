import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_contact.dart';
import '../models/chat_poll.dart';
import '../models/message_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../core/cache/offline_outbox.dart';
import '../providers/riverpod/storage_provider.dart';
import '../utils.dart' show dlog;
import '../utils/mention.dart';
import '../widgets/chat_info_snack.dart';
import '../widgets/message/image_decode_core.dart' show warmPhotoCacheForPath;

/// Modul BERSAMA antrean pesan offline (private ↔ room).
///
/// Dulu logika ini disalin-tempel di `private_chat_screen` dan
/// `room_chat_screen` dan sudah mulai divergen. Sekarang satu implementasi;
/// tiap screen hanya menyediakan identitas chat + cara kirimnya.
///
/// ACUAN perilaku = `private_chat_screen` (paling baru). Room menyesuaikan.
///
/// Kontrak implementor:
/// - [outboxKind]          'private' / 'room'
/// - [outboxChatId]        id chat untuk penyimpanan antrean
/// - [outboxUploadChatId]  id folder upload storage (room: `room_<id>`)
/// - [outboxPending]       list bubble pending milik State (biasanya `_pending`)
/// - [outboxQueuedIds]     set id yang sedang mengantre (`_queuedIds`)
/// - [outboxIsFlushing]    flag guard flush
/// - [outboxIsOnline]      status koneksi saat ini
/// - [outboxScrollToBottom] scroll setelah antrean dimuat/terkirim
/// - [outboxSendEntry]     cara kirim satu entri (bedakan private/room)
/// - [outboxOnSent]        efek samping setelah 1 entri sukses (bonus/poin)
mixin ChatOutboxMixin<T extends StatefulWidget> on State<T> {
  String get outboxKind;
  String get outboxChatId;
  String get outboxUploadChatId;
  List<MessageModel> get outboxPending;
  Set<String> get outboxQueuedIds;
  bool get outboxIsFlushing;
  set outboxIsFlushing(bool v);
  bool get outboxIsOnline;
  void outboxScrollToBottom();
  Future<void> outboxSendEntry(OutboxEntry e, String imageData);
  void outboxOnSent();

  /// Id bubble yang DITOLAK karena blokir (centang-1 permanen). Pencocokan
  /// konfirmasi server WAJIB melewati id ini — kalau tidak, kiriman baru
  /// sejenis setelah unblock "memakan" bubble blokir lama.
  final Set<String> outboxBlockedIds = {};

  /// Ditolak karena BLOKIR → tangani senyap (bubble tetap centang-1). Hanya
  /// chat PRIVATE: di room, 42501/RLS berarti bukan anggota/dibisukan —
  /// user WAJIB diberi tahu, jangan disenyapkan.
  bool isSilentBlock(Object e) =>
      outboxKind == 'private' && OfflineOutbox.isBlockedError(e);

  /// Muat sisa antrean sesi lalu untuk chat ini — bubble langsung tampil lagi.
  Future<void> loadQueuedForChat() async {
    await OfflineOutbox.instance.load();
    if (!mounted) return;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final entries = OfflineOutbox.instance.forChat(outboxKind, outboxChatId);
    if (entries.isEmpty) return;
    setState(() {
      for (final e in entries) {
        if (e.blocked) outboxBlockedIds.add(e.pendingId);
        if (outboxPending.any((m) => m.id == e.pendingId)) {
          if (!e.blocked) outboxQueuedIds.add(e.pendingId);
          continue;
        }
        outboxPending.add(
          MessageModel(
            id: e.pendingId,
            senderId: e.senderId.isNotEmpty ? e.senderId : (auth.uid ?? ''),
            senderName: e.senderName.isNotEmpty
                ? e.senderName
                : (auth.profile?.nickname ?? ''),
            senderGender: e.senderGender,
            isRegistered: auth.profile?.isRegistered ?? false,
            text: e.text,
            type: e.type,
            imageData: e.imagePayload,
            timestamp: e.createdAt,
            durationMs: e.durationMs,
            repliedToId: e.repliedToId,
            repliedToText: e.repliedToText,
            repliedToSenderName: e.repliedToSenderName,
            repliedToMeta: e.repliedToMeta,
            isForwarded: e.isForwarded,
            mentions: e.mentions,
            poll: ChatPoll.tryParse(e.poll),
            contact: ChatContact.tryParse(e.contact),
          ),
        );
        if (!e.blocked) outboxQueuedIds.add(e.pendingId);
      }
    });
    outboxScrollToBottom();
    flushOutbox();
  }

  /// Simpan bubble pending ke antrean — bubble TETAP di layar (centang-1).
  Future<void> queueOffline({
    required MessageModel pending,
    required String pointsKind,
    required bool pointsDeducted,
    String? imagePayload,
    bool needsUpload = false,
    String uploadKind = '',
    int? durationMs,
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    Map<String, dynamic>? repliedToMeta,
    bool isForwarded = false,
    List<Mention> mentions = const [],
    String videoPosterB64 = '',
  }) async {
    await OfflineOutbox.instance.enqueue(
      OutboxEntry(
        pendingId: pending.id,
        kind: outboxKind,
        chatId: outboxChatId,
        senderId: pending.senderId,
        senderName: pending.senderName,
        senderGender: pending.senderGender,
        text: pending.text,
        type: pending.type,
        imagePayload: imagePayload ?? pending.imageData,
        needsUpload: needsUpload,
        uploadKind: uploadKind,
        durationMs: durationMs ?? pending.durationMs,
        repliedToId: repliedToId,
        repliedToText: repliedToText,
        repliedToSenderName: repliedToSenderName,
        repliedToMeta: repliedToMeta,
        isForwarded: isForwarded,
        mentions: mentions,
        createdAt: pending.timestamp,
        pointsDeducted: pointsDeducted,
        pointsKind: pointsKind,
        videoPosterB64: videoPosterB64,
      ),
    );
    if (!mounted) return;
    setState(() => outboxQueuedIds.add(pending.id));
  }

  /// Pesan DITOLAK server karena BLOKIR: bubble TETAP (centang-1), tanpa
  /// snackbar (blokir senyap), dan disimpan lokal supaya tidak hilang saat
  /// chat ditutup-buka. Tidak pernah dikirim ulang. [imagePayload] = data
  /// yang dipakai bubble untuk tampil lagi (base64/path lokal/path storage).
  Future<void> keepBlocked(
    MessageModel pending, {
    String? imagePayload,
    int? durationMs,
  }) async {
    dlog('[BLOCK] kirim ditolak (blokir) id=${pending.id} type=${pending.type}');
    if (mounted) {
      setState(() {
        outboxBlockedIds.add(pending.id);
        outboxQueuedIds.remove(pending.id);
        if (!outboxPending.any((m) => m.id == pending.id)) {
          outboxPending.add(pending);
        }
      });
    } else {
      outboxBlockedIds.add(pending.id);
    }
    await OfflineOutbox.instance.enqueue(
      OutboxEntry(
        pendingId: pending.id,
        kind: outboxKind,
        chatId: outboxChatId,
        senderId: pending.senderId,
        senderName: pending.senderName,
        senderGender: pending.senderGender,
        text: pending.text,
        type: pending.type,
        imagePayload: imagePayload ?? pending.imageData,
        durationMs: durationMs ?? pending.durationMs,
        repliedToId: pending.repliedToId,
        repliedToText: pending.repliedToText,
        repliedToSenderName: pending.repliedToSenderName,
        repliedToMeta: pending.repliedToMeta,
        isForwarded: pending.isForwarded,
        mentions: pending.mentions,
        createdAt: pending.timestamp,
        pointsKind: 'none',
        blocked: true,
        poll: pending.poll?.toJson(),
        contact: pending.contact?.toJson(),
      ),
    );
  }

  /// Kirim semua antrean chat ini (dipanggil saat koneksi pulih).
  Future<void> flushOutbox() async {
    if (outboxIsFlushing || !mounted) return;
    if (!outboxIsOnline) return;
    final entries = OfflineOutbox.instance
        .forChat(outboxKind, outboxChatId)
        .where((e) => !e.blocked)
        .toList();
    if (entries.isEmpty) return;
    outboxIsFlushing = true;
    try {
      // Baca provider SEKALI sebelum await — `context` tak aman dipakai
      // setelah widget dibuang (throw non-jaringan → entri hilang tanpa refund).
      final container = ProviderScope.containerOf(context, listen: false);
      final pp = container.read(pointsProvider.notifier);
      final storage = container.read(storageProvider);
      var sent = 0;
      for (var e in entries) {
        if (!mounted || !outboxIsOnline) break;
        if (!e.pointsDeducted && e.pointsKind != 'none') {
          final r = await pp.deductBeforeSend(e.pointsKind);
          if (r == -1) {
            await OfflineOutbox.instance.remove(e.pendingId);
            if (!mounted) break;
            setState(() {
              outboxQueuedIds.remove(e.pendingId);
              outboxPending.removeWhere((m) => m.id == e.pendingId);
            });
            pp.showOutOfPointsDialog(context, container.read(localeProvider).s.isId);
            continue;
          }
          if (r < 0) break; // Error jaringan/transien → coba lagi nanti.
          // Persist flag SEGERA: gagal jaringan di bawah → flush berikutnya
          // tidak memotong poin lagi.
          e = e.copyWith(pointsDeducted: true);
          await OfflineOutbox.instance.markPointsDeducted(e.pendingId);
          if (!mounted) break;
        }
        try {
          var imageData = e.imagePayload;
          if (e.needsUpload && imageData.isNotEmpty) {
            if (e.uploadKind == 'voice') {
              final path = await storage.uploadVoice(
                chatId: outboxUploadChatId,
                bytes: base64Decode(imageData),
              );
              if (path == null || path.isEmpty) {
                throw const SocketException('voice upload failed');
              }
              imageData = path;
            } else if (e.uploadKind == 'video') {
              // Video: payload = bytes video mentah (base64).
              final path = await storage.uploadChatVideo(
                chatId: outboxUploadChatId,
                bytes: base64Decode(imageData),
              );
              if (path == null || path.isEmpty) {
                throw const SocketException('video upload failed');
              }
              imageData = path;
            } else {
              final path = await storage.upload(
                chatId: outboxUploadChatId,
                base64: imageData,
              );
              if (path == null || path.isEmpty) {
                throw const SocketException('photo upload failed');
              }
              // Sama seperti jalur online: daftarkan decode agar bubble versi
              // server langsung tampil tanpa kotak dulu.
              warmPhotoCacheForPath(path, imageData);
              imageData = path;
            }
            // Widget dibuang saat upload → entri (flag poin sudah tersimpan)
            // tetap di antrean untuk flush berikutnya.
            if (!mounted) break;
          }
          await outboxSendEntry(e, imageData);
          await OfflineOutbox.instance.remove(e.pendingId);
          sent++;
          if (mounted) setState(() => outboxQueuedIds.remove(e.pendingId));
          outboxOnSent();
        } catch (err) {
          if (OfflineOutbox.isNetworkError(err)) break;
          if (e.pointsDeducted && e.pointsKind != 'none') {
            safeUnawaited(pp.refundChatPoint(e.pointsKind));
          }
          if (isSilentBlock(err)) {
            // Ditolak BLOKIR saat flush: bubble tetap (centang-1), entri
            // ditandai agar tidak dicoba lagi. Tanpa snackbar (senyap).
            dlog('[BLOCK] flush ditolak (blokir) id=${e.pendingId}');
            await OfflineOutbox.instance.markBlocked(e.pendingId);
            if (!mounted) break;
            setState(() {
              outboxQueuedIds.remove(e.pendingId);
              outboxBlockedIds.add(e.pendingId);
            });
            continue;
          }
          await OfflineOutbox.instance.remove(e.pendingId);
          if (!mounted) break;
          setState(() {
            outboxQueuedIds.remove(e.pendingId);
            outboxPending.removeWhere((m) => m.id == e.pendingId);
          });
        }
      }
      if (sent > 0 && mounted) {
        showChatSnack(context, container.read(localeProvider).s.msgQueueSent(sent));
        outboxScrollToBottom();
      }
    } finally {
      outboxIsFlushing = false;
    }
  }
}
