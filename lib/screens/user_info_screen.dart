import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../models/user_photo.dart';
import '../providers/locale_provider.dart';
import '../services/auth_service.dart';

class UserInfoScreen extends StatefulWidget {
  final String userId;
  final String fallbackName;
  const UserInfoScreen({super.key, required this.userId, required this.fallbackName});

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  UserModel? _profile;
  bool _loading = true;
  List<UserPhoto> _photos = [];
  bool _loadingPhotos = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPhotos();
  }

  Future<void> _load() async {
    try {
      final p = await AuthService().getProfileById(widget.userId);
      if (mounted) setState(() => _profile = p);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await AuthService().getPhotos(widget.userId);
      if (mounted) setState(() => _photos = photos);
    } catch (_) {}
    if (mounted) setState(() => _loadingPhotos = false);
  }

  void _showPhotoViewer(List<UserPhoto> photos, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _UserPhotoViewer(photos: photos, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final profile = _profile;

    final name = profile?.nickname ?? widget.fallbackName;
    final genderLabel = profile?.gender == 'male'
        ? s.genderLabelMale
        : profile?.gender == 'female'
            ? s.genderLabelFemale
            : s.genderLabelOther;
    final status = profile?.status ?? 'offline';
    final statusLabel = status == 'online'
        ? s.statusOnline
        : status == 'idle'
            ? s.statusIdle
            : s.statusOffline;
    final statusColor = status == 'online'
        ? AppTheme.online
        : status == 'idle'
            ? AppTheme.idle
            : AppTheme.textSecondary;

    return Scaffold(
      appBar: AppBar(title: Text(s.titleProfile)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // Avatar
                  Stack(
                    alignment: Alignment.bottomRight,
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
                                (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
                              )
                            : null,
                      ),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w700)),
                      ),
                      if (profile?.isRegistered == true) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.verified, size: 20, color: Color(0xFF4A90E2)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(genderLabel, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                      if (profile?.age != null && profile!.age > 0) ...[
                        const SizedBox(width: 12),
                        Text('${profile.age} ${s.labelYears}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Info card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _infoRow(s.labelStatus, statusLabel),
                          if (profile != null) ...[
                            const Divider(color: AppTheme.divider),
                            _infoRow(s.labelCountry, profile.country.isEmpty ? '-' : profile.country),
                            const Divider(color: AppTheme.divider),
                            _infoRow(s.labelCity, profile.city.isEmpty ? '-' : profile.city),
                          ],
                          const Divider(color: AppTheme.divider),
                          _infoRow(s.labelUserId, widget.userId.substring(0, 8)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Galeri Foto Profil
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.labelOthersGallery, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
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
                              itemBuilder: (ctx, i) => GestureDetector(
                                onTap: () => _showPhotoViewer(_photos, i),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(base64Decode(_photos[i].photo), fit: BoxFit.cover),
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
}

class _UserPhotoViewer extends StatefulWidget {
  final List<UserPhoto> photos;
  final int initialIndex;
  const _UserPhotoViewer({required this.photos, required this.initialIndex});

  @override
  State<_UserPhotoViewer> createState() => _UserPhotoViewerState();
}

class _UserPhotoViewerState extends State<_UserPhotoViewer> {
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
