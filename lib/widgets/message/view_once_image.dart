import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme.dart';
import '../../utils.dart';
import '../../core/cache/photo_cache.dart';
import '../../core/media/chat_photo_helper.dart';
import '../../core/media/native_image.dart';
import '../../core/screen_secure_service.dart';
import '../../providers/riverpod/chat_provider.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../core/storage_paths.dart';
import '../../providers/riverpod/service_locator.dart';
import '../chat_video_bubble.dart';
import 'image_decode_core.dart';
import 'photo_viewer_screen.dart';
import 'view_once_state.dart';

class ViewOnceImage extends StatefulWidget {
  final String imageData;
  final String chatKey;
  final bool isMe;
  final String? messageId;

  /// Durasi view-once detik dari pesan (durationMs): null = legacy 10 dtk,
  /// 0 = sampai ditutup (1x lihat).
  final int? viewSecs;
  final bool isExpired;
  // Admin monitor: lewati kartu "expired" — foto tetap bisa dilihat.
  final bool isAdminView;
  // Room chat pakai tabel 'messages', private pakai 'private_messages'.
  final bool isRoom;

  /// Batas lebar (px) dari induk. Dipakai kartu foto SEKALI-LIHAT yang
  /// merespons balasan (media di kiri, panel teks di kanan) — tanpa ini
  /// kartu selebar 72% layar tetap dipaksa ke dalam Row yang sempit →
  /// overflow vertikal (kartu di-clip lebar tapi tinggi dari rasio asli).
  final double? mediaMaxWidth;

  const ViewOnceImage({
    super.key,
    required this.imageData,
    required this.chatKey,
    required this.isMe,
    this.messageId,
    this.viewSecs,
    this.isExpired = false,
    this.isAdminView = false,
    this.isRoom = false,
    this.mediaMaxWidth,
  });

  @override
  State<ViewOnceImage> createState() => _ViewOnceImageState();
}

class _ViewOnceImageState extends State<ViewOnceImage> {
  /// Lebar nyata yang diberikan induk (diisi LayoutBuilder di [build]).
  /// Dipakai agar kartu tidak pernah lebih lebar dari bubble.
  double? _availW;
  late ViewOnceTick _tick;
  DecodedImage? _decoded;

