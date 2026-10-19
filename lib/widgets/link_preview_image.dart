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

  /// Dipanggil setelah rasio ASLI gambar (w/h) diketahui → parent bisa
  /// menyesuaikan LEBAR kartu seperti WhatsApp (foto potret → kartu sempit,
  /// "menyesuaikan konten"), bukan melebar 80% layar.
  final ValueChanged<double>? onAspect;
  const LinkPreviewImage({super.key, required this.url, this.onAspect});

  static const String kPrefix = 'linkimg:';

  /// Rasio ASLI gambar bila bytes-nya sudah ada di cache disk (SINKRON, tanpa
  /// jaringan) → parent menghitung lebar kartu tanpa lompatan layout.
  /// null bila belum ter-cache.
  static double? peekAspect(String url) {
    final b = MediaDiskCache.instance.readSync('$kPrefix$url');
    if (b == null || b.isEmpty) return null;
    final d = parseImageDimensions(b);
    if (d == null || d.width <= 0 || d.height <= 0) return null;
    return d.width / d.height;
  }

  @override
  State<LinkPreviewImage> createState() => _LinkPreviewImageState();
}

class _LinkPreviewImageState extends State<LinkPreviewImage> {
  Uint8List? _bytes;
  bool _failed = false;

  String get _key => '${LinkPreviewImage.kPrefix}${widget.url}';

  /// Kabari parent rasio gambar (untuk lebar kartu adaptif).
  void _emitAspect(Uint8List bytes) {
    final d = parseImageDimensions(bytes);
    if (d == null || d.width <= 0 || d.height <= 0) return;
    widget.onAspect?.call(d.width / d.height);
  }

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
      // Setelah frame — hindari setState parent saat initState/build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emitAspect(sync);
      });
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
      if (mounted) _emitAspect(bytes);
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
    // FLEKSIBEL ala WhatsApp: lebar penuh kartu, TINGGI mengikuti rasio ASLI
    // gambar — termasuk potret/Shorts (9:16) yang tampil TINGGI, bukan dipaksa
    // jadi kotak landscape. Yang dibatasi hanya tinggi ABSOLUT (min 120 supaya
    // banner gepeng tak jadi garis, maks 320 supaya kartu tak mendominasi).
    final dims = parseImageDimensions(bytes);
    final double aspect = (dims != null && dims.width > 0 && dims.height > 0)
        ? dims.width / dims.height
        : 16 / 9;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (_, c) {
          final double w = c.maxWidth.isFinite ? c.maxWidth : 300.0;
          return SizedBox(
            width: double.infinity,
            height: linkPreviewImageHeight(w, aspect),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: 480,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}

/// Tinggi render gambar preview link = lebar / rasio ASLI gambar. LEBAR kartu
/// dihitung parent (adaptif konten ala WhatsApp); di sini tinggi hanya
/// mengikuti lebar itu. Minimum 120 agar banner gepeng tak jadi garis.
@visibleForTesting
double linkPreviewImageHeight(double width, double aspect) {
  final double a = (aspect > 0 && aspect.isFinite) ? aspect : 16 / 9;
  return (width / a).clamp(120.0, 4000.0);
}

/// Lebar kartu link preview ala WhatsApp: tinggi gambar DIBATASI [capHeight],
/// lalu lebar mengikuti rasio ASLI gambar → foto potret menghasilkan kartu
/// yang lebih sempit ("menyesuaikan dengan kontennya"), bukan melebar penuh
/// seperti bubble teks. Tanpa rasio (belum ter-decode) → pakai lebar penuh.
double linkPreviewCardWidth(double maxWidth, double? aspect, double capHeight) {
  if (aspect == null || aspect <= 0 || !aspect.isFinite) return maxWidth;
  final double w = capHeight * aspect;
  return w.clamp(160.0, maxWidth);
}

/// Ikon situs kecil (favicon) di ujung kanan baris domain kartu link
/// (ala WhatsApp). Cache DISK sama dengan [LinkPreviewImage]; ukuran TETAP
/// [size] (placeholder kosong ukuran sama → tanpa lompatan layout); gagal /
/// format tak didukung → ruang kosong (bukan ikon rusak).
class LinkPreviewIcon extends StatefulWidget {
  final String url;
  final double size;
  final BoxFit fit;
  final double radius;
  const LinkPreviewIcon({
    super.key,
    required this.url,
    this.size = 18,
    this.fit = BoxFit.contain,
    this.radius = 4,
  });

  @override
  State<LinkPreviewIcon> createState() => _LinkPreviewIconState();
}

class _LinkPreviewIconState extends State<LinkPreviewIcon> {
  static const String _kPrefix = 'linkicon:';
  Uint8List? _bytes;
  bool _failed = false;

  String get _key => '$_kPrefix${widget.url}';

  @override
  void initState() {
    super.initState();
    final sync = MediaDiskCache.instance.readSync(_key);
    if (sync != null && sync.isNotEmpty) {
      _bytes = sync;
    } else {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (!widget.url.startsWith('http')) return;
    try {
      final res = await http
          .get(Uri.parse(widget.url), headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 8));
      final ct = res.headers['content-type'] ?? '';
      final bytes = res.statusCode == 200 ? res.bodyBytes : null;
      // HTML (halaman error/redirect) bukan ikon → anggap gagal.
      if (bytes == null || bytes.isEmpty || ct.contains('text/html')) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      unawaited(MediaDiskCache.instance.write(_key, bytes));
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final bytes = _bytes;
    if (_failed || bytes == null) return SizedBox(width: s, height: s);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Image.memory(
        bytes,
        width: s,
        height: s,
        fit: widget.fit,
        // Decode sesuai ukuran tampil (favicon 18 → 64; thumbnail besar →
        // s.d. 256) supaya thumbnail besar tidak buram.
        cacheWidth: (s * 3).round().clamp(64, 256).toInt(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => SizedBox(width: s, height: s),
      ),
    );
  }
}
