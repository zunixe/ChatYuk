import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../core/cache/offline_outbox.dart';
import '../services/storage_photo_service.dart';
import '../utils/mention.dart';

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

  /// Muat sisa antrean sesi lalu untuk chat ini — bubble langsung tampil lagi.
  Future<void> loadQueuedForChat() async {
    await OfflineOutbox.instance.load();
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final entries = OfflineOutbox.instance.forChat(outboxKind, outboxChatId);
    if (entries.isEmpty) return;
    setState(() {
      for (final e in entries) {
        if (outboxPending.any((m) => m.id == e.pendingId)) {
          outboxQueuedIds.add(e.pendingId);
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
            isForwarded: e.isForwarded,
            mentions: e.mentions,
          ),
        );
        outboxQueuedIds.add(e.pendingId);
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
    bool isForwarded = false,
    List<Mention> mentions = const [],
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
        isForwarded: isForwarded,
        mentions: mentions,
        createdAt: pending.timestamp,
        pointsDeducted: pointsDeducted,
        pointsKind: pointsKind,
      ),
    );
    if (!mounted) return;
    setState(() => outboxQueuedIds.add(pending.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocaleProvider>().s.msgQueuedOffline)),
    );
  }

  /// Kirim semua antrean chat ini (dipanggil saat koneksi pulih).
  Future<void> flushOutbox() async {
    if (outboxIsFlushing || !mounted) return;
    if (!outboxIsOnline) return;
    final entries = OfflineOutbox.instance.forChat(outboxKind, outboxChatId);
    if (entries.isEmpty) return;
    outboxIsFlushing = true;
    try {
      final pp = context.read<PointsProvider>();
      var sent = 0;
      for (final e in entries) {
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
            if (mounted) {
              pp.showOutOfPointsDialog(
                context,
                context.read<LocaleProvider>().s.isId,
              );
            }
            continue;
          }
          if (r < 0) break; // Error jaringan/transien → coba lagi nanti.
        }
        try {
          var imageData = e.imagePayload;
          if (e.needsUpload && imageData.isNotEmpty) {
            if (e.uploadKind == 'voice') {
              final path = await StoragePhotoService.instance.uploadVoice(
                chatId: outboxUploadChatId,
                bytes: base64Decode(imageData),
              );
              if (path == null || path.isEmpty) {
                throw const SocketException('voice upload failed');
              }
              imageData = path;
            } else {
              final path = await StoragePhotoService.instance.upload(
                chatId: outboxUploadChatId,
                base64: imageData,
              );
              if (path == null || path.isEmpty) {
                throw const SocketException('photo upload failed');
              }
              imageData = path;
            }
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
          await OfflineOutbox.instance.remove(e.pendingId);
          if (!mounted) break;
          setState(() {
            outboxQueuedIds.remove(e.pendingId);
            outboxPending.removeWhere((m) => m.id == e.pendingId);
          });
        }
      }
      if (sent > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<LocaleProvider>().s.msgQueueSent(sent)),
          ),
        );
        outboxScrollToBottom();
      }
    } finally {
      outboxIsFlushing = false;
    }
  }
}
