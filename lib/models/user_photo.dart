class UserPhoto {
  final String id;
  final String userId;
  final String photo;
  final DateTime createdAt;

  const UserPhoto({
    required this.id,
    required this.userId,
    required this.photo,
    required this.createdAt,
  });

  factory UserPhoto.fromMap(String id, Map<String, dynamic> map) {
    return UserPhoto(
      id: id,
      userId: map['userId'] ?? '',
      photo: map['photo'] ?? '',
      createdAt: map['createdAt'] is DateTime
          ? map['createdAt'] as DateTime
          : DateTime.parse('${map['createdAt']}'),
    );
  }
}