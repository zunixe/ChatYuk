import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';
import '../../core/cache/photo_aspect_cache.dart';
import '../../core/cache/photo_cache.dart';
import '../../core/media/chat_photo_helper.dart';
import '../../core/media/native_image.dart';
import '../../core/storage_paths.dart';
import '../../providers/riverpod/service_locator.dart';
import '../../providers/riverpod/locale_provider.dart';
import 'image_decode_core.dart';
import 'photo_viewer_screen.dart';

/// base64→bytes di isolate (lihat [_decode]: fallback dims). Top-level agar
/// bisa dipakai `compute` (spawn isolate per panggilan — hanya jalur fallback
/// saat parse header gagal, bukan jalur utama).
Uint8List _b64Decode(String b64) => base64Decode(b64);

class MessageImage extends StatefulWidget {  final String imageData;
  final String chatKey;
  final String messageId;
  /// Lapor lebar render foto (200 atau `tinggi*aspect` bila tinggi dibatasi
  /// 280) agar caption+jam bisa rata kanan sejajar tepi foto.
  final ValueChanged<double>? onRenderedWidth;
  /// true = isi penuh kotak parent (tanpa sudut membulat) — dipakai tile
  /// album ala WhatsApp. Ukuran mengikuti constraint parent.
  final bool fill;

  /// Album/grup foto: daftar `imageData` + `messageId` semua foto dalam
  /// pesan yang sama (urut kronologis). Bila diisi (>1), tap foto membuka
  /// viewer yang bisa di-SWIPE VERTIKAL antar foto, mulai dari foto ini.
  final List<({String imageData, String messageId})>? gallery;

  /// Index foto ini di dalam [gallery].
  final int galleryIndex;

  /// Tile ALBUM (isi penuh) → placeholder SENYAP (tanpa spinner) & tanpa
  /// fade: buka chat album tidak "kedip" berulang (spinner×4 + fade×4).
  bool get _albumTile => fill;

