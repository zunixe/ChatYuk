import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/avatar_service.dart';

Uint8List? _decodeAvatarB64(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

/// Avatar profil user lain: foto (base64, decode async + cache) dengan
/// fallback inisial. Lingkaran jika [borderRadius] = 0, atau kotak rounded.
class ProfileAvatar extends StatefulWidget {
  final String uid;
  final String name;
  final double size;
  final double borderRadius;
  final Color bgColor;
  final Color? textColor;
  final Widget? badge;

  const ProfileAvatar({
    super.key,
    required this.uid,
    required this.name,
    this.size = 44,
    this.borderRadius = 0,
    this.bgColor = AppTheme.accent,
    this.textColor,
    this.badge,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Uint8List? _bytes;
  static final _bytesCache = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b64 = await AvatarB64Service.instance.get(widget.uid);
    if (!mounted || b64.isEmpty) return;
    final cached = _bytesCache[b64];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    final bytes = await compute(_decodeAvatarB64, b64);
    if (!mounted || bytes == null) return;
    if (_bytesCache.length < 60) _bytesCache[b64] = bytes;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(widget.borderRadius);
    Widget child;
    if (_bytes != null) {
      child = ClipRRect(
        borderRadius: shape,
        child: Image.memory(
          _bytes!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } else {
      child = Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.bgColor,
          borderRadius: shape,
        ),
        child: Center(
          child: Text(
            widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
            style: TextStyle(
              color: widget.textColor ?? AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: AppGlyph.avatarInitial(widget.size),
            ),
          ),
        ),
      );
    }
    if (widget.badge == null) return child;
    return Stack(
      children: [
        child,
        if (widget.badge != null)
          Positioned(right: -2, bottom: -2, child: widget.badge!),
      ],
    );
  }
}
