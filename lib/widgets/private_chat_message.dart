import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils.dart';
import 'mention_spans.dart';
import 'chat_video_bubble.dart';
import 'media_caption_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/strings_admin.dart';
import '../config/gifts.dart';
import '../models/message_model.dart';
import '../providers/riverpod/locale_provider.dart';
import '../core/chat/chat_location.dart';
import '../widgets/location_bubble.dart';
import 'app_gesture.dart';
import 'reply_quote.dart';
import 'message/deferred_image.dart';
import 'message/swipe_to_reply.dart';
import 'message/message_text_with_time.dart';
import 'message/message_image.dart';
import 'message/view_once_image.dart';
import 'voice_bubble.dart';
import 'link_preview.dart';
import '../core/media/link_preview_service.dart';
import '../config/theme.dart';

// cacheKey untuk PhotoCache = cacheKey yang dipakai chat_service
// ('private_$chatId' untuk private chat). Dipakai private chat & admin monitor.
String cacheKeyFor(String chatId) => 'private_$chatId';

/// Ikon jenis pesan untuk penanda "dihapus" di monitor admin — supaya admin
/// tahu pesan apa yang dihapus (teks/gambar/video/suara/lokasi/panggilan).
/// Murni & testable.
IconData adminDeletedTypeIcon(String type) {
  switch (type) {
    case 'image':
    case 'view_once':
    case 'view_once_expired':
      return Icons.image_outlined;
    case 'video':
    case 'video_once':
    case 'video_once_expired':
      return Icons.videocam_outlined;
    case 'voice':
      return Icons.mic_outlined;
    case 'location':
      return Icons.location_on_outlined;
    case 'call':
      return Icons.call_outlined;
    default:
      return Icons.chat_bubble_outline;
  }
}




class MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final String chatKey;
  final bool isMe;
  final bool isRead;
  final bool isPending;
  final bool isQueued;
  // Image kosong karena di luar window auto-load (pesan lama) → tampilkan
  // icon refresh; klik memanggil onRetryImage(messageId).
  final bool isImageDeferred;
  final Future<void> Function(String messageId)? onRetryImage;
  // Video di luar window auto-load (pesan lama) → poster TIDAK diunduh/
  // generate otomatis; tampil placeholder + tap untuk memuat (pola sama
  // seperti isImageDeferred untuk foto).
  final bool autoVideoPoster;
  // Admin monitor: view-once yang sudah expired tetap bisa dilihat admin.
  final bool isAdminView;
  // Room chat pakai tabel 'messages' untuk clear view-once.
  final bool isRoom;
  // Long-press untuk buka menu (Balas / Edit / Hapus) seperti WhatsApp.
  // LayerLink dipakai agar action bar (icon) bisa di-anchor tepat di atas
  // bubble dan ikut mengikuti posisi bubble saat list di-scroll.
  final void Function(LongPressStartDetails, MessageModel, LayerLink)?
  onLongPressMenu;
  // Link anchor milik bubble ini (dibuat & dikelola oleh screen agar stabil
  // antar rebuild ListView — lihat _msgLinks di private_chat_screen).
  final LayerLink link;
  /// PRIVASI: id pesan (chat/room) yang terhapus — quote reply yang
  /// menunjuk salah satunya dirender "Pesan dihapus", bukan isinya.
  final Set<String> deletedIds;
  /// Geser bubble ke KANAN → langsung balas pesan ini (ala WhatsApp).
  /// Kosong = fitur swipe dimatikan (mis. monitor admin read-only).
  final VoidCallback? onSwipeReply;
  final bool selected;
  final Map<String, int>? reactions;
  final bool starred;
  final VoidCallback? onTapSelect;
  final VoidCallback? onTapBadge;
  /// Highlight `@all` — hanya private room/grup. Global room & private 1:1
  /// selalu false (token `@all` tampil sebagai teks biasa).
  final bool highlightMentionAll;
  // Kata kunci search chat — diteruskan ke teks bubble (kosong = mati).
  final String searchQuery;
  /// Admin monitor: tampilkan centang di KEDUA sisi (kiri & kanan), bukan
  /// hanya milik pengirim. Tujuannya admin melihat status baca kedua orang.
  final bool showChecksBothSides;
  const MessageBubble({
    super.key,
    required this.msg,
    required this.chatKey,
    required this.isMe,
    required this.isRead,
    this.isPending = false,
    this.isQueued = false,
    this.isImageDeferred = false,
    this.onRetryImage,
    this.autoVideoPoster = true,
    this.isAdminView = false,
    this.showChecksBothSides = false,
    this.isRoom = false,
    this.onLongPressMenu,
    this.onSwipeReply,
    required this.link,
    this.deletedIds = const {},
    this.selected = false,
    this.reactions,
    this.starred = false,
    this.onTapSelect,
    this.onTapBadge,
    this.highlightMentionAll = false,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final timeStr = formatBubbleTime(msg.timestamp);
    // Pesan yang dihapus (soft delete).
    // - Chat biasa: cukup teks redup "Pesan ini telah dihapus".
    // - Monitor admin: TETAP tampilkan ISI ASLI (teks/foto/video) + banner
    //   "Dihapus oleh pengirim" — supaya admin bisa memverifikasi laporan
    //   tanpa kehilangan bukti. RPC admin memang mengirim konten asli.
    if (msg.isDeleted && !isAdminView) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Text(
              s.messageDeleted,
              style: AppText.chatBodySmall.copyWith(
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
    return CompositedTransformTarget(
      link: link,
      // AppGestureDetector: tahan 600ms (longPressBubble) → toolbar seleksi/
      // reaksi. Lebih lama dari list (450ms) karena bubble sering kena jari
      // saat scroll → hindari toolbar muncul tak sengaja; tap tetap instan.
      child: AppGestureDetector(
        onLongPressStart: (d) => onLongPressMenu?.call(d, msg, link),
        onTap: onTapSelect,
        behavior: HitTestBehavior.opaque,
        longPressDuration: AppTiming.longPressBubble,
        child: SwipeToReply(
          enabled: onSwipeReply != null && onTapSelect == null,
          onReply: onSwipeReply,
          child: Padding(
          padding: EdgeInsets.only(bottom: reactions != null && reactions!.isNotEmpty ? 12 : 8),
          child: Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    // Bubble solid (tidak transparan) — tint primary di-blend ke bgCard.
                    // Bubble lawan (other) pakai bgCard (putih di light mode) + shadow
                    // halus supaya tetap kontras di atas wallpaper chat apa pun.
                    // Terpilih: tint primary 0.20 di atas warna dasar — senada
                    // kartu terpilih di list Pesan + toolbar seleksi.
                    color: Color.alphaBlend(
                      AppTheme.primary.withValues(
                        alpha: selected ? 0.20 : 0.0,
                      ),
                      msg.type == 'coin'
                          ? Color(0xFFFFF3C4)
                          : (isMe
                                ? Color.alphaBlend(
                                    AppTheme.primary.withValues(alpha: 0.25),
                                    AppTheme.bgCard,
                                  )
                                : AppTheme.bgCard),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 6,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                    border: selected
                        ? Border.all(color: AppTheme.primary, width: 2)
                        : null,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(10),
                      topRight: const Radius.circular(10),
                      bottomLeft: Radius.circular(isMe ? 10 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 10),
                    ),
                  ),
                  child: Column(
                    // Konten (teks + jam) center vertikal dalam bubble saat
                    // bubble lebih tinggi dari konten (mis. caption pendek di
                    // bawah foto). Horizontal tetap kiri/kanan seperti semula.
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (msg.isForwarded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.forward,
                                size: 14,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                s.msgForwardedLabel,
                                style: AppText.caption.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (starred)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Icon(
                            Icons.star,
                            size: 14,
                            color: const Color(0xFFFFB300),
                          ),
                        ),
                      if (msg.repliedToText != null &&
                          msg.repliedToText!.isNotEmpty)
                        ReplyQuote.fromMessage(
                          context: context,
                          repliedToText: msg.repliedToText,
                          repliedToId: msg.repliedToId,
                          repliedToSenderName: msg.repliedToSenderName,
                          isMe: isMe,
                          deletedIds: deletedIds,
                        )!,
                      // Monitor admin: pesan yang dihapus pengirim tetap
                      // menampilkan ISI ASLI, ditandai banner jelas supaya
                      // admin tahu itu sudah dihapus.
                      if (msg.isDeleted && isAdminView)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.danger.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 12,
                                  color: AppTheme.danger,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  s.adminDeletedMarker,
                                  style: AppText.micro.copyWith(
                                    color: AppTheme.danger,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (msg.type == 'voice' && msg.imageData.isNotEmpty)
                        VoiceBubble(
                          path: msg.imageData,
                          durationMs: msg.durationMs ?? 0,
                          isMe: isMe,
                          timeStr: timeStr,
                          isPending: isPending,
                          isQueued: isQueued,
                          isRead: isRead,
                        )
                      else if (msg.type == 'video_once_expired' &&
                          !isMe &&
                          !isAdminView)
                        // Video kadaluarsa sisi PENERIMA: kartu terkunci
                        // "Video sudah kadaluarsa". Jam OVERLAY di DALAM card
                        // (kanan 6 bawah 6) — SAMA seperti foto kadaluarsa
                        // (ViewOnce), bukan di bawah. Tidak ada badge durasi
                        // di card terkunci jadi tidak bertumpuk.
                        SizedBox(
                          width: ChatVideoBubble.bubbleWidth,
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ChatVideoBubble(
                              videoData: msg.imageData,
                              durationMs: msg.durationMs ?? 0,
                              // Terkunci untuk PENERIMA. Pengirim tetap boleh
                              // melihat videonya sendiri (pola sama foto).
                              // Admin monitor: tidak pernah terkunci.
                              locked: !isMe,
                              isOnce: true,
                              messageId: msg.id,
                              isMe: isMe,
                              isAdminView: isAdminView,
                              autoPoster: autoVideoPoster,
                              timeStr: timeStr,
                              showChecks: isMe || showChecksBothSides,
                              isPending: isPending,
                              isQueued: isQueued,
                              isRead: isRead,
                            ),
                            if (msg.text.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 4, 8, 0),
                                child: MentionAwareText(
                                  msg.text,
                                  style: AppText.chatBody.copyWith(
                                    color: AppTheme.textPrimary,
                                  ),
                                  mentions: msg.mentions,
                                ),
                              ),
                          ],
                          ),
                        )
                      else if (((msg.type == 'video' ||
                                  msg.type == 'video_once') &&
                              msg.imageData.isNotEmpty) ||
                          // Kadaluarsa sisi PENGIRIM/admin: videonya masih
                          // bisa diputar (data tidak dihapus) → jam di BAWAH
                          // seperti video biasa, bukan overlay.
                          msg.type == 'video_once_expired')
                        // Jam di BAWAH video dalam bubble (kanan) — TIDAK
                        // overlay supaya tidak bertumpuk dengan badge durasi
                        // di dalam video. Sama untuk pengirim & penerima.
                        // Lebar dikunci selebar video (ala LocationBubble).
                        SizedBox(
                          width: ChatVideoBubble.bubbleWidth,
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ChatVideoBubble(
                              videoData: msg.imageData,
                              durationMs: msg.durationMs ?? 0,
                              // Sekali lihat: sudah ditonton → terkunci.
                              locked: false,
                              isOnce: msg.type == 'video_once' ||
                                  msg.type == 'video_once_expired',
                              messageId: msg.id,
                              isMe: isMe,
                              isAdminView: isAdminView,
                              autoPoster: autoVideoPoster,
                            ),
                            // Caption + jam SEBARIS ala chat teks (nempel, hemat
                            // tinggi): caption pendek → jam nempel di ujung
                            // baris; caption panjang → jam di akhir baris
                            // terakhir. Tanpa caption → jam di bawah (rapat).
                            if (msg.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 4,
                                ),
                                child: MediaCaptionTime(
                                  text: msg.text,
                                  timeStr: timeStr,
                                  textStyle: AppText.chatBody.copyWith(
                                    color: AppTheme.textPrimary,
                                  ),
                                  timeStyle: AppText.chatTime.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  showChecks: isMe || showChecksBothSides,
                                  isPending: isPending,
                                  isQueued: isQueued,
                                  isRead: isRead,
                                  leftInset: 8,
                                ),
                              )
                            else
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 2, 0, 0),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        timeStr,
                                        style: AppText.chatTime.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      if (isMe || showChecksBothSides) ...[
                                        const SizedBox(width: 3),
                                        Icon(
                                          (isPending || isQueued)
                                              ? Icons.done
                                              : Icons.done_all,
                                          size: 12,
                                          color: (!isQueued &&
                                                  !isPending &&
                                                  isRead)
                                              ? AppTheme.primary
                                              : AppTheme.textSecondary,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                          ),
                        )
                      else if (msg.type == 'image' && msg.imageData.isNotEmpty)
                        _PhotoBubble(
                          msg: msg,
                          chatKey: chatKey,
                          timeStr: timeStr,
                          isMe: isMe,
                          isRead: isRead,
                          isPending: isPending,
                          isQueued: isQueued,
                          showChecksBothSides: showChecksBothSides,
                          highlightMentionAll: highlightMentionAll,
                        )
                      else if (msg.type == 'image' &&
                          msg.imageData.isEmpty &&
                          isImageDeferred)
                        DeferredImage(
                          onTap: () async => onRetryImage?.call(msg.id),
                        )
                      else if (msg.type == 'location' &&
                          parseLocation(msg.text) != null)
                        LocationBubble(
                          location: parseLocation(msg.text)!,
                          timeStr: timeStr,
                          showChecks: isMe || showChecksBothSides,
                          isPending: isPending,
                          isQueued: isQueued,
                          isRead: isRead,
                        )
                      else if (msg.type == 'view_once' ||
                          msg.type == 'view_once_expired')
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                ViewOnceImage(
                                  imageData: msg.imageData,
                                  chatKey: chatKey,
                                  isMe: isMe,
                                  messageId: msg.id,
                                  viewSecs: msg.durationMs,
                                  isExpired: msg.type == 'view_once_expired',
                                  isAdminView: isAdminView,
                                  isRoom: isRoom,
                                ),
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          timeStr,
                                          style: AppText.chatTime.copyWith(
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (isMe || showChecksBothSides) ...[
                                          const SizedBox(width: 3),
                                          Tooltip(
                                            message: isQueued
                                                ? s.msgWaitingConnection
                                                : '',
                                            child: Icon(
                                              (isPending || isQueued)
                                                  ? Icons.done
                                                  : Icons.done_all,
                                              size: 12,
                                              color: (isRead &&
                                                      !isPending &&
                                                      !isQueued)
                                                  ? const Color(0xFF7EC8FF)
                                                  : Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Caption foto sekali-lihat (dulu tersimpan di DB
                            // tapi TIDAK dirender → teks seolah hilang).
                            if (msg.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: MentionAwareText(
                                  msg.text,
                                  style: AppText.chatBody.copyWith(
                                    color: AppTheme.textPrimary,
                                  ),
                                  mentions: msg.mentions,
                                ),
                              ),
                          ],
                        )
                      else if (msg.type == 'coin')
                        Builder(
                          builder: (context) {
                            final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
                            final amount = int.tryParse(msg.text) ?? 0;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '🪙',
                                  style: TextStyle(fontSize: AppGlyph.sm),
                                ),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isMe
                                        ? s.coinBubbleSent(amount)
                                        : s.coinBubbleReceived(amount),
                                    style: AppText.chatBody.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB8860B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  timeStr,
                                  style: AppText.chatTime.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else if (msg.type == 'gift')
                        Builder(
                          builder: (context) {
                            final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
                            final g = giftById(msg.text);
                            final emoji = g?.emoji ?? '🎁';
                            final name = g == null
                                ? ''
                                : (s.isId ? g.nameId : g.nameEn);
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  emoji,
                                  style: TextStyle(fontSize: AppGlyph.md),
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    isMe
                                        ? s.giftBubbleSent(name)
                                        : s.giftBubbleReceived(name),
                                    style: AppText.chatBody.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB8860B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  timeStr,
                                  style: AppText.chatTime.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else if (msg.type == 'call')
                        Builder(
                          builder: (context) {
                            final isVideoCall = msg.text.contains('📹');
                            // Hapus emoji awal (📹/📞) dari teks karena ikon sudah
                            // ditampilkan terpisah — hindari ikon ganda. Pakai
                            // replace literal (bukan regex) supaya surrogate emoji
                            // tidak rusak jadi karakter '?'.
                            final displayText = msg.text
                                .replaceFirst('📹', '')
                                .replaceFirst('📞', '')
                                .trimLeft();
                            // Warna ikon mengikuti hasil panggilan (teks status
                            // disimpan berbahasa Inggris — stabil antar locale):
                            // hijau = panggilan terhubung, merah = gagal/tak dijawab.
                            const successMarkers = ['Call ended'];
                            const failMarkers = [
                              'Missed call',
                              'Call declined',
                              'Call canceled',
                              'Busy',
                              'Call failed',
                            ];
                            final callIconColor =
                                successMarkers.any(displayText.contains)
                                ? Colors.greenAccent
                                : failMarkers.any(displayText.contains)
                                ? Colors.redAccent
                                : AppTheme.textSecondary;
                            return RichText(
                              text: TextSpan(
                                style: AppText.chatBody.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                                children: [
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Icon(
                                      isVideoCall ? Icons.videocam : Icons.call,
                                      size: 16,
                                      color: callIconColor,
                                    ),
                                  ),
                                  const WidgetSpan(child: SizedBox(width: 6)),
                                  TextSpan(text: displayText),
                                  const TextSpan(text: '  '),
                                  WidgetSpan(
                                    alignment:
                                        PlaceholderAlignment.belowBaseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: Text(
                                      timeStr,
                                      style: AppText.chatTime.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      else
                        MessageTextWithTime(
                          text: msg.text,
                          timeStr: msg.edited
                              ? '$timeStr ${s.msgEdited}'
                              : timeStr,
                          textStyle: AppText.chatBody,
                          timeStyle: AppText.chatTime.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                          alignRight: isMe,
                          mentions: msg.mentions,
                          highlightMentionAll: highlightMentionAll,
                          searchQuery: searchQuery,
                          trailing: isMe
                              ? Tooltip(
                                  message:
                                      isQueued ? s.msgWaitingConnection : '',
                                  child: Icon(
                                    (isPending || isQueued)
                                        ? Icons.done
                                        : Icons.done_all,
                                    size: 12,
                                    color: (!isQueued &&
                                            !isPending &&
                                            isRead)
                                        ? AppTheme.primary
                                        : AppTheme.textSecondary,
                                  ),
                                )
                              : null,
                        ),
                    ],
                  ),
                    ),
                      if (reactions != null && reactions!.isNotEmpty)
                      Positioned(
                        bottom: -10,
                        left: isMe ? null : 8,
                        right: isMe ? 8 : null,
                        child: _InlineReactionBadge(
                          counts: reactions!,
                          onTap: onTapBadge,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _InlineReactionBadge extends StatelessWidget {
  final Map<String, int> counts;
  final VoidCallback? onTap;
  const _InlineReactionBadge({required this.counts, this.onTap});
  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = entries.take(3).map((e) => e.key).join();
    final total = entries.fold<int>(0, (p, e) => p + e.value);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(shown, style: TextStyle(fontSize: AppGlyph.xs)),
          if (total > 1) ...[
            const SizedBox(width: 3),
            Text(
              '$total',
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
      ),
    );
  }
}





/// Bubble FOTO private chat.
///
/// - Tanpa caption: jam di-overlay di sudut kanan-bawah gambar (seperti
///   sebelumnya).
/// - Ada caption: jam **tidak** overlay; caption di bawah + jam rata kanan
///   sejajar tepi kanan foto (lebar render foto dilaporkan oleh MessageImage)
///   — aturan jarak caption↔jam SAMA seperti bubble teks.
class _PhotoBubble extends StatefulWidget {
  final MessageModel msg;
  final String chatKey;
  final String timeStr;
  final bool isMe;
  final bool isRead;
  final bool isPending;
  final bool isQueued;
  final bool showChecksBothSides;
  final bool highlightMentionAll;

  const _PhotoBubble({
    required this.msg,
    required this.chatKey,
    required this.timeStr,
    required this.isMe,
    required this.isRead,
    required this.isPending,
    required this.isQueued,
    required this.showChecksBothSides,
    required this.highlightMentionAll,
  });

  @override
  State<_PhotoBubble> createState() => _PhotoBubbleState();
}

class _PhotoBubbleState extends State<_PhotoBubble> {
  // Lebar render foto (dilaporkan MessageImage); 200 = default sebelum tahu.
  double _imgW = 200;

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final isMe = widget.isMe;
    final showChecks = isMe || widget.showChecksBothSides;
    final hasCaption = msg.text.isNotEmpty;
    final hasLink =
        hasCaption && LinkPreviewService.instance.extractUrl(msg.text) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              MessageImage(
                imageData: msg.imageData,
                chatKey: widget.chatKey,
                messageId: msg.id,
                onRenderedWidth: (w) {
                  if (mounted && (w - _imgW).abs() > 0.5) {
                    setState(() => _imgW = w);
                  }
                },
              ),
              // Overlay jam HANYA bila tanpa caption (ada caption → jam di
              // bawah, rata kanan sejajar tepi foto).
              if (!hasCaption)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.timeStr,
                          style: AppText.chatTime.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        if (showChecks) ...[
                          const SizedBox(width: 3),
                          Icon(
                            (widget.isPending || widget.isQueued)
                                ? Icons.done
                                : Icons.done_all,
                            size: 12,
                            color: (widget.isRead &&
                                    !widget.isPending &&
                                    !widget.isQueued)
                                ? const Color(0xFF7EC8FF)
                                : Colors.white70,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasLink)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: _imgW,
              child: LinkPreview(text: msg.text),
            ),
          ),
        if (hasCaption)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: SizedBox(
              width: _imgW,
              child: MediaCaptionTime(
                text: msg.text,
                timeStr: widget.timeStr,
                textStyle: AppText.chatBody.copyWith(
                  color: AppTheme.textPrimary,
                ),
                timeStyle: AppText.chatTime.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
                showChecks: showChecks,
                isPending: widget.isPending,
                isQueued: widget.isQueued,
                isRead: widget.isRead,
                leftInset: 8,
              ),
            ),
          ),
      ],
    );
  }
}
