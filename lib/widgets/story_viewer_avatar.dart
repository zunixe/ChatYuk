import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../providers/riverpod/avatar_provider.dart';

/// Avatar baris penonton story.
///
/// `avatar` dari RPC `story_viewers` bisa dua bentuk:
///  - base64 siap pakai → decode langsung (instan, tanpa network), ATAU
///  - path storage `avatars/...` (atau kosong) → WAJIB dimuat lewat
///    [AvatarProvider] (RPC ber-privacy `avatar_for` + download + disk cache).
///
/// BUG LAMA: hanya bentuk base64 yang ditangani; path storage disangka
/// base64 → decode gagal → jatuh ke inisial huruf, sehingga foto penonton
/// tidak pernah muncul di daftar. Widget ini menangani keduanya.
class StoryViewerAvatar extends StatefulWidget {
  final String viewerId;
  final String avatar;
  final String nickname;
  final double radius;
  const StoryViewerAvatar({
    super.key,
    required this.viewerId,
    required this.avatar,
    required this.nickname,
    this.radius = 16,
  });

  @override
  State<StoryViewerAvatar> createState() => _StoryViewerAvatarState();
}

class _StoryViewerAvatarState extends State<StoryViewerAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant StoryViewerAvatar old) {
    super.didUpdateWidget(old);
    if (old.avatar != widget.avatar || old.viewerId != widget.viewerId) {
      _resolve();
    }
  }

  void _resolve() {
    final a = widget.avatar;
    // base64 siap pakai → decode langsung (sinkron, tanpa RPC).
    if (a.isNotEmpty) {
      try {
        _bytes = base64Decode(a);
        return;
      } catch (_) {
        // bukan base64 → path storage, lanjut ke provider.
      }
    }
    _bytes = null;
    if (widget.viewerId.isEmpty) return;
    // Path/kosong → ambil via AvatarProvider (fetch + download + cache).
    final prov = ProviderScope.containerOf(context, listen: false).read(avatarProvider);
    prov
        .get(widget.viewerId)
        .then((b64) {
          if (!mounted || b64.isEmpty) return;
          try {
            setState(() => _bytes = base64Decode(b64));
          } catch (_) {}
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final cap = (widget.radius * 4).round();
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
      backgroundImage: bytes != null
          ? ResizeImage(MemoryImage(bytes), width: cap)
          : null,
      child: bytes != null
          ? null
          : Text(
              widget.nickname.isNotEmpty
                  ? widget.nickname[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: AppTheme.primary,
                fontSize: AppGlyph.avatarInitial(widget.radius * 2),
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
