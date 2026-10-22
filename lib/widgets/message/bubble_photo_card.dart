part of '../private_chat_message.dart';

// Kartu FOTO pada bubble private chat (dipisah dari private_chat_message.dart
// agar file utama < 1000 baris). Perilaku tidak berubah — hanya pemindahan.

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
  final bool autoLinkPreview;

  /// Sembunyikan caption di bawah foto karena sudah dirender di PANEL KANAN
  /// (bubble foto berbalasan, ala WhatsApp). Jam ikut disembunyikan (panel
  /// punya jamnya sendiri).
  final bool suppressCaption;

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
    this.autoLinkPreview = true,
    this.suppressCaption = false,
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
    // Caption/link/jam DISEMBUNYIKAN bila pemanggil menaruhnya di panel
    // kanan (media berbalasan) — hanya kartu foto yang dirender di sini.
    final hasCaption = msg.text.isNotEmpty && !widget.suppressCaption;
    final hasLink = !widget.suppressCaption &&
        msg.text.isNotEmpty &&
        LinkPreviewService.instance.extractUrl(msg.text) != null;
    final hideOverlayTime = widget.suppressCaption;

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
              if (!hasCaption && !hideOverlayTime)
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
              child: LinkPreview(
                text: msg.text,
                enabled: widget.autoLinkPreview,
              ),
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
