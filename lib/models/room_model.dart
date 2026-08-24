class RoomModel {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String country;
  final String category;
  final int order;
  final int onlineCount;
  final bool isPrivate;
  final String ownerId;
  final String ownerName;
  final bool hasPassword;
  final DateTime? expiresAt;

  RoomModel({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.country,
    required this.category,
    required this.order,
    this.onlineCount = 0,
    this.isPrivate = false,
    this.ownerId = '',
    this.ownerName = '',
    this.hasPassword = false,
    this.expiresAt,
  });

  factory RoomModel.fromMap(String id, Map<String, dynamic> map) {
    return RoomModel(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      icon: map['icon'] ?? '💬',
      country: map['country'] ?? '',
      category: map['category'] ?? '',
      order: map['order'] ?? 0,
      onlineCount: map['onlineCount'] ?? 0,
      isPrivate: map['is_private'] == true,
      ownerId: map['owner_id'] ?? '',
      ownerName: map['owner_name'] ?? '',
      hasPassword: map['has_password'] == true,
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse('${map['expires_at']}')
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'icon': icon,
      'country': country,
      'category': category,
      'order': order,
      'onlineCount': onlineCount,
    };
  }

  RoomModel copyWith({int? onlineCount}) {
    return RoomModel(
      id: id,
      name: name,
      description: description,
      icon: icon,
      country: country,
      category: category,
      order: order,
      onlineCount: onlineCount ?? this.onlineCount,
      isPrivate: isPrivate,
      ownerId: ownerId,
      ownerName: ownerName,
      hasPassword: hasPassword,
      expiresAt: expiresAt,
    );
  }
}
