part of '../profile_screen.dart';


/// Seksi lanjutan halaman Profil: Foto Saya, Akun, Lainnya, poin, footer.
mixin _ProfileUiSections2Mx on _ProfileBase {
  /// [6] FOTO SAYA — tile Tambah + foto (92x116) horizontal.
  @override
  Widget _photosSection(BuildContext context, S s) {
    final maxPhotos = 4 + _extraSlotsCache;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _sectionTitle(
          s.titleMyPhotos,
          trailing: Text(
            '${_photos.length} ${s.ofLabel} $maxPhotos',
            style: TextStyle(
              fontSize: AppTextSize.s125,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        SizedBox(
          height: 116,
          child: LayoutBuilder(
            builder: (ctx, cons) {
              // Kartu "Belum ada foto" mengisi SISA lebar (rata kanan dengan
              // kartu Akun/Lainnya di bawahnya), bukan lebar tetap.
              final restW = (cons.maxWidth - 16 * 2 - 92 - 8).clamp(
                120.0,
                420.0,
              );
              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Tile Tambah
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _loadingPhotos ? null : _pickGalleryFromSource,
                    child: Container(
                      width: 92,
                      height: 116,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _Pc.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 24,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.photoAddLabel,
                            style: TextStyle(
                              fontSize: AppTextSize.s125,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_photos.isEmpty)
                    Container(
                      width: restW,
                      height: 116,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _Pc.card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            s.photoEmptyTitle,
                            style: TextStyle(
                              fontSize: AppTextSize.s14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.photoEmptyBody,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppTextSize.s125,
                              height: AppTextSize.lh135,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final ph in _photos) ...[
                      SizedBox(
                        width: 92,
                        height: 116,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProfilePhotoViewerScreen(
                                      photos: _photos,
                                      initialIndex: _photos.indexOf(ph),
                                    ),
                                  ),
                                ),
                                onLongPress: () => _confirmDeletePhoto(ph),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AsyncPhotoThumbnail(base64: ph.photo),
                                ),
                              ),
                            ),
                            // Tombol HAPUS per foto (pojok kanan atas) — tetap ada
                            // di samping long-press supaya jelas & mudah ditemukan.
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => _confirmDeletePhoto(ph),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// [7] KARTU AKUN — Email / Username / User ID.
  @override
  Widget _accountSection(
    BuildContext context,
    S s,
    UserModel? profile,
    String? uid,
    String? userEmail,
    bool emailConfirmed,
  ) {
    final email = (userEmail ?? '').isEmpty ? '-' : userEmail!;
    final username = profile?.nickname ?? '-';
    final shortId = (uid ?? '').length > 8
        ? uid!.substring(0, 8)
        : (uid ?? '-');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _sectionTitle(s.titleAccount),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _Pc.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _infoRow(
                  icon: Icons.mail_outline,
                  value: email,
                  label: 'Email',
                  trailing: emailConfirmed
                      ? _verifiedPill()
                      : TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: AppTextSize.s125,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LinkEmailScreen(),
                            ),
                          ),
                          child: Text(s.btnVerify),
                        ),
                ),
                Divider(height: 1, color: _Pc.cardDivider),
                _infoRow(
                  icon: Icons.alternate_email,
                  value: username,
                  label: 'Username',
                  trailing: IconButton(
                    tooltip: s.btnEditProfile,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    onPressed: _editProfile,
                  ),
                ),
                Divider(height: 1, color: _Pc.cardDivider),
                _infoRow(
                  icon: Icons.badge_outlined,
                  value: shortId,
                  label: s.labelUserId,
                  trailing: IconButton(
                    tooltip: 'Salin',
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    onPressed: () async {
                      final id = uid ?? '';
                      if (id.isEmpty) return;
                      await Clipboard.setData(ClipboardData(text: id));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.snackUserIdCopied)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Badge "Terverifikasi" — ikon polos 22px (SAMA ukuran & perataan dengan
  /// ikon kolom kiri: mail, @, badge) supaya sejajar; hanya berbeda warna.
  Widget _verifiedPill() {
    return Tooltip(
      message: 'Email terverifikasi',
      child: Icon(Icons.verified, size: 22, color: AppTheme.online),
    );
  }

  /// Baris info kartu Akun.
  ///
  /// Trailing DIALOKASIKAN lebih dulu (diukur via IntrinsicWidth pada
  /// `maxWidth` terbatas), lalu teks mendapat sisa lebar — jadi email
  /// TIDAK pernah tertutup pill "Terverifikasi" maupun tombol.
  Widget _infoRow({
    required IconData icon,
    required String value,
    required String label,
    Widget? trailing,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(icon, size: 22, color: AppTheme.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.s15,
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
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing,
              const SizedBox(width: 12),
            ] else
              const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }

  /// [8] KARTU LAINNYA — Pengaturan, Hubungi Kami.
  @override
  Widget _otherSection(BuildContext context, S s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _sectionTitle(s.titleOthers),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _Pc.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _linkRow(
                  icon: Icons.settings_outlined,
                  title: s.titleSettings,
                  subtitle: s.settingsSubtitle,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
                Divider(height: 1, color: _Pc.cardDivider),
                _linkRow(
                  icon: Icons.help_outline,
                  title: s.titleContactUs,
                  subtitle: s.contactUsSubtitle,
                  onTap: () => _contactUs(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _linkRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 56,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(icon, size: 22, color: AppTheme.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.s15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.s12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppTheme.textSecondary),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }

  /// Buka FORM Hubungi Kami (halaman yang sudah ada — pesan masuk ke admin).
  void _contactUs(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ContactScreen()),
    );
  }

  /// Info YukCoin (hanya bila sistem koin aktif) — kartu saldo + pintu
  /// riwayat/topup, diletakkan dekat atas agar tidak tenggelam di bawah.
  @override
  Widget _pointsInfo(
    BuildContext context,
    S s,
    int points,
    int extraSlots,
    bool v2, {
    bool isAnon = false,
  }) {
    void openHistory() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PointHistoryScreen()),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _sectionTitle(s.pointsTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: openHistory,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          // Akun anonim: poin bisa hilang → ikon gembok.
                          isAnon
                              ? Icons.lock_outlined
                              : Icons.monetization_on_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.walletTotal,
                              style: AppText.caption.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              formatPoints(points),
                              style: AppText.display.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${s.yukcoinFeatureExtraPhoto}: +$extraSlots'
                              '${v2 ? ' · v2' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Tombol diletakkan di Row sendiri dengan tap-target
                      // penuh: IconButton 48dp lebih tinggi dari isi kartu,
                      // jadi tap di atas/bawah ikon dulu jatuh ke InkWell
                      // kartu (buka riwayat padahal maksudnya "+ Slot").
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _buyExtraSlots,
                            tooltip: s.extraPhotoBuy,
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          IconButton(
                            onPressed: openHistory,
                            tooltip: s.pointHistoryTitle,
                            icon: const Icon(
                              Icons.chevron_right,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Peringatan akun anonim: poin bisa HILANG saat logout/ganti
        // perangkat. Dulu ada di kartu lama — jangan sampai hilang.
        if (isAnon)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Colors.orange.shade300,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.pointsAnonymousLose,
                    style: AppText.caption.copyWith(
                      color: Colors.orange.shade300,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Moderasi konten room publik ──────────────────────────────────────────

  /// Kartu "Moderasi": pilih NEGARA ASAL, ajukan jadi moderator, buka konsol.
  ///
  /// Negara asal dibaca dari PROFIL (`homeCountry`), bukan hanya dari pilihan
  /// sesi — dulu `_homeCountry` selalu null sehingga "Ajukan jadi moderator"
  /// dan "Buka konsol" mengirim string kosong dan SELALU gagal.
  @override
  Widget _moderationSection(BuildContext context, S s) {
    _homeCountry ??= ref.watch(authProvider).profile?.homeCountry;
    if (!_modRoleLoaded) {
      _modRoleLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadModerationRole());
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _sectionTitle(s.moderationTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: Text(s.moderationCountryTitle),
                  subtitle: Text(
                    (_homeCountry ?? '').isEmpty
                        ? s.moderationCountryHint
                        : '${_homeCountry!} · ${s.moderationCountryHint}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickHomeCountry(context, s),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(s.moderationApply),
                  subtitle: Text(s.moderationApplyHint),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final res = await ProviderScope.containerOf(
                      context,
                      listen: false,
                    ).read(chatProvider.notifier).applyCountryModerator(
                          _homeCountry ?? '',
                          reason: '',
                        );
                    if (!context.mounted) return;
                    final msg = switch (res['error']) {
                      'account_too_new' => s.moderationApplyNeedDays(
                          (res['min_days'] as num?)?.toInt() ?? 7,
                        ),
                      'not_enough_messages' => s.moderationApplyNeedMsgs(
                          (res['need'] as num?)?.toInt() ?? 50,
                          (res['have'] as num?)?.toInt() ?? 0,
                        ),
                      _ => res['already_moderator'] == true ||
                              res['already_pending'] == true
                          ? s.moderationApplyPending
                          : (res['ok'] == true
                              ? s.moderationApplySent
                              : s.errGeneric),
                    };
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  },
                ),
                // Konsol hanya untuk MODERATOR/ADMIN — user biasa yang
                // menekannya dulu selalu "gagal" (RPC forbidden), jadi
                // tombolnya disembunyikan.
                if (_canOpenConsole) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(s.moderationOpenConsole),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    final c = _homeCountry ?? '';
                    if (c.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.moderationCountryHint)),
                      );
                      return;
                    }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ModerationScreen(country: c),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String? _homeCountry;

  /// True bila user ini moderator negara (atau admin) → boleh buka konsol.
  bool _canOpenConsole = false;
  bool _modRoleLoaded = false;

  Future<void> _loadModerationRole() async {
    try {
      final res = await ref
          .read(chatProvider.notifier)
          .myModerationState();
      if (!mounted || res == null) return;
      final list = res['moderates'];
      final isMod = list is List && list.isNotEmpty;
      final isAdmin = ref.read(authProvider.notifier).isRealAdmin;
      if (isMod != _canOpenConsole || isAdmin != _canOpenConsole) {
        setState(() => _canOpenConsole = isMod || isAdmin);
      }
    } catch (_) {}
  }

  Future<void> _pickHomeCountry(BuildContext context, S s) async {
    final countries = getNegaraKeys()..sort();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.moderationCountryTitle),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: ListView.builder(
            itemCount: countries.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              title: Text(countries[i]),
              onTap: () => Navigator.pop(ctx, countries[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.btnCancel),
          ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    final res = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatProvider.notifier).setHomeCountry(picked);
    if (!context.mounted) return;
    if (res['ok'] == true) {
      _homeCountry = picked;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.moderationCountrySaved)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.moderationCountryCooldown)),
      );
    }
  }

  /// [9] FOOTER — Donasi + versi aplikasi.
  @override
  Widget _footer(BuildContext context, S s) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 20),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DonateScreen()),
            ),
            child: SizedBox(
              height: 40,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite, size: 18, color: AppTheme.danger),
                  const SizedBox(width: 6),
                  Text(
                    s.titleDonate,
                    style: TextStyle(
                      fontSize: AppTextSize.s14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          FutureBuilder<String>(
            future: _appVersion(),
            builder: (_, snap) => Text(
              'ChatYuk v${snap.data ?? ''}',
              style: TextStyle(
                fontSize: AppTextSize.s115,
                color: AppTheme.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Versi aplikasi dari package_info_plus (cache 1x).
  @override
  Future<String> _appVersion() async {
    if (_appVersionCache != null) return _appVersionCache!;
    try {
      final p = await PackageInfo.fromPlatform();
      _appVersionCache = p.version.isNotEmpty ? p.version : '';
    } catch (_) {
      _appVersionCache = '';
    }
    return _appVersionCache!;
  }
}
