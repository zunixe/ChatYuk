import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Tombol mic rekam voice: lingkaran kecil (40), pulse saat merekam.
/// Hold (long press) untuk mulai rekam; saat merekam, tap = stop & kirim.
class MicRecordButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onTap; // saat merekam = stop & kirim
  final VoidCallback onLongPressStart; // mulai rekam
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

class _MicRecordButtonState extends State<MicRecordButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  }

  @override
  void didUpdateWidget(covariant MicRecordButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording != old.isRecording) {
      if (widget.isRecording) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 1.18).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isRecording ? widget.onTap : null,
          onLongPressStart: widget.isRecording ? null : (_) => widget.onLongPressStart(),
          onLongPressCancel: widget.onLongPressCancel,
          child: Container(
            decoration: BoxDecoration(
              color: widget.isRecording ? Colors.red : AppTheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (widget.isRecording ? Colors.red : AppTheme.primary).withValues(alpha: 0.4),
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
