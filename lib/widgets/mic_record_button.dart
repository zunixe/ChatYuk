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
  final ValueChanged<bool>? onPickUpChanged;
  final double size;
  const MicRecordButton({
    super.key,
    required this.isRecording,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressCancel,
    this.isLocked = false,
    this.onLock,
    this.onPickUpChanged,
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
  Offset? _pointerOrigin;

  // Bulatan kunci dock digambar langsung di Overlay saat mode terkunci —
  // di atas segalanya, karena bulatan berada di luar bounds composer
  // (tanpa ini tap bulatan jatuh ke pesan di belakangnya → menu reply/delete).
  OverlayEntry? _dockShield;
  double _dockCx = 0;
  double _dockCy = 0;
  bool _shieldInserted = false;
  bool _fromShield = false;

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
    // easeOut — TANPA overshoot (easeOutBack bisa >1.0 → bulatan membengkak
    // sesaat saat reverse = "blink kunci besar").
    _grow = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(covariant MicRecordButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !old.isRecording) {
      if (_fingerDown || widget.isLocked) _animCtrl.forward();
    } else if (!widget.isRecording && old.isRecording) {
      // Recording berakhir (kirim/batal) — reset lock + kembali mengecil.
      _didLock = false;
      _leaving = false;
      _dragDx = 0;
      _dragDy = 0;
      _wasDragged = false;
      _wasPickUp = false;
      widget.onPickUpChanged?.call(false);
      _animCtrl.reverse();
    }
    // Shield area kunci: pasang saat terkunci, lepas saat tidak.
    // Insert DITUNDA ke frame berikutnya — mount overlay di frame yang sama
    // dengan latch lock membuat frame itu terlalu berat (raster meleset →
    // garbage putih setengah layar di Adreno).
    final docked = widget.isRecording && widget.isLocked;
    if (docked && _dockShield == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isRecording && widget.isLocked && _dockShield == null) {
          _insertDockShield();
        }
      });
    } else if (!docked && _dockShield != null) {
      _removeDockShield();
    }
  }

  /// Bulatan kunci dock DIGAMBAR & DIGERAKKAN langsung di Overlay — di atas
  /// segalanya. Ini menghilangkan seluruh masalah hit-test: bulatan dock
  /// berada di luar bounds composer, sehingga versi in-place selalu kehapus
  /// oleh tap list pesan di belakangnya (menu reply/delete).
  void _insertDockShield() {
    _pointerOrigin = null;
    _fingerDown = false;
    _dragDx = 0;
    _dragDy = 0;
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null || !rb.hasSize) return;
    // Semua koordinat LOGICAL — Positioned overlay & localToGlobal sama-sama
    // logical, JANGAN kalikan dpr.
    final slot = rb.localToGlobal(Offset.zero);
    _dockCx = slot.dx + rb.size.width / 2;
    _dockCy = slot.dy + rb.size.height / 2 - _dockHeight;
    _dockShield = OverlayEntry(builder: (_) => _buildDockCircle());
    Overlay.of(context, rootOverlay: true).insert(_dockShield!);
    _shieldInserted = true;
  }

  /// UI bulatan di overlay: hijau+kunci saat diam di dock, merah+stop &
  /// mengikuti jari saat di-pick-up, merah+✕ di zona batal. Ukuran & warna
  /// dianimasikan via _animCtrl (grow/shrink mulus saat pick-up/lepas).
  Widget _buildDockCircle() {
    final maxD = widget.size * 1.9;
    return Positioned(
      left: _dockCx + _dragDx - maxD / 2,
      top: _dockCy + _dragDy - maxD / 2,
      width: maxD,
      height: maxD,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) { _fromShield = true; _onPointerDown(e); },
        onPointerMove: (e) { _fromShield = true; _onPointerMove(e); },
        onPointerUp: (e) { _fromShield = true; _onPointerUp(e); },
        onPointerCancel: (e) { _fromShield = true; _onPointerCancel(e); },
          child: AnimatedBuilder(
            animation: _animCtrl,
            builder: (context2, _) {
              final picked = _pickUp;
              final cancel = picked && _isCancelZone;
              // Diam di dock = SELALU 40px. Hanya saat di-pick-up ukurannya
              // mengikuti animasi — mencegah "kunci besar" menetap setelah
              // relock (controller bisa nyangkut di nilai besar).
              final d = picked
                  ? widget.size + _grow.value * widget.size * 0.8
                  : widget.size;
            final color = cancel ? Colors.red : picked ? Colors.red : Colors.green;
            final icon = cancel
                ? Icons.close_rounded
                : picked
                ? Icons.stop_rounded
                : Icons.lock_rounded;
            return Center(
              child: Container(
                width: d,
                height: d,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: d * 0.5),
              ),
            );
          },
        ),
      ),
    );
  }

  void _removeDockShield() {
    _dockShield?.remove();
    _dockShield = null;
    _shieldInserted = false;
  }

  @override
  void dispose() {
    _removeDockShield();
    _animCtrl.dispose();
    super.dispose();
  }

  bool get _isCancelZone => _dragDx <= _cancelThreshold;

  bool get _lockedNow => widget.isLocked || _didLock;

  /// Tombol kunci ditekan LAGI saat mode terkunci → bulatan kembali jadi
  /// lingkaran merah recording yang mengikuti jari (bisa digeser ke bawah).
  bool get _pickUp => _fingerDown && widget.isLocked && !_didLock;

  void _setPickUp(bool value) {
    if (_wasPickUp == value) return;
    _wasPickUp = value;
    widget.onPickUpChanged?.call(value);
  }

  bool _wasPickUp = false;
  bool _wasDragged = false;
  // Aksi selesai (kirim/batal) — bulatan DIHILANGKAN total sampai parent
  // selesai menutup rekaman. Mencegah blink "kunci hijau" 1-2 frame.
  bool _leaving = false;

  double get _lockProgress {
    if (_lockedNow) return 1.0;
    if (_dragDy >= 0) return 0.0;
    return (-_dragDy / _lockThreshold).clamp(0.0, 1.0);
  }

  /// Rebuild bulatan overlay (setiap perubahan yang memengaruhi visualnya).
  void _markDirty(VoidCallback fn) {
    setState(fn);
    _dockShield?.markNeedsBuild();
  }

  // Listener pointer mentah — tidak pakai LongPress (delay ~500ms).
  void _onPointerDown(PointerDownEvent event) {
    if (_leaving) return;
    final src = _fromShield;
    _fromShield = false;
    // Saat locked & overlay bulatan aktif: HANYA bulatan overlay yang pegang
    // gesture — tap pada slot kosong in-place diabaikan.
    if (widget.isLocked && _shieldInserted && !src) return;
    if (_pointerOrigin != null) return;
    _pointerOrigin = event.position;
    _fingerDown = true;
    _didLock = false;
    _wasDragged = false;
    _wasPickUp = false;
    if (widget.isRecording) _animCtrl.forward();
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

    if (widget.isLocked && _fromShield) {
      // Pointer dari bulatan overlay (koordinat global → delta langsung).
      final downMode = dy.abs() >= dx.abs();
      _wasDragged = true;
      _markDirty(() {
        if (downMode) {
          // Rel vertikal terbatas: maksimal sampai posisi asli mic.
          _dragDx = 0;
          _dragDy = dy.clamp(0.0, _dockHeight);
        } else {
          // Rel kiri sejajar baris composer (lintasan batal).
          _dragDx = dx.clamp(_maxDrag, 0.0);
          _dragDy = _dockHeight;
        }
      });
      // RELOCK: bulatan dibawa kembali ke dock (jari naik melewati titik
      // tekan) → kembali jadi kunci hijau; jari ini berhiri mengendalikan.
      if (downMode && dy <= 0) {
        _didLock = true;
        HapticFeedback.selectionClick();
        _wasDragged = false;
        _pointerOrigin = null;
        _fingerDown = false;
        _animCtrl.reverse();
        _markDirty(() {
          _dragDx = 0;
          _dragDy = 0;
        });
        _setPickUp(false);
        return;
      }
      _setPickUp(_pickUp);
      return;
    }

    if (widget.isLocked) {
      // Sentuhan baru pada bulatan in-place (shield belum terpasang):
      // perlakukan sama seperti jalur overlay di atas.
      final downMode = dy.abs() >= dx.abs();
      _wasDragged = true;
      setState(() {
        if (downMode) {
          _dragDx = 0;
          _dragDy = dy.clamp(0.0, _dockHeight);
        } else {
          _dragDx = dx.clamp(_maxDrag, 0.0);
          _dragDy = _dockHeight;
        }
      });
      // RELOCK (jalur in-place) — perilaku sama dengan jalur overlay.
      if (downMode && dy <= 0) {
        _didLock = true;
        HapticFeedback.selectionClick();
        _wasDragged = false;
        _pointerOrigin = null;
        _fingerDown = false;
        _animCtrl.reverse();
        setState(() {
          _dragDx = 0;
          _dragDy = 0;
        });
        _setPickUp(false);
        return;
      }
      _setPickUp(_pickUp);
      return;
    }

    // Arah ditentukan per-gerakan dari DOMINANSI (bukan latch) — sedikit
    // gerakan naik di awal tidak lagi mencuri gesture; geser kiri kapan pun
    // langsung masuk mode batal.
    if (dy < -8 && dy.abs() >= dx.abs()) {
      // Geser ke atas → arahkan ke lock.
      setState(() {
        _dragDx = 0;
        _dragDy = dy.clamp(-_dockHeight, 0.0);
      });
      if (dy <= _lockThreshold && widget.onLock != null) {
        _didLock = true;
        HapticFeedback.mediumImpact();
        widget.onLock!();
        // Bulat beku PERSIS di titik dock — tanpa lompatan/jitter.
        // Reset pointer: gesture berakhir di sini; sentuhan berikutnya
        // (pickup) lewat shield Overlay yang baru terpasang.
        _pointerOrigin = null;
        _fingerDown = false;
        // Bulatan dock mengecil mulus ke ukuran mic asli (40px).
        _animCtrl.reverse();
        setState(() => _dragDy = 0);
      }
    } else if (dx < -8) {
      // Geser ke kiri → mode batal (rel lock langsung hilang).
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
      _dockShield?.markNeedsBuild();
      return;
    }
    if (widget.isLocked) {
      // Mode terkunci: geser (pickup) lalu lepas = kirim, kecuali ditarik
      // ke kiri = batal. TAP tanpa geser = no-op (pause ada di composer).
      _setPickUp(false);
      if (_wasDragged) {
        // Aksi selesai (kirim/batal) → bulatan DIHILANGKAN total:
        // overlay dilepas sekarang, jangan biarkan rebuild menampilkan
        // "kunci hijau di dock" 1-2 frame sebelum parent menutup rekaman.
        _leaving = true;
        _removeDockShield();
        if (cancelDrag) {
          widget.onLongPressCancel();
        } else {
          widget.onTap();
        }
      }
      // Reset SETELAH aksi — jangan sebelum, atau kirim/batal tak jalan.
      _wasDragged = false;
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
    _wasDragged = false;
    _setPickUp(false);
    if (widget.isLocked && !_wasPickUp) {
      // Aksi terputus (kirim/batal) → hilangkan bulatan total, tanpa blink
      // kunci hijau.
      _leaving = true;
      _removeDockShield();
    }
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

    // Saat locked & overlay aktif, bulatan digambar oleh _buildDockCircle
    // di Overlay — in-place hanya slot kosong (Listener tetap untuk
    // gesture pra-lock). RepaintBoundary mengisolasi repaint gerakan.
    return RepaintBoundary(
      child: Transform.translate(
        offset: Offset(0, hitDy),
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: AnimatedBuilder(
            animation: _animCtrl,
            builder: (context, _) {
              // _leaving: aksi kirim/batal sudah dieksekusi — bulatan
              // DIHILANGKAN total (tanpa blink kunci hijau) sampai parent
              // selesai menutup rekaman.
              if (_leaving || (_lockedNow && _shieldInserted)) {
                return SizedBox(width: widget.size, height: widget.size);
              }
              // Saat locked: bulatan mengecil ke ukuran awal (40px) di dock —
              // KECUALI sedang di-pick-up (ditekan lagi): membesar seperti
              // recording normal dan mengikuti jari.
              final progress = _pickUp
                  ? _grow.value
                  : (_lockedNow ? 0.0 : _grow.value);
              // Slot layout tetap (widget.size); visual circle melebihi batas
              // via OverflowBox — benar-benar bulat & bebas clip.
              final diameter = widget.size + progress * widget.size * 0.8;
              // Tidak pernah biru saat transisi locked→idle — merah tetap
              // sampai state recording benar-benar berakhir (anti blink).
              final color = _isCancelZone
                  ? Colors.red
                  : _pickUp
                  ? Colors.red
                  : _lockedNow
                  ? Colors.green
                  : (isRecording || _wasDragged)
                  ? Colors.red
                  : AppTheme.primary;
              final lockP = _lockProgress;
              // Saat locked: bulatan TIDAK diberi offset inner — ia sudah ikut
              // terangkat oleh transform luar (hitDy). Offset ganda dulu membuat
              // bulatan tampak di -120px sementara kotak sentuh di -60px →
              // bulatan dock tidak bisa dipencet. Sekarang visual = hit.
              final circleDy = _lockedNow ? 0.0 : _dragDy;
              return SizedBox(
                width: widget.size,
                height: widget.size,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Rel vertikal lock (gaya slide-to-cancel tapi ke atas):
                    // muncul saat mic ditahan & mulai digeser ke atas.
                    // Panah di ujung atas + bulatan gembok yang mengisi
                    // progres; SEMBUNYI saat digeser ke kiri (mode batal).
                    if (!_lockedNow && _dragDy < -4 && !_isCancelZone && _dragDx > -10)
                      Positioned(
                        bottom: widget.size + 4,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: ((-_dragDy) / 18).clamp(0.0, 1.0),
                            child: Container(
                              width: widget.size,
                              height: _dockHeight + 26,
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: AppTheme.divider),
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    size: 18,
                                    color: Colors.white70,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        // Netral → hijau (tanpa biru,
                                        // mencegah blink biru saat drag).
                                        color: Color.lerp(
                                          AppTheme.divider,
                                          Colors.green,
                                          lockP,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.lock_open_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
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
                            // Shadow ringan — blur besar + spread memicu
                            // saveLayer mahal di Adreno (frame parsial).
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isCancelZone
                                ? Icons.close_rounded
                                : _pickUp
                                ? Icons.stop_rounded
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
      ),
    );
  }
}
