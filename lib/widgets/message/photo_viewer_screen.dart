import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';
import '../../core/media/native_image.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../utils.dart';

// ── Photo Viewer Fullscreen ─────────────────────────────────────────────────
// Menampilkan foto fullscreen (hitam) dengan zoom + close. Bubble mengirim
// THUMBNAIL (bytes) supaya viewer langsung tampil, lalu fullLoader mengambil
// versi full-res dari PhotoCache dan menggantinya begitu siap.
// Untuk view-once, countdown diteruskan dari state pemilik sehingga timer
// terus berjalan.
/// Satu foto di dalam viewer. Boleh >1 supaya bisa di-SWIPE VERTIKAL antar
/// foto (ala WhatsApp: geser ke atas = foto berikutnya).
class ViewerPhoto {
  final Uint8List bytes;
  final Future<String?> Function()? fullLoader;
  const ViewerPhoto({required this.bytes, this.fullLoader});
}

class PhotoViewerScreen extends StatefulWidget {
  final Uint8List bytes;
  final Future<String?> Function()? fullLoader;
  final ValueNotifier<int>? countdown;

  /// Daftar foto (multi-foto/album). Bila null → mode satu foto lama.
  final List<ViewerPhoto>? photos;

  /// Index foto yang dibuka pertama kali (hanya dipakai bila [photos] ada).
  final int initialIndex;

