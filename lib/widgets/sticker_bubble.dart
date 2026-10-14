import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rv;

import '../core/cache/media_disk_cache.dart';
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

  @override
  State<StickerBubble> createState() => _StickerBubbleState();
}

class _StickerBubbleState extends State<StickerBubble> {
  // Cap RAM kecil (bounded) — sama pola AsyncPhotoThumbnail.
  static final _memCache = <String, Uint8List>{};
  static const int _memCap = 120;

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
    if (_memCache.length >= _memCap) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[_key] = b;
  }

  Future<void> _fetch() async {
    try {
      Uint8List? bytes;
      if (_isPath) {
        bytes = await rv.ProviderScope.containerOf(context, listen: false)
            .read(storageProvider)
            .downloadBytes(widget.data);
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
    } catch (_) {
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
    return Image.memory(
      _bytes!,
      width: s,
      height: s,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(width: s, height: s),
    );
  }
}

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
