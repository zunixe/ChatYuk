import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'entry_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;

  Future<void> _pickAndUpload(ImageSource source) async {
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
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membaca gambar')),
      );
      return;
    }

    final resized = img.copyResize(decoded, width: 300, height: 300);
    final jpg = img.encodeJpg(resized, quality: 70);
    final base64 = base64Encode(jpg);

    setState(() => _uploading = true);
    try {
      await context.read<AuthProvider>().updateAvatar(base64);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal simpan foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _showAvatarOptions() async {
    final auth = context.read<AuthProvider>();
    final hasAvatar = (auth.profile?.avatar ?? '').isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
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
              title: const Text('Ambil Foto'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUpload(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
              title: const Text('Dari Galeri'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
                title: const Text('Hapus Foto', style: TextStyle(color: AppTheme.danger)),
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

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: profile?.gender == 'male'
                      ? AppTheme.male
                      : profile?.gender == 'female'
                          ? AppTheme.female
                          : AppTheme.accent,
                  backgroundImage: (profile?.avatar ?? '').isNotEmpty
                      ? MemoryImage(base64Decode(profile!.avatar))
                      : null,
                  child: (profile?.avatar ?? '').isEmpty
                      ? Text(
                          profile?.initial ?? '?',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
                        )
                      : null,
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: GestureDetector(
                    onTap: _uploading ? null : _showAvatarOptions,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: _uploading
                          ? const Padding(
                              padding: EdgeInsets.all(7),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
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
              label: Text((profile?.avatar ?? '').isNotEmpty ? 'Ganti Foto Profil' : 'Tambah Foto Profil'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
            const SizedBox(height: 4),
            Text(
              profile?.nickname ?? 'Anon',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  profile?.gender == 'male' ? '👨 Laki-laki' : profile?.gender == 'female' ? '👩 Perempuan' : '🧑 Lainnya',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(width: 12),
                Text(
                  '${profile?.age ?? 0} tahun',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _infoRow('Status', _statusLabel(profile?.status ?? 'offline')),
                    const Divider(color: AppTheme.divider),
                    _infoRow('User ID', auth.uid?.substring(0, 8) ?? '-'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Logout
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final chat = context.read<ChatProvider>();
                  await auth.signOut();
                  chat.reset();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const EntryScreen()),
                      (route) => false,
                    );
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Keluar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  String _statusLabel(String status) {
    switch (status) {
      case 'idle':
        return '🟡 Idle';
      case 'offline':
        return '⚪ Offline';
      default:
        return '🟢 Online';
    }
  }
}
