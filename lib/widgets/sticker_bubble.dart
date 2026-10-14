import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rv;
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/cache/media_disk_cache.dart';
import '../core/cache/video_file_cache.dart';
import '../providers/riverpod/storage_provider.dart';

/// Stiker chat (ala Telegram) — kotak transparan TANPA background bubble,
/// ukuran tetap (≤512px sesuai spesifikasi stiker Telegram).
///
/// Sumber (salah satu):
///  - `data` = path storage (`stickers/...`) → unduh + cache disk, ATAU
///  - `data` = base64 (stiker pending belum ter-upload).
///
/// Jenis dari bytes/ekstensi:
///  - PNG/WebP statis → `Image.memory` (Flutter native).
///  - WebP animasi → tetap `Image.memory` (Flutter dukung animated-webp).
///  - `.tgs` (Lottie) → ditangani lewat [StickerLottie] (dipisah; opsional).
///  - `.webm` → ditangani `StickerVideo` (dipisah; video_player).
///
/// Cache disiplin: bounded (MediaDiskCache kuota) + map RAM kecil; TIDAK
/// pernah cache tak terbatas. Sesuai §48/§50 PERFORMANCE.md.
class StickerBubble extends StatefulWidget {
  /// Path storage atau base64.
  final String data;
  /// Ukuran tampil (px logical). Stiker Telegram 512px; di bubble chat ~140.
  final double size;
  const StickerBubble({super.key, required this.data, this.size = 140});

  /// Path standar stiker di bucket.
  static const String storagePrefix = 'stickers/';

  /// Titip bytes ke cache RAM (mis. pengirim baru upload) supaya bubble
  /// langsung tampil tanpa menunggu download. Key = hash path (sama
  /// seperti [_StickerBubbleState._key]).
  static void seedCache(String path, Uint8List bytes) =>
      _StickerBubbleState.seed(path, bytes);

  @override
  State<StickerBubble> createState() => _StickerBubbleState();
}

class _StickerBubbleState extends State<StickerBubble> {
  // Cap RAM kecil (bounded) — sama pola AsyncPhotoThumbnail.
  static final _memCache = <String, Uint8List>{};
  static const int _memCap = 120;

  /// Video bisa MB-an — jangan tahan di RAM (temp file + VideoFileCache
  /// yang menanganinya). PNG stiker (~200KB) tetap di-cache.
  static const int _memMaxBytes = 2 * 1024 * 1024;

  Uint8List? _bytes;
  bool _failed = false;

  String get _key => hashKey64(widget.data);
  String get _diskKey => 'sticker:$_key';
  bool get _isPath => widget.data.startsWith(StickerBubble.storagePrefix);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StickerBubble old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  void _load() {
    if (widget.data.isEmpty) {
      _failed = true;
      return;
    }
    final mem = _memCache[_key];
    if (mem != null) {
      _bytes = mem;
      return;
    }
    final disk = MediaDiskCache.instance.readSync(_diskKey);
    if (disk != null && disk.isNotEmpty) {

      _bytes = disk;
      return;
    }
    _fetch();
  }

  void _putToMem(Uint8List b) {
    if (b.length > _memMaxBytes) return;
    if (_memCache.length >= _memCap) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[_key] = b;
  }

  /// Lihat [StickerBubble.seedCache].
  static void seed(String path, Uint8List bytes) {
    if (bytes.length > _memMaxBytes) return;
    if (_memCache.length >= _memCap) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[hashKey64(path)] = bytes;
  }

