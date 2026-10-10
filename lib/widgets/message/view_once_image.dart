import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/cache/photo_cache.dart';
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
  });

  @override
  State<ViewOnceImage> createState() => _ViewOnceImageState();
}

class _ViewOnceImageState extends State<ViewOnceImage> {
  late ViewOnceTick _tick;
  DecodedImage? _decoded;

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
    _tick = viewOnceStates[id] ?? (viewOnceStates[id] = ViewOnceTick());
    if (widget.viewSecs != null) {
      _tick.totalSecs = resolveViewOnceSecs(widget.viewSecs);
    }
    if (widget.isExpired && _tick.state != ViewOnceState.viewing) {
      _tick.state = ViewOnceState.expired;
    }
    if (_tick.state == ViewOnceState.expired) return;
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
    if (widget.isExpired && _tick.state != ViewOnceState.viewing) {
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      setState(() {});
      return;
    }
    if (_tick.state == ViewOnceState.expired) return;
    if (widget.imageData != oldWidget.imageData &&
        widget.imageData.isNotEmpty) {
      _decoded = _tick.decoded;
      if (_decoded == null) _decode();
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
    // View-once SUDAH expired (server tandai type='view_once_expired') —
    // WAJIB terkunci permanen, apapun isi imageData. Jangan decode/tampil.
    if (widget.isExpired) {
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      if (mounted) setState(() {});
      return;
    }
    // Sender/load: kalau imageData thumbnail kosong, ambil dari PhotoCache
    // (messageId) dulu — view-once yang pernah dilihat pengirim harus tetap tampil.
    var data = widget.imageData;
    if (data.isEmpty) {
      final id = widget.messageId;
      if (id != null && !id.startsWith('pending-')) {
        try {
          data = await PhotoCache.instance.load(widget.chatKey, id) ?? '';
        } catch (_) {}
      }
    }
    // Data tidak tersedia (server sudah hapus image view-once & cache kosong)
    // → tampilkan kartu terkunci, jangan spinner muter terus.
    if (data.isEmpty) {
      // Kalau BUKAN expired (pesan baru view_once), jangan langsung kunci.
      // Realtime bisa truncate base64 besar → image_data broadcast kosong.
      // Photo download async akan mengisi imageData via didUpdateWidget.
      if (!widget.isExpired) return;
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      if (!mounted) return;
      setState(() {});
      return;
    }
    // Data bisa berupa PATH storage → download dulu sebelum decode.
    if (data.isNotEmpty && isStoragePathValue(data)) {
      data = await safeStorage(context).download(data) ?? '';
      if (data.isEmpty) return;
    }
    final res = await NativeImage.decodeWithDims(data);
    if (res == null || res.width <= 0 || res.height <= 0) {
      // Decode gagal — jangan set _tick.decoded ke null/rusak.
      return;
    }
    final decoded = DecodedImage(res.bytes, res.width, res.height);
    _tick.decoded = decoded;
    if (!mounted) return;
    setState(() => _decoded = decoded);
    // Kalau user sudah tap "Lihat" sebelum gambar siap → mulai timer sekarang
    if (_tick.state == ViewOnceState.viewing && _tick.timer == null) {
      _beginCountdown();
    }
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

  void _openViewer() {
    if (_decoded == null || _tick.state != ViewOnceState.viewing || !mounted)
      return;
    _tick.viewerOpen = true;
    Navigator.of(context)
        .push(
          // Route viewer sama dengan foto biasa (fade+scale halus), bukan slide.
          PageRouteBuilder<void>(
            opaque: true,
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 160),
            pageBuilder: (_, __, ___) => PhotoViewerScreen(
              bytes: _decoded!.bytes,
              fullLoader: () {
                final id = widget.messageId;
                if (id == null || id.startsWith('pending-'))
                  return Future.value(null);
                return PhotoCache.instance.load(widget.chatKey, id);
              },
              countdown: _tick.totalSecs > 0 ? _tick.countdown : null,
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
        )
        .whenComplete(() {
          _tick.viewerOpen = false;
          // Mode 1x: viewer ditutup = sudah dilihat → kunci permanen.
          if (_tick.totalSecs <= 0 &&
              _tick.state == ViewOnceState.viewing) {
            _expireNow();
          }
        });
  }

  Future<void> _clearFromServer() async {
    final id = widget.messageId;
    if (id == null || id.startsWith('pending-')) return;
    try {
      await ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier).clearViewOnceImage(
        id,
        isRoom: widget.isRoom,
      );
    } catch (_) {}
  }

  Widget _buildAdminView(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final decoded = _decoded;
    final w = decoded != null ? _viewWidth(decoded) : 200.0;
    final h = decoded != null ? _viewHeight(decoded) : 200.0;
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
        Navigator.of(context)
            .push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.memory(
                          zoomBytes,
                          fit: BoxFit.contain,
                          // Cap 1080px: layar HP tidak butuh full-res 12MP.
                          cacheWidth: 1080,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ).then((_) {
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
    return ValueListenableBuilder<ViewOnceState>(
      valueListenable: _tick.stateNotifier,
      builder: (_, st, _) {
        final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;

        // Pengirim lihat foto asli + badge
        if (widget.isMe) {
          // View-once terkunci (data sudah tidak tersedia) → kartu terkunci, bukan spinner
          if (_tick.state == ViewOnceState.expired) {
            return ViewOnceLockedCard(
              title: s.viewOnceExpired,
              hint: s.viewOnceExpiredHint,
            );
          }
          final decoded = _decoded;
          final w = decoded != null ? _viewWidth(decoded) : 200.0;
          final h = decoded != null ? _viewHeight(decoded) : 200.0;
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
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    child: const Icon(
                      Icons.remove_red_eye_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.viewOnceTitle,
                    style: AppText.chatBodySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.viewOnceTap,
                    textAlign: TextAlign.center,
                    style: AppText.chatCaption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.btnView,
                      style: AppText.chatName.copyWith(
                        color: const Color(0xFF1E88E5),
                        letterSpacing: 0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Expired — kartu terkunci (tanpa image — hemat memori & tidak load foto)
        if (_tick.state == ViewOnceState.expired) {
          return ViewOnceLockedCard(
            title: s.viewOnceExpired,
            hint: s.viewOnceExpiredHint,
          );
        }

        // Viewing — tampilkan foto proporsional + countdown; tap untuk memperbesar
        final decoded = _decoded;
        final vw = decoded != null ? _viewWidth(decoded) : 200.0;
        final vh = decoded != null ? _viewHeight(decoded) : 200.0;
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
  }

  // Lebar/tinggi tampilan proporsional (maks 200×280) sesuai rasio asli.
  static double _viewWidth(DecodedImage d) {
    final aspect = d.width / d.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return width;
  }

  static double _viewHeight(DecodedImage d) {
    final aspect = d.width / d.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return height;
  }
}
