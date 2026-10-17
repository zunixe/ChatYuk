part of '../user_info_screen.dart';

// Analyzer limitation: pada `part`+mixin, method yang dideklarasikan stubs di
// base tampak 'unused' walau dipanggil lintas-mixin. Aman diabaikan.
// ignore_for_file: unused_element

mixin _UiBuildMx on _UserInfoBase {  Widget build(BuildContext context) {
    PerfProbe.buildCount('UserInfo');
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    final profile = _profile;
    final authSnap = ref.watch(
      authProvider.select(
        (a) => (isAnon: a.isAnonymous, callAll: a.callAllEnabled, uid: a.uid),
      ),
    );
    final name = profile?.nickname ?? widget.fallbackName;
    final genderLabel = profile?.gender == 'male'
        ? s.genderLabelMale
        : profile?.gender == 'female'
        ? s.genderLabelFemale
        : s.genderLabelOther;
    final status = _status;
    final presence = status == 'online'
        ? 'Online'
        : (status == 'idle' ? s.statusIdle : s.statusOffline);
    final isSelf = authSnap.uid == widget.userId;
    final photos = _photos.where((p) => p.unlocked).toList();
    final galleryCount = photos.length + (_avatarB64.isEmpty ? 0 : 1);
    final initial = (name.isNotEmpty ? name[0] : '?').toUpperCase();
    // Foto masih kosong padahal profil punya path -> coba sekali lagi
    // (kegagalan pertama bisa sesaat). Guard `_avatarRetried` anti-loop.
    if (_avatarB64.isEmpty && _avatarPath.isNotEmpty && !_avatarRetried) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _avatarB64.isEmpty) _loadAvatar(_avatarPath);
      });
    }
    final location = profile == null
        ? ''
        : [profile.city, profile.country].where((e) => e.isNotEmpty).join(', ');

    return Scaffold(
      backgroundColor: PColors.bg,
      extendBody: true,
      body: _loading
          ? UserInfoLoadingPlaceholder(name: widget.fallbackName)
          : (_loadError && _profile == null)
          ? UserInfoLoadErrorView(onRetry: _retryLoad)
          : _PProfileBody(
              name: name,
              age: profile?.age ?? 0,
              genderLabel: genderLabel,
              country: profile?.country ?? '',
              presence: presence,
              isOnline: status == 'online',
              verified: profile?.isRegistered == true,
              avatarBytes: _decodedAvatarBytes(),
              gallery: photos,
              galleryBytes: _galleryBytesOf,
              avatarBytesFallback: _avatarB64.isNotEmpty
                  ? _decodedAvatarBytes()
                  : null,
              initial: initial,
              hashtags: profile?.hashtags ?? const <String>[],
              bio: null,
              location: location,
              userId: widget.userId,
              userIdShort: widget.userId.length > 8
                  ? widget.userId.substring(0, 8)
                  : widget.userId,
              followers: profile?.followersCount ?? 0,
              following: profile?.followingCount ?? 0,
              subscribers: profile?.subscriberCount ?? 0,
              isFriend: _friend,
              isFriendRequestSent: _friendRequestSent,
              isFollowing: _following,
              isSubscribed: _subscribed,
              isSelf: isSelf,
              canCall:
                  authSnap.callAll || (!authSnap.isAnon && profile?.isRegistered == true),
              s: s,
              onCall: (type) => _startCall(context, type),
              onMessage: _startChat,
              onAddFriend: _addFriend,
              onUnfriend: _unfriend,
              onToggleFollow: _toggleFollow,
              onSubscribe: _subscribe,
              onCancelFriendRequest: _cancelFriendRequest,
              onFollowersTap: () => _openSocialList('followers'),
              onFollowingTap: () => _openSocialList('following'),
              onOpenPhoto: (i) {
                if (photos.isEmpty) return;
                _showPhotoViewer(photos, i);
              },
              onCopyId: () => copyWithToast(context, widget.userId, 'User ID disalin'),
              onFollowInfo: () => _showFollowVsFriendInfo(context, s),
              onBlock: () => _blockUser(context),
              onReport: () => _reportUser(context),
              galleryCount: galleryCount,
            ),
    );
  }

  /// Carousel foto profil: avatar + foto terbuka, geser kiri-kanan.
  /// Tanpa foto sama sekali → lingkaran inisial (tidak bisa digeser).
  /// Blokir user ini (konfirmasi dulu, gaya dialog desain baru).
  Future<void> _blockUser(BuildContext context) async {
    final ok = await confirmPUnfriend(
      context,
      name: widget.fallbackName,
      title: 'Blokir pengguna?',
      body:
          '{name} tidak akan bisa mengirim pesan atau melihat profilmu. '
          'Kamu bisa membuka blokir kapan saja.',
      confirmLabel: 'Blokir',
    );
    if (!ok || !mounted) return;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final myUid = auth.uid;
    if (myUid == null) return;
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(chatProvider.notifier)
          .blockUser(myUid, widget.userId);
      if (mounted) showProfileToast(context, 'Pengguna diblokir');
    } catch (_) {
      if (mounted) showProfileToast(context, 'Gagal memblokir');
    }
  }

  /// Laporkan user ini (dialog laporan yang sudah ada di app).
  void _reportUser(BuildContext context) {
    showReportUserDialog(
      context,
      reportedId: widget.userId,
      reportedName: _profile?.nickname ?? widget.fallbackName,
    );
  }

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
