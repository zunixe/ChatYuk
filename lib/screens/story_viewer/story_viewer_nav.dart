part of '../story_viewer_screen.dart';

// ignore_for_file: unused_element

mixin _StoryNavMx on _StoryBase {
  List<int> _windowIndices() =>
      storyPreloadWindow(_slide, _slides.length, _preloadAhead);

  Future<void> _preloadAdjacent() async {
    await _preloadWindow(includeActive: false);
    // Retry tetangga yang gagal tanpa mengganggu gambar aktif.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) await _preloadWindow(includeActive: false);
    await _preloadNeighborPersons();
  }

  /// Preload slide PERTAMA person tetangga (kiri/kanan di PageView) supaya
  /// saat user swipe antar-author, halaman tujuan tidak tampil HITAM kosong —
  /// gambar pembuka sudah ada di `_slideBytesCache` global. `slidesFor`
  /// memakai cache internal provider, jadi ini murah (tak selalu hit DB).
  Future<void> _preloadNeighborPersons() async {
    final prov = _storyProv;
    if (prov == null || widget.items.isEmpty) return;
    final neighbors = <int>{
      if (_person - 1 >= 0) _person - 1,
      if (_person + 1 < widget.items.length) _person + 1,
    };
    for (final idx in neighbors) {
      try {
        final item = widget.items[idx];
        final slides = await prov.slidesFor(
          item.authorId,
          expectedCount: item.slideCount,
        );
        if (!mounted || slides.isEmpty) continue;
        // Hanya gambar pembuka (bukan video) — cukup untuk first-paint halus.
        final first = slides.first;
        if (first.isVideo || first.imagePath.isEmpty) continue;
        final b = await _bytes(first.imagePath);
        if (b != null && b.isNotEmpty) {
          _localImg[first.imagePath] = b;
          _neighborFirstPath[idx] = first.imagePath;
        }
      } catch (_) {}
    }
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
    if (path.isNotEmpty &&
        !ProviderScope.containerOf(
          context,
          listen: false,
        ).read(storageProvider).isPath(path)) {
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
      b ??= await ProviderScope.containerOf(context, listen: false)
          .read(storageProvider)
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
    // Saat user masih menggeser PageView, jangan mulai timer — biar ScrollEnd
    // / onPageChanged yang menyalakannya. Mencegah auto-advance di tengah swipe.
    if (_pageDragging) return;
    _paused = false;
    _progress.duration = duration ?? _slideDuration;
    _progress.forward(from: 0);
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _progress.stop();
    unawaited(_videoCtrl?.pause());
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
    final v = _videoCtrl;
    if (v != null && _current?.isVideo == true) unawaited(v.play());
  }

  /// Lompat langsung ke slide ke-[i] (diketuk dari progress bar).
  /// Di luar rentang = abaikan (tidak pindah author — itu tugas _next).
  /// Timer hanya jalan untuk slide GAMBAR. Slide video ditangani
  /// `_syncVideo` (mulai timer setelah video siap).
  void _startTimerIfImage() {
    // `_slide` valid & slides non-kosong.
    if (_slide >= 0 && _slide < _slides.length && !_slides[_slide].isVideo) {
      _startTimer();
    } else {
      _progress.stop();
    }
  }

  void _goToSlide(int i) {
    if (i < 0 || i >= _slides.length || i == _slide) return;
    setState(() => _slide = i);
    _markSeen();
    _startTimerIfImage();
    unawaited(_loadSlideAndPreloadAdjacent());
    unawaited(_syncVideo());
  }

  void _next() {
    if (_slide < _slides.length - 1) {
      setState(() => _slide++);
      _markSeen();
      _startTimerIfImage();
      unawaited(_loadSlideAndPreloadAdjacent());
      unawaited(_syncVideo());
    } else {
      _nextPerson();
    }
  }

  void _prev() {
    if (_slide > 0) {
      setState(() => _slide--);
      _startTimerIfImage();
      unawaited(_loadSlideAndPreloadAdjacent());
      unawaited(_syncVideo());
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
  /// Ghost-mode admin: lihat story orang TIDAK dikumpulkan sama sekali.
  void _markSeen() {
    if (_isAdminCached && !_own) return;
    if (_slide >= _slides.length) return;
    final id = _slides[_slide].id;
    if (id.isEmpty || !_seenDedup.add(id)) return;
    _seenIds.add(id);
  }

  Future<void> _deleteSlide() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final sp = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(storyProvider.notifier);
    final ok = await sp.deleteSlide(_slides[_slide].id, _item.authorId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? s.storyDeleted : s.storyDeleteFail),
        backgroundColor: ok ? AppTheme.online : AppTheme.danger,
      ),
    );
    if (!ok) return;
    // Slide TIDAK hilang (jadi privat) — biarkan viewer terbuka, tandai
    // slide ini ownerOnly + rebuild supaya badge "Private" langsung tampil.
    // (Dulu: pop saat slide terakhir — kini salah, slide masih ada.)
    if (_slide >= 0 && _slide < _slides.length) {
      setState(
        () => _slides[_slide] = _slides[_slide].copyWith(ownerOnly: true),
      );
    }
    sp.invalidateSlides(_item.authorId);
    _loadPerson();
  }

  Future<void> _confirmDelete() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
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
    // Guard tumpuk: fetch lambat + tap berkali-kali = N sheet bertumpuk
    // (terlihat seperti hang — harus tutup satu-satu).
    if (_viewersOpen) return;
    _viewersOpen = true;
    try {
      final s = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(localeProvider).s;
      final sp = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(storyProvider.notifier);
      final slide = _slides[_slide];
      final viewers = await sp.fetchViewers(slide.id);
      if (!mounted) return;
      // null = gagal memuat (network/unauthorized) — beda dari [] yang berarti
      // benar-benar belum ada penonton. Dulu keduanya tampil "belum ada penonton"
      // sehingga kegagalan tersembunyi.
      final failed = viewers == null;
      final list = viewers ?? const <StoryViewer>[];
      await showModalBottomSheet(
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
                        leading: StoryViewerAvatar(
                          viewerId: v.viewerId,
                          avatar: v.avatar,
                          nickname: v.nickname,
                        ),
                        title: Text(v.nickname, style: AppText.bodyStrong),
                        subtitle: Text(
                          formatRelativeTime(
                            v.viewedAt.toLocal(),
                            isId: s.isId,
                          ),
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
    } finally {
      _viewersOpen = false;
    }
  }
}