  const PhotoViewerScreen({
    super.key,
    required this.bytes,
    this.fullLoader,
    this.countdown,
    this.photos,
    this.initialIndex = 0,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  final TransformationController _trans = TransformationController();
  double _scale = 1.0;
  Offset _doubleTapPos = Offset.zero;

  /// Mode multi-foto (album): PageView vertikal.
  late final bool _multi = (widget.photos?.length ?? 0) > 1;
  late final PageController _page;
  late int _index;
  late List<Uint8List?> _full;

  Uint8List? get _fullBytes => _multi ? _full[_index] : _singleFull;
  Uint8List? _singleFull;

  Future<String?> Function()? _loaderAt(int i) =>
      _multi ? widget.photos![i].fullLoader : widget.fullLoader;

  Uint8List _thumbAt(int i) =>
      _multi ? widget.photos![i].bytes : widget.bytes;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(
      0,
      _multi ? widget.photos!.length - 1 : 0,
    );
    _page = PageController(initialPage: _index);
    _full = List<Uint8List?>.filled(_multi ? widget.photos!.length : 1, null);
    // Muat full-res MULAI frame pertama (post-frame) — BUKAN delay tetap
    // 350ms yang dulu bikin "nunggu dulu baru buka". Thumbnail sudah tampil
    // instan (bytes bubble ada di ImageCache); decode full dilakukan di
    // isolate (compute) sehingga TIDAK memblok frame transisi. Jadi foto
    // tampil seketika, ketajaman penuh menyusul begitu siap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFull(_index);
    });
  }

  @override
  void dispose() {
    // Keluarkan bitmap full-res viewer dari ImageCache — kalau tidak,
    // tiap buka-tutup foto menumpuk puluhan MB bitmap sampai èvict LRU.
    for (final b in _full) {
      if (b == null || b.isEmpty) continue;
      try {
        PaintingBinding.instance.imageCache.evict(MemoryImage(b));
      } catch (_) {}
    }
    _singleFull = null;
    _trans.dispose();
    _page.dispose();
    super.dispose();
  }

  void _setFull(int i, Uint8List? b) {
    if (i >= _full.length) return;
    _full[i] = b;
    if (!_multi) _singleFull = b;
  }

  Future<void> _loadFull(int i) async {
    final loader = _loaderAt(i);
    if (loader == null) return;
    // File full bisa BELUM selesai di-download saat viewer dibuka (foto room
    // berupa path storage → download on-demand). Sekali coba = gagal diam
    // → viewer nyangkut di thumb/spinner. Coba ulang terbatas dengan backoff
    // selama viewer masih terbuka.
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt * 2));
        if (!mounted || (i < _full.length && _full[i] != null)) return;
      }
      try {
        final t0 = DateTime.now();
        final b64 = await loader();
        final t1 = DateTime.now();
        if (b64 == null || b64.isEmpty || !mounted) continue;
        final bytes = await NativeImage.decodeBytes(b64);
        final t2 = DateTime.now();
        if (bytes == null || !mounted) return;
        dlog('[PHOTO-TIME] viewer full b64=${(b64.length / 1024).round()}KB '
            'loader=${t1.difference(t0).inMilliseconds}ms '
            'b64decode=${t2.difference(t1).inMilliseconds}ms '
            'attempt=$attempt');
        setState(() => _setFull(i, bytes));
        return;
      } catch (_) {}
    }
  }

  void _applyScale(double next, {Offset? focal}) {
    final clamped = next.clamp(1.0, 6.0);
    if ((clamped - _scale).abs() < 0.001) return;
    if (clamped <= 1.01) {
      _trans.value = Matrix4.identity();
    } else if (focal != null) {
      _trans.value = Matrix4.diagonal3Values(clamped, clamped, 1)
        ..setTranslationRaw(
          -focal.dx * (clamped - 1),
          -focal.dy * (clamped - 1),
          0,
        );
    } else {
      final size = MediaQuery.sizeOf(context);
      final cx = size.width / 2;
      final cy = size.height / 2;
      _trans.value = Matrix4.diagonal3Values(clamped, clamped, 1)
        ..setTranslationRaw(-cx * (clamped - 1), -cy * (clamped - 1), 0);
    }
    setState(() => _scale = clamped);
  }

  void _handleDoubleTap() {
    if (_scale > 1.01) {
      _applyScale(1.0);
    } else {
      _applyScale(3.0, focal: _doubleTapPos);
    }
  }

  /// Satu halaman foto (zoom + double-tap). Dipakai juga sebagai item
  /// PageView vertikal pada mode multi-foto.
  Widget _pageContent(int i, S s) {
    final full = i < _full.length ? _full[i] : null;
    final bytes = full ?? _thumbAt(i);
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _trans,
        clipBehavior: Clip.none,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 1.0,
        maxScale: 6.0,
        panEnabled: true,
        scaleEnabled: true,
        onInteractionUpdate: (_) {
          _scale = _trans.value.getMaxScaleOnAxis();
        },
        onInteractionEnd: (_) =>
            setState(() => _scale = _trans.value.getMaxScaleOnAxis()),
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            // FASE AWAL (thumb): JANGAN set cacheWidth — bytes thumb kecil
            // (~256px) di-decode natural = INSTAN. FASE FULL: 1600 agar tajam.
            cacheWidth: full == null ? null : 1600,
            // Decode gagal (bytes korup/kosong) → ikon JELAS, bukan layar
            // hitam polos (laporan "blank" tak terdiagnosa).
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              size: 64,
              color: Colors.white54,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final bool loadingFull = _fullBytes == null && _loaderAt(_index) != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              // MULTI-FOTO: swipe VERTIKAL antar foto (geser ke atas = foto
              // berikutnya), ala WhatsApp. Saat di-zoom, geser tidak boleh
              // pindah foto (dragging gambar lebih diutamakan).
              child: (_multi && _scale <= 1.01)
                  ? PageView.builder(
                      controller: _page,
                      scrollDirection: Axis.vertical,
                      itemCount: widget.photos!.length,
                      onPageChanged: (i) {
                        setState(() {
                          _index = i;
                          _scale = 1.0;
                          _trans.value = Matrix4.identity();
                        });
                        _loadFull(i);
                      },
                      itemBuilder: (_, i) => _pageContent(i, s),
                    )
                  : _pageContent(_index, s),
            ),
            if (_multi)
              Positioned(
                top: 12,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_index + 1}/${widget.photos!.length}',
                    style: AppText.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (loadingFull)
              const Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: s.btnClose,
              ),
            ),
            if (_scale <= 1.01)
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.viewerZoomHint,
                      style: AppText.caption.copyWith(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.zoom_in,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => _applyScale(_scale * 1.4),
                      tooltip: s.btnZoomIn,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.zoom_out,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => _applyScale(_scale / 1.4),
                      tooltip: s.btnZoomOut,
                    ),
                  ),
                  if (_scale > 1.01) ...[
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.restart_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () => _applyScale(1.0),
                        tooltip: s.btnZoomReset,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.countdown != null)
              Positioned(
                top: 12,
                right: 16,
                child: ValueListenableBuilder<int>(
                  valueListenable: widget.countdown!,
                  builder: (_, secs, _) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${secs}s',
                          style: AppText.bodyStrong.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
