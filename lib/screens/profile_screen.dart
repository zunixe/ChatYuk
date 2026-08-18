import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../widgets/async_photo.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../config/strings.dart';
import '../config/app_flavor.dart';
import '../models/user_photo.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/social_provider.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../utils.dart';
import 'link_email_screen.dart';
import 'admin_panel_screen.dart';
import 'donate_screen.dart';
import 'leaderboard_screen.dart';
import 'missions_screen.dart';
import 'point_history_screen.dart';
import 'top_up_screen.dart';
import 'kyc_screen.dart';
import 'withdraw_screen.dart';
import 'social_list_screen.dart';
import 'friend_requests_screen.dart';
import 'subscriptions_screen.dart';

// Top-level function untuk compute() isolate — decode + resize + encode di background
String? _processAvatar(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(decoded, width: 300, height: 300);
  final jpg = img.encodeJpg(resized, quality: 70);
  return base64Encode(jpg);
}

// Galeri foto + preview blur. Return {full, preview}.
// preview: resolusi kecil (120px) + gaussian blur kuat → aman dikirim ke
// user lain sebagai teaser (tidak bisa "dijernihkan"), tapi tetap bikin
// penasaran. Foto asli hanya dikirim server saat sudah unlock.
Map<String, String>? _processPhotoWithPreview(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(decoded, width: 600);
  final full = base64Encode(img.encodeJpg(resized, quality: 75));
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
  bool _loggingOut = false;

  final AuthService _authService = AuthService();
  List<UserPhoto> _photos = [];
  bool _loadingPhotos = true;

  final TextEditingController _hashtagCtrl = TextEditingController();
  List<String> _hashtags = [];
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
    super.dispose();
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
        ).showSnackBar(SnackBar(content: Text('${s.errProfileSave} $e')));
      }
    }
    if (mounted) setState(() => _savingHashtags = false);
  }

  Future<void> _loadPhotos() async {
    final uid = context.read<AuthProvider>().uid;
    if (uid == null) return;
    try {
      final photos = await _authService.getPhotos(uid);
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
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      imageQuality: 85,
    );
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
      await _authService.uploadPhoto(
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
        ).showSnackBar(SnackBar(content: Text('${s.errPhotoSave}$e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
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
      await _authService.deletePhoto(photo.id);
      await _loadPhotos();
    } catch (_) {}
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final s = context.read<LocaleProvider>().s;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    // Proses image di background isolate — tidak block UI thread
    final base64 = await compute(_processAvatar, bytes);
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${s.errPhotoSave}$e')));
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
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _editProfile() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    if (profile == null) return;
    final currentNick = profile.nickname;
    final ctrl = TextEditingController(text: currentNick);
    final focus = FocusNode();
    int age = profile.age;
    String negara = profile.country;
    String kota = profile.city;
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
                  DropdownButtonFormField<int>(
                    initialValue: age,
                    decoration: InputDecoration(
                      labelText: s.labelAge,
                      prefixIcon: const Icon(Icons.cake_outlined, size: 20),
                    ),
                    items: [
                      for (int i = 13; i <= 60; i++)
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
                                  setSheet(() {
                                    loading = false;
                                    error = '${s.errGeneric}$e';
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
    final isAnon = auth.isAnonymous;
    final dummyActive = auth.dummySessionActive;
    final pp = context.watch<PointsProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      body: CustomScrollView(
        slivers: [
          // ── Header Gradient ──
          SliverAppBar(
            backgroundColor: AppTheme.headerGradient.colors.first,
            expandedHeight: 220,
            pinned: true,
            leading: IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.power_settings_new, size: 20),
              tooltip: s.btnLogout,
              onPressed: _loggingOut ? null : () => _confirmLogout(),
            ),
            actions: [
              // Tombol Misi — sembunyikan saat sistem poin OFF
              if (context.watch<PointsProvider>().enabled)
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
                      SizedBox(height: 32),
                      // Avatar
                      Stack(
                        children: [
                          Container(
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
                                  ? MemoryImage(avatarBytes)
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
                            _HeaderChip(label: genderLabel),
                          if ((profile?.age ?? 0) > 0)
                            _HeaderChip(
                              label: '${profile?.age} ${s.labelYears}',
                            ),
                          if ((profile?.country ?? '').isNotEmpty)
                            _HeaderChip(label: profile!.country),
                          if ((profile?.city ?? '').isNotEmpty)
                            _HeaderChip(label: profile!.city),
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
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Banner sesi dummy — kembali ke admin tanpa login manual
                  if (auth.dummySessionActive) ...[
                    Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.accent.withValues(alpha: 0.18),
                            AppTheme.accent.withValues(alpha: 0.06),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(
                                    alpha: 0.18,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.theater_comedy_rounded,
                                  color: AppTheme.accent,
                                  size: 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.dummyBannerTitle,
                                      style: AppText.bodyStrong.copyWith(
                                        color: AppTheme.accent,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      s.dummyBannerSubtitle.replaceFirst(
                                        '%s',
                                        profile?.nickname ?? '—',
                                      ),
                                      style: AppText.caption.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                padding: EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => _backToAdmin(s),
                              icon: Icon(
                                Icons.admin_panel_settings_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: Text(
                                s.dummyBackToAdmin,
                                style: AppText.label.copyWith(
                                  letterSpacing: 0,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
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
                    _SectionCard(
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
                  _SectionCard(
                    children: [
                      _InfoTile(
                        icon: Icons.circle,
                        iconColor: _statusColor(profile?.status ?? 'offline'),
                        label: s.labelStatus,
                        value: _statusLabel(profile?.status ?? 'offline', s),
                      ),
                      Divider(height: 1, indent: 52),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.badge_outlined,
                                color: AppTheme.accent,
                                size: 18,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.labelUsername,
                                    style: AppText.caption.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    profile?.nickname ?? '-',
                                    style: AppText.bodyStrong,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: AppTheme.primary,
                              ),
                              tooltip: s.btnEditProfile,
                              onPressed: _editProfile,
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, indent: 52),
                      _InfoTile(
                        icon: Icons.badge_outlined,
                        iconColor: AppTheme.primary,
                        label: s.labelUserId,
                        value: auth.uid?.substring(0, 8) ?? '-',
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  // Hashtag
                  _SectionLabel(label: s.labelHashtags),
                  SizedBox(height: 6),
                  _SectionCard(
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
                  _SectionLabel(label: s.labelGallery),
                  SizedBox(height: 6),
                  _SectionCard(
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
                                if (_photos.length < 6)
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
                                      builder: (_) => _PhotoViewerScreen(
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
                  SizedBox(height: 12),

                  // Sosial — angka fans/following + akses list
                  if (!isAnon) ...[
                    _SectionLabel(label: s.socialFollowers),
                    SizedBox(height: 6),
                    _SectionCard(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _ProfileStat(
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
                            _ProfileStat(
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
                            _ProfileStat(
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
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            Icons.person_add_alt,
                            color: AppTheme.primary,
                          ),
                          title: Text(
                            s.friendRequestTitle,
                            style: AppText.bodyStrong,
                          ),
                          trailing: Consumer<SocialProvider>(
                            builder: (_, sp, __) => sp.friendRequestCount > 0
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
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FriendRequestsScreen(),
                            ),
                          ),
                        ),
                        // Subscribe hanya relevan saat sistem poin aktif —
                        // sembunyikan menu langganan & harga subscribe saat OFF.
                        if (pp.enabled) ...[
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
                    SizedBox(height: 12),
                  ],

                  // Poin ChatYuk — diletakkan di antara My Photos dan Pengaturan
                  if (pp.enabled) ...[
                    _SectionLabel(label: s.pointsTitle),
                    SizedBox(height: 6),
                    _SectionCard(
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
                                      _fmtPoints(pp.points),
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
                        ] else ...[
                          // Rincian 3 bucket (bonus / pro / bisa dicairkan)
                          _BucketRow(
                            icon: Icons.card_giftcard,
                            color: Colors.blueGrey,
                            label: s.walletBucketBonus,
                            hint: s.walletBonusHint,
                            value: pp.bonusBalance,
                          ),
                          _BucketRow(
                            icon: Icons.shopping_cart_outlined,
                            color: Colors.green,
                            label: s.walletBucketTopup,
                            hint: s.walletTopupHint,
                            value: pp.topupBalance,
                          ),
                          _BucketRow(
                            icon: Icons.currency_exchange,
                            color: Color(0xFF2E7D32),
                            label: s.walletBucketEarned,
                            hint: s.walletEarnedHint,
                            value: pp.earnedBalance,
                          ),
                        ],
                        SizedBox(height: 4),
                        Divider(height: 1),
                        SizedBox(height: 4),
                        // Aksi cepat — grid ikon + label, rapi tanpa bubble
                        _ActionGrid(
                          actions: [
                            if (isAnon && !dummyActive)
                              _ActionItem(
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
                            if (!isAnon && AppFlavor.topupEnabled)
                              _ActionItem(
                                icon: Icons.add_card,
                                color: Colors.green,
                                label: s.topupTitle,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TopUpScreen(),
                                  ),
                                ),
                              ),
                            if (!isAnon && AppFlavor.showCashOut) ...[
                              _ActionItem(
                                icon: Icons.verified_user_outlined,
                                color: Colors.teal,
                                label: s.menuKyc,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => KycScreen(),
                                  ),
                                ),
                              ),
                              _ActionItem(
                                icon: Icons.currency_exchange,
                                color: Color(0xFF2E7D32),
                                label: s.withdrawTitle,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => WithdrawScreen(),
                                  ),
                                ),
                              ),
                            ],
                            _ActionItem(
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

                  // Pengaturan
                  _SectionLabel(label: s.titleSettings),
                  SizedBox(height: 6),
                  _SectionCard(
                    children: [
                      // Admin Panel entry (hanya untuk zunixe@gmail.com)
                      if (auth.userEmail == 'zunixe@gmail.com')
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdminPanelScreen(),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.admin_panel_settings,
                                    color: AppTheme.primary,
                                    size: 20,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    s.adminPanel,
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
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
                      if (auth.userEmail == 'zunixe@gmail.com')
                        Divider(height: 1, indent: 52),
                      // Notifikasi
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
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
                                Icons.notifications_outlined,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.labelNotifications,
                                    style: AppText.bodyStrong.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    s.notifEnabledDesc,
                                    style: AppText.bodySmall.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: auth.notificationsEnabled,
                              onChanged: (v) => context
                                  .read<AuthProvider>()
                                  .setNotificationsEnabled(v),
                              activeThumbColor: AppTheme.primary,
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, indent: 52),
                      // Admin: izin screenshot aplikasi (hanya untuk zunixe@gmail.com)
                      if (auth.userEmail == 'zunixe@gmail.com')
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.online.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.screenshot_monitor,
                                  color: AppTheme.online,
                                  size: 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.labelScreenshotAllow,
                                      style: AppText.bodyStrong.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      s.descScreenshotAdmin,
                                      style: AppText.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: auth.screenshotEnabled,
                                onChanged: (v) => context
                                    .read<AuthProvider>()
                                    .setScreenshotEnabled(v),
                                activeThumbColor: AppTheme.primary,
                              ),
                            ],
                          ),
                        ),
                      Divider(height: 1, indent: 52),
                      // Admin: watermark forensik foto view-once (hanya untuk zunixe@gmail.com)
                      if (auth.userEmail == 'zunixe@gmail.com')
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.fingerprint,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.labelWatermarkAdmin,
                                      style: AppText.bodyStrong.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      s.descWatermarkAdmin,
                                      style: AppText.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: auth.watermarkEnabled,
                                onChanged: (v) => context
                                    .read<AuthProvider>()
                                    .setWatermarkEnabled(v),
                                activeThumbColor: AppTheme.primary,
                              ),
                            ],
                          ),
                        ),
                      Divider(height: 1, indent: 52),
                      // Admin: invisible (tidak muncul di daftar online) — hanya zunixe@gmail.com
                      if (auth.userEmail == 'zunixe@gmail.com')
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.visibility_off_outlined,
                                  color: Colors.purple,
                                  size: 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.labelInvisibleAdmin,
                                      style: AppText.bodyStrong.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      s.descInvisibleAdmin,
                                      style: AppText.bodySmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: auth.invisibleEnabled,
                                onChanged: (v) => context
                                    .read<AuthProvider>()
                                    .setInvisibleEnabled(v),
                                activeThumbColor: Colors.purple,
                              ),
                            ],
                          ),
                        ),
                      Divider(height: 1, indent: 52),
                      // Password: set (akun Google) / change (akun email)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _showPasswordDialog(
                            context,
                            isSet: !auth.hasPassword,
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
                                  auth.hasPassword
                                      ? Icons.password
                                      : Icons.lock_outline,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      auth.hasPassword
                                          ? s.btnChangePassword
                                          : s.btnSetPassword,
                                      style: AppText.bodyStrong.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      auth.hasPassword
                                          ? s.descChangePassword
                                          : s.descSetPassword,
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
                      Divider(height: 1, indent: 52),
                      // Bahasa
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.language_outlined,
                                color: AppTheme.accent,
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.labelLanguage,
                                    style: AppText.bodyStrong.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    locale.isId
                                        ? '🇮🇩 Indonesia'
                                        : '🇬🇧 English',
                                    style: AppText.bodySmall.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: locale.isId,
                              onChanged: (v) => context
                                  .read<LocaleProvider>()
                                  .setLang(v ? 'id' : 'en'),
                              activeThumbColor: AppTheme.primary,
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, indent: 52),
                      // Tema gelap/terang
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.dark_mode_outlined,
                                color: AppTheme.accent,
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.labelTheme,
                                    style: AppText.bodyStrong.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    s.descTheme,
                                    style: AppText.bodySmall.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: context.watch<ThemeProvider>().isDark,
                              onChanged: (v) =>
                                  context.read<ThemeProvider>().setDark(v),
                              activeThumbColor: AppTheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'online':
        return const Color(0xFF69F0AE);
      case 'idle':
        return const Color(0xFFFFD740);
      default:
        return Colors.grey;
    }
  }

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

  Future<void> _backToAdmin(S s) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(s.dummyBackConfirmTitle),
        content: Text(s.dummyBackConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              s.btnCancel,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              s.dummyBackToAdmin,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await auth.backToAdmin();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(ok ? s.dummyBackDone : s.dummyBackFailed)),
      );
  }

  /// Dialog set password (akun Google) / ganti password (akun email).
  Future<void> _showPasswordDialog(
    BuildContext context, {
    required bool isSet,
  }) async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var loading = false;
    String? errorText;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !loading,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(isSet ? s.btnSetPassword : s.btnChangePassword),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSet ? s.descSetPassword : s.descChangePassword,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              SizedBox(height: 12),
              if (!isSet) ...[
                TextField(
                  controller: currentCtrl,
                  obscureText: true,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: s.labelCurrentPassword,
                  ),
                ),
                SizedBox(height: 10),
              ],
              TextField(
                controller: newCtrl,
                obscureText: true,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(labelText: s.labelPassword),
              ),
              SizedBox(height: 10),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(labelText: s.labelConfirmPassword),
              ),
              if (errorText != null) ...[
                SizedBox(height: 8),
                Text(
                  errorText!,
                  style: AppText.caption.copyWith(color: AppTheme.danger),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx, false),
              child: Text(
                s.btnCancel,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
              ),
              onPressed: loading
                  ? null
                  : () async {
                      final newPw = newCtrl.text;
                      final confirm = confirmCtrl.text;
                      if (newPw.length < 8) {
                        setState(() => errorText = s.errPasswordShort);
                        return;
                      }
                      if (newPw != confirm) {
                        setState(() => errorText = s.errPasswordMismatch);
                        return;
                      }
                      setState(() {
                        loading = true;
                        errorText = null;
                      });
                      try {
                        if (isSet) {
                          await auth.setPassword(newPw);
                        } else {
                          await auth.changePassword(currentCtrl.text, newPw);
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        final msg = e.toString();
                        setState(() {
                          loading = false;
                          errorText = msg.contains('Invalid login credentials')
                              ? s.errCurrentPasswordWrong
                              : '${s.errChangePassword}$msg';
                        });
                      }
                    },
              child: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      s.btnSavePassword,
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(isSet ? s.msgPasswordSet : s.msgPasswordChanged),
          ),
        );
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

  Future<void> _confirmLogout() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.logout_rounded, color: AppTheme.danger, size: 24),
            SizedBox(width: 10),
            Expanded(child: Text(s.btnLogout, style: AppText.title)),
          ],
        ),
        content: Text(
          s.confirmLogoutBody,
          style: AppText.body.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              s.btnCancel,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: Text(
              s.btnLogout,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loggingOut = true);
    await auth.signOut();
    chat.reset();
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;
  const _HeaderChip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppText.label.copyWith(
          color: Colors.white,
          letterSpacing: 0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onTap;
  const _ProfileStat({
    required this.label,
    required this.value,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          children: [
            Text(
              value < 0 ? '—' : '$value',
              style: AppText.titleEmphasis.copyWith(color: AppTheme.primary),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppText.label.copyWith(color: AppTheme.textSecondary),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  const _InfoTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(value, style: AppText.bodyStrong),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoViewerScreen extends StatefulWidget {
  final List<UserPhoto> photos;
  final int initialIndex;
  const _PhotoViewerScreen({required this.photos, required this.initialIndex});

  @override
  State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  int _index = 0;
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.photos.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (ctx, i) => Center(
          child: InteractiveViewer(
            maxScale: 4,
            child: AsyncPhotoViewer(base64: widget.photos[i].photo),
          ),
        ),
      ),
    );
  }
}

/// Format angka dengan pemisah ribuan (1000 -> 1.000).
String _fmtPoints(int n) {
  final digits = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buf.write(digits[i]);
    final rem = digits.length - 1 - i;
    if (rem > 0 && rem % 3 == 0) buf.write('.');
  }
  return buf.toString();
}

class _BucketRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String hint;
  final int value;
  const _BucketRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.hint,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.label.copyWith(letterSpacing: 0)),
                Text(
                  hint,
                  style: AppText.micro.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtPoints(value),
            style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
}

/// Grid aksi cepat — ikon bulat + label di bawahnya, rapi tanpa bubble.
class _ActionGrid extends StatelessWidget {
  final List<_ActionItem> actions;
  const _ActionGrid({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              onTap: a.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: a.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(a.icon, size: 22, color: a.color),
                    ),
                    SizedBox(height: 6),
                    Text(
                      a.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
