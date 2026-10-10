import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/avatar_service.dart';
import '../../core/cache/media_disk_cache.dart';
import '../../core/media/native_image.dart';
import '../../services/storage_photo_service.dart';
import '../person_avatar.dart';
import '../user_avatar.dart' show cachedUserAvatarBytes, rememberAvatarBytes;

class PostAuthorAvatar extends StatefulWidget {
  final Map<String, dynamic> post;
  final String name;
  final double size;
  /// Tap avatar → zoom foto (dipisah dari tap nama → profil), pola sama
  /// dengan menu online. Menerima bytes hasil resolve (null = inisial).
  final void Function(Uint8List? bytes)? onAvatarTap;
  const PostAuthorAvatar({
    required this.post,
    required this.name,
    required this.size,
    this.onAvatarTap,
  });

  @override
  State<PostAuthorAvatar> createState() => PostAuthorAvatarState();
}

class PostAuthorAvatarState extends State<PostAuthorAvatar> {
  // Resolve SATU tahap langsung ke bytes per identitas avatar (fetch +
  // decode) — tanpa FutureBuilder dua tahap (fallback → future → decode
  // → foto) yang terlihat kedip. Rebuild/scroll tidak memicu kerja ulang.
  //
  // Bytes disimpan di cache BERSAMA UserAvatar (per-uid), BUKAN map statis
  // sendiri — dulu tiap kelas avatar menyimpan salinan bytes yang SAMA
  // (retensi ganda native → bloat). Lihat user_avatar.dart.
  Uint8List? _bytes;
  String? _resolvedFor;
  String get _uid => widget.post['authorId'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    // Jalur SINKRON dulu: cache statis → disk → decode B64 inline.
    // Berhasil = frame pertama langsung foto (tanpa fallback inisial).
    // Gagal (perlu network) = jalur async seperti dulu.
    if (!_resolveSync()) _resolveAsync();
  }

  @override
  void didUpdateWidget(PostAuthorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post['authorAvatar'] != widget.post['authorAvatar']) {
      _bytes = null;
      _resolvedFor = null;
      if (!_resolveSync()) _resolveAsync();
    }
  }

  /// Resolve sinkron sebelum frame pertama. Return true kalau bytes
  /// langsung tersedia (tidak perlu setState — build() jalan sesudahnya).
  bool _resolveSync() {
    final avatar = widget.post['authorAvatar'] as String? ?? '';
    if (avatar.isEmpty) return false;
    _resolvedFor = avatar;
    try {
      final cached = cachedUserAvatarBytes(_uid);
      if (cached != null) {
        _bytes = cached;
        return true;
      }
      if (StoragePhotoService.instance.isAvatarPath(avatar)) {
        final disk = MediaDiskCache.instance.readSync(avatar);
        if (disk != null && disk.isNotEmpty) {
          rememberAvatarBytes(_uid, disk);
          _bytes = disk;
          return true;
        }
        return false;
      }
      // B64 inline kecil → decode sinkron langsung (tanpa compute).
      if (avatar.length < 200000) {
        final b = base64Decode(avatar);
        if (b.isNotEmpty) {
          rememberAvatarBytes(_uid, b);
          _bytes = b;
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _resolveAsync() async {
    final avatar = widget.post['authorAvatar'] as String? ?? '';
    if (avatar.isEmpty) return;
    if (_resolvedFor == avatar && _bytes != null) return;
    _resolvedFor = avatar;
    final cached = cachedUserAvatarBytes(_uid);
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }
    final isPath = StoragePhotoService.instance.isAvatarPath(avatar);
    final b64 =
        isPath ? await AvatarB64Service.instance.getByPath(avatar) : avatar;
    if (b64.isEmpty || !mounted) return;
    if (_resolvedFor != avatar) return;
    final bytes = await NativeImage.decodeAvatar(b64, maxPx: 256);
    if (bytes == null || !mounted || _resolvedFor != avatar) return;
    rememberAvatarBytes(_uid, bytes);
    setState(() => _bytes = bytes);
  }

  /// Tanpa foto di payload → PersonAvatar (standar yang sama dengan
  /// Pengguna Online: latar tint + ring warna gender; foto di-resolve
  /// sendiri by uid bila ada).
  Widget _fallback(String uid) => PersonAvatar(
        uid: uid,
        name: widget.name,
        gender: widget.post['authorGender'] as String? ?? '',
        size: widget.size,
      );

  @override
  Widget build(BuildContext context) {
    final uid = widget.post['authorId'] as String? ?? '';
    final avatar = widget.post['authorAvatar'] as String? ?? '';
    // Zoom: pakai bytes resolve-sendiri bila ada, else bytes dari cache
    // render PersonAvatar/UserAvatar (fallback path me-load foto sendiri).
    final tap = widget.onAvatarTap == null
        ? null
        : () => widget.onAvatarTap!(cachedUserAvatarBytes(uid) ?? _bytes);
    if (avatar.isEmpty) {
      return tap == null
          ? _fallback(uid)
          : GestureDetector(onTap: tap, child: _fallback(uid));
    }
    final bytes = _bytes;
    // Belum siap → fallback (ProfileAvatar ikut lazy-load dari lokal,
    // jadi satu pop-in halus, bukan kedip berulang).
    if (bytes == null || _resolvedFor != avatar) {
      return tap == null
          ? _fallback(uid)
          : GestureDetector(onTap: tap, child: _fallback(uid));
    }
    final img = ClipRRect(
      borderRadius: BorderRadius.circular(widget.size / 2),
      child: Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        cacheWidth: (widget.size * 2).round(),
        gaplessPlayback: true,
      ),
    );
    return tap == null ? img : GestureDetector(onTap: tap, child: img);
  }
}
