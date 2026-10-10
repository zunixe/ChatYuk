import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Geser bubble ke KANAN untuk balas (ala WhatsApp).
/// - `enabled=false` → widget ini transparan (child dikembalikan apa adanya).
/// - Tarik 0–72 px: bubble ikut bergeser, ikon reply muncul & menguat.
/// - Lepas ≥48 px → `onReply()` (composer masuk mode balas + fokus).
/// - Lepas < 48 px → kembali ke posisi semula (spring balik).
/// Menggunakan `onHorizontalDrag*` (bukan `Dismissible`) supaya bubble
/// tidak ikut terhapus/tergeser permanen dan bisa dipakai bersama
/// long-press + tap biasa.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback? onReply;
  const SwipeToReply({
    required this.child,
    required this.enabled,
    this.onReply,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  /// Jarak geser maksimum — cukup terasa tapi tidak menutupi bubble.
  static const double _maxDrag = 72;
  /// Ambang lepas untuk memicu balas.
  static const double _trigger = 48;

  double _drag = 0;

  void _onUpdate(DragUpdateDetails d) {
    // Hanya ke kanan; ke kiri diabaikan (tidak ada aksi).
    final next = (_drag + d.delta.dx).clamp(0.0, _maxDrag);
    if (next != _drag) setState(() => _drag = next);
  }

  void _onEnd(DragEndDetails d) {
    final shouldReply = _drag >= _trigger;
    // Ambang 48 px tercapai → picu balas; selain itu kembali ke 0.
    setState(() => _drag = 0);
    if (shouldReply) widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final t = (_drag / _maxDrag).clamp(0.0, 1.0);
    return GestureDetector(
      // Horizontal drag dipakai HANYA untuk swipe-reply; scroll vertikal
      // list tetap menang karena gesture arena memisahkan arah.
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => setState(() => _drag = 0),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Ikon reply di kiri, muncul seiring tarikan.
          Positioned(
            left: 8,
            top: 0,
            bottom: 8,
            child: Center(
              child: Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: 0.7 + 0.3 * t,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.reply,
                      size: 16,
                      color: AppTheme.primary.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bubble bergeser mengikuti tarikan.
          Transform.translate(
            offset: Offset(_drag, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

