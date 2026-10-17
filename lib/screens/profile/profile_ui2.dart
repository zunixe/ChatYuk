part of '../profile_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

/// Seksi lanjutan halaman Profil: Foto Saya, Akun, Lainnya, poin, footer.
mixin _ProfileUiSections2Mx on _ProfileBase {
  /// [6] FOTO SAYA — tile Tambah + foto (92x116) horizontal.
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
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
        ),
        SizedBox(
          height: 116,
          child: ListView(
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
                          fontSize: 12.5,
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
                  width: 220,
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
                          fontSize: 14,
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
                          fontSize: 12.5,
                          height: 1.35,
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
          ),
        ),
      ],
    );
  }

  /// [7] KARTU AKUN — Email / Username / User ID.
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
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: AppTheme.online,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Terverifikasi',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.online,
                              ),
                            ),
                          ],
                        )
                      : TextButton(
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
                        const SnackBar(content: Text('User ID disalin')),
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

  Widget _infoRow({
    required IconData icon,
    required String value,
    required String label,
    Widget? trailing,
  }) {
    return SizedBox(
      height: 60,
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
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing else const SizedBox(width: 14),
        ],
      ),
    );
  }

  /// [8] KARTU LAINNYA — Pengaturan, Hubungi Kami.
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
                      fontSize: 15,
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
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppTheme.textSecondary,
            ),
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

  /// Info poin (hanya bila sistem koin aktif) — ringkas, satu baris.
  Widget _pointsInfo(int points, int extraSlots, bool v2) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _Pc.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.stars_rounded, size: 18, color: AppTheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'YukCoin: $points${v2 ? ' · v2' : ''} · slot foto +$extraSlots',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            InkWell(
              onTap: _buyExtraSlots,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  '+ Slot',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [9] FOOTER — Donasi + versi aplikasi.
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
                      fontSize: 14,
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
                fontSize: 11.5,
                color: AppTheme.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }



  /// Versi aplikasi dari package_info_plus (cache 1x).
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
