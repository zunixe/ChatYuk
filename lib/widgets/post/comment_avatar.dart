import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/storage_paths.dart';
import '../../providers/riverpod/service_locator.dart';
import '../../core/cache/media_disk_cache.dart';
import '../../core/media/native_image.dart';
import '../gender_avatar.dart';
import '../user_avatar.dart' show cachedUserAvatarBytes, rememberAvatarBytes;

class CommentAvatar extends StatefulWidget {
  final String uid;
  final String name;
  final String gender;
  final String avatar;
  final double size;
  const CommentAvatar({
    required this.uid,
    required this.name,
    required this.gender,
    required this.avatar,
    this.size = 28,
  });

  @override
  State<CommentAvatar> createState() => CommentAvatarState();
}

class CommentAvatarState extends State<CommentAvatar> {
  // Bytes memakai cache BERSAMA UserAvatar (per-uid) — bukan map statis
  // sendiri (retensi ganda). Lihat user_avatar.dart.
  Uint8List? _bytes;
  String? _resolvedFor;

  @override
  void initState() {
    super.initState();
    if (!_resolveSync()) _resolveAsync();
  }

  @override
  void didUpdateWidget(CommentAvatar old) {
    super.didUpdateWidget(old);
    if (old.avatar != widget.avatar || old.uid != widget.uid) {
      _bytes = null;
      _resolvedFor = null;
      if (!_resolveSync()) _resolveAsync();
    }
  }

  bool _resolveSync() {
    final avatar = widget.avatar;
    if (avatar.isEmpty) return false;
    _resolvedFor = avatar;
    try {
      final cached = cachedUserAvatarBytes(widget.uid);
      if (cached != null) {
        _bytes = cached;
        return true;
      }
      if (isAvatarPathValue(avatar)) {
        final disk = MediaDiskCache.instance.readSync(avatar);
        if (disk != null && disk.isNotEmpty) {
          rememberAvatarBytes(widget.uid, disk);
          _bytes = disk;
          return true;
        }
        return false;
      }
      if (avatar.length < 200000) {
        final b = base64Decode(avatar);
        if (b.isNotEmpty) {
          rememberAvatarBytes(widget.uid, b);
          _bytes = b;
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _resolveAsync() async {
    final avatar = widget.avatar;
    if (avatar.isEmpty) return;
    if (_resolvedFor == avatar && _bytes != null) return;
    _resolvedFor = avatar;
    final cached = cachedUserAvatarBytes(widget.uid);
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }
    final isPath = isAvatarPathValue(avatar);
    final b64 =
        isPath ? await safeAvatar(context).getByPath(avatar) : avatar;
    if (b64.isEmpty || !mounted || _resolvedFor != avatar) return;
    final bytes = await NativeImage.decodeAvatar(b64, maxPx: 256);
    if (bytes == null || !mounted || _resolvedFor != avatar) return;
    rememberAvatarBytes(widget.uid, bytes);
    setState(() => _bytes = bytes);
  }

  /// Fallback: ring warna gender + foto lazy-load by uid (GenderAvatar →
  /// ProfileAvatar ambil dari AvatarB64Service).
  Widget _fallback() => GenderAvatar(
        uid: widget.uid,
        name: widget.name,
        gender: widget.gender,
        size: widget.size,
      );

  @override
  Widget build(BuildContext context) {
    final avatar = widget.avatar;
    final bytes = _bytes;
    if (avatar.isEmpty || bytes == null || _resolvedFor != avatar) {
      return _fallback();
    }
    return ClipOval(
      child: Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        cacheWidth: (widget.size * 2).round(),
        gaplessPlayback: true,
      ),
    );
  }
}
