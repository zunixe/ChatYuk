import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../services/avatar_service.dart';
import '../services/storage_photo_service.dart';
import '../widgets/profile_avatar.dart';
import 'private_chat_screen.dart';

Uint8List? _decodeB64(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

class OtherProfileScreen extends StatefulWidget {
  final String uid;
  final String name;
  final String avatar; // path or base64 or empty
  const OtherProfileScreen({super.key, required this.uid, required this.name, this.avatar = ''});

  @override
  State<OtherProfileScreen> createState() => _OtherProfileScreenState();
}

class _OtherProfileScreenState extends State<OtherProfileScreen> {
  UserModel? _user;
  bool _loading = true;
  Uint8List? _bytes;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = widget.uid;
    if (uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    // avatar dari post payload dulu biar langsung tampil
    var initialB64 = widget.avatar;
    if (initialB64.isNotEmpty && StoragePhotoService.instance.isAvatarPath(initialB64)) {
      initialB64 = await AvatarB64Service.instance.getByPath(initialB64);
    }
    if (initialB64.isNotEmpty && mounted) {
      final b = await compute(_decodeB64, initialB64);
      if (mounted) setState(() => _bytes = b);
    }
    try {
      final u = await context.read<AuthProvider>().getOtherProfile(uid);
      if (!mounted) return;
      setState(() {
        _user = u;
        _loading = false;
      });
      if (u != null && u.avatar.isNotEmpty) {
        String b64 = u.avatar;
        if (StoragePhotoService.instance.isAvatarPath(b64)) {
          b64 = await AvatarB64Service.instance.getByPath(b64);
        }
        if (b64.isNotEmpty && mounted) {
          final b = await compute(_decodeB64, b64);
          if (mounted) setState(() => _bytes = b);
        }
      }
      // cek follow status via SocialProvider
      try {
        final sp = context.read<SocialProvider>();
        // SocialProvider tidak ada getter langsung, cek via isFollowing di post? fallback query
        // kita coba cek dengan fetch follow status via provider jika ada
      } catch (_) {}
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showZoom() {
    if (_bytes == null) return;
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(_bytes!, fit: BoxFit.contain),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final name = u?.nickname ?? widget.name;
    final gender = u?.gender ?? '';
    final country = u?.country ?? '';
    final city = u?.city ?? '';
    final age = u?.age ?? 0;
    final color = gender == 'male' ? AppTheme.male : gender == 'female' ? AppTheme.female : AppTheme.primary;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Profil' : name),
        backgroundColor: AppTheme.headerGradient.colors.first,
      ),
      body: _loading && u == null
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(gradient: AppTheme.headerGradient),
                    child: SafeArea(
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: _showZoom,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))],
                              ),
                              child: CircleAvatar(
                                radius: 46,
                                backgroundColor: color,
                                backgroundImage: _bytes != null ? MemoryImage(_bytes!) : null,
                                child: _bytes == null
                                    ? Text(
                                        (name.isEmpty ? '?' : name[0].toUpperCase()),
                                        style: TextStyle(color: Colors.white, fontSize: AppGlyph.avatarInitial(92), fontWeight: FontWeight.w800),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(name, style: AppText.headline.copyWith(color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(
                            [if (gender.isNotEmpty) gender, if (age > 0) '$age th', if (city.isNotEmpty) city, if (country.isNotEmpty) country].join(' · '),
                            style: AppText.bodySmall.copyWith(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                    label: const Text('Chat'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                    onPressed: () {
                                      final myUid = context.read<AuthProvider>().uid ?? '';
                                      if (myUid.isEmpty || myUid == widget.uid) return;
                                      final ids = [myUid, widget.uid]..sort();
                                      final chatId = '${ids[0]}_${ids[1]}';
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PrivateChatScreen(
                                            chatId: chatId,
                                            otherName: name,
                                            otherUid: widget.uid,
                                            otherGender: u?.gender ?? '',
                                            otherCountry: u?.country ?? '',
                                            otherCity: u?.city ?? '',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: Icon(_isFollowing ? Icons.person_remove_outlined : Icons.person_add_outlined, size: 18, color: Colors.white),
                                    label: Text(_isFollowing ? 'Unfollow' : 'Follow', style: const TextStyle(color: Colors.white)),
                                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                    onPressed: () async {
                                      try {
                                        final sp = context.read<SocialProvider>();
                                        if (_isFollowing) {
                                          await sp.unfollow(widget.uid);
                                        } else {
                                          await sp.follow(widget.uid);
                                        }
                                        if (mounted) setState(() => _isFollowing = !_isFollowing);
                                      } catch (_) {}
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  if (u != null) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _InfoRow(label: 'Status', value: u.status),
                          _InfoRow(label: 'Negara', value: country),
                          _InfoRow(label: 'Kota', value: city),
                          if (u.hashtags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: u.hashtags.map((t) => Chip(label: Text(t, style: AppText.label), backgroundColor: AppTheme.primary.withValues(alpha: 0.1))).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: AppText.caption.copyWith(color: AppTheme.textSecondary))),
          Expanded(child: Text(value.isEmpty ? '-' : value, style: AppText.bodyStrong)),
        ],
      ),
    );
  }
}
