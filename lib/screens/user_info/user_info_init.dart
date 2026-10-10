part of '../user_info_screen.dart';

// Analyzer limitation: pada `part`+mixin, method yang dideklarasikan stubs di
// base tampak 'unused' walau dipanggil lintas-mixin. Aman diabaikan.
// ignore_for_file: unused_element

mixin _UiInitMx on _UserInfoBase {
  @override
  void initState() {
    super.initState();
    // Seed: kalau pemanggil sudah punya data (nama/gender/foto), tampilkan
    // langsung — jangan lewat fase spinner dulu.
    if (widget.initialProfile != null) {
      _profile = widget.initialProfile;
      _loading = false;
      // Status live tidak perlu menunggu fetch profil selesai.
      _subscribeStatus(widget.initialProfile);
    }
    // ── ANTI-KEDIP (urutan prioritas foto) ──
    // 1) Foto B64 yang DIKIRIM pemanggil (mis. dari leaderboard yang sudah
    //    menampilkan foto) → pakai langsung, frame pertama = foto.
    // 2) Cache RAM/disk per-uid.
    // 3) Path → muat dari disk/RAM (async), placeholder = latar kosong.
    final seedAvatar = _profile?.avatar ?? '';
    final seedIsPath =
        seedAvatar.isNotEmpty &&
        StoragePhotoService.instance.isAvatarPath(seedAvatar);
    if (seedAvatar.isNotEmpty && !seedIsPath) {
      // B64 langsung dari pemanggil.
      _avatarB64 = seedAvatar;
    } else {
      _avatarB64 =
          ProviderScope.containerOf(
            context,
            listen: false,
          ).read(authProvider.notifier).cachedAvatarSyncDeep(widget.userId) ??
          '';
    }
    if (_avatarB64.isEmpty && seedIsPath) {
      // Foto ada sebagai path → muat (inisial tampil sampai bytes siap).
      _loadAvatar(seedAvatar);
    } else if (_avatarB64.isEmpty) {
      // Belum tahu ada foto atau tidak → coba cache RAM/disk per-uid.
      _ensureAvatarFromCache();
    }
    _load();
    _loadPhotos();
    _loadSocial();
    // Ambil nominal biaya buka foto untuk label harga.
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier).refreshPhotoCosts();
  }

  /// Fallback anti-kedip: kalau belum ada b64 dari pemanggil, coba ambil
  /// dari cache RAM/disk per-uid (async, murah). Tidak menggagalkan UI.
  Future<void> _ensureAvatarFromCache() async {
    final uid = widget.userId;
    if (uid.isEmpty) return;
    try {
      final b64 = await AvatarB64Service.instance.get(uid);
      if (!mounted) return;
      if (b64.isNotEmpty) setState(() => _avatarB64 = b64);
    } catch (_) {}
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _carouselCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSocial() async {
    try {
      final st = await ProviderScope.containerOf(context, listen: false)
          .read(socialProvider.notifier)
          .mySocialStatus(widget.userId)
          .timeout(_loadTimeout);
      if (!mounted) return;
      setState(() {
        _following = st['following'] == true;
        _friend = st['friend'] == true;
        _friendRequestSent = st['friend_request_sent'] == true;
        _subscribed = st['subscribed'] == true;
      });
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final targetRegistered = _profile?.isRegistered ?? false;
    if (auth.isAnonymous || !(auth.profile?.isRegistered ?? false)) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgRegisterToFollow)));
      return;
    }
    if (!targetRegistered) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgTargetNotRegistered)));
      return;
    }
    final social = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(socialProvider.notifier);
    setState(() => _busySocial = true);
    final ok = _following
        ? await social.unfollow(widget.userId)
        : await social.follow(widget.userId);
    if (!mounted) return;
    setState(() {
      // Hanya toggle kalau RPC sukses — kalau gagal, biarkan state tetap
      // sinkron dengan server (tidak menampilkan tombol yang menyesatkan).
      if (ok) {
        _following = !_following;
        if (!_following) _friend = false;
      }
      _busySocial = false;
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_following ? s.btnFollow : s.btnUnfollow)),
      );
    }
  }

  Future<void> _addFriend() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final targetRegistered = _profile?.isRegistered ?? false;
    if (auth.isAnonymous || !(auth.profile?.isRegistered ?? false)) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgRegisterToFollow)));
      return;
    }
    if (!targetRegistered) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgTargetNotRegistered)));
      return;
    }
    final social = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(socialProvider.notifier);
    setState(() => _busySocial = true);
    final status = await social.sendFriendRequest(widget.userId);
    if (!mounted) return;
    setState(() {
      if (status == 'pending') _friendRequestSent = true;
      _busySocial = false;
    });
    // Pesan akurat: 'friends' (sudah teman), 'pending' (terkirim),
    // selain itu gagal — jangan selalu bilang "terkirim".
    if (status == 'friends') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.snackNowFriends(_profile?.nickname ?? ''))),
      );
    } else if (status == 'pending') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.friendRequestSentMutual)));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  /// Putus pertemanan: konfirmasi dulu, lalu unfollow (yang juga menghapus
  /// relasi friend_requests kedua arah di server → benar-benar putus).
  /// Dialog & snackbar lewat helper bersama `social_actions.dart`.
  Future<void> _unfriend() async {
    final name = _profile?.nickname ?? '';
    final social = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(socialProvider.notifier);
    setState(() => _busySocial = true);
    final ok = await runUnfriend(context, social, widget.userId, name);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _friend = false;
        _following = false;
      }
      _busySocial = false;
    });
  }

  /// Batalkan permintaan teman yang sudah dikirim (id diambil dari outbox).
  Future<void> _cancelFriendRequest() async {
    final name = _profile?.nickname ?? '';
    final social = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(socialProvider.notifier);
    setState(() => _busySocial = true);
    final ok = await runCancelRequest(context, social, widget.userId, name);
    if (!mounted) return;
    setState(() {
      if (ok) _friendRequestSent = false;
      _busySocial = false;
    });
  }

  /// Bottom sheet penjelasan beda "Ikuti" (Follow) vs "Tambah Teman".
  void _showFollowVsFriendInfo(BuildContext context, S s) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.sheetFollowVsFriendTitle,
                style: AppText.title.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              _followFriendInfoRow(
                icon: Icons.person_add_alt_1_rounded,
                color: AppTheme.primary,
                title: s.sheetFollowLabel,
                desc: s.sheetFollowDesc,
              ),
              const SizedBox(height: 14),
              _followFriendInfoRow(
                icon: Icons.group_add_rounded,
                color: Colors.green,
                title: s.sheetFriendLabel,
                desc: s.sheetFriendDesc,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.hintFriendMutual,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _followFriendInfoRow({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.label.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _subscribe() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final profile = _profile;
    if (profile == null) return;
    final price = profile.subscriptionPrice;
    if (price <= 0) return;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    if (!auth.canUsePaid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
      return;
    }
    final points = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            Icon(Icons.star_rounded, color: Color(0xFFB8860B)),
            SizedBox(width: 8),
            Expanded(child: Text(s.subscribeConfirmTitle)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.subscribeConfirmBody(profile.nickname, price, 1),
              style: AppText.bodyStrong,
            ),
            SizedBox(height: 12),
            Text(
              s.subscribeFansHint,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.btnSubscribe,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busySocial = true);
    try {
      await points.subscribeCreator(widget.userId);
      if (!mounted) return;
      setState(() => _subscribed = true);
      points.refreshWallet();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.subscribeSuccess)));
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('registered')
          ? s.subscribeNeedRegister
          : msg.contains('Not enough paid') || msg.contains('Not enough')
          ? s.subscribeNeedPaid
          : s.errGeneric;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(show)));
    } finally {
      if (mounted) setState(() => _busySocial = false);
    }
  }
}
