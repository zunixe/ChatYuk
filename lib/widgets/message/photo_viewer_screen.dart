import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class PhotoViewerScreen extends StatefulWidget {
  final Uint8List bytes;
  final Future<String?> Function()? fullLoader;
  final ValueNotifier<int>? countdown;
  const PhotoViewerScreen({
    super.key,
    required this.bytes,
    this.fullLoader,
    this.countdown,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  Uint8List? _fullBytes;
  final TransformationController _trans = TransformationController();
  double _scale = 1.0;
  Offset _doubleTapPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    // Muat full-res MULAI frame pertama (post-frame) — BUKAN delay tetap
    // 350ms yang dulu bikin "nunggu dulu baru buka". Thumbnail sudah tampil
    // instan (bytes bubble ada di ImageCache); decode full dilakukan di
    // isolate (compute) sehingga TIDAK memblok frame transisi. Jadi foto
    // tampil seketika, ketajaman penuh menyusul begitu siap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFull();
    });
  }

  @override
  void dispose() {
    // Keluarkan bitmap full-res viewer dari ImageCache — kalau tidak,
    // tiap buka-tutup foto menumpuk puluhan MB bitmap sampai èvict LRU.
    final b = _fullBytes;
    if (b != null && b.isNotEmpty) {
      try {
        PaintingBinding.instance.imageCache.evict(MemoryImage(b));
      } catch (_) {}
    }
    _fullBytes = null;
    _trans.dispose();
    super.dispose();
  }

  Future<void> _loadFull() async {
    final loader = widget.fullLoader;
    if (loader == null) return;
    // File full bisa BELUM selesai di-download saat viewer dibuka (foto room
    // berupa path storage → download on-demand). Sekali coba = gagal diam
    // → viewer nyangkut di thumb/spinner. Coba ulang terbatas dengan backoff
    // selama viewer masih terbuka.
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt * 2));
        if (!mounted || _fullBytes != null) return;
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
        setState(() => _fullBytes = bytes);
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

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final bytes = _fullBytes ?? widget.bytes;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
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
                  onInteractionEnd: (_) => setState(
                    () => _scale = _trans.value.getMaxScaleOnAxis(),
                  ),
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      // FASE AWAL (belum ada full): bytes = thumbnail bubble
                      // yang SUDAH didecode di ImageCache dengan cacheWidth
                      // 1080. Pakai 1080 juga → ImageCache HIT → tampil INSTAN
                      // tanpa re-decode. Dulu viewer memaksa 1600 walau masih
                      // bytes bubble 1080 → cache MISS → decode ulang bitmap
                      // besar tepat saat transisi push = "serasa lambat".
                      // FASE FULL (setelah _loadFull): pakai 1600 untuk zoom.
                      cacheWidth: _fullBytes == null ? 1080 : 1600,
                    ),
                  ),
                ),
              ),
            ),
            if (_fullBytes == null && widget.fullLoader != null)
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
