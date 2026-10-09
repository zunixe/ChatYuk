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
  final int likeCount;
  final bool liked;
  final DateTime createdAt;
  // Video pendek: 'image' | 'video'. Video polos (tanpa teks overlay).
  final String mediaType;
  final String videoPath;
  final int durationMs;
  /// true = slide PRIVATE (dulu "dihapus") — hanya author (atau admin) lihat.
  final bool ownerOnly;

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
    this.likeCount = 0,
    this.liked = false,
    required this.createdAt,
    this.mediaType = 'image',
    this.videoPath = '',
    this.durationMs = 0,
    this.ownerOnly = false,
  });

  bool get isVideo => mediaType == 'video' && videoPath.isNotEmpty;

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
      likeCount: _toInt(m['like_count'], 0),
      liked: m['liked'] == true,
      createdAt: parseDate(m['created_at']),
      mediaType: '${m['media_type'] ?? 'image'}',
      videoPath: '${m['video_path'] ?? ''}',
      durationMs: _toInt(m['duration_ms'], 0),
      ownerOnly: m['owner_only'] == true,
    );
  }

  /// Salinan dengan status like diubah (optimistic di viewer/provider).
  StorySlide copyWith({int? likeCount, bool? liked, bool? ownerOnly}) {
    return StorySlide(
      id: id,
      authorId: authorId,
      authorName: authorName,
      imagePath: imagePath,
      mediaType: mediaType,
      videoPath: videoPath,
      durationMs: durationMs,
      textOverlay: textOverlay,
      textX: textX,
      textY: textY,
      textColorIndex: textColorIndex,
      textSizeIndex: textSizeIndex,
      textScale: textScale,
      textRotation: textRotation,
      textBg: textBg,
      visibility: visibility,
      likeCount: likeCount ?? this.likeCount,
      liked: liked ?? this.liked,
      createdAt: createdAt,
      ownerOnly: ownerOnly ?? this.ownerOnly,
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
  // Dibisukan (mute ala IG): tile transparan + paling belakang.
  final bool muted;
  // Ada slide video (badge di tile).
  final bool hasVideo;
  // Ada slide private (owner_only) di tray author ini — penanda admin.
  final bool hasOwnerOnly;
  // Batas kedaluwarsa slide terakhir (max expires_at per author). Dipakai
  // untuk membuang item cache yang sudah lewat agar tray tidak NGEBLINK saat
  // cold start (tampil sekejap dari cache lalu hilang setelah server refresh).
  final DateTime? expiresAt;

  const StoryTrayItem({
    required this.authorId,
    required this.authorName,
    this.avatar = '',
    this.isRegistered = false,
    this.slideCount = 0,
    this.thumbPath = '',
    this.hasUnseen = false,
    this.own = false,
    this.muted = false,
    this.hasVideo = false,
    this.hasOwnerOnly = false,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

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
      muted: m['muted'] == true,
      hasVideo: m['has_video'] == true,
      hasOwnerOnly: m['has_owner_only'] == true,
      expiresAt: DateTime.tryParse('${m['expires_at'] ?? ''}')?.toLocal(),
    );
  }

  StoryTrayItem copyWith({bool? hasUnseen, bool? muted, bool? hasVideo}) {
    return StoryTrayItem(
      authorId: authorId,
      authorName: authorName,
      avatar: avatar,
      isRegistered: isRegistered,
      slideCount: slideCount,
      thumbPath: thumbPath,
      hasUnseen: hasUnseen ?? this.hasUnseen,
      own: own,
      muted: muted ?? this.muted,
      hasVideo: hasVideo ?? this.hasVideo,
      hasOwnerOnly: hasOwnerOnly,
      expiresAt: expiresAt,
    );
  }

  /// Serialisasi untuk cache disk (offline tetap tampil) — kunci SAMA dengan
  /// `fromMap` server supaya bisa dibaca bolak-balik tanpa konversi.
  Map<String, dynamic> toMap() => {
        'author_id': authorId,
        'author_name': authorName,
        'avatar': avatar,
        'is_registered': isRegistered,
        'slide_count': slideCount,
        'thumb_path': thumbPath,
        'has_unseen': hasUnseen,
        'own': own,
        'muted': muted,
        'has_video': hasVideo,
        'has_owner_only': hasOwnerOnly,
        'expires_at': expiresAt?.toUtc().toIso8601String(),
      };
}

/// Baris daftar penonton satu slide.
class StoryViewer {
  final String viewerId;
  final String nickname;
  final String avatar;
  final DateTime viewedAt;
  final bool liked;

  const StoryViewer({
    required this.viewerId,
    required this.nickname,
    this.avatar = '',
    required this.viewedAt,
    this.liked = false,
  });

  factory StoryViewer.fromMap(Map<String, dynamic> m) {
    return StoryViewer(
      viewerId: '${m['viewer_id'] ?? ''}',
      nickname: '${m['nickname'] ?? '?'}',
      avatar: '${m['avatar'] ?? ''}',
      viewedAt: parseDate(m['viewed_at']),
      liked: m['liked'] == true,
    );
  }
}
