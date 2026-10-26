import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/cache/photo_aspect_cache.dart';
import '../core/chat/chat_location.dart';
import '../core/chat/reply_meta.dart';
import '../models/message_model.dart';

/// Kartu preview "membalas" di atas kolom ketik (private + room), ala
/// WhatsApp: kartu solid berpinggir bulat dengan garis aksen kiri, nama
/// pengirim, ringkasan pesan (ikon + label untuk foto/video/lokasi) dan
/// tombol tutup. Warna solid [AppTheme.bgCard] agar tidak menyatu dengan
/// wallpaper chat.
///
/// Untuk FOTO/VIDEO, thumbnail kecil ikut ditampilkan di kanan — sama
/// dengan kutipan di dalam bubble (`ReplyQuote`).
class ReplyComposerPreview extends StatefulWidget {
  final MessageModel message;
  final String senderLabel;
  final S s;
  final VoidCallback onCancel;

  /// Chat key cache lokal (`private_<chatId>` / `room_<id>`) untuk thumbnail
  /// foto. Kosong = tanpa thumbnail foto.
  final String cacheChatKey;

  const ReplyComposerPreview({
    super.key,
    required this.message,
    required this.senderLabel,
    required this.s,
    required this.onCancel,
    this.cacheChatKey = '',
  });

  @override
  State<ReplyComposerPreview> createState() => _ReplyComposerPreviewState();
}

class _ReplyComposerPreviewState extends State<ReplyComposerPreview> {
  ui.Image? _thumb;

  ReplyMediaKind get _kind => replyMediaKindOfType(widget.message.type);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReplyComposerPreview old) {
    super.didUpdateWidget(old);
    if (old.message.id != widget.message.id) {
      _thumb = null;
      _load();
    }
  }

  void _load() {
    final m = widget.message;
    if (m.text.trim().isNotEmpty) return; // caption dipakai sebagai ringkasan
    if (_kind == ReplyMediaKind.video) {
      final sync = replyVideoThumbSync(m.imageData);
      if (sync != null) {
        _thumb = sync;
        return;
      }
      loadReplyVideoThumb(m.imageData).then((img) {
        if (mounted && img != null) setState(() => _thumb = img);
      });
      return;
    }
    if (_kind == ReplyMediaKind.photo && widget.cacheChatKey.isNotEmpty) {
      loadReplyPhotoThumb(
        chatKey: widget.cacheChatKey,
        messageId: m.id,
      ).then((img) {
        if (mounted && img != null) setState(() => _thumb = img);
      });
    }
  }

  ({IconData? icon, String text}) _summary() {
    final m = widget.message;
    final s = widget.s;
    final t = m.text.trim();
    final kind = _kind;
    // Lokasi: JSON mentah → label ramah.
    if (isLocationPayload(t)) {
      return (icon: Icons.location_on_outlined, text: s.msgLocation);
    }
    if (t.isNotEmpty) {
      return (
        icon: replyMediaIcon(kind),
        text: kind == ReplyMediaKind.location
            ? locationPreviewLabel(t, s.msgLocation)
            : t,
      );
    }
    return (
      icon: replyMediaIcon(kind),
      text: replyMediaFallbackLabel(kind, s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sum = _summary();
    final kind = _kind;
    final photoAspect = widget.message.id.isEmpty
        ? 0.0
        : (PhotoAspectCache.instance.aspectOf(widget.message.id) ?? 0.0);
    final thumbAspect = photoAspect > 0 ? photoAspect : 1.0;
    final thumbH = 34.0;
    final thumbW = (thumbH * thumbAspect).clamp(24.0, 48.0);
    final showThumb = replyQuoteHasThumb(kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: AppTheme.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.senderLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.chatCaption.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          if (sum.icon != null) ...[
                            Icon(
                              sum.icon,
                              size: 14,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              sum.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.chatBodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (showThumb)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: ClipRRect(
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
                          : ColoredBox(
                              color: AppTheme.bgScreen.withValues(alpha: 0.7),
                              child: Icon(
                                kind == ReplyMediaKind.video
                                    ? Icons.play_arrow_rounded
                                    : Icons.image_outlined,
                                size: 16,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                onPressed: widget.onCancel,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper kecil: jenis yang punya thumbnail (foto/video) — foto dicek via
/// [replyMediaKindOfType] karena enum tidak punya nilai `image`.
bool replyQuoteHasThumb(ReplyMediaKind k) =>
    k == ReplyMediaKind.photo || k == ReplyMediaKind.video;
