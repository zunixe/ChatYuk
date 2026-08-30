import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Tombol mic rekam voice: membesar saat long-press (WhatsApp style).
/// Long press → scale 1.0 → 1.5 + merah + icon stop.
/// Saat merekam: pulse kecil. Lepas → shrink balik ke 1.0.
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
  late final AnimationController _growCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _growCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      lowerBound: 0,
      upperBound: 1,
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void didUpdateWidget(covariant MicRecordButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !old.isRecording) {
      _growCtrl.forward();
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.isRecording && old.isRecording) {
      _growCtrl.reverse();
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _growCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isRecording ? Colors.red : AppTheme.primary;

    return SizedBox(
      width: widget.size * 1.6,
      height: widget.size * 1.6,
      child: AnimatedBuilder(
        animation: Listenable.merge([_growCtrl, _pulseCtrl]),
        builder: (context, child) {
          final grow = 1.0 + _growCtrl.value * 0.5;
          final pulse = widget.isRecording
              ? 1.0 + _pulseCtrl.value * 0.08
              : 1.0;
          return Transform.scale(
            scale: grow * pulse,
            child: child,
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isRecording ? widget.onTap : null,
          onLongPressStart:
              widget.isRecording ? null : (_) => widget.onLongPressStart(),
          onLongPressCancel: widget.onLongPressCancel,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: widget.isRecording ? 2 : 0,
                ),
              ],
            ),
            child: Icon(
              widget.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
              color: Colors.white,
              size: widget.size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
