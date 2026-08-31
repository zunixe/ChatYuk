import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Tombol mic WA-style: sentuh → LANGSUNG membesar (tanpa jeda long-press);
/// lepas tanpa geser → kirim; geser kiri sampai ambang → batal.
class MicRecordButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressCancel;
  final double size;
  const MicRecordButton({
    super.key,
    required this.isRecording,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressCancel,
    this.size = 40,
  });

  @override
  State<MicRecordButton> createState() => _MicRecordButtonState();
}

class _MicRecordButtonState extends State<MicRecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final CurvedAnimation _grow;
  double _dragOffset = 0;
  bool _fingerDown = false;
  Offset? _pointerOrigin;

  // Geser cukup jauh ke kiri → batal; lepas tanpa geser → kirim.
  static const double _cancelThreshold = -120;
  static const double _maxDrag = -200;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: widget.isRecording ? 1.0 : 0.0,
    );
    _grow = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeOutBack,
    );
  }

  @override
  void didUpdateWidget(covariant MicRecordButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !old.isRecording) {
      if (_fingerDown) _animCtrl.forward();
    } else if (!widget.isRecording && old.isRecording) {
      _animCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  bool get _isCancelZone => _dragOffset <= _cancelThreshold;

  // Listener pointer mentah — tidak pakai LongPress (delay ~500ms).
  void _onPointerDown(PointerDownEvent event) {
    _pointerOrigin = event.position;
    _fingerDown = true;
    _animCtrl.forward();
    if (!widget.isRecording) {
      widget.onLongPressStart();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final origin = _pointerOrigin;
    if (origin == null) return;
    setState(() {
      _dragOffset = (event.position.dx - origin.dx).clamp(_maxDrag, 0.0);
    });
  }

  void _onPointerUp(PointerUpEvent _) {
    final origin = _pointerOrigin;
    if (origin == null) return;
    _pointerOrigin = null;
    _fingerDown = false;
    // WhatsApp-style: lepas tanpa geser = kirim; geser ke kiri = batal.
    // Kalau recording belum mulai (race sentuh-lepas cepat), anggap batal.
    final shouldCancel = _isCancelZone || !widget.isRecording;
    _animCtrl.reverse();
    setState(() => _dragOffset = 0);
    if (shouldCancel) {
      widget.onLongPressCancel();
    } else {
      widget.onTap();
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    if (_pointerOrigin == null) return;
    _pointerOrigin = null;
    _fingerDown = false;
    _animCtrl.reverse();
    setState(() => _dragOffset = 0);
    widget.onLongPressCancel();
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.isRecording;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, _) {
          final progress = _grow.value;
          // Slot layout tetap (widget.size); visual circle melebihi batas
          // via OverflowBox — benar-benar bulat & bebas clip.
          final diameter = widget.size + progress * widget.size * 0.8;
          final color = _isCancelZone
              ? Colors.red
              : isRecording
                  ? Colors.red
                  : AppTheme.primary;
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              alignment: Alignment.center,
              child: Transform.translate(
                offset: Offset(_dragOffset, 0),
                child: Container(
                  width: diameter,
                  height: diameter,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 10 + progress * 10,
                        spreadRadius: progress * 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isCancelZone
                        ? Icons.close_rounded
                        : isRecording
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                    color: Colors.white,
                    size: diameter * 0.5,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
