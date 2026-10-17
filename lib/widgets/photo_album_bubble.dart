import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/message_model.dart';
import 'message/photo_viewer_screen.dart';

/// Bubble ALBUM foto (bundle multi-foto ala WhatsApp).
///
/// Tata letak:
///  - 2 foto  → 2 kotak berdampingan.
///  - 3 foto  → 1 besar di kiri + 2 kecil bertumpuk di kanan.
///  - 4+ foto → grid 2×2 dengan overlay "+N" pada kotak terakhir.
///
/// Jam + centang muncul SEKALI di pojok kanan bawah (dari foto terakhir).
/// Caption (bila ada di foto terakhir) tampil di bawah grid.
class PhotoAlbumBubble extends StatelessWidget {
  /// Foto-foto album, urut kronologis (minimal 2).
  final List<MessageModel> photos;
  final double tileSize;
  final String timeStr;
  final bool showChecks;
  final bool isPending;
  final bool isQueued;
  final bool isRead;

  const PhotoAlbumBubble({
    super.key,
    required this.photos,
    required this.timeStr,
    this.tileSize = 108,
    this.showChecks = false,
    this.isPending = false,
    this.isQueued = false,
    this.isRead = false,
  });

  static const int _maxTiles = 4;

  int get _hidden => photos.length > _maxTiles ? photos.length - _maxTiles : 0;

  @override
  Widget build(BuildContext context) {
    final caption = photos.last.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: _gridWidth,
            height: _gridHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _grid(context),
                // Jam + centang sekali untuk seluruh album.
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: _timePill(),
                ),
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
    );
  }

  double get _gap => 2;
  double get _half => (tileSize - _gap) / 2;

  double get _gridWidth => photos.length == 2 ? tileSize * 2 + _gap : tileSize;
  double get _gridHeight =>
      photos.length == 2 ? tileSize : tileSize;

  /// Satu kotak foto (thumbnail bytes) yang bisa diketuk.
  Widget _tile(BuildContext context, MessageModel m, double w, double h) {
    final bytes = _bytesOf(m);
    return GestureDetector(
      onTap: () => _openViewer(context, m),
      child: SizedBox(
        width: w,
        height: h,
        child: bytes == null
            ? ColoredBox(color: AppTheme.bgInput)
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) =>
                    ColoredBox(color: AppTheme.bgInput),
              ),
      ),
    );
  }

  Uint8List? _bytesOf(MessageModel m) {
    final d = m.imageData;
    if (d.isEmpty) return null;
    try {
      return base64Decode(d);
    } catch (_) {
      return null;
    }
  }

  void _openViewer(BuildContext context, MessageModel m) {
    final bytes = _bytesOf(m);
    if (bytes == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PhotoViewerScreen(bytes: bytes)),
    );
  }

  Widget _grid(BuildContext context) {
    // 2 foto: berdampingan penuh.
    if (photos.length == 2) {
      return Row(
        children: [
          _tile(context, photos[0], _half, tileSize),
          SizedBox(width: _gap),
          _tile(context, photos[1], _half, tileSize),
        ],
      );
    }

    final shown = photos.take(_maxTiles).toList();
    final lastIndex = shown.length - 1;

    Widget cell(int i, double w, double h) {
      final isLast = i == lastIndex;
      return Stack(
        fit: StackFit.expand,
        children: [
          _tile(context, shown[i], w, h),
          if (isLast && _hidden > 0)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _openViewer(context, shown[i]),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.52),
                  child: Center(
                    child: Text(
                      '+$_hidden',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            SizedBox(width: _half, height: _half, child: cell(0, _half, _half)),
            SizedBox(width: _gap),
            SizedBox(
              width: _half,
              height: _half,
              child: cell(1, _half, _half),
            ),
          ],
        ),
        SizedBox(height: _gap),
        Row(
          children: [
            SizedBox(
              width: _half,
              height: _half,
              child: shown.length > 2
                  ? cell(2, _half, _half)
                  : const SizedBox.shrink(),
            ),
            SizedBox(width: _gap),
            SizedBox(
              width: _half,
              height: _half,
              child: shown.length > 3
                  ? cell(3, _half, _half)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
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
          Text(
            timeStr,
            style: AppText.chatTime.copyWith(color: Colors.white),
          ),
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
