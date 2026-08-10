import '../utils.dart';

class UserModel {
  final String uid;
  final String nickname;
  final String gender;
  final int age;
  final String country;
  final String city;
  final String ipAddress;
  final String status;
  final String avatar;
  final bool isRegistered;
  final DateTime loginAt;
  final DateTime createdAt;
  final DateTime lastSeen;
  final List<String> hashtags;
  final int points;

  UserModel({
    required this.uid,
    required this.nickname,
    required this.gender,
    required this.age,
    required this.country,
    required this.city,
    required this.ipAddress,
    required this.status,
    required this.avatar,
    required this.isRegistered,
    required this.loginAt,
    required this.createdAt,
    required this.lastSeen,
    this.hashtags = const [],
    this.points = 50,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      nickname: map['nickname'] ?? 'Anon',
      gender: map['gender'] ?? 'male',
      age: map['age'] ?? 0,
      country: map['country'] ?? 'Indonesia',
      city: map['city'] ?? 'Jakarta',
      ipAddress: map['ipAddress'] ?? '',
      status: map['status'] ?? (map['online'] == true ? 'online' : 'offline'),
      avatar: map['avatar'] ?? '',
      isRegistered: map['isRegistered'] == true,
      loginAt: parseDate(map['loginAt']),
      createdAt: parseDate(map['createdAt']),
      lastSeen: parseDate(map['lastSeen']),
      hashtags: map['hashtags'] is List ? (map['hashtags'] as List).cast<String>() : const [],
      points: map['points'] ?? 50,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nickname': nickname,
      'gender': gender,
      'age': age,
      'country': country,
      'city': city,
      'ipAddress': ipAddress,
      'status': status,
      'avatar': avatar,
      'isRegistered': isRegistered,
      'loginAt': loginAt.toUtc().toIso8601String(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'lastSeen': lastSeen.toUtc().toIso8601String(),
      'hashtags': hashtags,
      'points': points,
    };
  }

  UserModel copyWith({
    String? nickname,
    String? gender,
    int? age,
    String? country,
    String? city,
    String? ipAddress,
    String? status,
    String? avatar,
    bool? isRegistered,
    DateTime? lastSeen,
    List<String>? hashtags,
    int? points,
  }) {
    return UserModel(
      uid: uid,
      nickname: nickname ?? this.nickname,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      country: country ?? this.country,
      city: city ?? this.city,
      ipAddress: ipAddress ?? this.ipAddress,
      status: status ?? this.status,
      avatar: avatar ?? this.avatar,
      isRegistered: isRegistered ?? this.isRegistered,
      loginAt: loginAt,
      createdAt: createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      hashtags: hashtags ?? this.hashtags,
      points: points ?? this.points,
    );
  }

  String get initial => nickname.isNotEmpty ? nickname[0].toUpperCase() : '?';
}
