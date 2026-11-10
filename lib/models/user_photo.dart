class UserPhoto {
  final String id;
  final String userId;

  /// Foto: base64 JPEG (sudah diunduh dari storage).
  /// VIDEO terbuka: PATH storage (`gallery/<uid>/<stamp>.mp4`) — video TIDAK
  /// pernah diunduh jadi base64 (ukurannya MB, bukan KB).
  final String photo;
  final DateTime createdAt;
  // Paywall: apakah foto ini terbuka untuk viewer saat ini.
  final bool unlocked;
  // Preview blur (base64) untuk foto terkunci.
  final String preview;
  // true = foto diambil lewat selfie liveness (kewajiban akun female).
  // false pada foto lama → UI menandai "perlu diganti".
  final bool faceVerified;

  /// true = item ini VIDEO (galeri profil mendukung foto + video).
  final bool isVideo;

  /// Poster jernih video (base64 JPEG) — hanya untuk video TERBUKA;
  /// dipakai sebagai thumbnail grid/hero tanpa mengunduh video penuh.
  final String poster;

  const UserPhoto({
    required this.id,
    required this.userId,
    required this.photo,
    required this.createdAt,
    this.unlocked = true,
    this.preview = '',
    this.faceVerified = false,
    this.isVideo = false,
    this.poster = '',
  });

  factory UserPhoto.fromMap(String id, Map<String, dynamic> map) {
    return UserPhoto(
      id: id,
      userId: map['userId'] ?? '',
      photo: map['photo'] ?? '',
      createdAt: map['createdAt'] is DateTime
          ? map['createdAt'] as DateTime
          : map['createdAt'] != null
          ? DateTime.parse('${map['createdAt']}')
          : DateTime.now(),
      unlocked: map['unlocked'] == null ? true : map['unlocked'] == true,
      preview: map['preview'] ?? '',
      faceVerified: map['faceVerified'] == true,
      isVideo: map['isVideo'] == true,
      poster: map['poster'] ?? '',
    );
  }
}
