part of '../story_viewer_screen.dart';

// ignore_for_file: unused_element

mixin _StoryBuildMx on _StoryBase {
  Widget build(BuildContext context) {
    PerfProbe.buildCount('StoryViewer');
    return Scaffold(
      backgroundColor: Colors.black,
      // Jeda auto-advance SELAMA drag horizontal antar-person. Tanpa ini,
      // timer slide terus berjalan saat user menggeser PageView → bisa
      // memicu `_next()`/pindah slide di TENGAH swipe → transisi terasa
      // tersendat / "tabrakan dengan timer".
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification) {
            _pageDragging = true;
            _progress.stop();
          } else if (n is ScrollEndNotification) {
            _pageDragging = false;
            // Resume HANYA jika tidak sedang berpindah halaman (kalau pindah,
            // _onPageChanged → _loadPerson yang mengatur timer baru).
            if (mounted &&
                _person == _pageCtrl.page?.round() &&
                _slides.isNotEmpty) {
              _startTimerIfImage();
            }
          }
          return false;
        },
        child: PageView.builder(
          controller: _pageCtrl,
          itemCount: widget.items.length,
          onPageChanged: (i) {
            _person = i;
            _loadPerson();
          },
          itemBuilder: (_, i) => _buildPerson(i),
        ),
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
      // Halaman tetangga — render ringan. Kalau gambar pembukanya sudah
      // ter-preload, tampilkan langsung (bukan hitam polos) agar transisi
      // swipe antar-author terasa mulus, bukan "kosong lalu muncul".
      final path = _neighborFirstPath[index];
      final bytes = path != null ? _localImg[path] : null;
      if (bytes != null && bytes.isNotEmpty) {
        final rectNeighbor = _storyRect(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Positioned.fromRect(
              rect: rectNeighbor,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // Halaman tetangga hanya tampil SEBAGIAN (di-clip rect) &
                  // tidak di-zoom → cap 720px cukup. Tanpa cap, slide story
                  // (~5MB full-res) di-decode penuh untuk tiap tetangga yang
                  // di-preload → spike memory saat swipe antar-author.
                  cacheWidth: 720,
                ),
              ),
            ),
          ],
        );
      }
      return Container(color: Colors.black);
    }
    final s = ref.watch(localeProvider).s;
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
                        child: _loadError
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    s.storyLoadFail,
                                    style: AppText.body.copyWith(
                                      color: Colors.white54,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: () {
                                      if (mounted) _loadPerson();
                                    },
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: Text(s.btnRetry),
                                  ),
                                ],
                              )
                            : Text(
                                s.storyEmptyTray,
                                style: AppText.body.copyWith(
                                  color: Colors.white54,
                                ),
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
          // Tiap segmen bisa diketuk untuk lompat langsung ke slide itu
          // (area sentuh diperlebar 24px agar mudah kena jari).
          if (_slides.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 36,
              left: 12,
              right: 12,
              height: 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (int i = 0; i < _slides.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _goToSlide(i),
                        child: Container(
                          height: 24,
                          alignment: Alignment.center,
                          padding: EdgeInsets.only(
                            right: i < _slides.length - 1 ? 4 : 0,
                          ),
                          child: i < _slide
                              ? Container(
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                )
                              : i == _slide
                              ? SizedBox(
                                  height: 2,
                                  child: AnimatedBuilder(
                                    animation: _progress,
                                    builder: (_, __) => LinearProgressIndicator(
                                      value: _progress.value,
                                      backgroundColor: Colors.white24,
                                      valueColor: const AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                              : Container(height: 2, color: Colors.white24),
                        ),
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
                  // Visibilitas story: oleh pembuat sendiri ATAU admin (mode
                  // moderasi) — jawab "story ini tayang untuk siapa" /
                  // "ini private" (badge kunci).
                  if ((_own || _isAdmin) &&
                      !_loading &&
                      _slides.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    StoryVisibilityBadge(
                      visibility: _slides[_slide].visibility,
                      ownerOnly: _slides[_slide].ownerOnly,
                    ),
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
                    StoryHeaderBtn(
                      icon: Icons.visibility,
                      onPressed: _showViewers,
                    ),
                    const SizedBox(width: 12),
                    StoryHeaderBtn(
                      icon: Icons.delete_outline,
                      onPressed: _confirmDelete,
                    ),
                    const SizedBox(width: 12),
                  ],
                  StoryHeaderBtn(
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
            StoryCircleBtn(
              icon: Icons.send_rounded,
              color: AppTheme.primary,
              busy: _sendingReply,
              onTap: hasText && !_sendingReply ? _sendReply : null,
            ),
            const SizedBox(width: 8),
            StoryCircleBtn(
              icon: liked ? Icons.favorite : Icons.favorite_border,
              color: liked ? AppTheme.danger : Colors.white24,
              onTap: _toggleLike,
              popOnTap: true,
            ),
            const SizedBox(width: 8),
            StoryCircleBtn(
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
    // Jeda sebentar saat memproses like supaya slide tidak lompat.
    _pause();
    final authorId = _item.authorId;
    final sp = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(storyProvider.notifier);
    // Provider sudah menerapkan optimistic update secara sinkron sebelum
    // menunggu RPC. Rebuild viewer sekarang supaya hati langsung berubah;
    // hasil server menyusul untuk mengoreksi count/status bila perlu.
    final pending = sp.toggleLike(slide.id, authorId);
    if (mounted) setState(() {});
    await pending;
    if (mounted) {
      setState(() {});
      // Lanjutkan story setelah like — JANGAN biarkan timer mati "diam".
      // Kecuali user sedang menulis balasan (reply field fokus) → biarkan jeda.
      if (!_replyFocus.hasFocus) _resume();
    }
  }

  Future<void> _shareStory() async {
    if (_sharingStory) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final slide = _current;
    if (slide == null) return;
    setState(() => _sharingStory = true);
    try {
      // Video: bagikan file mp4 temp (sudah diunduh untuk playback).
      if (slide.isVideo) {
        final dir = await getTemporaryDirectory();
        final vf = File('${dir.path}/chatyuk_story_${slide.id}.mp4');
        if (await vf.exists()) {
          await Share.shareXFiles([
            XFile(vf.path, mimeType: 'video/mp4'),
          ], text: s.storyShareMsg(_item.authorName));
        } else {
          await Share.share(s.storyShareMsg(_item.authorName));
        }
      } else {
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
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final myUid = auth.uid;
    final authorId = _item.authorId;
    if (myUid == null || authorId.isEmpty || authorId == myUid) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    setState(() => _sendingReply = true);
    try {
      final chat = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(chatProvider.notifier);
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
    // Slide video: player (cover) atau spinner sambil init.
    if (slide.isVideo) {
      final v = _videoCtrl;
      final ready =
          v != null && v.value.isInitialized && _videoSlideId == slide.id;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: v.value.size.width,
                height: v.value.size.height,
                child: VideoPlayer(v),
              ),
            )
          else
            // Video dimuat → spinner polos (PLAY OTOMATIS, tanpa tombol
            // play). Ketuk tetap bisa memicu muat ulang bila macet.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_syncVideo()),
              child: Container(
                color: Colors.white10,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
        ],
      );
    }
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
