part of '../user_info_screen.dart';

// Analyzer limitation: pada `part`+mixin, method yang dideklarasikan stubs di
// base tampak 'unused' walau dipanggil lintas-mixin. Aman diabaikan.
// ignore_for_file: unused_element

mixin _UiBuildMx on _UserInfoBase {
  Widget build(BuildContext context) {
    PerfProbe.buildCount('UserInfo');
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    final profile = _profile;
    final pointsEnabled = ref.watch(pointsProvider.select((p) => p.enabled));
    // Tombol sosial (pengikut/mengikuti/subscriber + ikuti/tambah teman)
    // SELALU tampil — viewer anon yang mengetuk diberi snackbar daftar
    // (guard di _toggleFollow/_addFriend). Jangan disembunyikan.
    // PERF (§26b): dulu `watch<AuthNotifier>()` penuh → seluruh halaman
    // rebuild tiap AuthNotifier notify. `select` snapshot field yang dipakai
    // render (value-type) saja.
    final authSnap = ref.watch(
      authProvider.select(
        (a) => (isAnon: a.isAnonymous, callAll: a.callAllEnabled, uid: a.uid),
      ),
    );
    final isAnonViewer = authSnap.isAnon;

    final name = profile?.nickname ?? widget.fallbackName;
    final genderLabel = profile?.gender == 'male'
        ? s.genderLabelMale
        : profile?.gender == 'female'
        ? s.genderLabelFemale
        : s.genderLabelOther;
    final status = _status;
    final statusLabel = status == 'online'
        ? s.statusOnline
        : status == 'idle'
        ? s.statusIdle
        : s.statusOffline;
    final statusColor = AppTheme.statusColor(status);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.titleProfile),
        actions: [
          // Tombol call: default hanya untuk viewer terdaftar & target
          // terdaftar. Admin bisa membukanya ke SEMUA user via panel
          // (app_settings.call_all_enabled).
          if (authSnap.callAll ||
              (!isAnonViewer && profile?.isRegistered == true)) ...[
            PopupMenuButton<String>(
              icon: Icon(Icons.call, size: 22),
              color: AppTheme.bgCard,
              tooltip: s.callAudio,
              onSelected: (val) => _startCall(context, val),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'audio',
                  child: Row(
                    children: [
                      Icon(Icons.call, size: 18),
                      const SizedBox(width: 12),
                      Text(s.callAudio),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'video',
                  child: Row(
                    children: [
                      Icon(Icons.videocam, size: 18),
                      const SizedBox(width: 12),
                      Text(s.callVideo),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _loading
          ? UserInfoLoadingPlaceholder(name: widget.fallbackName)
          : (_loadError && _profile == null)
          ? UserInfoLoadErrorView(onRetry: _retryLoad)
          : SafeArea(
              // Cegah konten menembus system UI (nav bar/gesture bar
              // Android). top: false — AppBar sudah menangani status bar.
              top: false,
              child: Builder(
                builder: (_) {
                  // Foto masih kosong padahal profil punya path → coba sekali lagi
                  // (kegagalan pertama bisa sesaat). Guard `_avatarRetried` supaya
                  // tidak memicu loop kalau memang tidak ada fotonya.
                  if (_avatarB64.isEmpty &&
                      _avatarPath.isNotEmpty &&
                      !_avatarRetried) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _avatarB64.isEmpty)
                        _loadAvatar(_avatarPath);
                    });
                  }
                  return SingleChildScrollView(
                    // padding bawah + tinggi nav bar Android supaya card galeri
                    // (terakhir) tidak tertutup gesture bar / 3-tombol.
                    padding: EdgeInsets.fromLTRB(
                      24,
                      24,
                      24,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Column(
                      children: [
                        SizedBox(height: 8),

                        // Galeri geser: avatar + foto terbuka, slide kiri-kanan.
                        // Ketuk foto = tampil penuh.
                        _profileCarousel(
                          avatarB64: _avatarB64,
                          avatarBg: profile?.gender == 'male'
                              ? AppTheme.male
                              : profile?.gender == 'female'
                              ? AppTheme.female
                              : AppTheme.accent,
                          initial: (name.isNotEmpty ? name[0] : '?')
                              .toUpperCase(),
                          statusColor: statusColor,
                          unlocked: _photos.where((p) => p.unlocked).toList(),
                        ),
                        SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: AppText.headline.copyWith(
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (profile?.isRegistered == true) ...[
                              SizedBox(width: 5),
                              VerifiedBadgeForUid(uid: widget.userId, size: 20),
                            ],
                            // Ikon chat kecil di samping username — klik langsung chat.
                            // Anon BOLEH chat (sama dengan perilaku menu online) —
                            // dulu disembunyikan untuk anon = inkonsisten.
                            if (authSnap.uid != widget.userId) ...[
                              SizedBox(width: 8),
                              UserChatIconButton(onTap: _startChat),
                            ],
                          ],
                        ),
                        SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              genderLabel,
                              style: AppText.bodyStrong.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            if (profile?.age != null && profile!.age > 0) ...[
                              SizedBox(width: 12),
                              Text(
                                '${profile.age} ${s.labelYears}',
                                style: AppText.bodyStrong.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 24),

                        if (profile != null && profile.hashtags.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: profile.hashtags
                                .map(
                                  (tag) => Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accent.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppTheme.accent.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '#$tag',
                                      style: AppText.label.copyWith(
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          SizedBox(height: 24),
                        ],

                        // Info card
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _infoRow(s.labelStatus, statusLabel),
                                if (profile != null) ...[
                                  Divider(color: AppTheme.divider),
                                  _infoRow(
                                    s.labelCountry,
                                    profile.country.isEmpty
                                        ? '-'
                                        : profile.country,
                                  ),
                                  Divider(color: AppTheme.divider),
                                  _infoRow(
                                    s.labelCity,
                                    profile.city.isEmpty ? '-' : profile.city,
                                  ),
                                ],
                                Divider(color: AppTheme.divider),
                                _infoRow(
                                  s.labelUserId,
                                  widget.userId.substring(0, 8),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 16),

                        // Sosial kompak: stat mini + tombol ikon kecil, langsung
                        // terlihat tanpa scroll. Selalu tampil (termasuk viewer
                        // anon) — guard daftar ada di tiap aksi.
                        if (profile != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _miniStat(
                                Icons.favorite_rounded,
                                const Color(0xFFE91E63),
                                profile.followersCount,
                                s.socialFollowers,
                                onTap: () => _openSocialList('followers'),
                              ),
                              _miniStat(
                                Icons.person_rounded,
                                AppTheme.primary,
                                profile.followingCount,
                                s.socialFollowing,
                                onTap: () => _openSocialList('following'),
                              ),
                              _miniStat(
                                Icons.star_rounded,
                                const Color(0xFFB8860B),
                                profile.subscriberCount,
                                s.socialSubscribers,
                                onTap: () => _openSocialList('subscribers'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_busySocial)
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _friend
                                    ? _iconActionBtn(
                                        icon: Icons.group_rounded,
                                        label: s.btnFriends,
                                        color: Colors.green,
                                        active: true,
                                        onTap: _unfriend,
                                      )
                                    : _friendRequestSent
                                    ? _iconActionBtn(
                                        icon: Icons.schedule_rounded,
                                        label: s.btnCancelRequest,
                                        color: Colors.orange,
                                        active: true,
                                        onTap: _cancelFriendRequest,
                                      )
                                    : _iconActionBtn(
                                        icon: Icons.group_add_rounded,
                                        label: s.btnAddFriend,
                                        color: Colors.green,
                                        active: false,
                                        onTap: _addFriend,
                                      ),
                                const SizedBox(width: 12),
                                // Saat berteman, tombol ini = "Putus Teman" (unfollow
                                // juga memutus friend_requests di server).
                                _iconActionBtn(
                                  icon: _friend
                                      ? Icons.group_remove_rounded
                                      : (_following
                                            ? Icons.check_rounded
                                            : Icons.person_add_alt_1_rounded),
                                  label: _friend
                                      ? s.btnUnfriend
                                      : (_following
                                            ? s.btnUnfollow
                                            : s.btnFollow),
                                  color: _friend
                                      ? AppTheme.danger
                                      : (_following
                                            ? AppTheme.textSecondary
                                            : AppTheme.primary),
                                  active: _friend || _following,
                                  onTap: _friend ? _unfriend : _toggleFollow,
                                ),
                                const SizedBox(width: 6),
                                // Info: beda Follow vs Tambah Teman.
                                IconButton(
                                  tooltip: s.sheetFollowVsFriendTitle,
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    Icons.info_outline_rounded,
                                    size: 20,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed: () =>
                                      _showFollowVsFriendInfo(context, s),
                                ),
                                if (pointsEnabled &&
                                    profile.subscriptionPrice > 0) ...[
                                  const SizedBox(width: 12),
                                  _subscribed
                                      ? _iconActionBtn(
                                          icon: Icons.star_rounded,
                                          label: s.btnSubscribed,
                                          color: const Color(0xFFB8860B),
                                          active: true,
                                          onTap: () {},
                                        )
                                      : _iconActionBtn(
                                          icon: Icons.star_rounded,
                                          label:
                                              '${s.btnSubscribe} · ${s.subscribePrice(profile.subscriptionPrice)}',
                                          color: const Color(0xFFB8860B),
                                          active: false,
                                          onTap: _subscribe,
                                        ),
                                ],
                              ],
                            ),
                          const SizedBox(height: 8),
                        ],

                        // Galeri Foto Profil dihapus sesuai permintaan — tidak
                        // ditampilkan lagi di halaman profil orang lain.
                        const SizedBox.shrink(),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  /// Carousel foto profil: avatar + foto terbuka, geser kiri-kanan.
  /// Tanpa foto sama sekali → lingkaran inisial (tidak bisa digeser).
  Widget _profileCarousel({
    required String avatarB64,
    required Color avatarBg,
    required String initial,
    required Color statusColor,
    required List<UserPhoto> unlocked,
  }) {
    // Bytes dari cache (decode sekali saat b64 berubah) — jangan decode di
    // dalam build. Parameter `avatarB64` = `_avatarB64` (lihat pemanggil).
    final Uint8List? avatarBytes = _decodedAvatarBytes();
    final pageCount = (avatarBytes != null ? 1 : 0) + unlocked.length;
    if (pageCount == 0) {
      // Tidak ada foto → INISIAL dengan WARNA GENDER (tint + huruf + ring),
      // konsisten dgn avatar orang yang sama di list Online/chat/leaderboard.
      // `avatarBg` di sini = warna gender (dihitung pemanggil).
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: avatarBg.withValues(alpha: 0.15),
          border: Border.all(color: avatarBg, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: TextStyle(
            color: avatarBg,
            fontSize: AppGlyph.avatarInitial(120),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (_carouselIndex >= pageCount) _carouselIndex = 0;
    Widget avatarPage() {
      final b = avatarBytes;
      final img = b == null
          ? Container(
              color: avatarBg.withValues(alpha: 0.15),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: avatarBg,
                    fontSize: AppGlyph.avatarInitial(120),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          // Carousel 280px — cap 720px (bukan full-res).
          : Image.memory(
              b,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: 720,
            );
      return GestureDetector(
        onTap: b == null ? null : () => _showFullscreenPhoto(b),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox.expand(child: img),
        ),
      );
    }

    Widget galleryPage(UserPhoto photo) {
      final b = _galleryBytesOf(photo);
      return GestureDetector(
        onTap: () => _showPhotoViewer(unlocked, unlocked.indexOf(photo)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox.expand(
            child: b == null
                ? Container(color: AppTheme.bgCard)
                : Image.memory(
                    b,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: 720,
                  ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 280,
          width: double.infinity,
          child: Stack(
            children: [
              PageView.builder(
                controller: _carouselCtrl,
                onPageChanged: (i) => setState(() => _carouselIndex = i),
                itemCount: pageCount,
                itemBuilder: (_, i) {
                  if (avatarBytes != null && i == 0) return avatarPage();
                  final photo = unlocked[i - (avatarBytes != null ? 1 : 0)];
                  return galleryPage(photo);
                },
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (pageCount > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              pageCount,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _carouselIndex == i ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _carouselIndex == i
                      ? AppTheme.primary
                      : AppTheme.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showFullscreenPhoto(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                // Cap 1080px: dialog zoom tidak butuh full-res 12MP.
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  cacheWidth: 1080,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Keluarkan bitmap zoom dari ImageCache (pola PhotoViewerScreen).
      if (bytes.isNotEmpty) {
        try {
          PaintingBinding.instance.imageCache.evict(MemoryImage(bytes));
        } catch (_) {}
      }
    });
  }

  /// Stat mini di bawah nama: ikon kecil + angka (tanpa kartu besar).
  Widget _miniStat(
    IconData icon,
    Color color,
    int value,
    String label, {
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: row,
    );
  }

  void _openSocialList(String kind) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialListScreen(kind: kind, userId: widget.userId),
      ),
    );
  }

  /// Tombol aksi ikon kecil (ikuti/teman/subscribe): lingkaran + tulisan
  /// mungil di bawahnya supaya jelas maksud ikonnya. Nonaktif saat sibuk
  /// / sudah aktif.
  Widget _iconActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool active,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: color.withValues(alpha: active ? 0.14 : 1),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _busySocial ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: _busySocial
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: active ? color : Colors.white,
                        ),
                      )
                    : Icon(
                        icon,
                        size: 20,
                        color: active ? color : Colors.white,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 76,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.micro.copyWith(
                color: active ? color : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textSecondary)),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
