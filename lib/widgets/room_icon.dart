import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../core/cache/photo_cache.dart';
import '../providers/storage_provider.dart';

/// Ikon room: prioritas (1) foto upload-an (`room-icons/...` di rooms.icon),
/// (2) glyph Material per kategori, (3) emoji custom sebagai fallback.
/// rooms.icon berisi emoji ATAU path storage — bedakan via prefix path.
class RoomIcon extends StatelessWidget {
  final String category;
  final String emoji;
  final double size;
  final String roomId;
  const RoomIcon({
    super.key,
    required this.category,
    required this.emoji,
    this.size = 44,
    this.roomId = '',
  });

  /// Path storage ikon upload-an (bukan emoji). rooms.icon emoji tidak
  /// pernah mengandung '/'.
  static bool isUploadedIcon(String icon) =>
      icon.startsWith('room-icons/');

  static const _map = <String, _RoomGlyph>{
    'general': _RoomGlyph(Icons.chat_bubble_rounded, AppTheme.primary),
    'curhat': _RoomGlyph(Icons.forum_rounded, Colors.purple),
    'pertemanan': _RoomGlyph(Icons.group_rounded, AppTheme.accent),
    'teknologi': _RoomGlyph(Icons.computer_rounded, Colors.indigo),
    'gaming': _RoomGlyph(Icons.sports_esports_rounded, Colors.deepPurple),
    'musik': _RoomGlyph(Icons.music_note_rounded, Colors.pink),
    'film': _RoomGlyph(Icons.movie_rounded, Colors.deepOrange),
    'joke': _RoomGlyph(Icons.emoji_emotions_rounded, Colors.amber),
    'belajar': _RoomGlyph(Icons.school_rounded, AppTheme.primaryDark),
    'flirt': _RoomGlyph(Icons.favorite_rounded, AppTheme.female),
  };

  @override
  Widget build(BuildContext context) {
    // Foto upload-an menang atas glyph kategori maupun emoji.
    if (isUploadedIcon(emoji)) {
      return _UploadedIcon(path: emoji, roomId: roomId, size: size);
    }
    final g = _map[category];
    if (g == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: AppGlyph.md)),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: g.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(g.icon, color: g.color, size: 24),
    );
  }
}

/// Foto ikon room dari Storage + cache thumb disk (pola MessageImage).
/// Gagal dimuat → glyph kategori (tidak pernah blank).
class _UploadedIcon extends StatefulWidget {
  final String path;
  final String roomId;
  final double size;
  const _UploadedIcon({
    required this.path,
    required this.roomId,
    required this.size,
  });

  @override
  State<_UploadedIcon> createState() => _UploadedIconState();
}

class _UploadedIconState extends State<_UploadedIcon> {
  late final Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<String?> _fetch() async {
    final key = widget.roomId.isNotEmpty ? widget.roomId : widget.path;
    try {
      final cached =
          await PhotoCache.instance.loadThumb('roomicon', key);
      if (cached != null && cached.isNotEmpty) return cached;
    } catch (_) {}
    try {
      final data =
          await context.read<StorageProvider>().download(widget.path);
      if (data == null || data.isEmpty) return null;
      await PhotoCache.instance.save('roomicon', key, data);
      return await PhotoCache.instance.loadThumb('roomicon', key) ?? data;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        final b64 = snap.data;
        if (b64 == null || b64.isEmpty) {
          // Loading/gagal → placeholder netral (bukan blank).
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(
                Icons.image_rounded,
                color: AppTheme.primary,
                size: 24,
              ),
            ),
          );
        }
        try {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              base64Decode(b64),
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        } catch (_) {
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }
      },
    );
  }
}

class _RoomGlyph {
  final IconData icon;
  final Color color;
  const _RoomGlyph(this.icon, this.color);
}
