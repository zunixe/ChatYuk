import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../models/story_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../providers/storage_provider.dart';
import '../../../providers/story_provider.dart';
import '../../../core/cache/media_disk_cache.dart';
import '../../../utils.dart';
import '../../../widgets/story_text_overlay.dart';

/// Cache RAM bytes slide (path → image) — bertahan antar slide/penonton
/// selama sesi viewer supaya mundur/maju tidak download ulang.
///
/// PERF: dibatasi kecil (bukan 60) karena tiap byte slide bisa ~5MB
/// (960x1440). 8 entri cukup untuk window maju/mundur tanpa membanjiri
/// RAM (8 x ~5MB ≈ 40MB). Cap lama 60 ≈ 300MB → risiko OOM di HP low-end.
final Map<String, Uint8List> _slideBytesCache = {};
const int _kSlideBytesCacheMax = 8;

/// Index slide yang perlu dimuat untuk window preload: [start-1 .. start+ahead],
/// di-clamp ke [0, total-1]. Top-level & murni supaya bisa di-unit-test tanpa
/// membangun widget/halaman.
@visibleForTesting
List<int> storyPreloadWindow(int start, int total, int ahead) {
  if (total <= 0) return const [];
  final s = (start - 1).clamp(0, total - 1);
  final e = (start + ahead).clamp(0, total - 1);
  return [for (var i = s; i <= e; i++) i];
}

/// Apakah entri terlama harus dibuang setelah insert (size > max)? Murni &
/// top-level supaya kontrak cap cache bisa dikunci tanpa widget.
@visibleForTesting
bool slideCacheShouldEvict(int size, {int max = _kSlideBytesCacheMax}) =>
    size > max;

/// Viewer story fullscreen (gaya IG):
/// - Progress segmented atas (1 segmen per slide), auto-advance 5 detik.
/// - Hold = pause. Tap kanan/kiri = next/prev slide. Swipe vertikal = tutup.
/// - Horizontal PageView antar penonton (urutan tray).
/// - Slide milik sendiri: tombol hapus + tombol daftar penonton.
/// - Slide orang lain: foto SEUKURAN punya pembuat story (bisa digeser
///   ke atas/bawah) + kolom balas, like, dan share DI DALAM foto.
class StoryViewerScreen extends StatefulWidget {
  final List<StoryTrayItem> items;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late PageController _pageCtrl;
  late int _person;
  late AnimationController _progress;
  List<StorySlide> _slides = [];
  int _slide = 0;
  bool _loading = true;
  bool _paused = false;
  final Map<String, Uint8List?> _localImg = {};

  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  bool _sendingReply = false;
  bool _sharingStory = false;
  // Tokoh yang sudah dikirimi notifikasi "balasan terkirim" (sekali).
  final Set<String> _replyNotified = {};

  // Slide yang benar-benar ditonton → dikirim SEKALI (bulk) saat keluar
  // viewer / ganti author. Dulu 1 RPC per slide.
  final List<String> _seenIds = [];
  final Set<String> _seenDedup = {};
  // Sisa waktu slide saat app di-background — lanjut dari sisa,
  // bukan mulai ulang 5 detik penuh.
  Duration? _remainingOnResume;

