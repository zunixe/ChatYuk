import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import '../widgets/async_photo.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config/theme.dart';
import 'profile/widgets/profile_widgets.dart';
import '../config/regions.dart';
import '../config/strings.dart';
import '../models/user_photo.dart';
import '../providers/auth_provider.dart';
import '../providers/device_info_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/online_users_provider.dart';
import '../providers/points_provider.dart';
import '../providers/social_provider.dart';
import '../providers/timeline_provider.dart';
import '../utils.dart';
import 'link_email_screen.dart';
import 'settings_screen.dart';
import 'contact_screen.dart';
import 'donate_screen.dart';
import '../core/admin_gate.dart';
import 'leaderboard_screen.dart';
import 'missions_screen.dart';
import 'point_history_screen.dart';
import 'social_list_screen.dart';
import 'friend_requests_screen.dart';
import 'subscriptions_screen.dart';
import '../core/perf/perf_probe.dart';

// Top-level function untuk compute() isolate — decode + resize + encode di background
Future<String?> _processAvatar(Uint8List bytes) async {
  // SELALU JPEG. Dulu dicoba WebP via FlutterImageCompress dulu, tapi encoder
  // WebP native itu menghasilkan file dengan ICC profile/krominansi yang tidak
  // konsisten antar-device → avatar tampil "biro-biro" (warna aneh) saat
  // dilihat dari HP LAIN lewat CDN. JPEG polos tidak punya masalah ini dan
  // di-decode universal — sama seperti foto chat. Cropper interaktif sudah
  // menentukan area 1:1, jadi cukup resize + encode.
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(
    decoded,
    width: 1024,
    height: 1024,
    interpolation: img.Interpolation.cubic,
  );
  return base64Encode(img.encodeJpg(resized, quality: 90));
}

