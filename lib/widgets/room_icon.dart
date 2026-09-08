import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Ikon room gaya pengaturan: Material icon di container tinted,
/// bukan emoji. Mapping per kategori; room buatan user (emoji custom)
/// tetap tampil emoji sebagai fallback.
class RoomIcon extends StatelessWidget {
  final String category;
  final String emoji;
  final double size;
  const RoomIcon({
    super.key,
    required this.category,
    required this.emoji,
    this.size = 44,
  });

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

class _RoomGlyph {
  final IconData icon;
  final Color color;
  const _RoomGlyph(this.icon, this.color);
}
