import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Uint8List? _decodeBase64(String b64) {
  try { return base64Decode(b64); } catch (_) { return null; }
}

/// Foto thumbnail grid — decode di isolate, tampil placeholder dulu.
class AsyncPhotoThumbnail extends StatefulWidget {
  final String base64;
  final double? width;
  final double? height;
  final BoxFit fit;
  const AsyncPhotoThumbnail({super.key, required this.base64, this.width, this.height, this.fit = BoxFit.cover});

  @override
  State<AsyncPhotoThumbnail> createState() => _AsyncPhotoThumbnailState();
}

class _AsyncPhotoThumbnailState extends State<AsyncPhotoThumbnail> {
  Uint8List? _bytes;
  static final _cache = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.base64];
    if (cached != null) { _bytes = cached; return; }
    _decode();
  }

  Future<void> _decode() async {
    final bytes = await compute(_decodeBase64, widget.base64);
    if (!mounted) return;
    if (bytes != null && _cache.length < 100) _cache[widget.base64] = bytes;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(width: widget.width, height: widget.height, color: const Color(0xFF1E1E2E));
    }
    return Image.memory(_bytes!, width: widget.width, height: widget.height, fit: widget.fit, gaplessPlayback: true);
  }
}

/// Foto full-screen viewer — decode async.
class AsyncPhotoViewer extends StatefulWidget {
  final String base64;
  const AsyncPhotoViewer({super.key, required this.base64});

  @override
  State<AsyncPhotoViewer> createState() => _AsyncPhotoViewerState();
}

class _AsyncPhotoViewerState extends State<AsyncPhotoViewer> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final bytes = await compute(_decodeBase64, widget.base64);
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Image.memory(_bytes!, fit: BoxFit.contain);
  }
}

/// CircleAvatar async — decode dari base64 dengan cache sederhana.
class AsyncCircleAvatar extends StatefulWidget {
  final String base64;
  final double radius;
  final Color? bgColor;
  final Widget? fallback;
  const AsyncCircleAvatar({super.key, required this.base64, this.radius = 40, this.bgColor, this.fallback});

  @override
  State<AsyncCircleAvatar> createState() => _AsyncCircleAvatarState();
}

class _AsyncCircleAvatarState extends State<AsyncCircleAvatar> {
  Uint8List? _bytes;
  static final _cache = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.base64];
    if (cached != null) { _bytes = cached; return; }
    _decode();
  }

  Future<void> _decode() async {
    final bytes = await compute(_decodeBase64, widget.base64);
    if (!mounted) return;
    if (bytes != null && _cache.length < 50) _cache[widget.base64] = bytes;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) return widget.fallback ?? const SizedBox.shrink();
    return CircleAvatar(radius: widget.radius, backgroundColor: widget.bgColor, backgroundImage: MemoryImage(_bytes!));
  }
}
