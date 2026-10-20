import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;

import '../config/theme.dart';

import '../core/chat/chat_location.dart';
import '../core/chat/reply_meta.dart';
import '../providers/riverpod/locale_provider.dart';

/// Kutipan balasan (reply quote) di dalam bubble chat — dipakai bersama oleh
/// bubble private (`private_chat_message.dart`), bubble room
/// (`room_chat_screen.dart`), dan pratinjau composer
/// (`reply_composer_preview.dart`).
///
/// Bentuk mengikuti WhatsApp: garis aksen kiri + nama pengirim + ringkasan
/// (ikon jenis + teks), dan **thumbnail kecil di sisi KANAN** bila pesan yang
/// dibalas berupa FOTO/VIDEO. Untuk lokasi, ikon pin biasa diletakkan di kiri
/// seperti teks.
///
/// PRIVASI: bila pesan yang dibalas sudah dihapus (`targetDeleted`), teks
/// ditampilkan miring sebagai "Pesan dihapus" dan thumbnail TIDAK dirender —
/// jangan hapus guard ini.
class ReplyQuote extends StatefulWidget {
  final String? senderName;
  final String text;
  final bool isMe;
  final bool targetDeleted;

  /// Warna nama pengirim. Null → warna default tema (`AppText.chatName`).
  final Color? senderColor;

  /// Jenis media pesan yang dibalas (menentukan ikon + label + thumbnail).
  final ReplyMediaKind kind;

  /// Chat key cache lokal (`private_<chatId>` / `room_<id>`) untuk thumbnail
  /// foto. Kosong = tanpa thumbnail foto.
  final String cacheChatKey;

  /// Id pesan asli (kunci cache thumbnail foto).
  final String? messageId;

  /// Path video asli (kunci poster/thumbnail video).
  final String videoPath;

  /// Rasio (w/h) media yang dibalas; <=0 = pakai rasio default.
  final double aspect;

  const ReplyQuote({
    super.key,
    required this.senderName,
    required this.text,
    required this.isMe,
    required this.targetDeleted,
    this.senderColor,
    this.kind = ReplyMediaKind.text,
    this.cacheChatKey = '',
    this.messageId,
    this.videoPath = '',
    this.aspect = 0,
  });

  /// Helper: bangun dari data pesan + daftar id terhapus. Mengembalikan
  /// null bila tidak ada isi balasan (pemanggil tetap memutuskan layout).
  ///
  /// [meta] = payload `replied_to_meta` (lihat [replyQuoteData]).
  static ReplyQuote? fromMessage({
    required BuildContext context,
    required String? repliedToText,
    required String? repliedToId,
    required String? repliedToSenderName,
    required bool isMe,
    required Set<String> deletedIds,
    Color? senderColor,
    Map<String, dynamic>? meta,
  }) {
    final data = replyQuoteData(
      repliedToText: repliedToText,
      repliedToId: repliedToId,
      repliedToSenderName: repliedToSenderName,
      meta: meta,
    );
    if (data == null) return null;
    return ReplyQuote(
      senderName: data.senderName,
      text: data.text,
      isMe: isMe,
      targetDeleted: repliedToId != null && deletedIds.contains(repliedToId),
      senderColor: senderColor,
      kind: data.kind,
      cacheChatKey: data.cacheChatKey,
      messageId: data.messageId,
      videoPath: data.videoPath,
      aspect: data.aspect,
    );
  }

  /// Media yang di WhatsApp tampil dengan THUMBNAIL di kanan kutipan.
  static bool hasThumbKind(ReplyMediaKind k) =>
      k == ReplyMediaKind.photo || k == ReplyMediaKind.video;

  @override
  State<ReplyQuote> createState() => _ReplyQuoteState();
}

