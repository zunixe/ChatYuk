import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../config/theme.dart';
import '../core/cache/media_disk_cache.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../services/storage_photo_service.dart';
import '../utils.dart';
import 'package:video_player/video_player.dart';

/// Gate konkurensi sederhana (max N paralel) — dipakai membatasi unduhan
/// poster video lintas-instance bubble. Mirip `_Semaphore` di
/// chat_stream_session.dart (tidak diekspor lintas file).
class _PosterGate {
  final int max;
  int _count = 0;
  final _waiters = <Completer<void>>[];
  _PosterGate(this.max);
  Future<void> _acquire() async {
    if (_count < max) {
      _count++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void _release() {
    _count--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      _count++;
    }
  }

  Future<T> run<T>(Future<T> Function() fn) async {
    await _acquire();
    try {
      return await fn();
    } finally {
      _release();
    }
  }
}

/// Label durasi video ringkas: "0:07" / "1:00". Murni & testable.
String formatVideoDuration(int ms) {
  final total = (ms / 1000).round();
  if (total <= 0) return '0:00';
  final m = total ~/ 60;
  final sec = total % 60;
  return '$m:${sec.toString().padLeft(2, '0')}';
}

/// Bubble video di chat: poster (thumbnail) + ikon play + badge durasi.
/// Tap → fullscreen player. Poster berasal dari frame video (diambil saat
/// kompres di sisi PENGIRIM) untuk pesan sendiri, atau di-generate sekali
/// lalu di-cache ke disk untuk pesan lawan.
///
/// Video butuh FILE untuk diputar (`VideoPlayerController.file`), jadi
/// byte diunduh ke cache disk dulu (MediaDiskCache = sumber kebenaran
/// lokal, sama seperti foto/voice).
class ChatVideoBubble extends StatefulWidget {
  /// Lebar kartu video (poster + kartu terkunci sama) — dipakai bubble chat
  /// untuk mengunci lebar kolom supaya kartu rapat (tidak melebar ke max).
  static const double bubbleWidth = 200;

  /// Path storage (`chat/....mp4`) ATAU base64 (bubble optimistik sendiri).
  final String videoData;
  /// Durasi (ms) dari model pesan — label tanpa perlu buka video.
  final int durationMs;
  /// Cap tinggi bubble (samakan dengan foto: ≤280).
  final double maxHeight;
  /// Video "sekali lihat" sudah ditonton → TERKUNCI (tak bisa dibuka).
  final bool locked;
  /// Video ini bertipe "sekali lihat" (belum tentu terkunci).
  final bool isOnce;
  /// ID pesan (untuk menandai sudah ditonton di server). Null = pending.
  final String? messageId;
  /// Pesan milik sendiri.
  final bool isMe;
  /// Admin monitor: boleh melihat video sekali-lihat walau sudah kadaluarsa
  /// (akses istimewa; menonaktifkan kunci + tidak menandai server).
  final bool isAdminView;
  /// Jam kirim ("" = tidak tampil). Digabung dengan badge durasi di
  /// kanan-bawah — SAMA posisi dengan overlay jam foto (kanan 6 bawah 6).
  final String timeStr;
  /// Tampilkan centang dibaca (pengirim / kedua sisi).
  final bool showChecks;
  final bool isPending;
  final bool isQueued;
  final bool isRead;

  const ChatVideoBubble({
    super.key,
    required this.videoData,
    this.durationMs = 0,
    this.maxHeight = 280,
    this.locked = false,
    this.isOnce = false,
    this.messageId,
    this.isMe = false,
    this.isAdminView = false,
    this.timeStr = '',
    this.showChecks = false,
    this.isPending = false,
    this.isQueued = false,
    this.isRead = false,
  });

