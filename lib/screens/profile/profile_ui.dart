part of '../profile_screen.dart';


/// Warna halaman Profil — DINAMIS mengikuti tema aplikasi (bukan warna baru).
/// `bg`/`card`/`divider` memakai palet yang sudah ada di [AppTheme].
class _Pc {
  static Color get bg => AppTheme.bgScreen;
  static Color get card => AppTheme.bgCard;
  static Color get cardDivider => AppTheme.divider;
  static Color get button => AppTheme.bgInput;
  static Color get border => AppTheme.divider;
}

mixin _ProfileUiMx on _ProfileBase {
  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('Profile');
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
    final s = ref.watch(localeProvider).s;
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
    final isAnon = isAnonymous && !signingOut;
    final dummyActive = dummySessionActive;
    final pointsEnabled = ref.watch(pointsProvider.select((p) => p.enabled));
    final pointsValue = ref.watch(pointsProvider.select((p) => p.points));
    final extraPhotoSlots = ref.watch(
      pointsProvider.select((p) => p.extraPhotoSlots),
    );
    final yukcoinV2Active = ref.watch(
      pointsProvider.select((p) => p.yukcoinV2Active),
    );
    // Simpan untuk seksi Foto (dibaca tanpa watch tambahan).
    _extraSlotsCache = extraPhotoSlots;

    return Scaffold(
      backgroundColor: _Pc.bg,
      appBar: AppBar(
        backgroundColor: _Pc.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 52,
        titleSpacing: 16,
        automaticallyImplyLeading: false,
        title: Text(
          profile?.nickname ?? s.titleProfile,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AppTextSize.s20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: s.btnShareApp,
            icon: Icon(
              Icons.share_outlined,
              size: 21,
              color: AppTheme.textPrimary,
            ),
            onPressed: () async {
              await Share.share(s.msgShareApp);
            },
          ),
          IconButton(
            tooltip: s.titleSettings,
            icon: Icon(
              Icons.settings_outlined,
              size: 21,
              color: AppTheme.textPrimary,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (dummySessionActive)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child:
                    AdminGate.dummySessionBanner?.call(
                      context,
                      profile?.nickname,
                    ) ??
                    const SizedBox.shrink(),
              ),
            if (isAnon && !dummyActive) _anonBanner(context, s),
            _topSection(
              context,
              s,
              profile,
              avatarBytes,
              avatarColor,
              genderLabel,
              emailConfirmed,
            ),
            _hashtagSection(context, s),
            _actionButtons(context, s, profile),
            if (pointsEnabled)
              _pointsInfo(
                context,
                s,
                pointsValue,
                extraPhotoSlots,
                yukcoinV2Active,
                isAnon: isAnon,
              ),
            _friendRequestBanner(context, s),
            _photosSection(context, s),
            if (!isAnon)
              _accountSection(
                context,
                s,
                profile,
                uid,
                userEmail,
                emailConfirmed,
              ),
            _otherSection(context, s),
            _footer(context, s),
          ],
        ),
      ),
    );
  }
}

/// ── Judul seksi (13 w700 abu, tinggi 32) ──
Widget _sectionTitle(String text, {Widget? trailing}) {
  return SizedBox(
    height: 32,
    child: Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppTextSize.s13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

///// ── Label status kecil (hijau bila online) ──
Widget _statusPill(bool online) {
  final c = online ? AppTheme.online : AppTheme.textSecondary;
  return Container(
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          online ? 'Online' : 'Offline',
          style: TextStyle(
            fontSize: AppTextSize.s115,
            fontWeight: FontWeight.w700,
            color: c,
          ),
        ),
      ],
    ),
  );
}

