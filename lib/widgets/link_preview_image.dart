import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/theme.dart';
import '../core/cache/media_disk_cache.dart';
import '../core/media/chat_photo_helper.dart';

/// Foto thumbnail LINK PREVIEW dengan cache DISK (bukan `Image.network` RAW).
///
/// Masalah (LP-E): `Image.network(url)` hanya di-cache RAM Flutter → saat
/// app dibuka ulang / scroll balik, gambar preview diunduh ULANG dari sumber
/// (boros data + lambat), dan tanpa cache disk tak ada persistence.
///
/// Solusi (pola sama avatar/post): unduh → simpan ke [MediaDiskCache] (kuota
/// LRU) → baca SINKRON dari disk untuk frame pertama; render via provider
/// stabil. Disk menahan gambar preview walau RAM dibersihkan.
class LinkPreviewImage extends StatefulWidget {
  final String url;
  final double height;
  const LinkPreviewImage({super.key, required this.url, this.height = 140});

  @override
  State<LinkPreviewImage> createState() => _LinkPreviewImageState();
}

class _LinkPreviewImageState extends State<LinkPreviewImage> {
  static const String _kPrefix = 'linkimg:';
  Uint8List? _bytes;
  bool _failed = false;

  String get _key => '$_kPrefix${widget.url}';

  @override
  void initState() {
    super.initState();
    _loadSyncThenAsync();
  }

  @override
  void didUpdateWidget(LinkPreviewImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _failed = false;
      _loadSyncThenAsync();
    }
  }

  void _loadSyncThenAsync() {
    final sync = MediaDiskCache.instance.readSync(_key);
    if (sync != null && sync.isNotEmpty) {
      _bytes = sync;
      return;
    }
    _fetch();
  }

  Future<void> _fetch() async {
    if (widget.url.isEmpty || !widget.url.startsWith('http')) return;
    try {
      // og:image = URL EKSTERNAL (bukan storage) → http.get langsung.
      final res = await http
          .get(Uri.parse(widget.url), headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));
      final bytes = res.statusCode == 200 ? res.bodyBytes : null;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      // Simpan ke disk (fire-and-forget) → persistence.
      unawaited(MediaDiskCache.instance.write(_key, bytes));
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || widget.url.isEmpty) return const SizedBox.shrink();
    final bytes = _bytes;
    if (bytes == null) {
      // Placeholder ringan (anti layout shift) saat memuat.
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(color: AppTheme.bgInput),
      );
    }
    // PROPORSI (fix "gepeng"): pakai rasio ASLI gambar (dari header) + clamp
    // tinggi [minH..maxH] ala Telegram. Dulu tinggi dipaksa 140 + lebar penuh
    // -> cover memotong gambar lebar (16:9) = terlihat gepeng.
    final dims = parseImageDimensions(bytes);
    final double aspect = (dims != null && dims.width > 0 && dims.height > 0)
        ? dims.width / dims.height
        : 16 / 9;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(8),
      ),
      // Batas tinggi = widget.height (mis. 140) supaya kartu tak memanjang;
      // rasio asli tetap dipertahankan (tidak gepeng).
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.height),
        child: AspectRatio(
          // Clamp rasio agar sangat tinggi/lebar tak mendominasi kartu.
          aspectRatio: aspect.clamp(0.8, 2.4),
          child: Image.memory(
            bytes,
            width: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: 480,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