  static const _slideDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Nav bar Android opaque hitam selama viewer aktif — foto fullscreen
    // tidak tembus/transparan di area menu bawah.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _person = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _person);
    _progress = AnimationController(vsync: this, duration: _slideDuration);
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) _next();
    });
    // Balasan DI DALAM foto: ketik = auto-advance berhenti (tidak pindah
    // slide saat sedang membalas).
    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) {
        _pause();
      } else if (_slides.isNotEmpty) {
        _resume();
      }
    });
    _loadPerson();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _progress.dispose();
    // Sisa slide yang belum terkirim (user keluar sebelum timer ganti
    // author) → kirim sekarang supaya ring tray tetap akurat.
    _flushSeen();
    _pageCtrl.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  /// App di-background → hentikan auto-advance (jangan tandai slide yang
  /// tidak ditonton). Kembali → lanjut dari SISA waktu.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final rem = _remainingOnResume;
      _remainingOnResume = null;
      if (rem != null && !_paused && _slides.isNotEmpty) {
        _startTimer(duration: rem);
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_progress.isAnimating) {
        final rem = Duration(
          milliseconds:
              (_progress.duration!.inMilliseconds * (1 - _progress.value))
                  .round(),
        );
        _remainingOnResume = rem.isNegative
            ? const Duration(milliseconds: 200)
            : rem;
      }
      _progress.stop();
    }
  }

  /// Kirim semua id slide yang ditonton dalam satu RPC, lalu reset.
  void _flushSeen() {
    if (_seenIds.isEmpty) return;
    final ids = List<String>.of(_seenIds);
    final author = _item.authorId;
    _seenIds.clear();
    _seenDedup.clear();
    unawaited(context.read<StoryProvider>().markSeenBulk(ids, author));
  }

  StoryTrayItem get _item => widget.items[_person];
  bool get _own => _item.own;
  bool get _isAdmin => context.read<AuthProvider>().isRealAdmin;
  StorySlide? get _current =>
      (_slide >= 0 && _slide < _slides.length) ? _slides[_slide] : null;

  Future<void> _loadPerson() async {
    _progress.stop();
    // Ganti author → kirim slide yang sudah ditonton author sebelumnya
    // (bulk), lalu mulai kumpulan baru.
    _flushSeen();
    _replyCtrl.clear();
    _sendingReply = false;
    setState(() {
      _loading = true;
      _slide = 0;
    });
    final sp = context.read<StoryProvider>();
    final authorId = _item.authorId;
    final slides = await sp.slidesFor(_item.authorId);
    if (!mounted) return;
    setState(() {
      _slides = slides;
      // Tetap loading sampai gambar aktif tersedia. Sebelumnya false terlalu
      // cepat setelah RPC selesai, sehingga placeholder tampil sementara
      // gambar aktif masih berebut bandwidth dengan preload tetangga.
      _loading = slides.isNotEmpty;
    });
    if (slides.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _markSeen();
    // Prioritas pertama selalu gambar aktif. Sebelumnya tiga gambar
    // (aktif-1..aktif+2) dimulai bersamaan sehingga gambar yang terlihat
    // ikut berebut bandwidth dan tampak seperti lazy-load tidak bekerja.
    final activePath = slides[_slide].imagePath;
    // `finally`: apa pun yang terjadi (author berganti, gambar gagal/gantung)
    // spinner WAJIB berhenti. Tanpa ini, `return` dini di bawah meninggalkan
    // `_loading = true` selamanya → "muter-muter" dan viewer terasa nyangkut.
    try {
      final active = await _bytes(activePath);
      if (!mounted || _item.authorId != authorId) return;
      if (active != null && active.isNotEmpty) {
        _localImg[activePath] = active;
      }
    } finally {
      if (mounted && _item.authorId == authorId) {
        setState(() => _loading = false);
        _startTimer();
        // Tetangga dimuat setelah gambar aktif siap, tanpa menahan first paint.
        unawaited(_preloadAdjacent());
      }
    }
  }

  /// PERF: hanya preload slide di sekitar slide aktif (window ±N), bukan
  /// SEMUA slide sekaligus. Dulu Future.wait untuk seluruh list → semua byte
  /// story (bisa ~5MB/slide) masuk RAM bareng → risiko OOM di HP low-end.
  /// Sekarang memuat [aktif-1 .. aktif+2] saja; sisanya dimuat saat navigasi.
  static const int _preloadAhead = 2;

  /// Index slide di window preload aktif (delegasi ke fungsi murni).
  List<int> _windowIndices() =>
      storyPreloadWindow(_slide, _slides.length, _preloadAhead);

  Future<void> _preloadAdjacent() async {
    await _preloadWindow(includeActive: false);
    // Retry tetangga yang gagal tanpa mengganggu gambar aktif.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) await _preloadWindow(includeActive: false);
  }

  /// Muat byte untuk slide di window aktif yang belum ada. Paralel agar
  /// slide berikutnya siap tanpa nunggu sequential, tapi terbatas pada
  /// window (bukan seluruh list).
  Future<void> _preloadWindow({bool includeActive = true}) async {
    if (_slides.isEmpty) return;
    final idxs = _windowIndices()
        .where((i) => includeActive || i != _slide)
        .where((i) => !_localImg.containsKey(_slides[i].imagePath))
        .toList();
    if (idxs.isEmpty) return;
    await Future.wait(
      idxs.map((i) async {
        final sl = _slides[i];
        final b = await _bytes(sl.imagePath);
        if (b != null && b.isNotEmpty) {
          _localImg[sl.imagePath] = b;
          if (mounted) setState(() {});
        }
      }),
    );
  }

  /// Muat ulang foto slide aktif bila masih kosong (dipanggil saat
  /// pindah slide) — jaring pengaman kedua selain retry _preload.
  Future<void> _reloadCurrentIfMissing() async {
    if (_slides.isEmpty || _slide < 0 || _slide >= _slides.length) return;
    final path = _slides[_slide].imagePath;
    if (_localImg[path] != null) return;
    final b = await _bytes(path);
    if (b != null && b.isNotEmpty && mounted) {
      _localImg[path] = b;
      setState(() {});
    }
  }

  Future<Uint8List?> _bytes(String path) async {
    final cached = _slideBytesCache[path];
    if (cached != null) return cached;
    // Legacy: row lama berisi base64 langsung (bukan path storage).
    // Tanpa cabang ini slide lama gagal total (return null → kotak retry).
    if (path.isNotEmpty && !context.read<StorageProvider>().isPath(path)) {
      try {
        final legacy = base64Decode(path);
        if (legacy.isNotEmpty) {
          _slideBytesCache[path] = legacy;
          return legacy;
        }
      } catch (_) {}
    }
    try {
      // Disk dulu (repeat view instan) — baru network + simpan disk.
      var b = MediaDiskCache.instance.readSync(path);
      b ??= await MediaDiskCache.instance.read(path);
      // Timeout WAJIB: tanpa ini satu unduhan yang menggantung menahan
      // `_loading` (spinner) selamanya di jalur pemanggil.
      b ??= await context
          .read<StorageProvider>()
          .downloadBytes(path)
          .timeout(const Duration(seconds: 8));
      if (b != null && b.isNotEmpty) {
        _slideBytesCache[path] = b;
        if (slideCacheShouldEvict(_slideBytesCache.length)) {
          _slideBytesCache.remove(_slideBytesCache.keys.first);
        }
        unawaited(MediaDiskCache.instance.write(path, b));
      }
      return b;
    } catch (_) {
      return null;
    }
  }

  void _startTimer({Duration? duration}) {
    _progress.stop();
    _paused = false;
    _progress.duration = duration ?? _slideDuration;
    _progress.forward(from: 0);
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _progress.stop();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    final rem = Duration(
      milliseconds: (_progress.duration!.inMilliseconds * (1 - _progress.value))
          .round(),
    );
    _progress.duration = rem.isNegative || rem.inMilliseconds < 50
        ? _slideDuration
        : rem;
    _progress.forward(from: 0);
  }

  void _next() {
    if (_slide < _slides.length - 1) {
      setState(() => _slide++);
      _markSeen();
      _startTimer();
      unawaited(_loadSlideAndPreloadAdjacent());
    } else {
      _nextPerson();
    }
  }

  void _prev() {
    if (_slide > 0) {
      setState(() => _slide--);
      _startTimer();
      unawaited(_loadSlideAndPreloadAdjacent());
    } else {
      _prevPerson();
    }
  }

  Future<void> _loadSlideAndPreloadAdjacent() async {
    await _reloadCurrentIfMissing();
    if (mounted) await _preloadAdjacent();
  }

  void _nextPerson() {
    if (_person < widget.items.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _prevPerson() {
    if (_person > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Kumpulkan id slide yang ditonton (dedupe) — dikirim bulk saat ganti
  /// author / keluar viewer. Update ring tray lokal sudah instan.
  void _markSeen() {
    if (_slide >= _slides.length) return;
    final id = _slides[_slide].id;
    if (id.isEmpty || !_seenDedup.add(id)) return;
    _seenIds.add(id);
  }

  Future<void> _deleteSlide() async {
    final s = context.read<LocaleProvider>().s;
    final sp = context.read<StoryProvider>();
    final ok = await sp.deleteSlide(_slides[_slide].id, _item.authorId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? s.storyDeleted : s.storyDeleteFail),
        backgroundColor: ok ? AppTheme.online : AppTheme.danger,
      ),
    );
    if (!ok) return;
    // Slide terakhir milik orang ini → tutup viewer; else muat ulang.
    if (_slides.length <= 1) {
      Navigator.pop(context);
    } else {
      sp.invalidateSlides(_item.authorId);
      _loadPerson();
    }
  }

  Future<void> _confirmDelete() async {
    final s = context.read<LocaleProvider>().s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.storyDeleteSlideTitle),
        content: Text(s.storyDeleteSlideMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.btnDelete,
              style: AppText.button.copyWith(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true) _deleteSlide();
  }

  Future<void> _showViewers() async {
    final s = context.read<LocaleProvider>().s;
    final sp = context.read<StoryProvider>();
    final slide = _slides[_slide];
    final viewers = await sp.fetchViewers(slide.id);
    if (!mounted) return;
    // null = gagal memuat (network/unauthorized) — beda dari [] yang berarti
    // benar-benar belum ada penonton. Dulu keduanya tampil "belum ada penonton"
    // sehingga kegagalan tersembunyi.
    final failed = viewers == null;
    final list = viewers ?? const <StoryViewer>[];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 20, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    failed
                        ? s.storyViewersTitle
                        : '${s.storyViewersTitle} · ${list.length}',
                    style: AppText.bodyStrong,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.divider),
            if (failed)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.storyViewersLoadFail,
                  style: AppText.bodySmall.copyWith(color: AppTheme.danger),
                ),
              )
            else if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.storyViewersEmpty,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final v = list[i];
                    return ListTile(
                      dense: true,
                      leading: _viewerAvatar(v.avatar, v.nickname),
                      title: Text(v.nickname, style: AppText.bodyStrong),
                      subtitle: Text(
                        formatRelativeTime(v.viewedAt.toLocal(), isId: s.isId),
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      trailing: v.liked
                          ? const Icon(
                              Icons.favorite,
                              size: 16,
                              color: AppTheme.danger,
                            )
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _viewerAvatar(String avatar, String nickname) {
    Uint8List? bytes;
    if (avatar.isNotEmpty &&
        !context.read<StorageProvider>().isAvatarPath(avatar)) {
      try {
        bytes = base64Decode(avatar);
      } catch (_) {}
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
      // Avatar mungil (radius 16) — cap decode.
      backgroundImage: bytes != null
          ? ResizeImage(MemoryImage(bytes), width: 64)
          : null,
      child: bytes != null
          ? null
          : Text(
              nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
              style: TextStyle(
                color: AppTheme.primary,
                fontSize: AppGlyph.avatarInitial(32),
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.items.length,
        onPageChanged: (i) {
          _person = i;
          _loadPerson();
        },
        itemBuilder: (_, i) => _buildPerson(i),
      ),
    );
  }

  /// Kotak foto — ukuran SAMA antara pembuat story & penonton (WYSIWYG).
  Rect _storyRect(BuildContext ctx) {
    final mq = MediaQuery.of(ctx);
    // Koordinat ini harus identik dengan composer:
    // AppBar 40 + top body 20 = 60, bawah body = padding + 68.
    final top = mq.padding.top + 60;
    // Composer menyembunyikan navigation bar, sehingga padding.bottom-nya
    // efektif 0. Viewer harus memakai batas visual yang sama agar foto tidak
    // berhenti lebih tinggi dari foto saat dibuat.
    const bottom = 68.0;
    final h = mq.size.height - top - bottom;
    return Rect.fromLTWH(0, top, mq.size.width, h);
  }

  Widget _buildPerson(int index) {
    if (index != _person) {
      // Halaman tetangga — render ringan (background saja).
      return Container(color: Colors.black);
    }
    final s = context.watch<LocaleProvider>().s;
    final rect = _storyRect(context);
    final showReply = !_own && !_loading && _slides.isNotEmpty;
    return GestureDetector(
      onTapDown: (_) => _pause(),
      onTapUp: (_) => _resume(),
      onLongPressStart: (_) => _pause(),
      onLongPressEnd: (_) => _resume(),
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity != null && d.primaryVelocity! > 300) {
          Navigator.pop(context);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Foto slide: kartu yang bisa digeser ke atas/bawah ──
          Positioned.fromRect(
            rect: rect,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (d) {
                if (d.primaryVelocity != null && d.primaryVelocity! > 300) {
                  Navigator.pop(context);
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _slides.isEmpty
                    ? Center(
                        child: Text(
                          s.storyEmptyTray,
                          style: AppText.body.copyWith(color: Colors.white54),
                        ),
                      )
                    : _buildSlide(),
              ),
            ),
          ),

          // ── Kontrol (progress + zona tap + balasan) DI ATAS foto,
          //    dibatasi tepat ke kotak foto supaya tidak menutupi
          //    header/bawah dan foto tetap bisa digeser. ──
          Positioned.fromRect(
            rect: rect,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Zona tap kanan/kiri — DI BAWAH baris tombol header
                  // supaya tombol delete/close/penonton tetap bisa ditekan.
                  if (!_loading && _slides.isNotEmpty) ...[
                    Positioned.fill(
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _prev,
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _next,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Progress berada tepat di bawah nama dan icon header.
          if (_slides.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 42,
              left: 12,
              right: 12,
              height: 2,
              child: Row(
                children: [
                  for (int i = 0; i < _slides.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: i < _slides.length - 1 ? 4 : 0,
                        ),
                        child: i < _slide
                            ? Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              )
                            : i == _slide
                            ? AnimatedBuilder(
                                animation: _progress,
                                builder: (_, __) => LinearProgressIndicator(
                                  value: _progress.value,
                                  backgroundColor: Colors.white24,
                                  valueColor: const AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Container(color: Colors.white24),
                      ),
                    ),
                ],
              ),
            ),

          // Comment tetap berada DI ATAS layer gambar sebagai overlay.
          // Kotak fotonya tetap memakai ukuran pembuat story.
          if (showReply)
            Positioned.fromRect(
              // Posisi normal tetap mengikuti gambar. Saat keyboard muncul,
              // seluruh bar naik sebesar keyboard dikurangi ruang bawah
              // normal composer (68px), agar berhenti 5px di atas keyboard.
              rect: rect.translate(
                0,
                -((MediaQuery.of(context).viewInsets.bottom - 68).clamp(
                  0.0,
                  double.infinity,
                )),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
                  child: _replyBar(s),
                ),
              ),
            ),

          // ── Header: nama kiri + tombol kanan — TERPISAH via Stack
          // supaya X menempel TEPAT di ujung kanan layar (right: 0).
          if (_slides.isNotEmpty) ...[
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 100,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _own ? s.storyMine : _item.authorName,
                      style: AppText.bodyStrong.copyWith(
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Color(0xCC000000), blurRadius: 6),
                          Shadow(
                            color: Color(0x80000000),
                            blurRadius: 2,
                            offset: Offset(1, 1),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_slides.isNotEmpty)
                    Text(
                      formatRelativeTime(
                        _slides[_slide].createdAt.toLocal(),
                        isId: s.isId,
                      ),
                      style: AppText.caption.copyWith(
                        color: Colors.white54,
                        shadows: const [
                          Shadow(color: Color(0xCC000000), blurRadius: 6),
                        ],
                      ),
                    ),
                  // Visibilitas story milik sendiri — jawab "story ini
                  // tayang untuk siapa" (Semua orang / Pengikut / Teman).
                  if (_own && !_loading && _slides.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _VisibilityBadge(visibility: _slides[_slide].visibility),
                  ],
                ],
              ),
            ),
            // Tombol aksi — kanan (sejajar padding progress bar)
            Positioned(
              top: MediaQuery.of(context).padding.top + 6,
              right: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((_own || _isAdmin) &&
                      !_loading &&
                      _slides.isNotEmpty) ...[
                    _HeaderBtn(icon: Icons.visibility, onPressed: _showViewers),
                    const SizedBox(width: 12),
                    _HeaderBtn(
                      icon: Icons.delete_outline,
                      onPressed: _confirmDelete,
                    ),
                    const SizedBox(width: 12),
                  ],
                  _HeaderBtn(
                    icon: Icons.close,
                    iconSize: 22,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Kolom balas + tombol like & share — DI DALAM foto story orang lain.
  Widget _replyBar(S s) {
    final slide = _current;
    final liked = slide?.liked ?? false;
    final likeCount = slide?.likeCount ?? 0;
    final hasText = _replyCtrl.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Jumlah suka — kecil di atas tombol (tidak menutupi isi foto).
        if (likeCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                s.storyLikeCount(likeCount),
                style: AppText.caption.copyWith(
                  color: Colors.white70,
                  shadows: const [
                    Shadow(color: Color(0xCC000000), blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 40,
                  maxHeight: 132,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _replyCtrl,
                        focusNode: _replyFocus,
                        style: AppText.body.copyWith(color: Colors.white),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: s.storyReplyHint(_item.authorName),
                          hintStyle: AppText.body.copyWith(
                            color: Colors.white60,
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: hasText
                            ? (_) => _sendReply()
                            : (_) => _replyFocus.unfocus(),
                        minLines: 1,
                        maxLines: 4,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _CircleBtn(
              icon: Icons.send_rounded,
              color: AppTheme.primary,
              busy: _sendingReply,
              onTap: hasText && !_sendingReply ? _sendReply : null,
            ),
            const SizedBox(width: 8),
            _CircleBtn(
              icon: liked ? Icons.favorite : Icons.favorite_border,
              color: liked ? AppTheme.danger : Colors.white24,
              onTap: _toggleLike,
            ),
            const SizedBox(width: 8),
            _CircleBtn(
              icon: Icons.share_outlined,
              color: Colors.white24,
              busy: _sharingStory,
              onTap: _shareStory,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleLike() async {
    final slide = _current;
    if (slide == null) return;
    _pause();
    final authorId = _item.authorId;
    final sp = context.read<StoryProvider>();
    // Provider sudah menerapkan optimistic update secara sinkron sebelum
    // menunggu RPC. Rebuild viewer sekarang supaya hati langsung berubah;
    // hasil server menyusul untuk mengoreksi count/status bila perlu.
    final pending = sp.toggleLike(slide.id, authorId);
    if (mounted) setState(() {});
    await pending;
    if (mounted) setState(() {});
  }

  Future<void> _shareStory() async {
    if (_sharingStory) return;
    final s = context.read<LocaleProvider>().s;
    final slide = _current;
    if (slide == null) return;
    setState(() => _sharingStory = true);
    try {
      final bytes = _localImg[slide.imagePath];
      if (bytes == null || bytes.isEmpty) {
        await Share.share(s.storyShareMsg(_item.authorName));
      } else {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/chatyuk_story_${slide.id.replaceAll('-', '')}.jpg',
        );
        await file.writeAsBytes(bytes, flush: true);
        // Share sheet Android akan menampilkan Instagram Stories, WhatsApp
        // Status, Instagram, atau target lain yang menerima gambar.
        await Share.shareXFiles([
          XFile(file.path, mimeType: 'image/jpeg'),
        ], text: s.storyShareMsg(_item.authorName));
      }
    } catch (_) {}
    if (mounted) setState(() => _sharingStory = false);
  }

  /// Kirim balasan story sebagai pesan private chat ke pembuat story.
  /// TIDAK membuka halaman chat — penonton lanjut menyimak story.
  Future<void> _sendReply() async {
    // Kapitalkan huruf pertama balasan story (gaya WhatsApp).
    final text = capitalizeFirst(_replyCtrl.text.trim());
    if (text.isEmpty || _sendingReply) return;
    final auth = context.read<AuthProvider>();
    final myUid = auth.uid;
    final authorId = _item.authorId;
    if (myUid == null || authorId.isEmpty || authorId == myUid) return;
    final s = context.read<LocaleProvider>().s;
    setState(() => _sendingReply = true);
    try {
      final chat = context.read<ChatProvider>();
      final myName = auth.profile?.nickname ?? 'Anon';
      final ids = [myUid, authorId]..sort();
      final chatId = '${ids[0]}_${ids[1]}';
      await chat.startPrivateChat(
        myUid: myUid,
        otherUid: authorId,
        myName: myName,
        otherName: _item.authorName,
        myGender: auth.profile?.gender ?? '',
        myCountry: auth.profile?.country ?? '',
        myAge: auth.profile?.age ?? 0,
      );
      await chat.sendPrivateMessage(
        chatId: chatId,
        senderId: myUid,
        senderName: myName,
        senderGender: auth.profile?.gender ?? '',
        text: text,
      );
      if (!mounted) return;
      setState(() => _sendingReply = false);
      _replyCtrl.clear();
      _replyFocus.unfocus();
      // Notifikasi sekali per penonton — balasan TIDAK membuka chat;
      // penonton lanjut menyimak story.
      if (_replyNotified.add(authorId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.storyReplySent),
            backgroundColor: AppTheme.online,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingReply = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errSendFailed)));
    }
  }

  Widget _buildSlide() {
    final slide = _slides[_slide];
    final bytes = _localImg[slide.imagePath];
    // Sama seperti composer: Stack langsung mengisi seluruh kotak story.
    // Jangan memakai AspectRatio di sini karena itu membuat gambar mengecil
    // dan menyisakan ruang hitam di kiri/kanan atau bawah.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (bytes != null)
          // PERF: decode dikurangi sesuai lebar layar (story umumnya
          // 960-1440px). Cap 1080 → hemat memori bitmap besar tanpa
          // terlihat buram di HP.
          Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 1080)
        else
          // Gambar belum termuat / unduhan gagal. Ketuk untuk coba lagi —
          // dulu hanya kotak putih kosong sehingga tampak seperti "belum ada
          // story" walau slide-nya sebenarnya ada.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _reloadCurrentIfMissing(),
            child: Container(
              color: Colors.white10,
              alignment: Alignment.center,
              child: Icon(
                Icons.refresh_rounded,
                color: Colors.white54,
                size: 32,
              ),
            ),
          ),
        StoryTextOverlay(
          text: slide.textOverlay,
          x: slide.textX,
          y: slide.textY,
          colorIndex: slide.textColorIndex,
          sizeIndex: slide.textSizeIndex,
          scale: slide.textScale,
          rotation: slide.textRotation,
          withBg: slide.textBg,
        ),
      ],
    );
  }
}

/// Badge visibilitas story milik sendiri — ikon + label pendek di
/// header viewer (Semua orang / Pengikut / Teman), gaya menyatu dgn
/// header (teks putih + shadow, tanpa kotak supaya tidak berat).
class _VisibilityBadge extends StatelessWidget {
  final String visibility;
  const _VisibilityBadge({required this.visibility});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final isEveryone = visibility == 'everyone';
    final isFriends = visibility == 'friends';
    final icon = isEveryone
        ? Icons.public
        : (isFriends ? Icons.favorite_rounded : Icons.group_rounded);
    final label = isEveryone
        ? s.storyVisibilityEveryone
        : (isFriends ? s.storyVisibilityFriends : s.storyVisibilityFollowers);
    const shadows = [
      Shadow(color: Color(0xCC000000), blurRadius: 6),
      Shadow(color: Color(0x80000000), blurRadius: 2, offset: Offset(1, 1)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white70, shadows: shadows),
        const SizedBox(width: 3),
        Text(
          label,
          style: AppText.caption.copyWith(
            color: Colors.white70,
            shadows: shadows,
          ),
        ),
      ],
    );
  }
}

/// Tombol bulat kecil di dalam foto (like / share / kirim) — GestureDetector
/// murni 40px supaya rapat dan tidak menambah padding Material.
class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool busy;
  final VoidCallback? onTap;

  const _CircleBtn({
    required this.icon,
    required this.color,
    this.busy = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

/// Tombol header viewer yang rapat — IconButton Material 3 selalu
/// menambah tap-target/padding internal (48px) walau padding: zero →
/// ikon tidak pernah menempel tepi. Pakai GestureDetector murni.
class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;

  const _HeaderBtn({
    required this.icon,
    this.iconSize = 20,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Bayangan ganda — ikon putih tetap kontras di foto terang/gelap.
    const shadows = [
      Shadow(color: Color(0xCC000000), blurRadius: 8),
      Shadow(color: Color(0x80000000), blurRadius: 2, offset: Offset(1, 1)),
    ];
    final ic = Icon(
      icon,
      color: Colors.white,
      size: iconSize,
      shadows: shadows,
    );
    final btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: iconSize + 4,
        height: iconSize + 8,
        // Icon RATA KANAN dalam kotak → glyph terakhir menempel tepi layar.
        child: Align(alignment: Alignment.centerRight, child: ic),
      ),
    );
    // Tooltip MENambah margin 4px + padding 8px → tombol terdorong dari tepi.
    // Hapus Tooltip supaya glyph menempel tepi layar.
    return btn;
  }
}
