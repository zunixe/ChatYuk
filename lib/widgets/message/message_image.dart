import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';
import '../../core/cache/photo_cache.dart';
import '../../core/media/chat_photo_helper.dart';
import '../../core/media/native_image.dart';
import '../../core/storage_paths.dart';
import '../../providers/riverpod/service_locator.dart';
import '../../providers/riverpod/locale_provider.dart';
import 'image_decode_core.dart';
import 'photo_viewer_screen.dart';

class MessageImage extends StatefulWidget {
  final String imageData;
  final String chatKey;
  final String messageId;
  /// Lapor lebar render foto (200 atau `tinggi*aspect` bila tinggi dibatasi
  /// 280) agar caption+jam bisa rata kanan sejajar tepi foto.
  final ValueChanged<double>? onRenderedWidth;
  const MessageImage({
    super.key,
    required this.imageData,
    required this.chatKey,
    required this.messageId,
    this.onRenderedWidth,
  });

  @override
  State<MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<MessageImage> {
  DecodedImage? _decoded;
  // Foto BIASA (bukan view-once) tidak punya konsep expired — null berarti
  // "belum keload / gagal", bukan "kedaluwarsa". Selama download tampil
  // spinner; gagal tampil "ketuk untuk memuat", bukan tulisan expired.
  bool _loading = true;
  // Ukuran placeholder loading — langsung dicadangkan sesuai aspek foto
  // (header JPEG/PNG dibaca sinkron) supaya TIDAK mulai dari kotak 200×200
  // lalu loncat bentuk (nge-blink). Sama persis dengan ukuran gambar final.
  double _phW = 200;
  double _phH = 200;
  // Generasi decode: cegah hasil basi menimpa yang baru bila imageData
  // berubah cepat (path → thumbnail) sementara decode lama belum selesai.
  int _gen = 0;
  // Fade-in hanya untuk konten yang BARU dimuat elemen ini (dari placeholder
  // / pergantian gambar). Scroll-back (cache hit di initState) langsung
  // tampil tanpa animasi ulang — daftar foto tetap persistence.
  bool _fadeNext = false;
  // Zoom inline di dalam bubble — gambar tetap kecil di chat, tapi bisa
  // di-pinch 2 jari / ketuk 2x per kotak (mis. baca teks diagram).
  final TransformationController _trans = TransformationController();
  double _scale = 1.0;
  Offset _doubleTapPos = Offset.zero;
  // Lebar terakhir yang dilaporkan ke parent (hindari callback berulang).
  double _reportedWidth = -1;

  @override
  void initState() {
    super.initState();
    final key = widget.imageData.hashCode;
    _decoded = decodedImageCache[key];
    if (_decoded == null) {
      _loading = true;
      _fadeNext = true;
      _reservePlaceholder(widget.imageData);
      _decode(key, ++_gen);
    } else {
      _loading = false;
      final s = photoViewSize(_decoded!.width, _decoded!.height);
      _phW = s.width;
      _phH = s.height;
    }
    // PREFETCH full-res ke mem cache PhotoCache — supaya saat foto di-TAP,
    // viewer langsung dapat versi full (tanpa "tahan dulu" disk-read+decrypt).
    // Fire-and-forget; membuka viewer tetap instan dgn thumbnail lebih dulu.
    if (widget.chatKey.isNotEmpty && widget.messageId.isNotEmpty) {
      unawaited(PhotoCache.instance.load(widget.chatKey, widget.messageId));
    }
  }

  @override
  void dispose() {
    _trans.dispose();
    super.dispose();
  }

  void _resetZoom() {
    if (_scale <= 1.01) return;
    _trans.value = Matrix4.identity();
    _scale = 1.0;
  }

  void _toggleZoom() {
    if (!mounted) return;
    if (_scale > 1.01) {
      _trans.value = Matrix4.identity();
      setState(() => _scale = 1.0);
    } else {
      const s = 2.5;
      _trans.value = Matrix4.diagonal3Values(s, s, 1)
        ..setTranslationRaw(
          -_doubleTapPos.dx * (s - 1),
          -_doubleTapPos.dy * (s - 1),
          0,
        );
      setState(() => _scale = s);
    }
  }

  @override
  void didUpdateWidget(MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // imageData berubah (fetch awal kosong → photo download selesai) → re-decode
    if (widget.imageData != oldWidget.imageData &&
        widget.imageData.isNotEmpty) {
      _resetZoom();
      // Cadangkan aspek baru segera (sinkron) bila base64; path → ukuran lama
      // dipertahankan (gapless) sampai download memberi aspek sebenarnya.
      _reservePlaceholder(widget.imageData);
      final key = widget.imageData.hashCode;
      final hit = decodedImageCache[key];
      if (hit != null) {
        _gen++;
        _fadeNext = true;
        if (mounted) {
          setState(() {
            _decoded = hit;
            _loading = false;
            final s = photoViewSize(hit.width, hit.height);
            _phW = s.width;
            _phH = s.height;
          });
        }
      } else {
        // JANGAN kosongkan _decoded — foto lama tetap tampil sampai yang baru
        // siap (persistence, anti kedip). Hanya tandai loading untuk spinner
        // bila memang belum ada gambar sama sekali (lihat build).
        _fadeNext = true;
        if (mounted) {
          setState(() {
            _loading = true;
          });
        }
        _decode(key, ++_gen);
      }
    }
  }

  // Cadangkan ukuran placeholder dari header gambar (sinkron, tanpa isolate).
  // Base64 → baca dimensi JPEG/PNG langsung; path storage / tak dikenal →
  // biarkan ukuran lama (gapless, jangan kembali ke kotak).
  //
  // PERF: decode HANYA prefix header (bukan SELURUH base64) — foto besar bisa
  // ratusan KB; decode penuh di UI thread saat bubble mount/rebuild (mis. ada
  // pesan baru saat user mengetik) = stall input ("ngetik berenti").
  void _reservePlaceholder(String data) {
    if (data.isEmpty || isStoragePathValue(data)) return;
    try {
      var dims = parseImageDimensions(_decodeHeaderPrefix(data));
      // Header di luar prefix (EXIF besar) → fallback decode penuh (jarang).
      dims ??= parseImageDimensions(base64Decode(data));
      if (dims == null) return;
      final s = photoViewSize(dims.width, dims.height);
      _phW = s.width;
      _phH = s.height;
    } catch (_) {}
  }

  /// Decode prefix base64 (header gambar) agar tak men-decode seluruh foto.
  static Uint8List _decodeHeaderPrefix(String b64) {
    const maxChars = 16384; // ~12 KB bytes — cukup untuk JPEG SOF/PNG/WebP.
    if (b64.length <= maxChars) return base64Decode(b64);
    var chunk = b64.substring(0, maxChars);
    final rem = chunk.length % 4;
    if (rem != 0) chunk = chunk.substring(0, chunk.length - rem);
    return base64Decode(chunk);
  }

  Future<void> _decode(int key, int gen) async {
    var data = widget.imageData;
    // LAZY PENUH: imageData kosong tapi file lokal ada (foto lama yang tidak
    // ikut bulk-decrypt saat buka chat) → pulihkan thumb dari disk. Tanpa ini
    // foto lama tampil "ketuk untuk memuat" selamanya.
    if (data.isEmpty &&
        widget.chatKey.isNotEmpty &&
        widget.messageId.isNotEmpty) {
      try {
        final diskThumb = await PhotoCache.instance.loadThumb(
          widget.chatKey,
          widget.messageId,
        );
        if (diskThumb != null && diskThumb.isNotEmpty) data = diskThumb;
      } catch (_) {}
    }
    // PATH storage (belum base64) → download dulu. decodeImageB64 melempar
    // null untuk input non-base64, jadi jangan memanggilnya dengan path.
    if (data.isNotEmpty && isStoragePathValue(data)) {
      // Prefetch background (list pesan) biasanya sudah menyimpan thumb di
      // disk → tampilkan instan tanpa menunggu download + drain. Versi full
      // menyusul via drain (aspek sama, swap gapless).
      try {
        final thumbB64 = await PhotoCache.instance.loadThumb(
          widget.chatKey,
          widget.messageId,
        );
        if (thumbB64 != null &&
            thumbB64.isNotEmpty &&
            mounted &&
            gen == _gen) {
          final thumbBytes = base64Decode(thumbB64);
          final thumbDims = parseImageDimensions(thumbBytes);
          if (thumbDims != null) {
            final td = DecodedImage(
              thumbBytes,
              thumbDims.width,
              thumbDims.height,
            );
            putDecodedCache(key, td);
            _fadeNext = true;
            setState(() {
              _decoded = td;
              _loading = false;
              final s = photoViewSize(thumbDims.width, thumbDims.height);
              _phW = s.width;
              _phH = s.height;
            });
            return;
          }
        }
      } catch (_) {}
      data = await safeStorage(context).download(data) ?? '';
    }
    if (!mounted || gen != _gen) return;
    if (data.isEmpty) {
      setState(() {
        _loading = false;
      });
      return;
    }
    // Pakai ulang hasil decode bila isinya SAMA (pending base64 vs download
    // path hasil upload sendiri) — tanpa compute ulang, tanpa kedip.
    final contentHit = decodedImageCache[data.hashCode];
    if (contentHit != null && contentHit.width > 0 && contentHit.height > 0) {
      putDecodedCache(key, contentHit);
      if (!mounted || gen != _gen) return;
      setState(() {
        _decoded = contentHit;
        _loading = false;
        final s = photoViewSize(contentHit.width, contentHit.height);
        _phW = s.width;
        _phH = s.height;
      });
      return;
    }
    // Aspek sudah bisa dicadangkan dari data yang baru diunduh (sebelum
    // decode penuh) — placeholder menyesuaikan sekali ke bentuk benar,
    // piksel menyusul fade-in tanpa lompatan lagi.
    try {
      var dims = parseImageDimensions(_decodeHeaderPrefix(data));
      dims ??= parseImageDimensions(base64Decode(data));
      if (dims != null && mounted && gen == _gen) {
        final s = photoViewSize(dims.width, dims.height);
        setState(() {
          _phW = s.width;
          _phH = s.height;
        });
      }
    } catch (_) {}
    final res = await NativeImage.decodeWithDims(data);
    if (!mounted || gen != _gen) return;
    if (res == null) {
      // Decode gagal — jangan cache null (dipaksa `!` dulu bikin crash).
      setState(() {
        _loading = false;
      });
      return;
    }
    final decoded = DecodedImage(res.bytes, res.width, res.height);
    if (decoded.width <= 0 || decoded.height <= 0) {
      setState(() {
        _loading = false;
      });
      return;
    }
    putDecodedCache(data.hashCode, decoded);
    putDecodedCache(key, decoded);
    if (!mounted || gen != _gen) return;
    setState(() {
      _decoded = decoded;
      _loading = false;
      final s = photoViewSize(decoded.width, decoded.height);
      _phW = s.width;
      _phH = s.height;
    });
  }

  void _retry() {
    final key = widget.imageData.hashCode;
    _fadeNext = true;
    setState(() {
      _loading = true;
    });
    _decode(key, ++_gen);
  }

  // Lapor lebar render ke parent (sekali / berubah) → caption+jam rata kanan
  // sejajar tepi foto. Dipakai gambar final DAN placeholder supaya caption
  // langsung selebar foto dari frame pertama (tidak ikut loncat).
  void _reportWidth(double w) {
    final cb = widget.onRenderedWidth;
    if (cb != null && (w - _reportedWidth).abs() > 0.5) {
      _reportedWidth = w;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cb(w);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final decoded = _decoded;
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      // Foto biasa: belum keload = spinner; gagal = "ketuk untuk memuat".
      // JANGAN pakai tulisan expired di sini — itu hanya untuk view-once.
      // Ukuran = cadangan aspek foto (bukan kotak 200×200) + lebar dilaporkan
      // ke parent supaya caption langsung pas dari frame pertama.
      _reportWidth(_phW);
      return GestureDetector(
        onTap: _loading ? null : _retry,
        child: Container(
          width: _phW,
          height: _phH,
          color: AppTheme.bgInput,
          alignment: Alignment.center,
          child: _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppTheme.primary,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh,
                      color: AppTheme.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.msgPhotoTapToLoad,
                      style: AppText.chatBodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
        ),
      );
    }
    final size = photoViewSize(decoded.width, decoded.height);
    final width = size.width;
    final height = size.height;
    // Lapor lebar render ke parent (sekali / berubah) → caption+jam rata kanan
    // sejajar tepi foto.
    _reportWidth(width);
    return GestureDetector(
      onTap: () => _openFullscreen(),
      onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InteractiveViewer(
          transformationController: _trans,
          clipBehavior: Clip.hardEdge,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          minScale: 1.0,
          maxScale: 6.0,
          // Pan satu jari hanya saat sudah zoom — kalau skala 1.0, drag
          // tetap untuk scroll chat (pola sama seperti post_photo_viewer).
          panEnabled: _scale > 1.01,
          scaleEnabled: true,
          onInteractionUpdate: (_) {
            _scale = _trans.value.getMaxScaleOnAxis();
          },
          onInteractionEnd: (_) => setState(
            () => _scale = _trans.value.getMaxScaleOnAxis(),
          ),
          child: _fadeNext
              // Fade-in tiap KONTEN baru. Scroll-back / cache hit di initState
              // (_fadeNext=false) langsung tampil — tidak animasi ulang.
              ? TweenAnimationBuilder<double>(
                  key: ValueKey(decoded),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 180),
                  onEnd: () => _fadeNext = false,
                  builder: (_, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
                  child: _bubbleImage(
                    context,
                    decoded,
                    width,
                    height,
                    s,
                  ),
                )
              : _bubbleImage(context, decoded, width, height, s),
        ),
      ),
    );
  }

