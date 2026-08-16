class UserPhoto {
  final String id;
  final String userId;
  final String photo;
  final DateTime createdAt;
  // Paywall: apakah foto ini terbuka untuk viewer saat ini.
  final bool unlocked;
  // Preview blur (base64) untuk foto terkunci.
  final String preview;

  const UserPhoto({
    required this.id,
    required this.userId,
    required this.photo,
    required this.createdAt,
    this.unlocked = true,
    this.preview = '',
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
    );
  }
}
