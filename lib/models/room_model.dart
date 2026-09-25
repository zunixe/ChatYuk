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
  // Explore (dari list_room_explore; default 0 agar list lama tetap jalan).
  final int memberCount;
  final String lastSenderName;
  final String lastText;
  final String lastType;
  final DateTime? lastAt;
  final int unread;
  final bool isLive;

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
    this.memberCount = 0,
    this.lastSenderName = '',
    this.lastText = '',
    this.lastType = 'text',
    this.lastAt,
    this.unread = 0,
    this.isLive = false,
  });

  factory RoomModel.fromMap(String id, Map<String, dynamic> map) {
    return RoomModel(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      icon: map['icon'] ?? '💬',
      country: map['country'] ?? '',
      category: map['category'] ?? '',
      order: map['order'] is int
          ? map['order']
          : int.tryParse('${map['order'] ?? 0}') ?? 0,
      onlineCount: map['onlineCount'] is int
          ? map['onlineCount']
          : int.tryParse('${map['onlineCount'] ?? map['online_count'] ?? 0}') ??
                0,
      isPrivate: map['is_private'] == true,
      ownerId: map['owner_id'] ?? '',
      ownerName: map['owner_name'] ?? '',
      hasPassword: map['has_password'] == true,
      expiresAt: map['expires_at'] != null
          ? DateTime.tryParse('${map['expires_at']}')
          : null,
      memberCount: map['memberCount'] is int
          ? map['memberCount']
          : int.tryParse('${map['memberCount'] ?? map['member_count'] ?? 0}') ??
                0,
      lastSenderName:
          '${map['lastSenderName'] ?? map['last_sender_name'] ?? ''}',
      lastText: '${map['lastText'] ?? map['last_text'] ?? ''}',
      lastType: '${map['lastType'] ?? map['last_type'] ?? 'text'}',
      lastAt: map['lastAt'] != null
          ? DateTime.tryParse('${map['lastAt']}')
          : (map['last_at'] != null
                ? DateTime.tryParse('${map['last_at']}')
                : null),
      unread: map['unread'] is int
          ? map['unread']
          : int.tryParse('${map['unread'] ?? 0}') ?? 0,
      isLive: map['isLive'] == true || map['is_live'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'country': country,
      'category': category,
      'order': order,
      'onlineCount': onlineCount,
      'is_private': isPrivate,
      'owner_id': ownerId,
      'owner_name': ownerName,
      'has_password': hasPassword,
      'expires_at': expiresAt?.toIso8601String(),
      'memberCount': memberCount,
      'lastSenderName': lastSenderName,
      'lastText': lastText,
      'lastType': lastType,
      'lastAt': lastAt?.toIso8601String(),
      'unread': unread,
      'isLive': isLive,
    };
  }

  RoomModel copyWith({
    int? onlineCount,
    int? memberCount,
    String? lastSenderName,
    String? lastText,
    String? lastType,
    DateTime? lastAt,
    int? unread,
    bool? isLive,
  }) {
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
      memberCount: memberCount ?? this.memberCount,
      lastSenderName: lastSenderName ?? this.lastSenderName,
      lastText: lastText ?? this.lastText,
      lastType: lastType ?? this.lastType,
      lastAt: lastAt ?? this.lastAt,
      unread: unread ?? this.unread,
      isLive: isLive ?? this.isLive,
    );
  }
}
