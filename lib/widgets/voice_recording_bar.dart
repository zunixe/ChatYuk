import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Bar rekam voice: timer + "slide to cancel" + mic icon draggable.
/// Slide mic ke kiri → cancel. Lepas tanpa slide → kirim.
class VoiceRecordingBar extends StatefulWidget {
  final int elapsedSeconds;
  final VoidCallback onRelease;
  final VoidCallback onCancel;
  final String slideToCancelText;

  const VoiceRecordingBar({
    super.key,
    required this.elapsedSeconds,
    required this.onRelease,
    required this.onCancel,
    required this.slideToCancelText,
  });

  @override
  State<VoiceRecordingBar> createState() => _VoiceRecordingBarState();
}

class _VoiceRecordingBarState extends State<VoiceRecordingBar>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _isCancelled = false;
  late final AnimationController _pulseCtrl;

  static const double _cancelThreshold = -80;
  static const double _maxDrag = -160;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  String get _timerText {
    final m = widget.elapsedSeconds ~/ 60;
    final s = widget.elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _cancelProgress {
    if (_dragOffset > 0) return 0;
    return (_dragOffset / _cancelThreshold).clamp(0.0, 1.0);
  }

  void _onPanStart(DragStartDetails _) {}

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(_maxDrag, 0.0);
      _isCancelled = _dragOffset <= _cancelThreshold;
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (_isCancelled) {
      widget.onCancel();
    } else {
      widget.onRelease();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Color.lerp(AppTheme.textPrimary, Colors.red, _cancelProgress)!;
    final micColor = Color.lerp(AppTheme.primary, Colors.red, _cancelProgress)!;

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Color.lerp(AppTheme.bgCard, Colors.red, _cancelProgress)!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Timer
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                final opacity = 0.5 + _pulseCtrl.value * 0.5;
                return Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Text(
              _timerText,
              style: AppText.bodyStrong.copyWith(
                color: AppTheme.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            // Slide to cancel text + arrow
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: textColor.withValues(
                      alpha: 0.3 + _cancelProgress * 0.7,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.slideToCancelText,
                    style: AppText.label.copyWith(
                      color: textColor.withValues(
                        alpha: 0.3 + _cancelProgress * 0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Draggable mic icon
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: micColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: micColor.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: _cancelProgress * 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