// Galeri foto + preview blur. Return {full, preview}.
// preview: resolusi kecil (120px) + gaussian blur kuat → aman dikirim ke
// user lain sebagai teaser (tidak bisa "dijernihkan"), tapi tetap bikin
// penasaran. Foto asli hanya dikirim server saat sudah unlock.
Map<String, String>? _processPhotoWithPreview(Uint8List bytes) {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  // Orientasi EXIF — foto kamera jangan sampai miring.
  decoded = img.bakeOrientation(decoded);
  final resized = img.copyResize(decoded, width: 600);
  final full = base64Encode(img.encodeJpg(resized, quality: 82));
  // Preview: kecil + blur berat, kualitas rendah.
  var preview = img.copyResize(decoded, width: 120);
  preview = img.gaussianBlur(preview, radius: 8);
  final previewB64 = base64Encode(img.encodeJpg(preview, quality: 50));
  return {'full': full, 'preview': previewB64};
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;

  List<UserPhoto> _photos = [];
  bool _loadingPhotos = true;

  final TextEditingController _hashtagCtrl = TextEditingController();
  List<String> _hashtags = [];
  // About diedit inline di tempat (tanpa bottom sheet).
  bool _editingAbout = false;
  bool _savingAbout = false;
  final TextEditingController _aboutCtrl = TextEditingController();
  bool _savingHashtags = false;
  Uint8List? _cachedAvatarBytes;
  String? _lastAvatarB64;
  // UID user yang datanya sedang ditampilkan — dipakai mendeteksi swap
  // sesi dummy ⇄ admin (ProfileScreen hidup di IndexedStack, initState
  // tidak jalan lagi saat swap), supaya foto/hashtag/avatar ikut ganti.
  String? _loadedUid;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _hashtags = List.of(
      context.read<AuthProvider>().profile?.hashtags ?? const [],
    );
    // Onboarding + daily login toast
    Future.microtask(() {
      final pp = context.read<PointsProvider>();
      final s = context.read<LocaleProvider>().s;
      pp.refreshEnabled().then((_) => pp.showOnboardingIfNeeded(context, s));
    });
  }

  @override
  void dispose() {
    _hashtagCtrl.dispose();
    _aboutCtrl.dispose();
    super.dispose();
  }

  void _startEditAbout(String current) {
    _aboutCtrl.text = current;
    setState(() => _editingAbout = true);
  }

  void _cancelEditAbout() {
    FocusScope.of(context).unfocus();
    setState(() => _editingAbout = false);
  }

  Future<void> _saveAbout() async {
    final auth = context.read<AuthProvider>();
    final s = context.read<LocaleProvider>().s;
    final text = _aboutCtrl.text.trim();
    if (text == (auth.profile?.about ?? '')) {
      setState(() => _editingAbout = false);
      return;
    }
    setState(() => _savingAbout = true);
    try {
      await auth.updateProfile(about: text);
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        _editingAbout = false;
        _savingAbout = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingAbout = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  void _addHashtag(String raw) {
    final s = context.read<LocaleProvider>().s;
    final tag = raw.trim().replaceAll(RegExp(r'^#+'), '').toLowerCase();
    if (tag.isEmpty) return;
    if (_hashtags.contains(tag)) return;
    if (_hashtags.length >= 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errHashtagMax)));
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]{1,20}$').hasMatch(tag)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errHashtagFormat)));
      return;
    }
    final tags = List<String>.of(_hashtags)..add(tag);
    _saveHashtags(tags);
    _hashtagCtrl.clear();
  }

  void _removeHashtag(String tag) {
    final tags = List<String>.of(_hashtags)..remove(tag);
    _saveHashtags(tags);
  }

  Future<void> _saveHashtags(List<String> tags) async {
    final s = context.read<LocaleProvider>().s;
    final previous = _hashtags;
    setState(() {
      _hashtags = tags;
      _savingHashtags = true;
    });
    try {
      await context.read<AuthProvider>().updateHashtags(tags);
    } catch (e) {
      if (mounted) setState(() => _hashtags = previous);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errProfileSave)));
      }
    }
    if (mounted) setState(() => _savingHashtags = false);
  }

  Future<void> _loadPhotos() async {
    final uid = context.read<AuthProvider>().uid;
    if (uid == null) return;
    try {
      final photos = await context.read<AuthProvider>().getPhotos(uid);
      if (mounted) setState(() => _photos = photos);
    } catch (_) {}
    if (mounted) setState(() => _loadingPhotos = false);
  }

  void _pickGalleryFromSource() {
    final s = context.read<LocaleProvider>().s;
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
    final s = context.read<LocaleProvider>().s;
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
    final processed = await compute(_processPhotoWithPreview, bytes);
    if (!mounted) return;
    if (processed == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errPhotoLoad)));
      return;
    }
    // Slot = jumlah foto sebelum upload (0-based). Slot 1..5 dapat reward.
    final slotIndex = _photos.length;
    setState(() => _uploading = true);
    try {
      await context.read<AuthProvider>().uploadPhoto(
        processed['full']!,
        preview: processed['preview'],
      );
      await _loadPhotos();
      // Reward koin upload (slot 1..5) bila sistem koin aktif.
      if (mounted) {
        final pp = context.read<PointsProvider>();
        if (pp.enabled && slotIndex >= 1 && slotIndex <= 5) {
          final earned = await pp.rewardPhotoSlot(slotIndex);
          if (earned > 0 && mounted) {
            pp.showPointsToast(
              context,
              s.pointsGain(earned, s.reasonPhotoUpload),
            );
          }
        }
      }
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
    final pp = context.read<PointsProvider>();
    final s = context.read<LocaleProvider>().s;
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
    final s = context.read<LocaleProvider>().s;
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
      await context.read<AuthProvider>().deletePhoto(photo.id);
      // Hapus item saja dari list lokal (tanpa reload penuh getPhotos yang
      // me-download ulang semua foto). Grid max 6 item — murah.
      if (mounted) {
        setState(() => _photos.removeWhere((p) => p.id == photo.id));
      }
    } catch (_) {}
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final s = context.read<LocaleProvider>().s;
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
    final base64 = await _processAvatar(bytes);
    if (base64 == null) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoLoad)));
      return;
    }

    setState(() => _uploading = true);
    try {
      await context.read<AuthProvider>().updateAvatar(base64);
      if (mounted) {
        final uid = context.read<AuthProvider>().profile?.uid ?? '';
        if (uid.isNotEmpty) {
          try {
            context.read<OnlineUsersProvider>().updateAvatarForUid(uid, base64);
          } catch (_) {}
          try {
            context.read<TimelineProvider>().refreshAvatarForUid(uid, base64);
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
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
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
                  await context.read<AuthProvider>().removeAvatar();
                  if (mounted) {
                    final uid = context.read<AuthProvider>().profile?.uid ?? '';
                    if (uid.isNotEmpty) {
                      try {
                        context.read<OnlineUsersProvider>().removeAvatarForUid(
                          uid,
                        );
                      } catch (_) {}
                      try {
                        context.read<TimelineProvider>().refreshAvatarForUid(
                          uid,
                          '',
                        );
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
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
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
                                    !context.read<AuthProvider>().isRealAdmin) {
                                  setSheet(() => error = s.errNicknameBanned);
                                  focus.requestFocus();
                                  return;
                                }
                                final available = await context
                                    .read<AuthProvider>()
                                    .isNicknameAvailable(nick);
                                if (!available) {
                                  setSheet(() => error = s.errNicknameTaken);
                                  focus.requestFocus();
                                  return;
                                }
                              }
                              setSheet(() => loading = true);
                              try {
                                await context
                                    .read<AuthProvider>()
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
                                  final pp = context.read<PointsProvider>();
                                  pp.oneTimeBonus('completed_profile', 10).then(
                                    (earned) {
                                      if (earned && mounted) {
                                        pp.showPointsToast(
                                          context,
                                          s.pointsGain(
                                            10,
                                            s.reasonProfileComplete,
                                          ),
                                        );
                                      }
                                    },
                                  );
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

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('Profile');
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
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
    final locale = context.watch<LocaleProvider>();
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
    final isAnon = auth.isAnonymous && !auth.signingOut;
    // Sesi dummy aktif HANYA bisa dibuat dari panel admin (becomeDummy) —
    // flag internal AuthService. Dulu: kondisi && isRealAdmin membuat banner
    // TIDAK PERNAH tampil, karena saat sesi dummy aktif currentUser.email
    // = email DUMMY (bukan zunixe) → isRealAdmin false → "klik untuk
    // kembali ke admin" hilang.
    final dummyActive = auth.dummySessionActive;
    // `select` (bukan `watch`): PointsProvider di-refresh beberapa kali saat
    // buka halaman (get_points_enabled/get_wallet/yukcoin_v2_status). `watch`
    // membuat SELURUH halaman Profil (CustomScrollView + slivers) rebuild tiap
    // refresh selesai — sering menabrak frame tap tab → jank (diukur 2026-09-30:
    // tab3 = tab paling sering jank, max 21ms). Aturan §2.3: halaman penuh WAJIB
    // `select` per field untuk provider yang sering berubah.
    final pointsEnabled = context.select<PointsProvider, bool>(
      (p) => p.enabled,
    );
    final pointsValue = context.select<PointsProvider, int>((p) => p.points);
    final extraPhotoSlots = context.select<PointsProvider, int>(
      (p) => p.extraPhotoSlots,
    );
    final yukcoinV2Active = context.select<PointsProvider, bool>(
      (p) => p.yukcoinV2Active,
    );

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      body: CustomScrollView(
        slivers: [
          // ── Header Gradient ──
          SliverAppBar(
            backgroundColor: AppTheme.headerGradient.colors.first,
            expandedHeight: 280,
            pinned: true,
            // Keluar pindah ke Pengaturan › Akun.
            actions: [
              // Tombol Misi — sembunyikan saat sistem poin OFF
              if (pointsEnabled)
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 44,
                  ),
                  icon: const Icon(Icons.emoji_events_outlined, size: 20),
                  tooltip: s.missionsTitle,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MissionsScreen()),
                  ),
                ),
              IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 44,
                ),
                icon: const Icon(Icons.share_outlined, size: 20),
                tooltip: s.btnShareApp,
                onPressed: () async {
                  final pp = context.read<PointsProvider>();
                  final result = await Share.share(s.msgShareApp);
                  // Hanya beri bonus kalau benar-benar dibagikan (bukan sekadar
                  // buka lalu tutup share sheet). Bonus invited_friend one-time —
                  // kalau sudah pernah, earned=false → toast tidak muncul lagi.
                  if (result.status != ShareResultStatus.success) return;
                  final earned = await pp.oneTimeBonus('invited_friend', 30);
                  if (earned && context.mounted) {
                    pp.showPointsToast(
                      context,
                      s.pointsGain(30, s.reasonShare),
                    );
                  }
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
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
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
                                    ? ResizeImage(MemoryImage(avatarBytes),
                                        width: 184)
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
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                    ),
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
                            style: AppText.headline.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          if (profile?.isRegistered == true) ...[
                            SizedBox(width: 4),
                            Icon(
                              Icons.verified,
                              size: 18,
                              color: Color(0xFF8AB4F8),
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
          ),

          // ── Body ──
          SliverToBoxAdapter(
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
                  if (auth.dummySessionActive)
                    AdminGate.dummySessionBanner?.call(
                          context,
                          profile?.nickname,
                        ) ??
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
                              color:
                                  (auth.emailConfirmed
                                          ? Colors.green
                                          : Colors.orange)
                                      .shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              auth.emailConfirmed
                                  ? Icons.verified_user
                                  : Icons.warning_amber_rounded,
                              color: auth.emailConfirmed
                                  ? Colors.green
                                  : Colors.orange,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            auth.emailConfirmed
                                ? s.labelEmailVerified
                                : s.labelEmailUnverified,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          subtitle: Text(
                            auth.userEmail ?? '-',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: Icon(
                            auth.emailConfirmed
                                ? Icons.check_circle
                                : Icons.error_outline,
                            color: auth.emailConfirmed
                                ? Colors.green
                                : Colors.orange,
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
                        value: auth.uid?.substring(0, 8) ?? '-',
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
                                color: AppTheme.primary.withValues(
                                  alpha: 0.1,
                                ),
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
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
                                        hintStyle:
                                            AppText.bodySmall.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
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
                                    onPressed: _savingAbout
                                        ? null
                                        : _cancelEditAbout,
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
                                onPressed: () => _startEditAbout(
                                  profile?.about ?? '',
                                ),
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
                                      backgroundColor: AppTheme.accent
                                          .withValues(alpha: 0.08),
                                      side: BorderSide(
                                        color: AppTheme.accent.withValues(
                                          alpha: 0.3,
                                        ),
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
                                prefixIconConstraints: BoxConstraints(
                                  minWidth: 40,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppTheme.divider,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppTheme.divider,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppTheme.accent,
                                  ),
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
                                if (_photos.length <
                                    6 + context.watch<PointsProvider>().extraPhotoSlots)
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
                                      '${s.extraPhotoBuy} · ${context.read<PointsProvider>().costExtraPhotoSlot}',
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
                                  onLongPress: () =>
                                      _confirmDeletePhoto(_photos[i]),
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
                                  builder: (_) =>
                                      SocialListScreen(kind: 'followers'),
                                ),
                              ),
                            ),
                            ProfileStat(
                              label: s.socialFollowing,
                              value: profile?.followingCount ?? 0,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SocialListScreen(kind: 'following'),
                                ),
                              ),
                            ),
                            ProfileStat(
                              label: s.socialFriends,
                              value: profile?.friendsCount ?? 0,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SocialListScreen(kind: 'friends'),
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
                                    color: AppTheme.primary.withValues(
                                      alpha: 0.1,
                                    ),
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
                                Consumer<SocialProvider>(
                                  builder: (_, sp, __) =>
                                      sp.friendRequestCount > 0
                                      ? Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.danger,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '${sp.friendRequestCount}',
                                            style: AppText.caption.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        )
                                      : Icon(
                                          Icons.chevron_right,
                                          color: AppTheme.textSecondary,
                                        ),
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
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
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
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.1,
                                  ),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                          Icon(
                            Icons.favorite,
                            size: 16,
                            color: AppTheme.danger,
                          ),
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
                    future: context
                        .read<DeviceInfoProvider>()
                        .appVersionLabel(),
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
          ),
        ],
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
    final s = context.read<LocaleProvider>().s;
    final social = context.read<SocialProvider>();
    final current =
        context.read<AuthProvider>().profile?.subscriptionPrice ?? 0;
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
    if (ok) await context.read<AuthProvider>().reloadProfile();
  }
}
