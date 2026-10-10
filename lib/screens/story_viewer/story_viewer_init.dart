part of '../story_viewer_screen.dart';

// ignore_for_file: unused_element

mixin _StoryInitMx on _StoryBase {
  @override
  void initState() {
    super.initState();
    // Cache provider selagi context masih aktif (lihat catatan _storyProv).
    _storyProv = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(storyProvider.notifier);
    // Cache status admin untuk ghost-mode (lihat catatan _isAdminCached).
    try {
      _isAdminCached = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authProvider.notifier).isRealAdmin;
    } catch (_) {
      _isAdminCached = false;
    }
    WidgetsBinding.instance.addObserver(this);
    // Android 15: setStatusBarColor/setNavigationBarColor DEPRECATED
    // (Play menolak). Jangan isi systemNavigationBarColor — Scaffold hitam
    // + edge-to-edge transparan memberi visual yang sama tanpa API lama.
    // Hanya ikon terang + matikan scrim kontras bawaan sistem.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
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

  /// Sinkronkan video dengan slide aktif: init bila slide video,
  /// buang controller bila pindah ke gambar / author lain.
  Future<void> _syncVideo() async {
    final cur = _current;
    if (cur == null || !cur.isVideo) {
      await _dropVideo();
      return;
    }
    if (_videoSlideId == cur.id && _videoCtrl != null) return;
    await _dropVideo();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/chatyuk_story_${cur.id}.mp4');
      if (!await file.exists()) {
        final sp = _storyProv;
        if (sp == null) return;
        Uint8List? bytes = MediaDiskCache.instance.readSync(cur.videoPath);
        bytes ??= await MediaDiskCache.instance.read(cur.videoPath);
        if (bytes == null || bytes.isEmpty) {
          final dl = await _storyProv?.fetchSlideVideo(cur.videoPath);
          bytes = dl;
        }
        if (bytes == null || bytes.isEmpty) return;
        await file.writeAsBytes(bytes, flush: true);
      }
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize().timeout(const Duration(seconds: 10));
      if (!mounted || _current?.id != cur.id) {
        await ctrl.dispose();
        return;
      }
      // Loop: kalau video pendek/berhenti, tetap tampil (bukan layar mati)
      // — auto-advance slide tetap dikendalikan timer.
      await ctrl.setLooping(true);
      _videoCtrl = ctrl;
      _videoSlideId = cur.id;
      // Auto-advance mengikuti durasi video (bukan 5 dtk).
      final dur = ctrl.value.duration;
      _progress.duration = dur.inMilliseconds > 0 ? dur : _slideDuration;
      // Video SIAP → baru progress bar (timer) jalan; sebelumnya loading.
      // Ini yang benar: progress tidak "mendahului" frame video.
      if (mounted) {
        setState(() {});
        if (!_paused) {
          await ctrl.play();
          _progress.forward(from: 0);
        }
      }
    } catch (e) {
      dlog('[StoryViewer] video init error: $e');
      await _dropVideo();
    }
  }

  Future<void> _dropVideo() async {
    _videoSlideId = '';
    final c = _videoCtrl;
    _videoCtrl = null;
    try {
      await c?.pause();
      await c?.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_dropVideo());
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
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
      unawaited(_videoCtrl?.pause());
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
  /// Ghost-mode admin: kalau yang menonton admin dan bukan story sendiri,
  /// JANGAN kirim apa pun (buang antrean) supaya tidak tercatat di penonton.
  void _flushSeen() {
    if (_seenIds.isEmpty) return;
    final ids = List<String>.of(_seenIds);
    final author = _item.authorId;
    final ghost = _isAdminCached && !_own;
    _seenIds.clear();
    _seenDedup.clear();
    if (ghost) return;
    final prov = _storyProv;
    if (prov == null) return;
    unawaited(prov.markSeenBulk(ids, author));
  }

  StoryTrayItem get _item => widget.items[_person];
  bool get _own => _item.own;
  bool get _isAdmin => ProviderScope.containerOf(
    context,
    listen: false,
  ).read(authProvider.notifier).isRealAdmin;
  StorySlide? get _current =>
      (_slide >= 0 && _slide < _slides.length) ? _slides[_slide] : null;

  Future<void> _loadPerson() async {
    _progress.stop();
    try {
      await _loadPersonInner();
    } catch (e) {
      // Jaring pengaman: exception TAK TERDUGA di jalur mana pun (provider
      // hilang, parsing, dsb.) tidak boleh meninggalkan spinner selamanya —
      // tampilkan retry. Return dini (ganti author/unmount) tidak lewat sini.
      dlog('[StoryViewer] _loadPerson error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  Future<void> _loadPersonInner() async {
    // Ganti author → kirim slide yang sudah ditonton author sebelumnya
    // (bulk), lalu mulai kumpulan baru.
    _flushSeen();
    _replyCtrl.clear();
    _sendingReply = false;
    setState(() {
      _loading = true;
      _loadError = false;
      _slide = 0;
    });
    final sp = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(storyProvider.notifier);
    final authorId = _item.authorId;
    // Minta sesuai hitungan tray (segar) — jangan pakai cache basi.
    var slides = await sp.slidesFor(
      _item.authorId,
      expectedCount: _item.slideCount,
    );
    // Retry sekali bila kosong padahal tray ada isinya: fetch pertama
    // sering kena timeout 6 dtk di jaringan flaky.
    if (slides.isEmpty && mounted && _item.slideCount > 0) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || _item.authorId != authorId) return;
      slides = await sp.slidesFor(_item.authorId);
    }
    if (!mounted) return;
    setState(() {
      _slides = slides;
      // Tetap loading sampai gambar aktif tersedia. Sebelumnya false terlalu
      // cepat setelah RPC selesai, sehingga placeholder tampil sementara
      // gambar aktif masih berebut bandwidth dengan preload tetangga.
      _loading = slides.isNotEmpty;
    });
    if (slides.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          // Bedakan "gagal" vs "benar kosong": tray bilang ada isi tapi
          // fetch (2×) tetap kosong → kemungkinan jaringan, tawarkan retry.
          _loadError = _item.slideCount > 0;
        });
      }
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
        // Video: progress bar JANGAN jalan dulu — tunggu video benar-benar
        // siap (frame + play), baru timer mulai (progress tidak mendahului).
        final isVideoSlide = slides[_slide].isVideo;
        if (!isVideoSlide) _startTimer();
        // Tetangga dimuat setelah gambar aktif siap, tanpa menahan first paint.
        unawaited(_preloadAdjacent());
        unawaited(_syncVideo());
      }
    }
  }

  /// PERF: hanya preload slide di sekitar slide aktif (window ±N), bukan
  /// SEMUA slide sekaligus. Dulu Future.wait untuk seluruh list → semua byte
  /// story (bisa ~5MB/slide) masuk RAM bareng → risiko OOM di HP low-end.
  /// Sekarang memuat [aktif-1 .. aktif+2] saja; sisanya dimuat saat navigasi.

  /// Index slide di window preload aktif (delegasi ke fungsi murni).
}
