part of '../profile_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _ProfileBuildMx on _ProfileBase {
  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('Profile');
    // PERF (§2.3 / §26): dulu `context.watch<AuthNotifier>()` — SELURUH
    // halaman (CustomScrollView + slivers + galeri) rebuild tiap
    // `notifyListeners` AuthNotifier, termasuk **heartbeat presence** &
    // refresh profil berkala → sering menabrak frame transisi/tap tab =
    // jank. Sekarang `select` SNAPSHOT field yang benar-benar dipakai render,
    // dibandingkan via equality record: notify yang tidak mengubah field ini
    // TIDAK me-rebuild halaman.
    final (
      :profile,
      :uid,
      :isAnonymous,
      :signingOut,
      :dummySessionActive,
      :emailConfirmed,
      :userEmail,
    ) = ref.watch(
      authProvider.select(
        (a) => (
          profile: a.profile,
          uid: a.uid,
          isAnonymous: a.isAnonymous,
          signingOut: a.signingOut,
          dummySessionActive: a.dummySessionActive,
          emailConfirmed: a.emailConfirmed,
          userEmail: a.userEmail,
        ),
      ),
    );
    // Deteksi swap sesi (dummy ⇄ admin): profil berubah identitas tanpa
    // initState ulang. Pakai profile.id (bukan auth.uid) supaya reset hanya
    // terjadi saat DATA profil benar-benar milik akun baru — auth.uid sudah
    // berganti sebelum reloadProfile() selesai (race).
    final profileId = profile?.uid;
    if (profileId != null && profileId != _loadedUid) {
      _loadedUid = profileId;
      _cachedAvatarBytes = null;
      _lastAvatarB64 = null;
      _hashtags = List.of(profile?.hashtags ?? const []);
      _photos = [];
      _loadingPhotos = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPhotos();
      });
    }
    final avatarB64 = profile?.avatar ?? '';
    if (_lastAvatarB64 != avatarB64) {
      _lastAvatarB64 = avatarB64;
      _cachedAvatarBytes = null;
      if (avatarB64.isNotEmpty) {
        try {
          _cachedAvatarBytes = base64Decode(avatarB64);
        } catch (_) {}
      }
    }
    final avatarBytes = _cachedAvatarBytes;
    final locale = ref.watch(localeProvider);
    final s = locale.s;
    final avatarColor = profile?.gender == 'male'
        ? AppTheme.male
        : profile?.gender == 'female'
        ? AppTheme.female
        : AppTheme.accent;
    final genderLabel = profile?.gender == 'male'
        ? s.labelGenderMale
        : profile?.gender == 'female'
        ? s.labelGenderFemale
        : '';
    // Sesi anon SESUNGGUHNYA — jangan tampilkan banner saat proses keluar
    // (signingOut): sesi belum kosong & isAnonymous masih true sekejap →
    // banner oranye berkedip sebelum EntryScreen muncul.
    final isAnon = isAnonymous && !signingOut;
    // Sesi dummy aktif HANYA bisa dibuat dari panel admin (becomeDummy) —
    // flag internal AuthService. Dulu: kondisi && isRealAdmin membuat banner
    // TIDAK PERNAH tampil, karena saat sesi dummy aktif currentUser.email
    // = email DUMMY (bukan zunixe) → isRealAdmin false → "klik untuk
    // kembali ke admin" hilang.
    final dummyActive = dummySessionActive;
    // `select` (bukan `watch`): PointsProvider di-refresh beberapa kali saat
    // buka halaman (get_points_enabled/get_wallet/yukcoin_v2_status). `watch`
    // membuat SELURUH halaman Profil (CustomScrollView + slivers) rebuild tiap
    // refresh selesai — sering menabrak frame tap tab → jank (diukur 2026-09-30:
    // tab3 = tab paling sering jank, max 21ms). Aturan §2.3: halaman penuh WAJIB
    // `select` per field untuk provider yang sering berubah.
    final pointsEnabled = ref.watch(pointsProvider.select((p) => p.enabled));
    final pointsValue = ref.watch(pointsProvider.select((p) => p.points));
    final extraPhotoSlots = ref.watch(
      pointsProvider.select((p) => p.extraPhotoSlots),
    );
    final yukcoinV2Active = ref.watch(
      pointsProvider.select((p) => p.yukcoinV2Active),
    );

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      body: CustomScrollView(
        slivers: [
          _buildHeaderSliver(
            context,
            s,
            profile,
            avatarBytes,
            avatarColor,
            genderLabel,
          ),
          _buildBodySliver(
            context,
            s,
            profile,
            uid,
            isAnon,
            dummyActive,
            dummySessionActive,
            emailConfirmed,
            userEmail,
            pointsEnabled,
            pointsValue,
            extraPhotoSlots,
            yukcoinV2Active,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSliver(
    BuildContext context,
    S s,
    UserModel? profile,
    Uint8List? avatarBytes,
    Color avatarColor,
    String genderLabel,
  ) {
    return SliverAppBar(
      backgroundColor: AppTheme.headerGradient.colors.first,
      expandedHeight: 280,
      pinned: true,
      // Keluar pindah ke Pengaturan › Akun.
      actions: [
        // Tombol Misi DISEMBUNYIKAN — misi/reward dihapus (overhaul coin).
        IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 40, height: 44),
          icon: const Icon(Icons.share_outlined, size: 20),
          tooltip: s.btnShareApp,
          onPressed: () async {
            // Bonus share DIHAPUS (overhaul coin: tidak ada poin gratis).
            await Share.share(s.msgShareApp);
          },
        ),
        SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(gradient: AppTheme.headerGradient),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 20),
                // Avatar
                Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _showAvatarZoom(
                        avatarBytes,
                        avatarColor,
                        profile?.initial ?? '?',
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 46,
                          backgroundColor: avatarColor,
                          backgroundImage: avatarBytes != null
                              // Header profil radius 46 — cap decode.
                              ? ResizeImage(
                                  MemoryImage(avatarBytes),
                                  width: 184,
                                )
                              : null,
                          child: (profile?.avatar ?? '').isEmpty
                              ? Text(
                                  profile?.initial ?? '?',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: AppGlyph.avatarInitial(92),
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _uploading ? null : _showAvatarOptions,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          child: _uploading
                              ? Padding(
                                  padding: EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                )
                              : Icon(
                                  Icons.camera_alt,
                                  color: AppTheme.primary,
                                  size: 16,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                // Nama + verified badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      profile?.nickname ?? '-',
                      style: AppText.headline.copyWith(color: Colors.white),
                    ),
                    if (profile?.isRegistered == true) ...[
                      SizedBox(width: 4),
                      VerifiedBadge(
                        verified: ref.watch(
                          phoneVerifyProvider.select((p) => p.verified),
                        ),
                        size: 18,
                        tooltip: ref.read(localeProvider).s.phoneVerifiedBadge,
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 6),
                // Chips info
                Wrap(
                  spacing: 6,
                  children: [
                    if (genderLabel.isNotEmpty)
                      ProfileHeaderChip(label: genderLabel),
                    if ((profile?.age ?? 0) > 0)
                      ProfileHeaderChip(
                        label: '${profile?.age} ${s.labelYears}',
                      ),
                    if ((profile?.country ?? '').isNotEmpty)
                      ProfileHeaderChip(label: profile!.country),
                    if ((profile?.city ?? '').isNotEmpty)
                      ProfileHeaderChip(label: profile!.city),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) => AppTheme.statusColor(status);

  String _statusLabel(String status, S s) {
    switch (status) {
      case 'idle':
        return '🌙 ${s.statusIdle}';
      case 'offline':
        return '⚪ ${s.statusOffline}';
      case 'invisible':
        return '👻 ${s.statusInvisible}';
      default:
        return '🟢 ${s.statusOnline}';
    }
  }

  Future<void> _editSubscriptionPrice(BuildContext context) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final social = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(socialProvider.notifier);
    final current =
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(authProvider.notifier).profile?.subscriptionPrice ??
        0;
    final ctrl = TextEditingController(text: current > 0 ? '$current' : '');
    final price = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            Icon(Icons.star_rounded, color: Color(0xFFB8860B)),
            SizedBox(width: 8),
            Expanded(child: Text(s.setSubPriceTitle)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.subscribeCreatorHint,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: s.setSubPriceTitle,
                hintText: s.setSubPriceHint,
                suffixText: s.subscribePriceSuffix,
              ),
            ),
            SizedBox(height: 10),
            Text(
              s.setSubPriceExplain,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.btnCancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.pop(ctx, v);
            },
            child: Text(s.btnSave, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (price == null || !mounted) return;
    final ok = await social.setSubscriptionPrice(price);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? s.msgProfileSaved : s.errGeneric)),
    );
    if (ok)
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authProvider.notifier).reloadProfile();
  }
}
