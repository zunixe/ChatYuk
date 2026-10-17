import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../core/media/chat_photo_helper.dart';
import '../models/message_model.dart';
import 'message/message_image.dart';

/// Bubble ALBUM foto (bundle multi-foto ala WhatsApp).
///
/// Tata letak:
///  - 2 foto  → 2 kotak berdampingan.
///  - 3 foto  → 1 besar di kiri + 2 kecil bertumpuk di kanan.
///  - 4+ foto → grid 2×2 dengan overlay "+N" pada kotak terakhir.
///  Semua tata letak = kotak persegi ±72% lebar layar, foto di-crop (cover).
///
/// Jam + centang muncul SEKALI di pojok kanan bawah (dari foto terakhir).
/// Caption (bila ada di foto terakhir) tampil di bawah grid.
class PhotoAlbumBubble extends StatelessWidget {
  /// Foto-foto album, urut kronologis (minimal 2).
  final List<MessageModel> photos;

  /// chatKey untuk cache foto (`private_<chatId>` / `room_<id>`).
  final String chatKey;
  final double tileSize;
  final String timeStr;
  final bool showChecks;
  final bool isPending;
  final bool isQueued;
  final bool isRead;
  /// Pengirim = saya → sudut ekor bubble di kanan bawah (kiri bila lawan).
  final bool isMe;
  /// Warna card latar (sama bubble 1 foto). null = tanpa card.
  final Color? cardColor;

  const PhotoAlbumBubble({
    super.key,
    required this.photos,
    required this.chatKey,
    required this.timeStr,
    this.tileSize = 0, // 0 = otomatis 72% lebar layar
    this.showChecks = false,
    this.isPending = false,
    this.isQueued = false,
    this.isRead = false,
    this.isMe = false,
    this.cardColor,
  });

  static const int _maxTiles = 4;

  int get _hidden => photos.length > _maxTiles ? photos.length - _maxTiles : 0;

  @override
  Widget build(BuildContext context) {
    final caption = photos.last.text.trim();
    // Ala WhatsApp: grid persegi ±72% lebar layar (bila tileSize tidak
    // dipaksa pemanggil). Semua tata letak (2/3/4+) memakai kotak W×W.
    final screenW = MediaQuery.sizeOf(context).width;
    final side = tileSize > 0 ? tileSize : chatMediaWidth(screenW);
    final album = SizedBox(
      width: side,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(
                children: [
                  Positioned.fill(child: _grid(context)),
                  // Jam + centang sekali untuk seluruh album.
                  Positioned(right: 6, bottom: 6, child: _timePill()),
                ],
              ),
            ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2, right: 2),
              child: Text(
                caption,
                style: AppText.chatBody.copyWith(color: AppTheme.textPrimary),
              ),
            ),
        ],
      ),
    );
    final bg = cardColor;
    if (bg == null) return album;
    // Card latar ala bubble 1 foto (WhatsApp: bingkai tipis warna bubble).
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(12),
          topRight: const Radius.circular(12),
          bottomLeft: Radius.circular(isMe ? 12 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: album,
    );
  }

  static const double _gap = 3;

  /// Satu kotak foto — isi penuh (cover) seperti WhatsApp.
  /// MessageImage menangani base64 pending MAUPUN path storage (unduh lazy
  /// + cache disk/mem + retry) dan tap → viewer fullscreen.
  Widget _tile(int i) {
    final m = photos[i];
    final isLast = i == _maxTiles - 1;
    return Stack(
      fit: StackFit.expand,
      children: [
        MessageImage(
          imageData: m.imageData,
          chatKey: chatKey,
          messageId: m.id,
          fill: true,
        ),
        if (isLast && _hidden > 0)
          IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.52),
              child: Center(
                child: Text(
                  '+$_hidden',
                  style: AppText.display.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(List<Widget> c) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: c[0]),
      const SizedBox(width: _gap),
      Expanded(child: c[1]),
    ],
  );

  Widget _col(List<Widget> c) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: c[0]),
      const SizedBox(height: _gap),
      Expanded(child: c[1]),
    ],
  );

  Widget _grid(BuildContext context) {
    // 2 foto: dua kotak tegak berdampingan.
    if (photos.length == 2) return _row([_tile(0), _tile(1)]);
    // 3 foto: 1 besar di kiri + 2 bertumpuk di kanan.
    if (photos.length == 3) {
      return _row([
        _tile(0),
        _col([_tile(1), _tile(2)]),
      ]);
    }
    // 4+ foto: grid 2×2, kotak ke-4 diberi overlay "+N".
    return _col([
      _row([_tile(0), _tile(1)]),
      _row([_tile(2), _tile(3)]),
    ]);
  }

  Widget _timePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(timeStr, style: AppText.chatTime.copyWith(color: Colors.white)),
          if (showChecks) ...[
            const SizedBox(width: 3),
            Icon(
              (isPending || isQueued) ? Icons.done : Icons.done_all,
              size: 12,
              color: (isRead && !isPending && !isQueued)
                  ? AppTheme.primary
                  : Colors.white70,
            ),
          ],
        ],
      ),
    );
  }
}