  @override
  State<ChatVideoBubble> createState() => _ChatVideoBubbleState();
}

class _ChatVideoBubbleState extends State<ChatVideoBubble> {
  Uint8List? _poster;
  bool _loading = true;
  bool _failed = false;
  bool _opening = false;
  // Spinner TERTUNDA: baca disk yang cepat (ms) tidak boleh mem-flash
  // spinner — tampilkan kotak hitam polos sampai terbukti lambat (>300ms,
  // berarti benar-benar mengunduh). Kunci anti-kedip cold start.
  bool _slow = false;
  Timer? _slowTimer;
  // Poster sinkron (initState, HIT disk) tampil INSTAN tanpa fade.
  // Poster async (datang belakangan) fade-in halus. Tanpa pembedaan ini,
  // fade selalu jalan → justru terlihat seperti loading/kedip.
  bool _fadePoster = false;
  // Terkunci lokal setelah ditonton (optimistis, tanpa menunggu realtime) —
  // pengirim tetap boleh melihat videonya sendiri.
  bool _lockedLocal = false;

  // Batas unduhan poster paralel (lintas-instance). Tiap poster mengunduh
  // video PENUH lalu ambil 1 frame — kalau puluhan bubble video tampil saat
  // cold start, tanpa batas mereka berebut bandwidth + RAM decode sekaligus
  // (gejala "ngeblink" / app freeze di HP RAM kecil).
  // 2 bersamaan: cukup cepat, sisa antri — jaga puncak memori tetap rendah.
  static final _posterGate = _PosterGate(2);

  // Terkunci: video sekali-lihat sudah ditonton & milik lawan. Admin monitor
  // DILARANG dikunci (harus bisa melihat semua).
  bool get _locked =>
      !widget.isAdminView &&
      (widget.locked || (_lockedLocal && !widget.isMe));

  // Kunci cache poster di disk (anti-blink cold start): poster yang sudah
  // pernah dibuat dipakai ulang TANPA unduh video + generate frame lagi.
  String get _posterKey => 'video_poster:${widget.videoData}';

