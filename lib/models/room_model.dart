class RoomModel {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int order;
  final int onlineCount;

  RoomModel({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.order,
    this.onlineCount = 0,
  });

  factory RoomModel.fromMap(String id, Map<String, dynamic> map) {
    return RoomModel(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      icon: map['icon'] ?? '💬',
      order: map['order'] ?? 0,
      onlineCount: map['onlineCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'icon': icon,
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
      order: order,
      onlineCount: onlineCount ?? this.onlineCount,
    );
  }
}