  // Gambar bubble (dipakai langsung / sebagai child fade-in).
  Widget _bubbleImage(
    BuildContext context,
    DecodedImage decoded,
    double width,
    double height,
    S s,
  ) {
    return Image.memory(
      decoded.bytes,
      width: width,
      height: height,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      // Decode max 1080px (bukan full-res 12MP): bubble max 280px,
      // zoom inline 6x tetap tajam; hemat ~6x RAM bitmap.
      cacheWidth: 1080,
      errorBuilder: (_, _, _) => GestureDetector(
        onTap: _retry,
        child: Container(
          width: width,
          height: height,
          color: AppTheme.bgInput,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh,
                color: AppTheme.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                s.msgPhotoTapToLoad,
                style: AppText.chatBodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullscreen() {
    final decoded = _decoded;
    if (decoded == null || !mounted) return;
    // Route KHUSUS viewer (fade + scale 200ms) — BUKAN slide global. Slide
    // horizontal terasa "berat/menunggu" untuk foto; zoom-in ala WhatsApp/M3
    // jauh lebih halus & tidak ada jeda. Thumbnail sudah tampil instan
    // (bytes bubble ada di ImageCache), full-res menyusul tanpa delay buatan.
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: null,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, __, ___) => PhotoViewerScreen(
          bytes: decoded.bytes,
          fullLoader: () =>
              PhotoCache.instance.load(widget.chatKey, widget.messageId),
        ),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
