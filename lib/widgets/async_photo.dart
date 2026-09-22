import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../config/theme.dart';
import '../utils.dart';

Uint8List? _decodeBase64(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

// Top-level untuk compute() — decode + resize ke thumbnail kecil (~256px).
// Grid galeri tidak perlu memegang gambar penuh 800px; render jadi ringan.
@visibleForTesting
Uint8List? decodeThumbB64(String b64) {
  try {
    final bytes = base64Decode(b64);
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final thumb = img.copyResize(
      image,
      width: 256,
      interpolation: img.Interpolation.linear,
    );
    return img.encodeJpg(thumb, quality: 80);
  } catch (_) {
    return null;
  }
}

/// Foto thumbnail grid — decode + resize di isolate, tampil placeholder dulu.
class AsyncPhotoThumbnail extends StatefulWidget {
  final String base64;
  final double? width;
  final double? height;
  final BoxFit fit;
  const AsyncPhotoThumbnail({
    super.key,
    required this.base64,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<AsyncPhotoThumbnail> createState() => _AsyncPhotoThumbnailState();
}

class _AsyncPhotoThumbnailState extends State<AsyncPhotoThumbnail> {
  Uint8List? _bytes;
  static final _cache = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AsyncPhotoThumbnail old) {
    super.didUpdateWidget(old);
    // base64 berubah (list foto di-refresh) → decode ulang, jangan pakai state lama.
    if (old.base64 != widget.base64) {
      _bytes = null;
      _load();
    }
  }

  void _load() {
    if (widget.base64.isEmpty) return;
    final cached = _cache[widget.base64];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    _decode();
  }

  Future<void> _decode() async {
    final bytes = await compute(decodeThumbB64, widget.base64);
    if (!mounted) return;
    if (bytes != null && _cache.length < 300) _cache[widget.base64] = bytes;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFFEDEDED),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      // Thumb sudah di-resize 256px; cap decode agar tak raster lebih
      // besar dari tile (mis. grid 3 kolom di HP lebar).
      cacheWidth: 256,
      gaplessPlayback: true,
    );
  }
}

/// Foto full-screen viewer — decode async.
class AsyncPhotoViewer extends StatefulWidget {
  final String base64;
  const AsyncPhotoViewer({super.key, required this.base64});

  @override
  State<AsyncPhotoViewer> createState() => _AsyncPhotoViewerState();
}

class _AsyncPhotoViewerState extends State<AsyncPhotoViewer> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final bytes = await compute(_decodeBase64, widget.base64);
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Image.memory(_bytes!, fit: BoxFit.contain);
  }
}

/// CircleAvatar async — decode dari base64 dengan cache sederhana.
///
/// ANTI-KEDIP (jangan dibalik): hasil decode yang GAGAL (`null`) TIDAK BOLEH
/// menimpa bytes yang sudah tampil. Dulu `setState(() => _bytes = bytes)`
/// dipanggil apa pun hasilnya, sehingga satu decode gagal (base64 korup dari
/// emission ternetwork, isolate kehabisan memori) langsung mengosongkan foto
/// — lalu muncul lagi saat decode berikutnya berhasil. Gejala: "kadang ada
/// kadang hilang".
class AsyncCircleAvatar extends StatefulWidget {
  final String base64;
  final double radius;
  final Color? bgColor;
  final Widget? fallback;

  /// Huruf inisial saat foto belum/gagal tampil. Kalau kosong, memakai
  /// `fallback` (bila ada) — perilaku lama.
  final String initial;

  /// Warna huruf inisial (default putih, kontras dgn bgColor berwarna).
  final Color? initialColor;

  const AsyncCircleAvatar({
    super.key,
    required this.base64,
    this.radius = 40,
    this.bgColor,
    this.fallback,
    this.initial = '',
    this.initialColor,
  });

  @override
  State<AsyncCircleAvatar> createState() => _AsyncCircleAvatarState();
}

class _AsyncCircleAvatarState extends State<AsyncCircleAvatar>
    with SingleTickerProviderStateMixin {
  Uint8List? _bytes;
  // RAM cache dipasangkan fade agar first-appearance tidak pop kasar.
  static final _cache = <String, Uint8List>{};
  // Percobaan decode per base64 (maks 2: awal + 1 retry) supaya base64 rusak
  // tidak memicu decode berulang tanpa henti tiap rebuild.
  final Map<String, int> _attempts = {};
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.base64];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    // First appearance → fade-in dari inisial (anti pop).
    _fade.value = 0;
    _decode();
  }

  @override
  void didUpdateWidget(covariant AsyncCircleAvatar old) {
    super.didUpdateWidget(old);
    if (old.base64 != widget.base64) {
      final cached = _cache[widget.base64];
      if (cached != null) {
        if (_bytes != cached) setState(() => _bytes = cached);
      } else {
        // JANGAN reset _bytes — pertahankan foto lama sampai decode baru
        // selesai (gapless), tanpa flash inisial.
        _decode();
      }
    }
  }

  Future<void> _decode() async {
    final src = widget.base64;
    final bytes = await compute(_decodeBase64, src);
    if (!mounted) return;
    if (bytes != null) {
      if (_cache.length < 200) _cache[src] = bytes;
      setState(() => _bytes = bytes);
      _fade.forward();
      return;
    }
    // ── GAGAL DECODE ──
    // Jangan sentuh `_bytes` (foto lama tetap tampil). Coba sekali lagi
    // setelah jeda pendek — kegagalan sering sesaat (isolate belum siap /
    // base64 terpotong saat emission bertabrakan).
    final tried = (_attempts[src] ?? 0) + 1;
    _attempts[src] = tried;
    dlog('[AVATAR] decode-fail len=${src.length} attempt=$tried '
        'keep-old=${_bytes != null}');
    if (tried >= 2) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted || widget.base64 != src) return;
    final retry = await compute(_decodeBase64, src);
    if (!mounted || widget.base64 != src) return;
    if (retry != null) {
      if (_cache.length < 200) _cache[src] = retry;
      setState(() => _bytes = retry);
      _fade.forward();
      dlog('[AVATAR] decode-retry OK len=${src.length}');
    } else {
      dlog('[AVATAR] decode-retry GAGAL len=${src.length} keep-old=${_bytes != null}');
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) {
      // Foto belum/gagal siap. Utamakan `fallback` eksplisit; kalau tidak ada
      // dan ada inisial, tampilkan huruf (lebih jelas daripada kosong).
      if (widget.fallback != null) return widget.fallback!;
      if (widget.initial.isNotEmpty) {
        return Center(
          child: Text(
            widget.initial,
            style: TextStyle(
              color: widget.initialColor ?? Colors.white,
              fontSize: AppGlyph.avatarInitial(widget.radius * 2),
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    return FadeTransition(
      opacity: _fade,
      child: CircleAvatar(
        radius: widget.radius,
        backgroundColor: widget.bgColor ?? AppTheme.avatarBg,
        // Avatar kecil — decode di-cap (radius x2 utk density retina)
        // agar tidak raster gambar penuh untuk lingkaran mungil.
        backgroundImage: ResizeImage(
          MemoryImage(b),
          width: (widget.radius * 2 * 2).round(),
          allowUpscaling: false,
        ),
      ),
    );
  }
}