  /// Sedang decode (cegah pemanggilan ganda dari initState+didUpdateWidget).
  bool _decoding = false;
  /// Decode/download GAGAL → tampilkan kartu "coba lagi" (dulu spinner abadi).
  bool _failed = false;
  /// Percobaan decode otomatis (retry terbatas untuk path storage yang belum
  /// siap / jaringan lambat).
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    // Admin monitor: bypass global viewOnceStates — tidak perlu timer/expired.
    // Decode langsung dari imageData (yang sekarang selalu utuh di DB).
    if (widget.isAdminView) {
      if (widget.imageData.isNotEmpty) _decodeAdmin();
      return;
    }
    final id = widget.messageId ?? 'pending-${widget.imageData.hashCode}';
    _tick = putViewOnceState(id, ViewOnceTick());
    if (widget.viewSecs != null) {
      _tick.totalSecs = resolveViewOnceSecs(widget.viewSecs);
    }
    if (widget.isExpired) {
      // SERVER sudah menandai kadaluarsa → kunci permanen SEBELUM frame
      // pertama. WAJIB juga menimpa state CACHE (dulu `putViewOnceState`
      // mengembalikan tick lama yang mungkin masih `idle`/`viewing` → isi
      // foto sempat tergambar sekejap lalu berubah jadi kartu = BLINK saat
      // masuk chat). `setSyncronous` supaya frame pertama sudah terkunci.
      _tick
        ..state = ViewOnceState.expired
        ..decoded = null
        ..timer?.cancel();
      _decoded = null;
      return;
    }
    _decoded = _tick.decoded;
    if (_decoded == null) _decode();
  }

  @override
  void didUpdateWidget(ViewOnceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAdminView) {
      if (widget.imageData.isNotEmpty &&
          widget.imageData != oldWidget.imageData) {
        _decodeAdmin();
      }
      return;
    }
    if (widget.isExpired) {
      // Kadaluarsa: kunci permanen + BUANG byte foto yang mungkin sudah
      // ter-decode, supaya isinya tidak pernah ter-render lagi.
      _tick.state = ViewOnceState.expired;
      _tick.decoded = null;
      _decoded = null;
      ScreenSecureService.exitViewOnce();
      setState(() {});
      return;
    }
    if (_tick.state == ViewOnceState.expired) return;
    if (widget.imageData != oldWidget.imageData &&
        widget.imageData.isNotEmpty) {
      _decoded = _tick.decoded;
      if (_decoded == null) {
        // Data baru masuk (mis. hasil download latar) → reset status gagal
        // dan decode ulang.
        _attempts = 0;
        _failed = false;
        _decode();
      }
    }
  }

  Future<void> _decodeAdmin() async {
    var data = widget.imageData;
    // imageData bisa berupa PATH storage (foto baru) → download dari bucket.
    if (data.isNotEmpty && isStoragePathValue(data)) {
      data = await safeStorage(context).download(data) ?? '';
    }
    if (data.isEmpty) return;
    final res = await NativeImage.decodeWithDims(data);
    if (!mounted) return;
    setState(() {
      _decoded = res == null
          ? null
          : DecodedImage(res.bytes, res.width, res.height);
    });
  }

  @override
  void dispose() {
    // Jangan dispose _tick selagi aktif — timer harus terus jalan via
    // viewOnceStates (mis. viewer masih terbuka / countdown berjalan, dan
    // widget bisa di-rebuild sementara state tetap hidup).
    //
    // TAPI: kalau sudah EXPIRED, state tidak dibutuhkan lagi (media hilang,
    // kartu terkunci permanen). Sebelumnya entri ini dibiarkan di map selamanya
    // → `viewOnceStates` tumbuh tanpa batas (tiap view-once menahan Timer +
    // DecodedImage=byte gambar) → memori naik terus sepanjang sesi. Sekarang
    // entri expired dibersihkan saat widget-nya dibuang.
    final id = widget.messageId;
    // Mode admin tidak memakai `_tick` (lihat initState) — jangan sentuh.
    if (!widget.isAdminView && id != null && _tick.state == ViewOnceState.expired) {
      if (identical(viewOnceStates[id], _tick)) {
        viewOnceStates.remove(id);
      }
      _tick.dispose();
    }
    super.dispose();
  }

  Future<void> _decode() async {
    if (_decoding) return;
    // View-once SUDAH expired (server tandai type='view_once_expired') —
    // WAJIB terkunci permanen, apapun isi imageData. Jangan decode/tampil.
    if (widget.isExpired) {
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      if (mounted) setState(() {});
      return;
    }
    _decoding = true;
    if (mounted && _failed) setState(() => _failed = false);
    var ok = false;
    try {
      ok = await _decodeAttempt();
    } finally {
      _decoding = false;
    }
    if (!mounted) return;
    if (ok) return;
    // Gagal: coba lagi otomatis terbatas (path storage kadang belum siap /
    // jaringan lambat). Setelah habis → tampilkan kartu "coba lagi", BUKAN
    // spinner berputar selamanya.
    _attempts++;
    if (_attempts < 3) {
      await Future<void>.delayed(Duration(seconds: 2 * _attempts));
      if (!mounted) return;
      return _decode();
    }
    if (mounted) setState(() => _failed = true);
  }

  /// Satu percobaan decode. Return true bila `_decoded` berhasil diisi.
  Future<bool> _decodeAttempt() async {
    var data = widget.imageData;
    dlog('[VO-DBG] decode id=${widget.messageId} '
        'srcLen=${data.length} isPath=${isStoragePathValue(data)}');
    // CACHE LOKAL DULU (instan, tanpa jaringan): pengirim baru saja mengirim
    // foto ini → PhotoCache sudah berisi bytes-nya. Dulu path storage
    // di-download dulu → bubble sempat menampilkan spinner ("blink") sebelum
    // foto muncul. Kini cache dipakai lebih dulu.
    final id = widget.messageId;
    final canUseCache = id != null && !id.startsWith('pending-');
    if (canUseCache) {
      try {
        final cached = await PhotoCache.instance.load(widget.chatKey, id);
        if (cached != null && cached.isNotEmpty) {
          data = cached;
          dlog('[VO-DBG] cache hit len=${data.length}');
        }
      } catch (_) {}
    }
    // MASIH kosong → ambil path langsung dari DB (view-once TIDAK di-auto-
    // prefetch oleh loadPhotosAsync, dan cols list tak memuat image_data →
    // widget.imageData = ''). Tanpa ini foto sekali-lihat tak pernah termuat
    // (spinner/gagal walau file ada di storage).
    if (data.isEmpty && canUseCache && mounted) {
      try {
        final sb = Supabase.instance.client;
        final table = widget.isRoom ? 'messages' : 'private_messages';
        final row = await sb
            .from(table)
            .select('image_data,image_path')
            .eq('id', id)
            .maybeSingle();
        final raw = (row?['image_data'] as String? ?? '');
        data = raw.isNotEmpty
            ? raw
            : (row?['image_path'] as String? ?? '');
        dlog('[VO-DBG] db fetch len=${data.length}');
      } catch (e) {
        dlog('[VO-DBG] db fetch error: $e');
      }
    }
    // Data bisa berupa PATH storage → download dulu sebelum decode.
    if (data.isNotEmpty && isStoragePathValue(data)) {
      if (!mounted) return false;
      final path = data;
      data = await safeStorage(context).download(path) ?? '';
      dlog('[VO-DBG] download path=$path -> len=${data.length}');
      // Download gagal → coba cache disk/memori lokal untuk path ini.
      if (data.isEmpty) {
        try {
          data = await PhotoCache.instance.load(widget.chatKey,
                  widget.messageId ?? '') ??
              '';
          dlog('[VO-DBG] download-fail cache fallback len=${data.length}');
        } catch (_) {}
      }
    }
    // Masih kosong → gagal (pemanggil menentukan retry/kartu gagal).
    if (data.isEmpty) {
      dlog('[VO-DBG] FAIL: data kosong');
      return false;
    }
    final res = await NativeImage.decodeWithDims(data);
    dlog('[VO-DBG] decode res=${res == null ? "null" : "${res.width}x${res.height}"}');
    if (res == null || res.width <= 0 || res.height <= 0) return false;
    if (!mounted) return false;
    // Kadaluarsa bisa terjadi SAAT decode berjalan (mis. realtime masuk) →
    // jangan pernah simpan/tampilkan foto setelah expired.
    if (widget.isExpired || _tick.state == ViewOnceState.expired) {
      return false;
    }
    final decoded = DecodedImage(res.bytes, res.width, res.height);
    _tick.decoded = decoded;
    setState(() => _decoded = decoded);
    // Kalau user sudah tap "Lihat" sebelum gambar siap → mulai timer sekarang
    if (_tick.state == ViewOnceState.viewing && _tick.timer == null) {
      _beginCountdown();
    }
    return true;
  }

  /// Tap kartu gagal → reset & coba decode lagi.
  void _retry() {
    _attempts = 0;
    _failed = false;
    setState(() {});
    _decode();
  }

  void _startViewing() {
    if (_tick.state != ViewOnceState.idle) return;
    _tick.state = ViewOnceState.viewing;
    setState(() {});
    ScreenSecureService.enterViewOnce();
    // Mulai timer hanya kalau gambar sudah siap — kalau belum, nunggu _decode selesai
    if (_decoded != null) {
      _beginCountdown();
    }
  }

  void _beginCountdown() {
    if (_tick.timer != null) return;
    // Mode 1x (totalSecs 0): tanpa timer — kedaluwarsa saat viewer ditutup.
    if (_tick.totalSecs <= 0) return;
    _tick.left = _tick.totalSecs;
    _tick.countdown.value = _tick.totalSecs;
    _tick.timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _tick.left--;
      _tick.countdown.value = _tick.left;
      if (_tick.left <= 0) {
        t.cancel();
        _tick.timer = null;
        if (_tick.viewerOpen && mounted) Navigator.of(context).maybePop();
        _expireNow();
        return;
      }
      if (mounted) setState(() {});
    });
  }

  /// Kunci permanen + bersihkan server (dipakai timer habis & viewer 1x ditutup).
  void _expireNow() {
    if (!mounted) return;
    _tick.state = ViewOnceState.expired;
    ScreenSecureService.exitViewOnce();
    setState(() {});
    _clearFromServer();
  }

  /// Loader HD dibuang: kualitas ditentukan saat KIRIM (toggle HD di
  /// preview composer), bukan lagi di viewer.

  void _openViewer() {
    if (_decoded == null || _tick.state != ViewOnceState.viewing || !mounted) {
      return;
    }
    _tick.viewerOpen = true;
    // SAMA seperti lihat foto biasa: fullscreen PhotoViewerScreen (bukan
    // bottom-sheet slide dari bawah). Countdown view-once tetap diteruskan.
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PhotoViewerScreen(
              bytes: _decoded!.bytes,
              countdown: _tick.totalSecs > 0 ? _tick.countdown : null,
            ),
          ),
        )
        .whenComplete(() {
          _tick.viewerOpen = false;
          // Mode 1x: viewer ditutup = sudah dilihat → kunci permanen.
          if (_tick.totalSecs <= 0 && _tick.state == ViewOnceState.viewing) {
            _expireNow();
          }
        });
  }

  Future<void> _clearFromServer() async {
    final id = widget.messageId;
    if (id == null || id.startsWith('pending-')) return;
    try {
      // chatId dikirim supaya server juga menyiarkan broadcast
      // `view_once_seen` → PENGIRIM langsung mengunci kartu (realtime).
      final chatId = widget.chatKey.startsWith('private_')
          ? widget.chatKey.substring('private_'.length)
          : '';
      await ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier).clearViewOnceImage(
        id,
        isRoom: widget.isRoom,
        chatId: chatId.isEmpty ? null : chatId,
      );
    } catch (_) {}
  }

  Widget _buildAdminView(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final decoded = _decoded;
    final size = _sizeFor(
      context,
      decoded,
      widget.imageData,
      maxWidth: _limitW,
    );
    final w = size.width;
    final h = size.height;
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            decoded != null
                ? Image.memory(
                    decoded.bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    // Thumb bubble: decode max 720px + filter sedang.
                    // Full-res 12MP = ~48MB bitmap; 720px = ~2MB.
                    cacheWidth: 720,
                    filterQuality: FilterQuality.medium,
                  )
                      : Container(
                          // Placeholder NETRAL (tanpa card/spinner) — foto
                          // muncul dari cache lokal dalam sepersekian detik;
                          // dulu spinner terlihat sebagai "blink card".
                          color: AppTheme.bgInput,
                        ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      s.msgViewOnce,
                      style: AppText.chatTime.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (decoded == null) return child;
    final zoomBytes = decoded.bytes;
    return GestureDetector(
      onTap: () {
        // Fullscreen seperti foto biasa (admin monitor tidak pakai timer).
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => PhotoViewerScreen(bytes: zoomBytes),
              ),
            )
            .whenComplete(() {
              // Keluarkan bitmap zoom dari ImageCache (pola PhotoViewerScreen).
              if (zoomBytes.isNotEmpty) {
                try {
                  PaintingBinding.instance.imageCache.evict(
                    MemoryImage(zoomBytes),
                  );
                } catch (_) {}
              }
            });
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAdminView) return _buildAdminView(context);
    // Batas lebar NYATA dari induk (bubble bisa lebih sempit dari 72% layar)
    // → kartu tidak pernah lebih lebar dari ruang yang tersedia.
    return LayoutBuilder(
      builder: (context, box) {
        _availW = box.maxWidth;
        return ValueListenableBuilder<ViewOnceState>(
      valueListenable: _tick.stateNotifier,
      builder: (_, st, _) {
        final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;

        // Pengirim lihat foto asli + badge
        if (widget.isMe) {
          // View-once terkunci (data sudah tidak tersedia) → kartu terkunci, bukan spinner
          if (_tick.state == ViewOnceState.expired) {
            // Kartu kedaluwarsa = KECIL 200×140 (default ViewOnceLockedCard).
            return ViewOnceLockedCard(
              title: s.viewOnceExpired,
              hint: s.viewOnceExpiredHint,
            );
          }
          final decoded = _decoded;
          final size = _sizeFor(
      context,
      decoded,
      widget.imageData,
      maxWidth: _limitW,
    );
          final w = size.width;
          final h = size.height;
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  decoded != null
                      ? Image.memory(
                          decoded.bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          cacheWidth: 720,
                          filterQuality: FilterQuality.medium,
                        )
                      : _InstantBytes(
                          // PENGIRIM: byte foto sudah ada lokal → tampilkan
                          // LANGSUNG (tanpa kartu besar + spinner). Dulu
                          // muncul kotak abu besar dulu baru foto =
                          // "ada card besar dulu" (minta user 2026-10-20).
                          data: widget.imageData,
                        ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            s.msgViewOnce,
                            style: AppText.chatTime.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Penerima — idle: kartu modern "tekan untuk melihat"
        if (_tick.state == ViewOnceState.idle) {
          return GestureDetector(
            onTap: _startViewing,
            child: Container(
              // Kartu PEMBUKA (tulisan "Foto Sekali Lihat") = KECIL 200×140
              // seperti semula. Hanya kartu yang MENAMPILKAN foto yang
              // mengikuti ukuran foto biasa.
              width: ViewOnceLockedCard.cardWidth,
              height: ViewOnceLockedCard.cardHeight,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryDark, AppTheme.accent],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              // Isi RINGKAS supaya pas di 176×120 (dalam kartu 200×140 —
              // ukuran sama dengan kartu kedaluwarsa).
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    child: const Icon(
                      Icons.remove_red_eye_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.viewOnceTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.chatBodySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.viewOnceTap(_tick.totalSecs),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.chatCaption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Expired — kartu terkunci (tanpa image — hemat memori & tidak load foto)
        if (_tick.state == ViewOnceState.expired) {
          // Kartu kedaluwarsa = KECIL 200×140.
          return ViewOnceLockedCard(
            title: s.viewOnceExpired,
            hint: s.viewOnceExpiredHint,
          );
        }

        // Viewing — tampilkan foto proporsional + countdown; tap untuk memperbesar
        final decoded = _decoded;
        // Decode/download gagal → kartu "coba lagi" (dulu spinner abadi).
        if (decoded == null && _failed) {
          return GestureDetector(
            onTap: _retry,
            child: ViewOnceLockedCard(
              title: s.errPhotoRead,
              hint: s.btnRetry,
              icon: Icons.refresh_rounded,
            ),
          );
        }
        final size = _sizeFor(
      context,
      decoded,
      widget.imageData,
      maxWidth: _limitW,
    );
        final vw = size.width;
        final vh = size.height;
        return GestureDetector(
          onTap: _openViewer,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: vw,
              height: vh,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  decoded != null
                      ? Image.memory(
                          decoded.bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          cacheWidth: 720,
                          filterQuality: FilterQuality.medium,
                        )
                      : Container(
                          color: AppTheme.bgInput,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          ValueListenableBuilder<int>(
                            valueListenable: _tick.countdown,
                            builder: (_, v, _) => Text(
                              _tick.totalSecs <= 0 ? '1×' : '${v}s',
                              style: AppText.chatName.copyWith(
                                color: Colors.white,
                                letterSpacing: 0,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
        );
      },
    );
  }

  // Ukuran kartu FOTO SEKALI-LIHAT = SAMA dengan kartu FOTO BIASA:
  // lebar `chatMediaWidth` (72% layar) dan tinggi mengikuti aspek foto
  // (`chatPhotoSize`). Saat foto belum ada (kartu "tekan untuk melihat" /
  // kedaluwarsa) dipakai kotak placeholder yang sama supaya ukurannya tidak
  // berubah-ubah. (Minta user: jangan mengikuti kartu bertulisan
  // "Foto Sekali Lihat" yang kecil.)
  static double _mediaWidth(BuildContext context) =>
      chatMediaWidth(MediaQuery.sizeOf(context).width);

  /// Batas lebar efektif: yang TERKECIL antara `mediaMaxWidth` dari pemanggil
  /// (mis. lebar panel saat media berbalasan) dan lebar nyata LayoutBuilder.
  double? get _limitW {
    final a = widget.mediaMaxWidth;
    final b = _availW;
    if (a == null) return b;
    if (b == null) return a;
    return a < b ? a : b;
  }



  /// Ukuran kartu = UKURAN FOTO (lebar 72% layar, tinggi mengikuti RASIO
  /// FOTO asli) — bukan kotak poster/placeholder. Bila dimensi foto sudah
  /// diketahui (header imageData) dipakai meski bitmap belum ter-decode,
  /// supaya kartu "tekan untuk melihat" & kartu terkunci PUNYA tinggi yang
  /// sama dengan foto aslinya (tidak gepeng/poster).
  /// Dimensi foto dari `imageData` (base64 atau path file) — baca HEADER saja
  /// (JPEG SOF / PNG IHDR), tanpa decode penuh.
  static ({int width, int height})? _dimsOf(String imageData) {
    if (imageData.isEmpty) return null;
    try {
      Uint8List? bytes;
      if (imageData.startsWith('/')) {
        final f = File(imageData);
        if (!f.existsSync()) return null;
        // 64 KB pertama cukup untuk header JPEG/PNG.
        final raf = f.openSync();
        try {
          bytes = raf.readSync(f.lengthSync().clamp(0, 64 * 1024));
        } finally {
          raf.closeSync();
        }
      } else {
        final b64 = imageData.length > 262144
            ? imageData.substring(0, 262144)
            : imageData;
        final pad = b64.length % 4 == 0 ? '' : '=' * (4 - b64.length % 4);
        bytes = base64Decode(b64 + pad);
      }
      return parseImageDimensions(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Ukuran kartu foto sekali-lihat.
  ///
  /// [maxWidth] = batas lebar dari induk (dipakai saat bubble sedang membalas
  /// media: kartu harus menyempit agar panel teks kanan muat). Tanpa batas →
  /// 72% lebar layar (perilaku lama).
  ///
  /// PENTING: lebar dikurangi 1dp dari batas agar pembulatan piksel (density
  /// 3) tidak membuat BulletChild/Row kelebihan lebar → "overflowed by N px".
  static ({double width, double height}) _sizeFor(
    BuildContext context,
    DecodedImage? d,
    String imageData, {
    double? maxWidth,
  }) {
    final maxW = (maxWidth != null && maxWidth > 0) ? maxWidth : null;
    // `_mediaWidth` = 72% layar, tapi bubble bisa LEBIH SEMPIT (batas 80%,
    // monitor admin, atau mode seleksi). Pakai batas nyata dari induk bila
    // tersedia via MediaQuery? Tidak — MediaQuery tetap lebar layar. Karena
    // itu `maxWidth` WAJIB diisi pemanggil saat ruang sempit. Fallback:
    // 72% layar (perilaku lama).
    // SELALU dibatasi lebar layar (72%) DAN maxWidth pemanggil — pilih yang
    // paling kecil. Tanpa clamp ini, bila `maxWidth` = batas bubble (712)
    // yang lebih LEBAR dari 72% layar, kartu memakai 712 dan meluber.
    // 72% layar adalah LEBAR BUBBLE MAKSIMUM, bukan lebar yang dijamin.
    // Kartu dikunci 72% layar dulu tampil lebih lebar dari bubble (mis. 440
    // vs 352 di layar 800) → RenderFlex overflow. Karena itu batas NYATA
    // dari induk (LayoutBuilder) dipakai bila lebih kecil.
    final mediaW = _mediaWidth(context);
    // Pilih yang TERKECIL antara 72% layar dan batas nyata dari induk.
    var w = mediaW;
    if (maxW != null && maxW > 0 && maxW - 1 < w) w = maxW - 1;
    var fw = d?.width ?? 0;
    var fh = d?.height ?? 0;
    if (fw <= 0 || fh <= 0) {
      final hdr = _dimsOf(imageData);
      if (hdr != null) {
        fw = hdr.width;
        fh = hdr.height;
      }
    }
    if (fw <= 0 || fh <= 0) return (width: w, height: w * 4 / 3);
    return chatPhotoSize(fw, fh, w);
  }
}

/// Menampilkan byte gambar LOKAL seketika (base64/path) tanpa menunggu
/// decode async — dipakai pengirim foto sekali-lihat supaya foto langsung
/// tampil, bukan kotak abu + spinner.
class _InstantBytes extends StatelessWidget {
  final String data;
  const _InstantBytes({required this.data});

  @override
  Widget build(BuildContext context) {
    final bytes = _resolve();
    if (bytes == null) return ColoredBox(color: AppTheme.bgInput);
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      cacheWidth: 720,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => ColoredBox(color: AppTheme.bgInput),
    );
  }

  Uint8List? _resolve() {
    if (data.isEmpty) return null;
    try {
      if (data.startsWith('/')) {
        final f = File(data);
        if (!f.existsSync()) return null;
        return f.readAsBytesSync();
      }
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }
}