  Future<void> _fetch() async {
    try {
      Uint8List? bytes;
      if (_isPath) {
        // Video (mp4/webm): cache PERSISTEN VideoFileCache (kuota 1GB LRU),
        // bukan mem/disk foto — file bisa MB-an & grid scroll memutar ulang.
        if (_looksLikeVideo(widget.data)) {
          var f = await VideoFileCache.instance.fileFor(widget.data);
          if (f == null) {
            debugPrint('[STICKER] fetch download ${widget.data}');
            final dl = await rv.ProviderScope.containerOf(context,
                    listen: false)
                .read(storageProvider)
                .downloadBytes(widget.data);
            if (dl != null && dl.isNotEmpty) {
              f = await VideoFileCache.instance.put(widget.data, dl);
            }
          }
          if (f != null) bytes = await f.readAsBytes();
          debugPrint('[STICKER] fetch video done len=${bytes?.length}');
        } else {
          debugPrint('[STICKER] fetch download ${widget.data}');
          bytes = await rv.ProviderScope.containerOf(context, listen: false)
              .read(storageProvider)
              .downloadBytes(widget.data);
          debugPrint('[STICKER] fetch done len=${bytes?.length}');
        }
      } else {
        // base64 pending
        bytes = base64Decode(widget.data);
      }
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _failed = true);
        return;
      }
      _putToMem(bytes);
      unawaited(MediaDiskCache.instance.write(_diskKey, bytes));
      setState(() => _bytes = bytes);
    } catch (e) {
      debugPrint('[STICKER] fetch error: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    if (_failed || _bytes == null) {
      // Placeholder ukuran SAMA (anti layout shift).
      return SizedBox(width: s, height: s);
    }
    return stickerWidget(_bytes!, widget.data, s);
  }
}

/// True bila sumber stiker adalah video pendek (mp4/mov/webm).
bool _looksLikeVideo(String src) {
  final l = src.toLowerCase();
  return l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.webm');
}

/// Deteksi format stiker dari PATH/nama & bytes, render sesuai jenis:
///  - `.tgs`/bytes gzip-Lottie → [Lottie.memory] (animasi vektor).
///  - `.webm` → [StickerVideoPlaceholder] (video; dipisah, butuh controller).
///  - sisanya (png/jpg/webp statis atau ANIMATED webp) → [Image.memory]
///    (Flutter dukung animated webp secara native — gratis).
Widget stickerWidget(Uint8List bytes, String src, double size) {
  final lower = src.toLowerCase();
  // .webm/.mp4 → video bisu loop (S5). Animated webp/gif → Image.memory
  // (Flutter native). .tgs → Lottie.
  if (_looksLikeVideo(src)) return StickerVideo(bytes: bytes, size: size);
  if (lower.endsWith('.tgs') || _looksLikeTgs(bytes)) {
    return Lottie.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
    );
  }
  // .webm & selainnya → Image.memory (webm akan gagal decode → placeholder
  // kosong; jalur video webm ditangani terpisah bila diaktifkan).
  return Image.memory(
    bytes,
    width: size,
    height: size,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
  );
}

/// Heuristik .tgs: gzip (magic 1f 8b) dan bukan gambar.
bool _looksLikeTgs(Uint8List b) =>
    b.length > 2 && b[0] == 0x1f && b[1] == 0x8b;

/// Stiker dari bytes mentah (mis. preview di picker/impor).
class StickerBytes extends StatelessWidget {
  final Uint8List bytes;
  final double size;
  const StickerBytes({super.key, required this.bytes, this.size = 140});

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
  }
}

/// Stiker VIDEO pendek (mp4/mov/webm): bisu + loop + autoplay, tanpa
/// kontrol — ala stiker video Telegram. File ditulis ke temp sekali per
/// konten (nama hash) lalu controller file; dispose saat bubble lepas.
class StickerVideo extends StatefulWidget {
  final Uint8List bytes;
  final double size;
  const StickerVideo({super.key, required this.bytes, this.size = 140});

  @override
  State<StickerVideo> createState() => _StickerVideoState();
}

class _StickerVideoState extends State<StickerVideo> {
  VideoPlayerController? _ctl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(StickerVideo old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes)) {
      _disposeCtl();
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final dir = await getTemporaryDirectory();
      final ext = '.mp4';
      final f = File(
        '${dir.path}/sticker_vid_${widget.bytes.hashCode.abs()}$ext',
      );
      if (!await f.exists()) {
        await f.writeAsBytes(widget.bytes, flush: true);
      }
      if (!mounted) return;
      final c = VideoPlayerController.file(f);
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ctl = c);
      await c.play();
    } catch (_) {}
  }

  void _disposeCtl() {
    try {
      _ctl?.dispose();
    } catch (_) {}
    _ctl = null;
  }

  @override
  void dispose() {
    _disposeCtl();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctl;
    // Placeholder ukuran SAMA (anti layout shift) selama init.
    if (c == null || !c.value.isInitialized) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}