  @override
  void initState() {
    super.initState();
    // ANTI-KEDIP: poster yang sudah ada di disk tampil SEJAK frame pertama
    // (baca sinkron — thumbnail kecil, aman di main isolate). Tanpa ini
    // selalu ada 1+ frame spinner walau poster sudah ter-cache.
    // Null bila prewarm belum jalan / poster belum ada → jalur async di
    // bawah yang mengurus (tidak mengubah perilaku lazy).
    if (!_locked && widget.videoData.isNotEmpty) {
      try {
        final hit = MediaDiskCache.instance.readSync(_posterKey);
        if (hit != null && hit.isNotEmpty) {
          dlog('[VideoBubble] poster HIT-sync key=${_posterKey.hashCode} bytes=${hit.length}');
          _poster = hit;
          _loading = false;
          return;
        }
        dlog('[VideoBubble] poster MISS-sync key=${_posterKey.hashCode} → async');
      } catch (_) {}
    }
    // LAZY: tunda 1 frame — bubble yang belum benar-benar tampil (di luar
    // viewport) tidak memicu unduh video + generate frame. Cegah puluhan
    // video berebut bandwidth saat cold start (gejala "ngeblink").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_locked && widget.videoData.isNotEmpty && _poster == null) {
        unawaited(_loadPoster());
      }
    });
  }

  @override
  void didUpdateWidget(ChatVideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pesan optimistik (base64) → path storage setelah upload selesai.
    if (widget.videoData != oldWidget.videoData) {
      unawaited(_loadPoster());
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  /// True bila videoData berupa path storage (bukan base64 lokal).
  bool get _isPath => StoragePhotoService.instance.isChatVideoPath(
    widget.videoData,
  );

  /// Bubble pesan sendiri yang belum ter-upload: `videoData` = base64
  /// (bukan path storage).
  bool get _isPendingBase64 =>
      !_isPath && widget.videoData.isNotEmpty;

  /// File video lokal siap putar: unduh path → file cache disk (sekali).
  Future<File?> _ensureLocalFile() async {
    // Base64 (bubble sendiri, belum ter-upload) → tulis ke temp.
    if (!_isPath) {
      try {
        final bytes = base64Decode(widget.videoData);
        final dir = await getTemporaryDirectory();
        // Nama unik per konten: nama tetap (`chat_vid_pending.mp4`) bisa
        // bertabrakan antar dua video pending sekaligus / memutar file basi.
        final f = File(
          '${dir.path}/chat_vid_pending_'
          '${widget.videoData.hashCode.abs()}.mp4',
        );
        await f.writeAsBytes(bytes, flush: true);
        return f;
      } catch (e) {
        dlog('[VideoBubble] decode base64 gagal: $e');
        return null;
      }
    }
    // Cache disk (putar ulang instan) dulu.
    final cached = await MediaDiskCache.instance.read(widget.videoData);
    final dir = await getTemporaryDirectory();
    // Nama file temp stabil per path — hashCode cukup (file sementara,
    // bukan cache permanen; MediaDiskCache tetap sumber kebenaran).
    final target = File(
      '${dir.path}/chat_vid_${widget.videoData.hashCode.abs()}.mp4',
    );
    if (cached != null && cached.isNotEmpty) {
      await target.writeAsBytes(cached, flush: true);
      return target;
    }
    final bytes = await StoragePhotoService.instance.downloadBytes(
      widget.videoData,
    );
    if (bytes == null || bytes.isEmpty) return null;
    // Simpan ke disk cache supaya putar ulang tidak unduh lagi.
    unawaited(MediaDiskCache.instance.write(widget.videoData, bytes));
    await target.writeAsBytes(bytes, flush: true);
    return target;
  }

  /// Poster: base64 kecil dari payload (bubble sendiri) atau generate
  /// frame dari video (pesan lawan; 1× lalu simpan memori + DISK).
  Future<void> _loadPoster() async {
    if (!mounted) return;
    // 1) Cache DISK dulu (instan, tanpa unduh video) — kunci anti-blink
    //    saat cold start / scroll ulang / keluar-masuk chat.
    try {
      final cached =
          MediaDiskCache.instance.readSync(_posterKey) ??
          await MediaDiskCache.instance.read(_posterKey);
      if (cached != null && cached.isNotEmpty) {
        dlog('[VideoBubble] poster HIT disk key=${_posterKey.hashCode} bytes=${cached.length}');
        if (!mounted) return;
        _stopSlow();
        setState(() {
          _poster = cached;
          _fadePoster = true;
          _loading = false;
          _failed = false;
        });
        return;
      }
      dlog('[VideoBubble] poster MISS disk key=${_posterKey.hashCode} → generate');
    } catch (_) {}
    setState(() {
      _loading = true;
      _failed = false;
    });
    _armSlow();
    // Bungkus bagian yang MENGUNDUH video + generate frame dengan gate
    // (bukan cache disk read di atas yang instan). Poster lalu disimpan ke
    // disk — pemanggilan berikutnya tidak lewat gate lagi.
    await _posterGate.run(() => _generatePoster());
    _stopSlow();
  }

  /// Nyalakan timer spinner-tertunda (cancel dulu bila ada).
  void _armSlow() {
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _loading && _poster == null) {
        setState(() => _slow = true);
      }
    });
  }

  /// Matikan timer + flag spinner-tertunda.
  void _stopSlow() {
    _slowTimer?.cancel();
    _slowTimer = null;
    _slow = false;
  }

  Future<void> _generatePoster() async {
    if (!mounted) return;
    // Bubble sendiri (belum ter-upload): videoData base64 → tulis ke file
    // dulu, lalu ambil poster frame-nya. Tanpa ini bubble hanya kotak hitam
    // (di latar gelap terlihat seperti "video hilang").
    if (_isPendingBase64) {
      try {
        final file = await _ensureLocalFile();
        if (file == null) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        final thumb = await StoragePhotoService.instance.storyVideoPoster(
          file.path,
        );
        if (!mounted) return;
        setState(() {
          _poster = thumb;
          _fadePoster = true;
          _loading = false;
        });
        _cachePoster(thumb);
      } catch (e) {
        dlog('[VideoBubble] poster pending gagal: $e');
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    try {
      final file = await _ensureLocalFile();
      if (file == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
        return;
      }
      final thumb = await StoragePhotoService.instance.storyVideoPoster(
        file.path,
      );
      if (!mounted) return;
      setState(() {
        _poster = thumb;
        _fadePoster = true;
        _loading = false;
      });
      _cachePoster(thumb);
    } catch (e) {
      dlog('[VideoBubble] poster gagal: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  /// Simpan poster ke cache disk (fire-and-forget) — cold start berikutnya
  /// langsung tampil dari disk tanpa generate frame / unduh video.
  void _cachePoster(Uint8List? thumb) {
    if (thumb == null || thumb.isEmpty) {
      dlog('[VideoBubble] poster generate KOSONG key=${_posterKey.hashCode}');
      return;
    }
    dlog('[VideoBubble] poster tulis disk key=${_posterKey.hashCode} bytes=${thumb.length}');
    unawaited(MediaDiskCache.instance.write(_posterKey, thumb));
  }

  Future<void> _openFullscreen() async {
    if (_opening || _locked) return;
    _opening = true;
    try {
      final file = await _ensureLocalFile();
      if (!mounted) return;
      if (file == null) {
        final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.videoCompressFail)));
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            file: file,
            durationMs: widget.durationMs,
          ),
        ),
      );
      // Sekali lihat: begitu viewer DITUTUP = sudah dilihat → kunci
      // permanen (optimistis lokal + tandai server supaya penerima lain
      // & restart app tetap terkunci).
      if (mounted && widget.isOnce && !widget.isMe) {
        setState(() => _lockedLocal = true);
        unawaited(_expireOnServer());
      }
    } finally {
      _opening = false;
    }
  }

  /// Tandai pesan video ini sudah ditonton (type → video_once_expired).
  /// image_data DIBIARKAN (admin tetap bisa lihat) — sama seperti foto.
  Future<void> _expireOnServer() async {
    final id = widget.messageId;
    if (id == null || id.isEmpty || id.startsWith('pending-')) return;
    if (!mounted) return;
    try {
      await ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier).clearViewOnceImage(id, video: true);
    } catch (e) {
      dlog('[VideoBubble] expire gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const double width = ChatVideoBubble.bubbleWidth;
    // Rasio 16:9 umum untuk video; bila poster ada, pakai rasionya.
    double height = width * 9 / 16;
    if (height > widget.maxHeight) height = widget.maxHeight;

    // Terkunci (sekali lihat, sudah ditonton): kartu status, bukan video.
    // Design DISAMAKAN dengan foto sekali-lihat (ViewOnceLockedCard) supaya
    // konsisten — dulu video memakai kotak polos tanpa judul/hint.
    // Jam tetap overlay kanan-bawah di atas kartu (sama seperti foto
    // view-once) supaya penerima tetap tahu waktunya.
    if (_locked) {
      final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ViewOnceLockedCard(
            title: s.videoOnceExpired,
            hint: s.viewOnceExpiredHint,
            icon: Icons.videocam_off_outlined,
          ),
          if (widget.timeStr.isNotEmpty)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.timeStr,
                      style: AppText.chatTime.copyWith(color: Colors.white),
                    ),
                    if (widget.showChecks) ...[
                      const SizedBox(width: 3),
                      Icon(
                        (widget.isPending || widget.isQueued)
                            ? Icons.done
                            : Icons.done_all,
                        size: 12,
                        color: (widget.isRead &&
                                !widget.isPending &&
                                !widget.isQueued)
                            ? const Color(0xFF7EC8FF)
                            : Colors.white70,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return GestureDetector(
      onTap: _loading ? null : _openFullscreen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Lapisan poster SELALU di tree — kemunculannya fade-in
              // halus (tidak pop). Placeholder di bawah hanya saat null.
              AnimatedOpacity(
                opacity: _poster != null ? 1 : 0,
                duration: _fadePoster
                    ? const Duration(milliseconds: 220)
                    : Duration.zero,
                curve: Curves.easeOut,
                child: _poster != null
                    ? Image.memory(
                        _poster!,
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                        gaplessPlayback: true,
                      )
                    : Container(color: Colors.black87),
              ),
              if (_poster == null)
                Container(
                  color: Colors.black87,
                  alignment: Alignment.center,
                  // Spinner hanya bila TERBUKTI lambat (_slow). Baca disk
                  // yang selesai <300ms tidak pernah mem-flash spinner.
                  child: _loading
                      ? (_slow
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const SizedBox())
                      : Icon(
                          _failed
                              ? Icons.refresh_rounded
                              : Icons.videocam_rounded,
                          color: Colors.white54,
                          size: 30,
                        ),
                ),
              // Overlay play (selalu tampil saat siap).
              if (!_loading)
                IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 26,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              // Badge "sekali lihat" (sebelum ditonton).
              if (widget.isOnce)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.visibility_off_outlined,
                          size: 11,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          ProviderScope.containerOf(context, listen: false).read(localeProvider).s.viewTimerOnce,
                          style: AppText.chatTime.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Badge kanan-bawah: [durasi] [jam] [centang] dalam SATU
              // badge — posisi SAMA dengan overlay jam foto (kanan 6
              // bawah 6) supaya tidak dobel badge bertumpuk.
              if (widget.durationMs > 0 || widget.timeStr.isNotEmpty)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.durationMs > 0)
                          Text(
                            formatVideoDuration(widget.durationMs),
                            style:
                                AppText.chatTime.copyWith(color: Colors.white),
                          ),
                        if (widget.durationMs > 0 &&
                            widget.timeStr.isNotEmpty)
                          const SizedBox(width: 5),
                        if (widget.timeStr.isNotEmpty)
                          Text(
                            widget.timeStr,
                            style:
                                AppText.chatTime.copyWith(color: Colors.white),
                          ),
                        if (widget.showChecks) ...[
                          const SizedBox(width: 3),
                          Icon(
                            (widget.isPending || widget.isQueued)
                                ? Icons.done
                                : Icons.done_all,
                            size: 12,
                            color: (widget.isRead &&
                                    !widget.isPending &&
                                    !widget.isQueued)
                                ? const Color(0xFF7EC8FF)
                                : Colors.white70,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pemutar video fullscreen: kontrol dasar (play/pause) + loop dimatikan
/// agar user tahu videonya selesai. Dipakai bubble chat DAN preview composer.
class VideoPlayerScreen extends StatefulWidget {
  final File file;
  final int durationMs;
  const VideoPlayerScreen({super.key, required this.file, this.durationMs = 0});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final ctrl = VideoPlayerController.file(widget.file);
      _ctrl = ctrl;
      await ctrl.initialize().timeout(const Duration(seconds: 20));
      await ctrl.setLooping(false);
      await ctrl.play();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      dlog('[VideoPlayer] init gagal: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _ctrl;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // SafeArea: video portrait penuh TANPA ini memanjang sampai ke
      // belakang menu navigasi Android bawah (overlap). Lihat PhotoViewer.
      body: SafeArea(
        child: Center(
          child: _failed
            ? Text(
                s.videoCompressFail,
                style: AppText.body.copyWith(color: Colors.white70),
              )
            : !_ready
            ? const CircularProgressIndicator(color: Colors.white)
            : GestureDetector(
                onTap: _togglePlay,
                child: AspectRatio(
                  aspectRatio: _ctrl!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_ctrl!),
                      if (!_ctrl!.value.isPlaying)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

// Kartu "foto sudah kadaluarsa" — dipakai pengirim & penerima (design sama).
class ViewOnceLockedCard extends StatelessWidget {
  /// Lebar kartu terkunci — SAMA dengan lebar video supaya bubble rapat.
  static const double cardWidth = 200;
  final String title;
  final String hint;
  /// Ikon dalam lingkaran (default kunci-jam). Video memakai ikon video.
  final IconData icon;
  const ViewOnceLockedCard({
    super.key,
    required this.title,
    required this.hint,
    this.icon = Icons.lock_clock_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: cardWidth,
        height: 140,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF37474F), Color(0xFF263238)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppText.chatName.copyWith(
                      color: Colors.white,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: AppText.chatTime.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