  const MessageImage({
    super.key,
    required this.imageData,
    required this.chatKey,
    required this.messageId,
    this.onRenderedWidth,
    this.fill = false,
    this.gallery,
    this.galleryIndex = 0,
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
  // FADE DIHAPUS (2026-10-17): memudar 180ms terasa "kedip" di chat — foto
  // kini muncul UTUH. Spinner pun DITUNDA 250ms: load cepat (cache/disk)
  // selesai sebelum spinner sempat tampil → tak ada kilatan spinner.
  bool _showSpinner = false;
  Timer? _spinnerTimer;

  static const Duration _spinnerDelay = Duration(milliseconds: 250);

  /// Mulai penundaan spinner (spinner hanya tampil bila MASIH memuat).
  void _scheduleSpinner() {
    _spinnerTimer?.cancel();
    _showSpinner = false;
    _spinnerTimer = Timer(_spinnerDelay, () {
      if (mounted && _loading) setState(() => _showSpinner = true);
    });
  }
  // Lebar terakhir yang dilaporkan ke parent (hindari callback berulang).
  double _reportedWidth = -1;

  /// Lebar kotak foto = 72% lebar layar. Nilai diperbarui di
  /// `didChangeDependencies` (MediaQuery tersedia) DAN di build (aman bila
  /// ukuran layar berubah: rotasi / split-screen).
  double _targetW = 260;

  /// Segerkan lebar target dari context (72% lebar layar).
  void _ensureTargetW(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final t = chatMediaWidth(screenW);
    if ((t - _targetW).abs() <= 0.5) return;
    _targetW = t;
    // Ukuran placeholder (frame loading) ikut disesuaikan supaya tidak ada
    // lompatan layout dari default → 72% layar. Bila bitmap belum ada,
    // hitung ulang dari HEADER gambar (murah, tak decode penuh).
    if (_decoded != null) {
      _syncSizes();
    } else {
      _reservePlaceholder(widget.imageData);
    }
    _reportedWidth = -1; // paksa lapor ulang lebar final ke parent
  }

  /// Ukuran kotak foto sesuai aspek + lebar target (72% layar).
  /// [w]/[h] boleh 0 → placeholder kotak mengikuti lebar target.
  ({double width, double height}) _sizeOf(int w, int h) =>
      chatPhotoSize(w, h, _targetW);

  /// Sinkronkan SEMUA ukuran tersimpan dengan lebar target terkini.
  void _syncSizes() {
    final d = _decoded;
    if (d != null && d.width > 0 && d.height > 0) {
      final s = _sizeOf(d.width, d.height);
      _phW = s.width;
      _phH = s.height;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lebar target (72% layar) harus siap SEBELUM frame pertama agar
    // placeholder & hasil akhir memakai ukuran sama (anti layout shift).
    _ensureTargetW(context);
    // initState (tanpa MediaQuery) memakai default → segarkan placeholder di
    // sini supaya ukuran frame pertama sudah 72% layar.
    _syncSizes();
  }

  @override
  void initState() {
    super.initState();
    final key = widget.imageData.hashCode;
    _decoded = getDecodedCache(key);
    // Fallback THUMB by messageId (di-precache saat tap) — dipakai saat cold
    // start di mana `imageData` kosong (base64 ter-strip dari cache pesan).
    // Tanpa ini, bubble kosong dulu lalu thumb muncul = "ngeload/kedip".
    if (_decoded == null && widget.messageId.isNotEmpty) {
      _decoded = getDecodedCache('thumb:${widget.messageId}'.hashCode);
    }
    if (_decoded == null) {
      _loading = true;
      _scheduleSpinner();
      // Aspek yang PERNAH diketahui (cache persisten) → kotak frame pertama
      // sudah final (tidak kotak persegi lalu melompat).
      final known = widget.messageId.isEmpty
          ? null
          : PhotoAspectCache.instance.aspectOf(widget.messageId);
      if (known != null && known > 0) {
        final sz = _sizeOf(1000, (1000 / known).round());
        _phW = sz.width;
        _phH = sz.height;
      } else {
        _reservePlaceholder(widget.imageData);
      }
      _decode(key, ++_gen);
    } else {
      _loading = false;
      final s = _sizeOf(_decoded!.width, _decoded!.height);
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
    _spinnerTimer?.cancel();
    _spinnerTimer = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // imageData berubah (fetch awal kosong → photo download selesai) → re-decode
    if (widget.imageData != oldWidget.imageData &&
        widget.imageData.isNotEmpty) {
      final key = widget.imageData.hashCode;
      final hit = getDecodedCache(key);
      // ANTI-KEDIP (2026-10-14, terbukti dari log HP): alur nyata saat buka
      // chat = frame-1 `imageData` masih PATH storage (initState ambil thumb
      // via `thumb:<id>` → foto SUDAH tampil), lalu ~100ms kemudian batch
      // `loadPhotosAsync` menimpa `imageData` → base64 thumb yang isinya SAMA.
      // "kedip" (fade ulang 180ms). Sekarang: bila bitmap yang SEDANG tampil
      // sudah ada (`_decoded != null`) & belum berubah besar, cukup re-key
      // cache ke kunci baru — NOL setState, NOL fade, NOL decode ulang.
      if (_decoded != null &&
          _decoded!.width > 0 &&
          _decoded!.height > 0 &&
          !_decoded!.disposed) {
        // Thumb yang sedang tampil = resolusi sama dgn thumb yang akan
        // di-inject (batch mengisi thumb, bukan full-res) → aman dipertahankan.
        if (hit == null) putDecodedCache(key, _decoded!);
        // Re-key juga jalur thumb:id agar konsisten ke depan.
        if (widget.messageId.isNotEmpty) {
          putDecodedCache('thumb:${widget.messageId}'.hashCode, _decoded!);
        }
        _reservePlaceholder(widget.imageData);
        return;
      }
      // Cadangkan aspek baru segera (sinkron) bila base64; path → ukuran lama
      // dipertahankan (gapless) sampai download memberi aspek sebenarnya.
      _reservePlaceholder(widget.imageData);
      if (hit != null) {
        _gen++;
        // Konten lama sudah di memori → tampil langsung (tanpa fade).
        if (mounted) {
          setState(() {
            _decoded = hit;
            _loading = false;
            final s = _sizeOf(hit.width, hit.height);
            _phW = s.width;
            _phH = s.height;
          });
        }
      } else {
        // JANGAN kosongkan _decoded — foto lama tetap tampil sampai yang baru
        // siap (persistence, anti kedip). Hanya tandai loading untuk spinner
        // bila memang belum ada gambar sama sekali (lihat build).
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
      final s = _sizeOf(dims.width, dims.height);
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
            PhotoAspectCache.instance.remember(
              widget.messageId,
              thumbDims.width,
              thumbDims.height,
            );
            // Bitmap thumb di latar → RawImage pada render berikutnya.
            unawaited(attachDecodedImage(td, targetWidth: 720).then((_) {
              if (mounted &&
                  gen == _gen &&
                  !td.disposed &&
                  td.image != null) {
                setState(() {});
              }
            }));
                  setState(() {
              _decoded = td;
              _loading = false;
              final s = _sizeOf(thumbDims.width, thumbDims.height);
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
    final contentHit = getDecodedCache(data.hashCode);
    if (contentHit != null && contentHit.width > 0 && contentHit.height > 0) {
      putDecodedCache(key, contentHit);
      if (!mounted || gen != _gen) return;
      // Isi sama sudah ada di memori → tampil langsung (tanpa fade).
      setState(() {
        _decoded = contentHit;
        _loading = false;
        final s = _sizeOf(contentHit.width, contentHit.height);
        _phW = s.width;
        _phH = s.height;
      });
      return;
    }
    // Aspek sudah bisa dicadangkan dari data yang baru diunduh (sebelum
    // decode penuh) — placeholder menyesuaikan sekali ke bentuk benar,
    // piksel menyusul fade-in tanpa lompatan lagi.
    // ZERO-JANK: fallback base64Decode FULL di-isolate (compute) — dulu di
    // main isolate → CPU berat di UI thread untuk foto besar tepat saat
    // bubble tampil. Header prefix (kecil) tetap sync di sini (murah).
    try {
      var dims = parseImageDimensions(_decodeHeaderPrefix(data));
      dims ??= parseImageDimensions(await compute(_b64Decode, data));
      if (dims != null && mounted && gen == _gen) {
        final s = _sizeOf(dims.width, dims.height);
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
    PhotoAspectCache.instance.remember(
      widget.messageId,
      decoded.width,
      decoded.height,
    );
    // Set state SEKARANG (fallback Image.memory render instan), lalu decode
    // bitmap di latar → begitu siap, RawImage dipakai (nol decode) pada render
    // berikutnya. TIDAK menunggu (agar tak gantung bila codec lambat/gagal).
    unawaited(attachDecodedImage(decoded, targetWidth: 720).then((_) {
      if (mounted &&
          gen == _gen &&
          !decoded.disposed &&
          decoded.image != null) {
        setState(() {});
      }
    }));
    if (!mounted || gen != _gen) return;
    // Piksel BARU didecode (belum pernah tampil di layar ini) → fade-in halus
    // supaya kemunculan tidak "pop". Bila ini sekadar re-decode isi yang sama
    // (sudah ditangani `contentHit`/`_decoded!=null` di atas), tak sampai sini.
    setState(() {
      _decoded = decoded;
      _loading = false;
      final s = _sizeOf(decoded.width, decoded.height);
      _phW = s.width;
      _phH = s.height;
    });
  }

  void _retry() {
    final key = widget.imageData.hashCode;
    setState(() {
      _loading = true;
    });
    _scheduleSpinner();
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
    _ensureTargetW(context);
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final decoded = _decoded;
    // Segarkan ukuran placeholder SEBELUM dipakai di frame ini (targetW
    // baru saja diperbarui dari MediaQuery).
    _syncSizes();
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      // Foto biasa: belum keload = spinner; gagal = "ketuk untuk memuat".
      // JANGAN pakai tulisan expired di sini — itu hanya untuk view-once.
      // Ukuran = cadangan aspek foto (bukan kotak 200×200) + lebar dilaporkan
      // ke parent supaya caption langsung pas dari frame pertama.
      _reportWidth(_phW);
      return GestureDetector(
        onTap: _loading ? null : _retry,
        child: Container(
          width: widget.fill ? double.infinity : _phW,
          height: widget.fill ? double.infinity : _phH,
          color: AppTheme.bgInput,
          alignment: Alignment.center,
          child: _loading
              ? ((widget._albumTile || !_showSpinner)
                    // Album ATAU masih <250ms → placeholder SENYAP (kotak
                    // warna saja, tanpa spinner) supaya tidak ada kilatan.
                    ? const SizedBox.shrink()
                    : const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppTheme.primary,
                        ),
                      ))
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
    final size = _sizeOf(decoded.width, decoded.height);
    final width = widget.fill ? double.infinity : size.width;
    final height = widget.fill ? double.infinity : size.height;
    // Lapor lebar render ke parent (sekali / berubah) → caption+jam rata kanan
    // sejajar tepi foto.
    if (!widget.fill) _reportWidth(width);
    return GestureDetector(
      onTap: () => _openFullscreen(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.fill ? 0 : 10),
        // THUMBNAIL TIDAK BISA zoom/geser (2026-10-11): dulu pakai
        // InteractiveViewer + onDoubleTap zoom → foto di bubble bisa membesar
        // & digeser padahal hanya thumbnail. Zoom/geser HANYA di fullscreen
        // viewer (PhotoViewerScreen). Di sini cukup tap → buka fullscreen.
        child: _bubbleImage(context, decoded, width, height, s),
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
    // CEPAT (contek video): bila bitmap siap (ui.Image), render via RawImage
    // = NOL decode saat render (foto secepat video). Fallback Image.memory
    // bila bitmap belum di-decode.
    // GUARD (R10): `decoded.disposed` → bitmap sudah dilepas → JANGAN render
    // RawImage (crash "disposed image"); jatuh ke Image.memory(bytes).
    final img = decoded.disposed ? null : decoded.image;
    if (img != null) {
      return RawImage(
        image: img,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    }
    return Image.memory(
      decoded.bytes,
      width: width,
      height: height,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      // Decode max 1080px (bukan full-res 12MP): bubble max 280px,
      // zoom inline 6x tetap tajam; hemat ~6x RAM bitmap.
      cacheWidth: 720,
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

  /// Thumbnail viewer untuk satu foto galeri. Bila bitmapnya sudah ada di
  /// cache mem → pakai langsung (instan); bila belum, ambil dari thumbnail
  /// disk/cache; bila tetap tidak ada, pakai bitmap foto yang sedang dibuka
  /// sebagai placeholder (agar frame pertama viewer tidak hitam).
  Uint8List _thumbFor(int i, Uint8List fallback) {
    final g = widget.gallery!;
    for (final key in [g[i].imageData.hashCode, g[i].messageId.hashCode]) {
      final d = getDecodedCache(key);
      if (d != null && d.bytes.isNotEmpty) return d.bytes;
    }
    return fallback;
  }

  List<ViewerPhoto> _buildGallery() {
    final g = widget.gallery!;
    final self = _decoded!.bytes;
    final selfIdx = widget.galleryIndex.clamp(0, g.length - 1);
    final sameChat = widget.chatKey.isNotEmpty;
    return [
      for (var i = 0; i < g.length; i++)
        ViewerPhoto(
          bytes: i == selfIdx ? self : _thumbFor(i, self),
          fullLoader: (i == selfIdx || sameChat)
              ? () => PhotoCache.instance.load(widget.chatKey, g[i].messageId)
              : null,
        ),
    ];
  }

  void _openFullscreen() {
    final decoded = _decoded;
    if (decoded == null || !mounted) return;
    final gallery =
        (widget.gallery != null && widget.gallery!.length > 1)
        ? _buildGallery()
        : null;
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
          photos: gallery,
          initialIndex: gallery == null
              ? 0
              : widget.galleryIndex.clamp(0, gallery.length - 1),
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