class _ReplyQuoteState extends State<ReplyQuote> {
  ui.Image? _thumb;
  bool _thumbTried = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(ReplyQuote old) {
    super.didUpdateWidget(old);
    if (old.messageId != widget.messageId ||
        old.videoPath != widget.videoPath ||
        old.cacheChatKey != widget.cacheChatKey ||
        old.kind != widget.kind ||
        old.targetDeleted != widget.targetDeleted) {
      _thumb = null;
      _thumbTried = false;
      _loadThumb();
    }
  }

  /// Thumbnail hanya untuk foto/video yang BELUM terhapus. Tidak pernah
  /// mengunduh: murni cache lokal (murah, aman offline).
  void _loadThumb() {
    if (widget.targetDeleted) return;
    if (!ReplyQuote.hasThumbKind(widget.kind)) return;
    if (widget.kind == ReplyMediaKind.video) {
      final sync = replyVideoThumbSync(widget.videoPath);
      if (sync != null) {
        _thumb = sync;
        _thumbTried = true;
        return;
      }
      loadReplyVideoThumb(widget.videoPath).then((img) {
        if (!mounted || img == null) return;
        setState(() {
          _thumb = img;
          _thumbTried = true;
        });
      });
      _thumbTried = true;
      return;
    }
    // FOTO
    loadReplyPhotoThumb(
      chatKey: widget.cacheChatKey,
      messageId: widget.messageId ?? '',
    ).then((img) {
      if (!mounted) return;
      setState(() {
        _thumb = img;
        _thumbTried = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final senderColor = widget.senderColor;
    final nameStyle = senderColor == null
        ? AppText.chatName
        : AppText.chatName.copyWith(color: senderColor);
    // Kutipan lokasi: JSON koordinat mentah → label ramah ("📍 Lokasi").
    final raw = widget.text;
    final kind = widget.kind;
    final label = widget.targetDeleted
        ? s.messageDeleted
        : (raw.isNotEmpty
              ? (isLocationPayload(raw)
                    ? '📍 ${s.msgLocation}'
                    : (kind == ReplyMediaKind.location
                          ? '📍 ${locationPreviewLabel(raw, s.msgLocation)}'
                          : raw))
              : replyMediaFallbackLabel(kind, s));
    final icon = replyMediaIcon(kind);
    final showThumb = !widget.targetDeleted &&
        ReplyQuote.hasThumbKind(kind) &&
        (_thumb != null || !_thumbTried || kind == ReplyMediaKind.photo);
    final thumbAspect = widget.aspect > 0 ? widget.aspect : 1.0;
    // Kotak thumbnail kotak ~40dp sisi pendek (ala WhatsApp).
    final thumbH = 40.0;
    final thumbW = (thumbH * thumbAspect).clamp(28.0, 56.0);

    return Padding(
      // Jarak dari tepi bubble dipasang sebagai Padding (BUKAN `margin` pada
      // Container ber-border: margin + border di Container membuat dekorasi
      // diletakkan di tepi luar margin, sehingga jaraknya tidak terlihat).
      // Terukur di HP (density 3) sebelum fix: garis aksen mulai x≈19px
      // sementara tepi bubble x≈18px → ~0.3-1dp = MENEMPEL (minta user).
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.15)
              : AppTheme.bgScreen.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.senderName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 13, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.chatBodySmall.copyWith(
                            fontStyle: widget.targetDeleted
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (showThumb) ...[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: thumbW,
                  height: thumbH,
                  child: _thumb != null
                      ? RawImage(
                          image: _thumb,
                          width: thumbW,
                          height: thumbH,
                          fit: BoxFit.cover,
                        )
                      : _ThumbPlaceholder(kind: kind),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder thumbnail saat poster/thumb belum siap (kotak abu + ikon).
class _ThumbPlaceholder extends StatelessWidget {
  final ReplyMediaKind kind;
  const _ThumbPlaceholder({required this.kind});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bgScreen.withValues(alpha: 0.7),
      alignment: Alignment.center,
      child: Icon(
        kind == ReplyMediaKind.video
            ? Icons.play_arrow_rounded
            : Icons.image_outlined,
        size: 18,
        color: AppTheme.textSecondary,
      ),
    );
  }
}
