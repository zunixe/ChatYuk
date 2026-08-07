import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../config/strings.dart';
import '../models/user_photo.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../services/auth_service.dart';
import 'link_email_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadPhotos();
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
    if (base64 == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errPhotoLoad)));
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

  void _showPhotoViewer(List<UserPhoto> photos, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewerScreen(photos: photos, initialIndex: index),
      ),
    );
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
                  value: age,
                  decoration: InputDecoration(labelText: s.labelAge),
                  items: [
                    for (int i = 13; i <= 60; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: (v) => setSheet(() => age = v ?? age),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: negara,
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
                  value: kota,
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
    final locale = context.watch<LocaleProvider>();
    final s = locale.s;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.titleProfile),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: s.btnEditProfile,
            onPressed: _editProfile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: profile?.gender == 'male' ? AppTheme.male : profile?.gender == 'female' ? AppTheme.female : AppTheme.accent,
                  backgroundImage: (profile?.avatar ?? '').isNotEmpty ? MemoryImage(base64Decode(profile!.avatar)) : null,
                  child: (profile?.avatar ?? '').isEmpty
                      ? Text(profile?.initial ?? '?', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800))
                      : null,
                ),
                Positioned(
                  right: 2, bottom: 2,
                  child: GestureDetector(
                    onTap: _uploading ? null : _showAvatarOptions,
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                      child: _uploading
                          ? const Padding(padding: EdgeInsets.all(7), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt, color: Colors.white, size: 17),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _uploading ? null : _showAvatarOptions,
              icon: const Icon(Icons.photo_camera_outlined, size: 16),
              label: Text((profile?.avatar ?? '').isNotEmpty ? s.btnChangePhoto : s.btnAddPhoto),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
            const SizedBox(height: 4),
            Text(profile?.nickname ?? 'Anon', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  profile?.gender == 'male' ? s.genderLabelMale : profile?.gender == 'female' ? s.genderLabelFemale : s.genderLabelOther,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(width: 12),
                Text('${profile?.age ?? 0} ${s.labelYears}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 24),

            // Info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                     _infoRow(s.labelStatus, _statusLabel(profile?.status ?? 'offline', s)),
                    const Divider(color: AppTheme.divider),
                    _infoRow(s.labelCountry, profile?.country ?? '-'),
                    const Divider(color: AppTheme.divider),
                    _infoRow(s.labelCity, profile?.city ?? '-'),
                    const Divider(color: AppTheme.divider),
                    _infoRow(s.labelUserId, auth.uid?.substring(0, 8) ?? '-'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Galeri Foto Pribadi
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(s.labelGallery, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                        if (_photos.length < 6)
                          TextButton.icon(
                            onPressed: _uploading ? null : _pickGalleryFromSource,
                            icon: _uploading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                                : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                            label: Text(s.btnAddGallery),
                            style: TextButton.styleFrom(foregroundColor: AppTheme.primary, padding: EdgeInsets.zero),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loadingPhotos)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
                      )
                    else if (_photos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: Text(s.labelGalleryEmpty, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: _photos.length,
                        itemBuilder: (ctx, i) {
                          final photo = _photos[i];
                          return GestureDetector(
                            onTap: () => _showPhotoViewer(_photos, i),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(base64Decode(photo.photo), fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 4, right: 4,
                                  child: GestureDetector(
                                    onTap: () => _confirmDeletePhoto(photo),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                                      child: const Icon(Icons.delete_outline, color: Colors.white, size: 14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Notifikasi ON/OFF
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_outlined, color: AppTheme.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.labelNotifications, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(s.notifEnabledDesc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: auth.notificationsEnabled,
                      onChanged: (v) => context.read<AuthProvider>().setNotificationsEnabled(v),
                      activeColor: AppTheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Settings — Bahasa / Language
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.labelLanguage, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _LangButton(
                            label: s.langId,
                            selected: locale.isId,
                            onTap: () => context.read<LocaleProvider>().setLang('id'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _LangButton(
                            label: s.langEn,
                            selected: !locale.isId,
                            onTap: () => context.read<LocaleProvider>().setLang('en'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Keamanan Akun
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.titleAccountSecurity, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    if (auth.isAnonymous) ...[
                      // Warning anonim
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(s.msgAnonymousWarning, style: const TextStyle(color: Colors.orange, fontSize: 12))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LinkEmailScreen())),
                          icon: const Icon(Icons.security, size: 18),
                          label: Text(s.btnSecureAccount),
                        ),
                      ),
                    ] else ...[
                      // Sudah punya email
                      Row(
                        children: [
                          const Icon(Icons.verified_user, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.labelSecuredAccount, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              Text(
                                auth.userEmail ?? '-',
                                style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Logout
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

            // Donasi
            Center(
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DonateScreen())),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, size: 16, color: AppTheme.danger),
                    SizedBox(width: 4),
                    Text('Donasi', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

String _statusLabel(String status, S s) {
    switch (status) {
      case 'idle': return '🌙 ${s.statusIdle}';
      case 'offline': return '⚪ ${s.statusOffline}';
      default: return '🟢 ${s.statusOnline}';
    }
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.divider, width: selected ? 2 : 1),
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: selected ? AppTheme.primary : AppTheme.textSecondary, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
        ),
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
  late final PageController _controller;
  late int _index;

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
            child: Image.memory(base64Decode(widget.photos[i].photo), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