/// Seksi-seksi halaman Profil (bagian atas, hashtag, aksi, foto, akun, lainnya).
///
/// CATATAN: `_buildBodySliver`, `_statusColor`, `_statusLabel`,
/// `_editSubscriptionPrice` tetap disediakan `_ProfileBuildMx` &
/// `_ProfileBodyMx` (file lama) supaya logika data tidak berubah — mixin itu
/// TIDAK lagi dipakai untuk render halaman, hanya sebagai penyedia helper.
mixin _ProfileUiSectionsMx on _ProfileBase {
  /// Banner peringatan sesi ANON (fitur lama, tetap ditampilkan).
  @override
  Widget _anonBanner(BuildContext context, S s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.titleAccountSecurity,
                    style: AppText.bodySmall.copyWith(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.msgAnonymousWarning,
              style: AppText.bodySmall.copyWith(color: Colors.orange.shade700),
            ),
            const SizedBox(height: 2),
            Text(
              s.msgAnonRetention7d,
              style: AppText.bodySmall.copyWith(color: Colors.orange.shade800),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LinkEmailScreen()),
                ),
                icon: const Icon(Icons.security, size: 18),
                label: Text(s.btnSecureAccount),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [2] BAGIAN ATAS: avatar 84 + 3 statistik sejajar, lalu nama/status/info,
  /// lalu baris TENTANG (label + nilai + pensil edit) — satu-satunya tampilan
  /// & editor about (bio lama dihapus supaya tidak dobel).
  @override
  Widget _topSection(
    BuildContext context,
    S s,
    UserModel? profile,
    Uint8List? avatarBytes,
    Color avatarColor,
    String genderLabel,
    bool emailConfirmed,
  ) {
    final online = profile?.status == 'online';
    final name = profile?.nickname ?? '-';
    final loc = [
      if ((profile?.city ?? '').isNotEmpty) profile!.city,
      if ((profile?.country ?? '').isNotEmpty) profile!.country,
    ].join(', ');
    final info = [
      if (genderLabel.isNotEmpty) genderLabel,
      if ((profile?.age ?? 0) > 0) '${profile!.age} ${s.labelYears}',
      if (loc.isNotEmpty) loc,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar 84 + tombol kamera 28 (border 3 warna bg).
              GestureDetector(
                onTap: () => _showAvatarZoom(
                  avatarBytes,
                  avatarColor,
                  profile?.initial ?? '?',
                ),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: avatarColor,
                        backgroundImage: avatarBytes != null
                            ? ResizeImage(MemoryImage(avatarBytes), width: 168)
                            : null,
                        child: (profile?.avatar ?? '').isEmpty
                            ? Text(
                                profile?.initial ?? '?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: AppGlyph.avatarInitial(84),
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: GestureDetector(
                          onTap: _uploading ? null : _showAvatarOptions,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: _Pc.bg, width: 3),
                            ),
                            child: _uploading
                                ? Padding(
                                    padding: const EdgeInsets.all(5),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _stat(
                        profile?.followersCount ?? 0,
                        s.socialFollowers,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SocialListScreen(kind: 'followers'),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _stat(
                        profile?.followingCount ?? 0,
                        s.socialFollowing,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SocialListScreen(kind: 'following'),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _stat(
                        profile?.friendsCount ?? 0,
                        s.socialFriends,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SocialListScreen(kind: 'friends'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextSize.s15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusPill(online),
            ],
          ),
          if (info.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              info,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTextSize.s135,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          // TENTANG — diedit inline di tempat (logika lama di profile_body).
          // Ditampilkan sebagai baris label + nilai + pensil edit agar fitur
          // "About" yang sebelumnya hilang di redesign kembali tersedia.
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.labelAbout,
                      style: TextStyle(
                        fontSize: AppTextSize.s12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (_editingAbout)
                      TextField(
                        controller: _aboutCtrl,
                        autofocus: true,
                        maxLength: 150,
                        maxLines: null,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveAbout(),
                        style: TextStyle(
                          fontSize: AppTextSize.s14,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: s.hintAbout,
                          hintStyle: TextStyle(
                            fontSize: AppTextSize.s13,
                            color: AppTheme.textSecondary,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                        ),
                      )
                    else
                      Text(
                        (profile?.about ?? '').isEmpty
                            ? s.aboutEmpty
                            : profile!.about,
                        style: (profile?.about ?? '').isEmpty
                            ? TextStyle(
                                fontSize: AppTextSize.s135,
                                color: AppTheme.textSecondary,
                              )
                            : TextStyle(
                                fontSize: AppTextSize.s14,
                                height: AppTextSize.lh145,
                                color: AppTheme.textPrimary.withValues(
                                  alpha: 0.88,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
              if (_editingAbout) ...[
                if (_savingAbout)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.check, size: 20),
                    color: AppTheme.primary,
                    onPressed: _saveAbout,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppTheme.textSecondary,
                    onPressed: _savingAbout ? null : _cancelEditAbout,
                  ),
                ],
              ] else
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: AppTheme.primary,
                  tooltip: s.btnEditProfile,
                  onPressed: () => _startEditAbout(profile?.about ?? ''),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(int value, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: AppTextSize.s18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTextSize.s125,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [3] HASHTAG: chip + hapus, plus chip "+ Tambah hashtag" inline.
  @override
  Widget _hashtagSection(BuildContext context, S s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Builder(
        builder: (_) => Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final t in _hashtags)
              _hashChip(context, t, () => _removeHashtag(t)),
            _addHashtagChip(context, s),
          ],
        ),
      ),
    );
  }

  Widget _hashChip(BuildContext context, String tag, VoidCallback onRemove) {
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: _Pc.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$tag',
            style: TextStyle(
              fontSize: AppTextSize.s13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addHashtagChip(BuildContext context, S s) {
    if (!_editingHashtag) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _editingHashtag = true),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _Pc.border),
          ),
          child: Text(
            _hashtags.isEmpty ? '+ ${s.hashtagAdd}' : '+ ${s.hashtagAddShort}',
            style: TextStyle(
              fontSize: AppTextSize.s13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 28,
      width: 150,
      child: TextField(
        controller: _hashtagCtrl,
        autofocus: true,
        style: TextStyle(
          fontSize: AppTextSize.s13,
          color: AppTheme.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: s.hintHashtag,
          hintStyle: TextStyle(
            fontSize: AppTextSize.s13,
            color: AppTheme.textSecondary,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppTheme.primary),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppTheme.primary),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
          ),
        ),
        onSubmitted: (v) {
          _addHashtag(v);
          setState(() {
            _editingHashtag = false;
            _hashtagCtrl.clear();
          });
        },
        onTapOutside: (_) => setState(() {
          _editingHashtag = false;
          _hashtagCtrl.clear();
        }),
      ),
    );
  }

  /// [4] TOMBOL AKSI: Edit Profil | Bagikan Profil | 40x40 ikon mata.
  @override
  Widget _actionButtons(BuildContext context, S s, UserModel? profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(child: _actionBtn(s.btnEditProfile, onTap: _editProfile)),
          const SizedBox(width: 8),
          Expanded(
            child: _actionBtn(
              s.btnShareApp,
              onTap: () async {
                await Share.share(s.msgShareApp);
              },
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Lihat sebagai orang lain',
            child: Material(
              color: _Pc.button,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  final uid = profile?.uid;
                  if (uid == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserInfoScreen(
                        userId: uid,
                        fallbackName: profile?.nickname ?? '',
                        initialProfile: profile,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.visibility_outlined,
                    size: 19,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, {required VoidCallback onTap}) {
    return SizedBox(
      height: 40,
      child: Material(
        color: _Pc.button,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTextSize.s14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [5] BANNER PERMINTAAN TEMAN.
  @override
  Widget _friendRequestBanner(BuildContext context, S s) {
    return rv.Consumer(
      builder: (ctx, ref2, _) {
        final n = ref2.watch(
          socialProvider.select((p) => p.friendRequestCount),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Material(
            color: AppTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendRequestsScreen()),
              ),
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_add_alt_1,
                      size: 20,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.friendRequestTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTextSize.s145,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (n > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        constraints: const BoxConstraints(minWidth: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          n > 99 ? '99+' : '$n',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: AppTextSize.s12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
