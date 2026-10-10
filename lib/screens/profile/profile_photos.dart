part of '../profile_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _ProfilePhotosMx on _ProfileBase {
  Future<void> _loadPhotos() async {
    final uid = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier).uid;
    if (uid == null) return;
    try {
      final photos = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authProvider.notifier).getPhotos(uid);
      if (mounted) setState(() => _photos = photos);
    } catch (_) {}
    if (mounted) setState(() => _loadingPhotos = false);
  }

  void _pickGalleryFromSource() {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppTheme.primary),
              title: Text(s.avatarCamera),
              onTap: () {
                Navigator.pop(sheetCtx);
                _addGalleryPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
              title: Text(s.avatarGallery),
              onTap: () {
                Navigator.pop(sheetCtx);
                _addGalleryPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _addGalleryPhoto(ImageSource source) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );
    } catch (e) {
      dlog('[PROFILE] pickImage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoPermission)));
      }
      return;
    }
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final processed = await NativeImage.processGalleryPhoto(bytes);
    if (!mounted) return;
    if (processed == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errPhotoLoad)));
      return;
    }
    // Reward koin upload DIHAPUS (overhaul coin: tidak ada poin gratis).
    setState(() => _uploading = true);
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(authProvider.notifier)
          .uploadPhoto(processed.full, preview: processed.preview);
      await _loadPhotos();
      // Reward koin upload DIHAPUS (overhaul coin: tidak ada poin gratis).
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoSave)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Beli +5 slot foto tambahan (YukCoin v2). Refresh limit setelahnya.
  Future<void> _buyExtraSlots() async {
    final pp = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(pointsProvider.notifier);
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.extraPhotoBuy),
        content: Text(s.yukcoinUseConfirmBody(pp.costExtraPhotoSlot)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.yukcoinCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.yukcoinConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await pp.buyExtraPhotoSlots(slots: 5);
      await pp.refreshYukcoinV2();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.yukcoinBought)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.yukcoinNotEnough)));
    }
  }

  Future<void> _confirmDeletePhoto(UserPhoto photo) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.btnDeletePhoto),
        content: Text(s.dialogDeletePhoto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.btnDeletePhoto,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authProvider.notifier).deletePhoto(photo.id);
      // Hapus item saja dari list lokal (tanpa reload penuh getPhotos yang
      // me-download ulang semua foto). Grid max 6 item — murah.
      if (mounted) {
        setState(() => _photos.removeWhere((p) => p.id == photo.id));
      }
    } catch (_) {}
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final picker = ImagePicker();
    final XFile? picked;
    try {
      // TANPA maxWidth/imageQuality — jangan re-encode di picker. Foto asli
      // utuh diteruskan ke cropper (kompresi cukup 1x di akhir proses).
      picked = await picker.pickImage(source: source);
    } catch (e) {
      // Cancel sebelum izin kamera/galeri → PlatformException, jangan error.
      dlog('[PROFILE] pickImage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoPermission)));
      }
      return;
    }
    if (picked == null) return;

    // Crop interaktif 1:1 — geser/zoom pilih bagian yang masuk avatar.
    // Apa yang dilihat user di lingkaran = persis yang tersimpan.
    final CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 1024,
        maxHeight: 1024,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: s.avatarCamera,
            toolbarColor: AppTheme.bgScreen,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: AppTheme.primary,
            lockAspectRatio: true,
            // Edge-to-edge Android 15+: ikon status bar ikut terang/gelap
            // toolbar (jangan isi warna bar — API deprecated, ditolak Play).
            statusBarLight: !AppTheme.isDark,
          ),
          IOSUiSettings(title: s.avatarCamera, aspectRatioLockEnabled: true),
        ],
      );
    } catch (e) {
      dlog('[PROFILE] crop error: $e');
      return;
    }
    if (cropped == null) return;

    final bytes = await cropped.readAsBytes();
    if (!mounted) return;

    // Proses image di background isolate — tidak block UI thread
    final base64 = await processAvatar(bytes);
    if (base64 == null) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoLoad)));
      return;
    }

    setState(() => _uploading = true);
    try {
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authProvider.notifier).updateAvatar(base64);
      if (mounted) {
        final uid =
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(authProvider.notifier).profile?.uid ??
            '';
        if (uid.isNotEmpty) {
          try {
            ProviderScope.containerOf(context, listen: false)
                .read(onlineUsersProvider.notifier)
                .updateAvatarForUid(uid, base64);
          } catch (_) {}
          try {
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(timelineProvider.notifier).refreshAvatarForUid(uid, base64);
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoSave)));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _showAvatarOptions() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final hasAvatar = (auth.profile?.avatar ?? '').isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppTheme.primary),
              title: Text(s.avatarCamera),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUpload(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
              title: Text(s.avatarGallery),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppTheme.danger,
                ),
                title: Text(
                  s.avatarDelete,
                  style: const TextStyle(color: AppTheme.danger),
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await ProviderScope.containerOf(
                    context,
                    listen: false,
                  ).read(authProvider.notifier).removeAvatar();
                  if (mounted) {
                    final uid =
                        ProviderScope.containerOf(
                          context,
                          listen: false,
                        ).read(authProvider.notifier).profile?.uid ??
                        '';
                    if (uid.isNotEmpty) {
                      try {
                        ProviderScope.containerOf(context, listen: false)
                            .read(onlineUsersProvider.notifier)
                            .removeAvatarForUid(uid);
                      } catch (_) {}
                      try {
                        ProviderScope.containerOf(context, listen: false)
                            .read(timelineProvider.notifier)
                            .refreshAvatarForUid(uid, '');
                      } catch (_) {}
                    }
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAvatarZoom(Uint8List? bytes, Color bgColor, String initial) {
    if (bytes == null && initial.isEmpty) return;
    final zoomBytes = bytes;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: zoomBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        // Cap 1080px: dialog zoom tidak butuh full-res 12MP.
                        child: Image.memory(
                          zoomBytes,
                          fit: BoxFit.contain,
                          cacheWidth: 1080,
                        ),
                      )
                    : CircleAvatar(
                        radius: 90,
                        backgroundColor: bgColor,
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppGlyph.xl,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Keluarkan bitmap zoom dari ImageCache (pola PhotoViewerScreen).
      if (zoomBytes != null && zoomBytes.isNotEmpty) {
        try {
          PaintingBinding.instance.imageCache.evict(MemoryImage(zoomBytes));
        } catch (_) {}
      }
    });
  }

  Future<void> _editProfile() async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final profile = auth.profile;
    if (profile == null) return;
    final currentNick = profile.nickname;
    final ctrl = TextEditingController(text: currentNick);
    // About TIDAK lagi diedit di sini — punya editor inline sendiri
    // di baris Tentang (tanpa bottom sheet).
    final focus = FocusNode();
    int age = profile.age;
    String negara = profile.country;
    String kota = profile.city;
    // null = tidak diubah; hanya male/female yang ditulis ke server.
    String? gender;
    String? error;
    bool loading = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (sheetCtx) {
        // Compact: sheet menempel bawah seperti dulu, tapi konten tetap
        // di atas menu Android (nav/gesture bar) & keyboard.
        final bottom =
            MediaQuery.viewInsetsOf(sheetCtx).bottom +
            MediaQuery.viewPaddingOf(sheetCtx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: StatefulBuilder(
            builder: (sheetCtx, setSheet) => SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(s.btnEditProfile, style: AppText.title),
                  SizedBox(height: 4),
                  Text(
                    s.msgUsernameOldReleased,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    focusNode: focus,
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: s.labelUsername,
                      hintText: s.hintNickname,
                      errorText: error,
                      prefixIcon: const Icon(Icons.alternate_email, size: 20),
                      suffixIcon:
                          error == null &&
                              ctrl.text.isNotEmpty &&
                              ctrl.text != currentNick
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                    ),
                    onChanged: (v) => setSheet(() => error = null),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: gender,
                    hint: Text(
                      profile.gender == 'female'
                          ? s.labelGenderFemale
                          : s.labelGenderMale,
                    ),
                    decoration: InputDecoration(
                      labelText: s.labelGenderFilter,
                      prefixIcon: const Icon(Icons.wc_outlined, size: 20),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'male',
                        child: Text(s.labelGenderMale),
                      ),
                      DropdownMenuItem(
                        value: 'female',
                        child: Text(s.labelGenderFemale),
                      ),
                    ],
                    onChanged: (v) => setSheet(() => gender = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: age,
                    decoration: InputDecoration(
                      labelText: s.labelAge,
                      prefixIcon: const Icon(Icons.cake_outlined, size: 20),
                    ),
                    items: [
                      for (int i = 18; i <= 60; i++)
                        DropdownMenuItem(value: i, child: Text('$i')),
                    ],
                    onChanged: (v) => setSheet(() => age = v ?? age),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: negara,
                    decoration: InputDecoration(
                      labelText: s.labelCountry,
                      prefixIcon: const Icon(Icons.public, size: 20),
                    ),
                    items: [
                      for (final n in kotaByNegara.keys)
                        DropdownMenuItem(
                          value: n,
                          child: Text(negaraLabel(n, s.isId)),
                        ),
                    ],
                    onChanged: (v) => setSheet(() {
                      if (v == null) return;
                      negara = v;
                      kota = kotaByNegara[v]!.first;
                    }),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: kota,
                    decoration: InputDecoration(
                      labelText: s.labelCity,
                      prefixIcon: const Icon(Icons.location_city, size: 20),
                    ),
                    items: [
                      for (final k in kotaByNegara[negara]!)
                        DropdownMenuItem(value: k, child: Text(k)),
                    ],
                    onChanged: (v) => setSheet(() => kota = v ?? kota),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading
                          ? null
                          : () async {
                              final nick = ctrl.text.trim();
                              final nickChanged = nick != currentNick;
                              if (nickChanged) {
                                if (nick.length < 3) {
                                  setSheet(() => error = s.errNicknameShort);
                                  focus.requestFocus();
                                  return;
                                }
                                if (nick.length > 20) {
                                  setSheet(() => error = s.errNicknameLong);
                                  focus.requestFocus();
                                  return;
                                }
                                if (!isValidNickname(nick)) {
                                  setSheet(() => error = s.errNicknameInvalid);
                                  focus.requestFocus();
                                  return;
                                }
                                if (isBannedNickname(nick) &&
                                    !ProviderScope.containerOf(
                                      context,
                                      listen: false,
                                    ).read(authProvider.notifier).isRealAdmin) {
                                  setSheet(() => error = s.errNicknameBanned);
                                  focus.requestFocus();
                                  return;
                                }
                                final available =
                                    await ProviderScope.containerOf(
                                          context,
                                          listen: false,
                                        )
                                        .read(authProvider.notifier)
                                        .isNicknameAvailable(nick);
                                if (!available) {
                                  setSheet(() => error = s.errNicknameTaken);
                                  focus.requestFocus();
                                  return;
                                }
                              }
                              setSheet(() => loading = true);
                              try {
                                await ProviderScope.containerOf(
                                      context,
                                      listen: false,
                                    )
                                    .read(authProvider.notifier)
                                    .updateProfile(
                                      nickname: nickChanged ? nick : null,
                                      age: age,
                                      country: negara,
                                      city: kota,
                                      gender: gender,
                                    );
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(s.msgProfileSaved)),
                                  );
                                  // Bonus profil DIHAPUS (tidak ada poin gratis).
                                }
                              } catch (e) {
                                if (sheetCtx.mounted) {
                                  final msg = e.toString().toLowerCase();
                                  setSheet(() {
                                    loading = false;
                                    error =
                                        (msg.contains('nickname_banned') ||
                                            msg.contains('banned'))
                                        ? s.errNicknameBanned
                                        : s.errGeneric;
                                    dlog(e.toString(), tag: 'PROFILE');
                                  });
                                }
                              }
                            },
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(s.btnSave, style: AppText.button),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
