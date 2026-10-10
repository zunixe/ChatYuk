part of '../profile_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _ProfileBodyMx on _ProfileBase {
  Widget _buildBodySliver(
    BuildContext context,
    S s,
    UserModel? profile,
    String? uid,
    bool isAnon,
    bool dummyActive,
    bool dummySessionActive,
    bool emailConfirmed,
    String? userEmail,
    bool pointsEnabled,
    int pointsValue,
    int extraPhotoSlots,
    bool yukcoinV2Active,
  ) {
    return SliverToBoxAdapter(
      child: Padding(
        // Top 10 = sama dengan jarak card pertama timeline ke atas
        // (list padding 4 + margin card 6) — konsisten antar halaman.
        padding: EdgeInsets.fromLTRB(10, 10, 10, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner sesi dummy — widget di-inject build admin
            // (lib/admin/profile_sections.dart) lewat AdminGate.
            // Tanpa isRealAdmin: saat dummy aktif, email session =
            // email dummy → isRealAdmin false → banner hilang.
            if (dummySessionActive)
              AdminGate.dummySessionBanner?.call(context, profile?.nickname) ??
                  const SizedBox.shrink(),
            // Anonymous warning — prominent (sembunyikan saat sesi dummy)
            if (isAnon && !dummyActive) ...[
              Container(
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade700,
                      size: 22,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.titleAccountSecurity,
                            style: AppText.bodySmall.copyWith(
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            s.msgAnonymousWarning,
                            style: AppText.bodySmall.copyWith(
                              color: Colors.orange.shade700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            s.msgAnonRetention7d,
                            style: AppText.bodySmall.copyWith(
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => LinkEmailScreen()),
                  ),
                  icon: Icon(Icons.security, size: 18),
                  label: Text(s.btnSecureAccount),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
            ],

            // Status + email section
            if (!isAnon) ...[
              ProfileSectionCard(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 4),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (emailConfirmed ? Colors.green : Colors.orange)
                            .shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        emailConfirmed
                            ? Icons.verified_user
                            : Icons.warning_amber_rounded,
                        color: emailConfirmed ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      emailConfirmed
                          ? s.labelEmailVerified
                          : s.labelEmailUnverified,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    subtitle: Text(
                      userEmail ?? '-',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Icon(
                      emailConfirmed ? Icons.check_circle : Icons.error_outline,
                      color: emailConfirmed ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
            ],

            // Status
            ProfileSectionCard(
              children: [
                ProfileInfoTile(
                  icon: Icons.circle,
                  iconColor: _statusColor(profile?.status ?? 'offline'),
                  label: s.labelStatus,
                  value: _statusLabel(profile?.status ?? 'offline', s),
                ),
                Divider(height: 1, indent: 52),
                ProfileInfoTile(
                  icon: Icons.badge_outlined,
                  iconColor: AppTheme.accent,
                  label: s.labelUsername,
                  value: profile?.nickname ?? '-',
                  trailing: IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    tooltip: s.btnEditProfile,
                    onPressed: _editProfile,
                  ),
                ),
                Divider(height: 1, indent: 52),
                ProfileInfoTile(
                  icon: Icons.badge_outlined,
                  iconColor: AppTheme.primary,
                  label: s.labelUserId,
                  value: uid?.substring(0, 8) ?? '-',
                ),
                Divider(height: 1, indent: 52),
                // About — teks bebas 150 karakter, diedit INLINE di
                // tempat (tanpa bottom sheet). Visibilitas diatur
                // di Pengaturan > Privasi (about_visibility).
                // Metrik sama dengan ProfileInfoTile (padding 4/6,
                // ikon lingkaran 36, celah 12) supaya sejajar.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.info_outline,
                          color: AppTheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.labelAbout,
                              style: AppText.caption.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            if (_editingAbout)
                              TextField(
                                controller: _aboutCtrl,
                                autofocus: true,
                                maxLength: 150,
                                maxLines: null,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _saveAbout(),
                                style: AppText.bodyStrong,
                                decoration: InputDecoration(
                                  hintText: s.hintAbout,
                                  hintStyle: AppText.bodySmall.copyWith(
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
                                    ? AppText.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      )
                                    : AppText.bodyStrong,
                              ),
                          ],
                        ),
                      ),
                      if (_editingAbout)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_savingAbout)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                icon: Icon(
                                  Icons.check,
                                  size: 20,
                                  color: AppTheme.primary,
                                ),
                                onPressed: _saveAbout,
                              ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                size: 20,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: _savingAbout ? null : _cancelEditAbout,
                            ),
                          ],
                        )
                      else
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                          tooltip: s.btnEditProfile,
                          onPressed: () =>
                              _startEditAbout(profile?.about ?? ''),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),

            // Hashtag
            ProfileSectionLabel(label: s.labelHashtags),
            SizedBox(height: 6),
            ProfileSectionCard(
              children: [
                Padding(
                  padding: EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _hashtags
                            .map(
                              (tag) => InputChip(
                                label: Text('#$tag'),
                                onDeleted: _savingHashtags
                                    ? null
                                    : () => _removeHashtag(tag),
                                deleteIcon: Icon(Icons.close, size: 16),
                                backgroundColor: AppTheme.accent.withValues(
                                  alpha: 0.08,
                                ),
                                side: BorderSide(
                                  color: AppTheme.accent.withValues(alpha: 0.3),
                                ),
                                labelStyle: AppText.bodySmall,
                                visualDensity: VisualDensity.compact,
                              ),
                            )
                            .toList(),
                      ),
                      if (_hashtags.isEmpty && !_savingHashtags)
                        Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text(
                            s.hintHashtag,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      SizedBox(height: 6),
                      TextField(
                        controller: _hashtagCtrl,
                        enabled: !_savingHashtags,
                        onSubmitted: _addHashtag,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: s.hintHashtag,
                          isDense: true,
                          prefixIcon: Padding(
                            padding: EdgeInsets.only(bottom: 2),
                            child: Icon(
                              Icons.tag,
                              size: 18,
                              color: AppTheme.accent,
                            ),
                          ),
                          prefixIconConstraints: BoxConstraints(minWidth: 40),
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppTheme.divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppTheme.divider),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppTheme.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),

            // Galeri
            ProfileSectionLabel(label: s.labelGallery),
            SizedBox(height: 6),
            ProfileSectionCard(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.pink.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.photo_library_outlined,
                                  color: Colors.pink.shade400,
                                  size: 18,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                s.labelGallery,
                                style: AppText.bodyStrong.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (_photos.length < 6 + extraPhotoSlots)
                            TextButton.icon(
                              onPressed: _uploading
                                  ? null
                                  : _pickGalleryFromSource,
                              icon: _uploading
                                  ? SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.primary,
                                      ),
                                    )
                                  : Icon(Icons.add, size: 16),
                              label: Text(
                                s.btnAddGallery,
                                style: AppText.bodySmall,
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          if (_photos.length >= 6 + extraPhotoSlots &&
                              yukcoinV2Active)
                            TextButton.icon(
                              onPressed: _uploading ? null : _buyExtraSlots,
                              icon: Icon(Icons.add_circle_outline, size: 16),
                              label: Text(
                                '${s.extraPhotoBuy} · ${ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).costExtraPhotoSlot}',
                                style: AppText.bodySmall,
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                      if (_loadingPhotos)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.primary,
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      else if (_photos.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              s.labelGalleryEmpty,
                              textAlign: TextAlign.center,
                              style: AppText.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                              ),
                          itemCount: _photos.length,
                          itemBuilder: (_, i) => GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProfilePhotoViewerScreen(
                                  photos: _photos,
                                  initialIndex: i,
                                ),
                              ),
                            ),
                            onLongPress: () => _confirmDeletePhoto(_photos[i]),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AsyncPhotoThumbnail(
                                    base64: _photos[i].photo,
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () =>
                                        _confirmDeletePhoto(_photos[i]),
                                    child: Container(
                                      padding: EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // Sosial — angka fans/following + akses list
            if (!isAnon) ...[
              SizedBox(height: 12),
              ProfileSectionLabel(label: s.socialFollowers),
              SizedBox(height: 6),
              ProfileSectionCard(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ProfileStat(
                        label: s.socialFollowers,
                        value: profile?.followersCount ?? 0,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SocialListScreen(kind: 'followers'),
                          ),
                        ),
                      ),
                      ProfileStat(
                        label: s.socialFollowing,
                        value: profile?.followingCount ?? 0,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SocialListScreen(kind: 'following'),
                          ),
                        ),
                      ),
                      ProfileStat(
                        label: s.socialFriends,
                        value: profile?.friendsCount ?? 0,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SocialListScreen(kind: 'friends'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 8),
                  // Pola sama dengan baris Pengaturan di bawah
                  // (lingkaran 36 + celah 12) supaya ikon sejajar.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FriendRequestsScreen(),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person_add_alt,
                              color: AppTheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              s.friendRequestTitle,
                              style: AppText.bodyStrong.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          rv.Consumer(
                            builder: (ctx, ref, __) {
                              final c = ref.watch(
                                socialProvider.select(
                                  (st) => st.friendRequestCount,
                                ),
                              );
                              return c > 0
                                  ? Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.danger,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$c',
                                        style: AppText.caption.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.chevron_right,
                                      color: AppTheme.textSecondary,
                                    );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Subscribe hanya relevan saat sistem poin aktif —
                  // sembunyikan menu langganan & harga subscribe saat OFF.
                  if (pointsEnabled) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(Icons.star, color: Color(0xFFB8860B)),
                      title: Text(
                        s.subscriptionsTitle,
                        style: AppText.bodyStrong,
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: AppTheme.textSecondary,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SubscriptionsScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        Icons.workspace_premium,
                        color: Color(0xFFB8860B),
                      ),
                      title: Text(
                        s.setSubPriceTitle,
                        style: AppText.bodyStrong,
                      ),
                      subtitle: Text(
                        '${s.subscribePrice(profile?.subscriptionPrice ?? 0)}',
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: AppTheme.textSecondary,
                      ),
                      onTap: () => _editSubscriptionPrice(context),
                    ),
                  ],
                ],
              ),
            ],

            // Poin ChatYuk — diletakkan di antara My Photos dan Pengaturan
            if (pointsEnabled) ...[
              SizedBox(height: 12),
              ProfileSectionLabel(label: s.pointsTitle),
              SizedBox(height: 6),
              ProfileSectionCard(
                children: [
                  // Header saldo — gradient amber dengan angka besar
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(14, 12, 6, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                            isAnon
                                ? Icons.lock_outlined
                                : Icons.monetization_on_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: 12),
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
                                formatPoints(pointsValue),
                                style: AppText.display.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Riwayat credit/debit poin
                        IconButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PointHistoryScreen(),
                            ),
                          ),
                          icon: Icon(
                            Icons.history,
                            size: 20,
                            color: Colors.white,
                          ),
                          tooltip: s.pointHistoryTitle,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  if (isAnon && !dummyActive) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: Colors.orange.shade700,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            s.pointsAnonymousLose,
                            style: AppText.caption.copyWith(
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: 4),
                  Divider(height: 1),
                  SizedBox(height: 4),
                  // Aksi cepat — grid ikon + label, rapi tanpa bubble
                  ProfileActionGrid(
                    actions: [
                      if (isAnon && !dummyActive)
                        ProfileActionItem(
                          icon: Icons.email_outlined,
                          color: Colors.orange,
                          label: s.pointsRegisterBonusLabel,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LinkEmailScreen(),
                            ),
                          ),
                        ),
                      ProfileActionItem(
                        icon: Icons.leaderboard_outlined,
                        color: AppTheme.primary,
                        label: s.lbTitle,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LeaderboardScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            SizedBox(height: 12),

            // Pengaturan — satu pintu (isi pindah ke SettingsScreen).
            ProfileSectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.settings_outlined,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.titleSettings,
                                style: AppText.bodyStrong.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                s.descSettings,
                                style: AppText.bodySmall.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ContactScreen()),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mail_outline,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      s.titleContact,
                      style: AppText.body.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DonateScreen()),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, size: 16, color: AppTheme.danger),
                    SizedBox(width: 4),
                    Text(
                      s.titleDonate,
                      style: AppText.body.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 8),
            FutureBuilder<String>(
              future: _appVersionFuture ??= ProviderScope.containerOf(
                context,
                listen: false,
              ).read(deviceInfoProvider).appVersionLabel(),
              builder: (_, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Center(
                  child: Text(
                    'ChatYuk ${snap.data}',
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
