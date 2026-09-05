import '../utils.dart';

/// Satu slide story (1 row tabel `stories`). Urutan tampil: created_at asc.
class StorySlide {
  final String id;
  final String authorId;
  final String authorName;
  final String imagePath;
  final String textOverlay;
  final double textX;
  final double textY;
  final int textColorIndex;
  final int textSizeIndex;
  final double textScale;
  final double textRotation;
  final bool textBg;
  final String visibility;
  final DateTime createdAt;

  const StorySlide({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.imagePath,
    this.textOverlay = '',
    this.textX = 0.5,
    this.textY = 0.85,
    this.textColorIndex = 0,
    this.textSizeIndex = 1,
    this.textScale = 1.0,
    this.textRotation = 0,
    this.textBg = false,
    this.visibility = 'registered',
    required this.createdAt,
  });

  factory StorySlide.fromMap(String id, Map<String, dynamic> m) {
    return StorySlide(
      id: id,
      authorId: '${m['author_id'] ?? ''}',
      authorName: '${m['author_name'] ?? 'Anon'}',
      imagePath: '${m['image_path'] ?? ''}',
      textOverlay: '${m['text_overlay'] ?? ''}',
      textX: _toDouble(m['text_x'], 0.5),
      textY: _toDouble(m['text_y'], 0.85),
      textColorIndex: _toInt(m['text_color'], 0),
      textSizeIndex: _toInt(m['text_size'], 1),
      textScale: _toScale(m['text_scale']),
      textRotation: _toRotation(m['text_rotation']),
      textBg: m['text_bg'] == true,
      visibility: '${m['visibility'] ?? 'registered'}',
      createdAt: parseDate(m['created_at']),
    );
  }

  static double _toDouble(dynamic v, double d) {
    final n = v is num ? v : double.tryParse('$v');
    if (n == null) return d;
    return n.clamp(0.0, 1.0).toDouble();
  }

  static int _toInt(dynamic v, int d) {
    final n = v is num ? v.toInt() : int.tryParse('$v');
    return n ?? d;
  }

  /// Skala pinch (0.5-3.0). Bukan _toDouble (itu clamp 0-1 untuk posisi).
  static double _toScale(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v');
    if (n == null) return 1.0;
    return n.clamp(0.5, 3.0).toDouble();
  }

  /// Rotasi radian (bebas, dinormalisasi -pi..pi).
  static double _toRotation(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v');
    if (n == null) return 0;
    double r = n;
    while (r > 3.14159265) r -= 6.28318530;
    while (r < -3.14159265) r += 6.28318530;
    return r;
  }
}

/// Item tray story di halaman pengguna online: agregat semua slide aktif
/// milik satu author + metadata untuk render kotak + ring.
class StoryTrayItem {
  final String authorId;
  final String authorName;
  final String avatar; // path storage atau base64
  final bool isRegistered;
  final int slideCount;
  final String thumbPath; // image_path slide terbaru
  final bool hasUnseen;
  final bool own;

  const StoryTrayItem({
    required this.authorId,
    required this.authorName,
    this.avatar = '',
    this.isRegistered = false,
    this.slideCount = 0,
    this.thumbPath = '',
    this.hasUnseen = false,
    this.own = false,
  });

  factory StoryTrayItem.fromMap(Map<String, dynamic> m) {
    return StoryTrayItem(
      authorId: '${m['author_id'] ?? ''}',
      authorName: '${m['author_name'] ?? 'Anon'}',
      avatar: '${m['avatar'] ?? ''}',
      isRegistered: m['is_registered'] == true,
      slideCount: (m['slide_count'] as num?)?.toInt() ?? 0,
      thumbPath: '${m['thumb_path'] ?? ''}',
      hasUnseen: m['has_unseen'] == true,
      own: m['own'] == true,
    );
  }
}

/// Baris daftar penonton satu slide.
class StoryViewer {
  final String viewerId;
  final String nickname;
  final String avatar;
  final DateTime viewedAt;

  const StoryViewer({
    required this.viewerId,
    required this.nickname,
    this.avatar = '',
    required this.viewedAt,
  });

  factory StoryViewer.fromMap(Map<String, dynamic> m) {
    return StoryViewer(
      viewerId: '${m['viewer_id'] ?? ''}',
      nickname: '${m['nickname'] ?? '?'}',
      avatar: '${m['avatar'] ?? ''}',
      viewedAt: parseDate(m['viewed_at']),
    );
  }
}
