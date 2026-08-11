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
import '../models/user_photo.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../services/auth_service.dart';
import '../utils.dart';
import 'link_email_screen.dart';
import 'admin_panel_screen.dart';
import 'donate_screen.dart';

// Top-level function untuk compute() isolate — decode + resize + encode di background
String? _processAvatar(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(decoded, width: 300, height: 300);
  final jpg = img.encodeJpg(resized, quality: 70);
  return base64Encode(jpg);
}

// Galeri foto — resize lebih besar (800px), pertahankan rasio
String? _processPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(decoded, width: 800);
  final jpg = img.encodeJpg(resized, quality: 80);
  return base64Encode(jpg);
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;

  final AuthService _authService = AuthService();
  List<UserPhoto> _photos = [];
  bool _loadingPhotos = true;

  final TextEditingController _hashtagCtrl = TextEditingController();
  List<String> _hashtags = [];
  bool _savingHashtags = false;
  Uint8List? _cachedAvatarBytes;
  String? _lastAvatarB64;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _hashtags = List.of(context.read<AuthProvider>().profile?.hashtags ?? const []);
    // Onboarding + daily login toast
    Future.microtask(() {
      final pp = context.read<PointsProvider>();
      final s = context.read<LocaleProvider>().s;
      pp.refreshEnabled().then((_) => pp.showOnboardingIfNeeded(context, s.isId));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errHashtagMax)));
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]{1,20}$').hasMatch(tag)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errHashtagFormat)));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errProfileSave} $e')));
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppTheme.primary),
              title: Text(s.avatarCamera),
              onTap: () { Navigator.pop(sheetCtx); _addGalleryPhoto(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
              title: Text(s.avatarGallery),
              onTap: () { Navigator.pop(sheetCtx); _addGalleryPhoto(ImageSource.gallery); },
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
    final picked = await picker.pickImage(source: source, maxWidth: 1200, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final base64 = await compute(_processPhoto, bytes);
    if (!mounted) return;
    if (base64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errPhotoLoad)));
      return;
    }
    setState(() => _uploading = true);
    try {
      await _authService.uploadPhoto(base64);
      await _loadPhotos();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errPhotoSave}$e')));
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.btnDeletePhoto, style: const TextStyle(color: AppTheme.danger))),
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
    final picked = await picker.pickImage(source: source, maxWidth: 600, maxHeight: 600, imageQuality: 80);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    // Proses image di background isolate — tidak block UI thread
    final base64 = await compute(_processAvatar, bytes);
    if (base64 == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errPhotoLoad)));
      return;
    }

    setState(() => _uploading = true);
    try {
      await context.read<AuthProvider>().updateAvatar(base64);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errPhotoSave}$e')));
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppTheme.primary),
              title: Text(s.avatarCamera),
              onTap: () { Navigator.pop(sheetCtx); _pickAndUpload(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
              title: Text(s.avatarGallery),
              onTap: () { Navigator.pop(sheetCtx); _pickAndUpload(ImageSource.gallery); },
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
                title: Text(s.avatarDelete, style: const TextStyle(color: AppTheme.danger)),
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

  Future<void> _editNickname() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final current = auth.profile?.nickname ?? '';
    final ctrl = TextEditingController(text: current);
    final focus = FocusNode();
    String? error;
    bool loading = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text(s.btnChangeUsername, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(s.msgUsernameOldReleased, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  focusNode: focus,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: s.labelUsername,
                    hintText: s.hintNickname,
                    errorText: error,
                    suffixIcon: error == null && ctrl.text.isNotEmpty && ctrl.text != current
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                  ),
                  onChanged: (v) => setSheet(() => error = null),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading
                        ? null
                        : () async {
                            final nick = ctrl.text.trim();
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
                            final available = await context.read<AuthProvider>().isNicknameAvailable(nick);
                            if (!available) {
                              setSheet(() => error = s.errNicknameTaken);
                              focus.requestFocus();
                              return;
                            }
                            setSheet(() => loading = true);
                            try {
                              await context.read<AuthProvider>().updateProfile(nickname: nick);
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
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
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(s.btnSave, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editProfile() async {
    final s = context.read<LocaleProvider>().s;
    final profile = context.read<AuthProvider>().profile;
    if (profile == null) return;
    int age = profile.age;
    String negara = profile.country;
    String kota = profile.city;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text(s.btnEditProfile, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: age,
                  decoration: InputDecoration(labelText: s.labelAge),
                  items: [
                    for (int i = 13; i <= 60; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: (v) => setSheet(() => age = v ?? age),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: negara,
                  decoration: InputDecoration(labelText: s.labelCountry),
                  items: [
                    for (final n in kotaByNegara.keys)
                      DropdownMenuItem(value: n, child: Text(negaraLabel(n, s.isId))),
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
                  decoration: InputDecoration(labelText: s.labelCity),
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
                    onPressed: () async {
                      Navigator.pop(sheetCtx);
                      try {
                        await context.read<AuthProvider>().updateProfile(age: age, country: negara, city: kota);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgProfileSaved)));
                          // Bonus: complete profile
                          final pp = context.read<PointsProvider>();
                          pp.oneTimeBonus('completed_profile', 10).then((earned) {
                            if (earned && mounted) {
                              pp.showPointsToast(context, s.isId ? '+10 Poin — Profil lengkap!' : '+10 Points — Profile complete!');
                            }
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errProfileSave}$e')));
                        }
                      }
                    },
                    child: Text(s.btnSave),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    final avatarB64 = profile?.avatar ?? '';
    if (avatarB64.isNotEmpty && _lastAvatarB64 != avatarB64) {
      _lastAvatarB64 = avatarB64;
      try { _cachedAvatarBytes = base64Decode(avatarB64); } catch (_) {}
    }
    final avatarBytes = _cachedAvatarBytes;
    final locale = context.watch<LocaleProvider>();
    final s = locale.s;
    final avatarColor = profile?.gender == 'male' ? AppTheme.male : profile?.gender == 'female' ? AppTheme.female : AppTheme.accent;
    final genderLabel = profile?.gender == 'male' ? s.labelGenderMale : profile?.gender == 'female' ? s.labelGenderFemale : '';
    final isAnon = auth.isAnonymous;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      body: CustomScrollView(
        slivers: [
          // ── Header Gradient ──
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            actions: [
              IconButton(icon: const Icon(Icons.share_outlined), tooltip: s.btnShareApp, onPressed: () {
            Share.share(s.msgShareApp);
            context.read<PointsProvider>().oneTimeBonus('invited_friend', 30).then((earned) {
              if (earned && context.mounted) {
                context.read<PointsProvider>().showPointsToast(context, s.isId ? '+30 Poin — Share!' : '+30 Points — Share!');
              }
            });
          }),
              IconButton(icon: const Icon(Icons.edit_outlined), tooltip: s.btnEditProfile, onPressed: _editProfile),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primaryDark, AppTheme.primary, AppTheme.accent],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),
                      // Avatar
                      Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
                            ),
                            child: CircleAvatar(
                              radius: 46,
                              backgroundColor: avatarColor,
                              backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
                              child: (profile?.avatar ?? '').isEmpty
                                  ? Text(profile?.initial ?? '?', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800))
                                  : null,
                            ),
                          ),
                          Positioned(
                            right: 0, bottom: 0,
                            child: GestureDetector(
                              onTap: _uploading ? null : _showAvatarOptions,
                              child: Container(
                                width: 30, height: 30,
                                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                                child: _uploading
                                    ? const Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                                    : const Icon(Icons.camera_alt, color: AppTheme.primary, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Nama + verified badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(profile?.nickname ?? '-', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          if (profile?.isRegistered == true) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, size: 18, color: Color(0xFF8AB4F8)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Chips info
                      Wrap(
                        spacing: 6,
                        children: [
                          if (genderLabel.isNotEmpty) _HeaderChip(label: genderLabel),
                          if ((profile?.age ?? 0) > 0) _HeaderChip(label: '${profile?.age} ${s.labelYears}'),
                          if ((profile?.country ?? '').isNotEmpty) _HeaderChip(label: profile!.country),
                          if ((profile?.city ?? '').isNotEmpty) _HeaderChip(label: profile!.city),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Anonymous warning — prominent
                  if (isAnon) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.titleAccountSecurity, style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w700, fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(s.msgAnonymousWarning, style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LinkEmailScreen())),
                        icon: const Icon(Icons.security, size: 18),
                        label: Text(s.btnSecureAccount),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Status + email section
                  if (!isAnon) ...[
                    _SectionCard(children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                          child: const Icon(Icons.verified_user, color: Colors.green, size: 20),
                        ),
                        title: Text(s.labelSecuredAccount, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        subtitle: Text(auth.userEmail ?? '-', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                        trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      ),
                    ]),
                    const SizedBox(height: 12),
                  ],

                  // Status
                  _SectionCard(children: [
                    _InfoTile(icon: Icons.circle, iconColor: _statusColor(profile?.status ?? 'offline'), label: s.labelStatus, value: _statusLabel(profile?.status ?? 'offline', s)),
                    const Divider(height: 1, indent: 52),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.badge_outlined, color: AppTheme.accent, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.labelUsername, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                Text(profile?.nickname ?? '-', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                            tooltip: s.btnChangeUsername,
                            onPressed: _editNickname,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, indent: 52),
                    _InfoTile(icon: Icons.badge_outlined, iconColor: AppTheme.primary, label: s.labelUserId, value: auth.uid?.substring(0, 8) ?? '-'),
                  ]),
                  const SizedBox(height: 12),

                  // Poin
                  if (context.watch<PointsProvider>().enabled) ...[
                    _SectionLabel(label: s.pointsTitle),
                    const SizedBox(height: 6),
                    _SectionCard(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: Colors.amber.shade50, shape: BoxShape.circle),
                            child: Icon(isAnon ? Icons.lock_outlined : Icons.monetization_on_outlined, color: Colors.amber.shade700, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${s.pointsBalance}: ${profile?.points ?? 50}',
                                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                                Text('≈ ${profile?.points ?? 50} ${s.isId ? "pesan lagi" : "more messages"}',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                if (isAnon)
                                  Text(s.pointsAnonymousLose, style: TextStyle(color: Colors.orange.shade700, fontSize: 11))
                                else
                                  Text(s.pointsSafe, style: const TextStyle(color: Colors.green, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isAnon) ...[
                      const Divider(height: 1, indent: 52),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LinkEmailScreen())),
                          icon: const Icon(Icons.email_outlined, size: 18, color: Colors.orange),
                          label: Text(s.pointsRegisterBonusLabel, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ]),
                  ],
                  const SizedBox(height: 12),

                  // Pengaturan
                  _SectionLabel(label: s.isId ? 'Pengaturan' : 'Settings'),
                  const SizedBox(height: 6),
                  _SectionCard(children: [
                    // Notifikasi
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.notifications_outlined, color: AppTheme.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.labelNotifications, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                                Text(s.notifEnabledDesc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          Switch(
                            value: auth.notificationsEnabled,
                            onChanged: (v) => context.read<AuthProvider>().setNotificationsEnabled(v),
                            activeThumbColor: AppTheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, indent: 52),
                    // Admin Panel entry (hanya untuk zunixe@gmail.com)
                    if (auth.userEmail == 'zunixe@gmail.com')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: InkWell(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelScreen())),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
                                child: const Icon(Icons.admin_panel_settings, color: AppTheme.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(child: Text('Admin Panel', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600))),
                              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    const Divider(height: 1, indent: 52),
                    // Admin: izin screenshot aplikasi (hanya untuk zunixe@gmail.com)
                    if (auth.userEmail == 'zunixe@gmail.com')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: AppTheme.online.withValues(alpha: 0.12), shape: BoxShape.circle),
                              child: const Icon(Icons.screenshot_monitor, color: AppTheme.online, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.labelScreenshotAllow, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                                  Text(s.descScreenshotAdmin, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            Switch(
                              value: auth.screenshotEnabled,
                              onChanged: (v) => context.read<AuthProvider>().setScreenshotEnabled(v),
                              activeThumbColor: AppTheme.primary,
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 1, indent: 52),
                    // Admin: watermark forensik foto view-once (hanya untuk zunixe@gmail.com)
                    if (auth.userEmail == 'zunixe@gmail.com')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                              child: const Icon(Icons.fingerprint, color: AppTheme.primary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.labelWatermarkAdmin, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                                  Text(s.descWatermarkAdmin, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            Switch(
                              value: auth.watermarkEnabled,
                              onChanged: (v) => context.read<AuthProvider>().setWatermarkEnabled(v),
                              activeThumbColor: AppTheme.primary,
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 1, indent: 52),
                    // Bahasa
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.language_outlined, color: AppTheme.accent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.labelLanguage, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                                Text(locale.isId ? '🇮🇩 Indonesia' : '🇬🇧 English', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          Switch(
                            value: locale.isId,
                            onChanged: (v) => context.read<LocaleProvider>().setLang(v ? 'id' : 'en'),
                            activeThumbColor: AppTheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // Hashtag
                  _SectionLabel(label: s.labelHashtags),
                  const SizedBox(height: 6),
                  _SectionCard(children: [
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _hashtags.map((tag) => InputChip(
                              label: Text('#$tag'),
                              onDeleted: _savingHashtags ? null : () => _removeHashtag(tag),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              backgroundColor: AppTheme.accent.withValues(alpha: 0.08),
                              side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3)),
                              labelStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                              visualDensity: VisualDensity.compact,
                            )).toList(),
                          ),
                          if (_hashtags.isEmpty && !_savingHashtags)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(s.hintHashtag, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _hashtagCtrl,
                            enabled: !_savingHashtags,
                            onSubmitted: _addHashtag,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: s.hintHashtag,
                              isDense: true,
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(bottom: 2),
                                child: Icon(Icons.tag, size: 18, color: AppTheme.accent),
                              ),
                              prefixIconConstraints: const BoxConstraints(minWidth: 40),
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.divider)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.divider)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.accent)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // Galeri
                  _SectionLabel(label: s.labelGallery),
                  const SizedBox(height: 6),
                  _SectionCard(children: [
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children: [
                                Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.pink.shade50, shape: BoxShape.circle), child: Icon(Icons.photo_library_outlined, color: Colors.pink.shade400, size: 20)),
                                const SizedBox(width: 12),
                                Text(s.labelGallery, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                              ]),
                              if (_photos.length < 6)
                                TextButton.icon(
                                  onPressed: _uploading ? null : _pickGalleryFromSource,
                                  icon: _uploading
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                                      : const Icon(Icons.add, size: 16),
                                  label: Text(s.btnAddGallery, style: const TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(foregroundColor: AppTheme.primary, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_loadingPhotos)
                            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)))
                          else if (_photos.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: Text(s.labelGalleryEmpty, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
                              itemCount: _photos.length,
                              itemBuilder: (_, i) => GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PhotoViewerScreen(photos: _photos, initialIndex: i))),
                                onLongPress: () => _confirmDeletePhoto(_photos[i]),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: AsyncPhotoThumbnail(base64: _photos[i].photo),
                                    ),
                                    Positioned(
                                      top: 4, right: 4,
                                      child: GestureDetector(
                                        onTap: () => _confirmDeletePhoto(_photos[i]),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.55),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close, size: 14, color: Colors.white),
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
                  ]),
                  const SizedBox(height: 20),

                  // Actions
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final chat = context.read<ChatProvider>();
                        await auth.signOut();
                        chat.reset();
                      },
                      icon: const Icon(Icons.logout),
                      label: Text(s.btnLogout),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: const BorderSide(color: AppTheme.danger),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DonateScreen())),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.favorite, size: 16, color: AppTheme.danger),
                        const SizedBox(width: 4),
                        Text(s.titleDonate, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                      ]),
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
      case 'online': return const Color(0xFF69F0AE);
      case 'idle': return const Color(0xFFFFD740);
      default: return Colors.grey;
    }
  }

  String _statusLabel(String status, S s) {
    switch (status) {
      case 'idle': return '🌙 ${s.statusIdle}';
      case 'offline': return '⚪ ${s.statusOffline}';
      default: return '🟢 ${s.statusOnline}';
    }
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
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5));
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.iconColor, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
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
