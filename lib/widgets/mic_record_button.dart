import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

/// Tombol mic WA-style: sentuh → langsung membesar; lepas tanpa geser → kirim;
/// geser kiri → batal; geser ke atas → LOCK: bulat naik, berubah jadi icon
/// kunci, dock diam di atas. Mode terkunci: lepas/tarik bawah = kirim,
/// tarik kiri = batal.
class MicRecordButton extends StatefulWidget {
  final bool isRecording;
  final bool isLocked;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressCancel;
  final VoidCallback? onLock;
  final double size;
  const MicRecordButton({
    super.key,
    required this.isRecording,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressCancel,
    this.isLocked = false,
    this.onLock,
    this.size = 40,
  });

  @override
  State<MicRecordButton> createState() => _MicRecordButtonState();
}

class _MicRecordButtonState extends State<MicRecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final CurvedAnimation _grow;
  double _dragDx = 0;
  double _dragDy = 0;
  bool _fingerDown = false;
  bool _didLock = false;
  bool _upDragMode = false;
  Offset? _pointerOrigin;

  // Geser kiri cukup jauh → batal; geser atas → lock + dock di atas.
  static const double _cancelThreshold = -120;
  static const double _maxDrag = -200;
  static const double _lockThreshold = -50;
  static const double _dockHeight = 60;

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
      if (_fingerDown || widget.isLocked) _animCtrl.forward();
    } else if (!widget.isRecording && old.isRecording) {
      // Recording berakhir (kirim/batal) — reset lock + kembali mengecil.
      _didLock = false;
      _dragDx = 0;
      _dragDy = 0;
      _animCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  bool get _isCancelZone => _dragDx <= _cancelThreshold;

  bool get _lockedNow => widget.isLocked || _didLock;

  double get _lockProgress {
    if (_lockedNow) return 1.0;
    if (_dragDy >= 0) return 0.0;
    return (-_dragDy / _lockThreshold).clamp(0.0, 1.0);
  }

  // Listener pointer mentah — tidak pakai LongPress (delay ~500ms).
  void _onPointerDown(PointerDownEvent event) {
    if (_pointerOrigin != null) return;
    _pointerOrigin = event.position;
    _fingerDown = true;
    _didLock = false;
    _upDragMode = false;
    _animCtrl.forward();
    if (!widget.isRecording) {
      widget.onLongPressStart();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final origin = _pointerOrigin;
    if (origin == null) return;
    // Gesture yang baru meng-lock: bulat diam di dock, abaikan gerakan.
    if (_didLock) return;
    final dx = event.position.dx - origin.dx;
    final dy = event.position.dy - origin.dy;
    if (!widget.isRecording) return;

    if (widget.isLocked) {
      // Mode terkunci (sentuhan baru): bebas ditarik bawah/kiri.
      setState(() {
        _dragDx = dx.clamp(_maxDrag, 200.0);
        _dragDy = dy.clamp(-40.0, 160.0);
      });
      return;
    }

    if (_upDragMode || (dy < -20 && dy.abs() >= dx.abs())) {
      // Geser ke atas → arahkan ke lock (latch: tetap mode atas).
      _upDragMode = true;
      setState(() {
        _dragDx = 0;
        _dragDy = dy.clamp(-_dockHeight, 0.0);
      });
      if (dy <= _lockThreshold && widget.onLock != null) {
        _didLock = true;
        HapticFeedback.mediumImpact();
        widget.onLock!();
        // Bulat beku PERSIS di titik dock — tanpa lompatan/jitter.
        setState(() => _dragDy = 0);
      }
    } else if (dx < -10) {
      // Geser ke kiri → mode batal.
      setState(() {
        _dragDx = dx.clamp(_maxDrag, 0.0);
        _dragDy = 0;
      });
    }
  }

  void _onPointerUp(PointerUpEvent _) {
    final origin = _pointerOrigin;
    if (origin == null) return;
    _pointerOrigin = null;
    _fingerDown = false;
    final cancelDrag = _isCancelZone;
    final wasLockGesture = _didLock;
    setState(() {
      _dragDx = 0;
      _dragDy = 0;
    });
    if (wasLockGesture) {
      // Lepas setelah lock — bulat tetap dock di atas, rekaman lanjut.
      return;
    }
    if (widget.isLocked) {
      // Mode terkunci: lepas = kirim, kecuali sempat ditarik ke kiri = batal.
      if (cancelDrag) {
        widget.onLongPressCancel();
      } else {
        widget.onTap();
      }
      return;
    }
    // Normal: lepas tanpa geser = kirim; geser kiri = batal.
    final shouldCancel = cancelDrag || !widget.isRecording;
    _animCtrl.reverse();
    if (shouldCancel) {
      widget.onLongPressCancel();
    } else {
      widget.onTap();
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    final origin = _pointerOrigin;
    if (origin == null) return;
    _pointerOrigin = null;
    _fingerDown = false;
    final cancelDrag = _isCancelZone;
    final wasLockGesture = _didLock;
    setState(() {
      _dragDx = 0;
      _dragDy = 0;
    });
    if (wasLockGesture || widget.isLocked) {
      if (cancelDrag) widget.onLongPressCancel();
      return;
    }
    _animCtrl.reverse();
    widget.onLongPressCancel();
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.isRecording;

    // Offset HIT TEST: transform di LUAR Listener supaya kotak sentuh ikut
    // naik mengikuti bulatan yang dock — tanpa ini sentuhan pada bulatan
    // dock tidak pernah diterima (gate hit test di box Listener sendiri).
    final hitDy = _lockedNow ? -_dockHeight + _dragDy : 0.0;

    return Transform.translate(
      offset: Offset(0, hitDy),
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, _) {
            // Saat locked: bulatan mengecil ke ukuran awal (40px) di dock.
            final progress = _lockedNow ? 0.0 : _grow.value;
            // Slot layout tetap (widget.size); visual circle melebihi batas
            // via OverflowBox — benar-benar bulat & bebas clip.
            final diameter = widget.size + progress * widget.size * 0.8;
            final color = _lockedNow
                ? Colors.green
                : _isCancelZone
                ? Colors.red
                : isRecording
                ? Colors.red
                : AppTheme.primary;
            final lockP = _lockProgress;
            final circleDy = _lockedNow ? -_dockHeight + _dragDy : _dragDy;
            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  // Icon gembok terbuka — hanya saat sedang menarik ke atas,
                  // sebelum lock. Setelah lock, bulatan sendiri jadi kunci.
                  if (!_lockedNow && _dragDy < -5)
                    Positioned(
                      bottom: widget.size + _dockHeight + 6,
                      child: Opacity(
                        opacity: lockP.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.85 + lockP * 0.15,
                          child: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.lock_open_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  OverflowBox(
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: Offset(_dragDx, circleDy),
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
                              : _lockedNow
                              ? Icons.lock_rounded
                              : isRecording
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
                          color: Colors.white,
                          size: diameter * 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
