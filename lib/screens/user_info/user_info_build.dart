part of '../user_info_screen.dart';

// Analyzer limitation: pada `part`+mixin, method yang dideklarasikan stubs di
// base tampak 'unused' walau dipanggil lintas-mixin. Aman diabaikan.

mixin _UiBuildMx on _UserInfoBase {  @override
  Widget build(BuildContext context) {
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
    final s = ref.read(localeProvider).s;
    final ok = await confirmPUnfriend(
      context,
      name: widget.fallbackName,
      title: s.blockConfirmTitle,
      body: s.blockConfirmBody,
      confirmLabel: s.btnBlock,
    );
    if (!ok || !context.mounted) return;
    final myUid = ref.read(authProvider.notifier).uid;
    if (myUid == null) return;
    try {
      await ref.read(chatProvider.notifier).blockUser(myUid, widget.userId);
      dlog('[BLOCK] ok (profil) me=$myUid other=${widget.userId}');
      if (context.mounted) showProfileToast(context, s.blockSuccess);
    } catch (e) {
      dlog('[BLOCK] GAGAL (profil) me=$myUid other=${widget.userId} err=$e');
      if (context.mounted) {
        showProfileToast(
          context,
          s.blockFailed(offline: ChatNotifier.isNetworkError(e)),
        );
      }
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

  void _openSocialList(String kind) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialListScreen(kind: kind, userId: widget.userId),
      ),
    );
  }

}
