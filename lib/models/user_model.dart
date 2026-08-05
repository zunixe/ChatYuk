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
  final DateTime loginAt;
  final DateTime createdAt;
  final DateTime lastSeen;

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
    required this.loginAt,
    required this.createdAt,
    required this.lastSeen,
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
      loginAt: parseDate(map['loginAt']),
      createdAt: parseDate(map['createdAt']),
      lastSeen: parseDate(map['lastSeen']),
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
      'loginAt': loginAt.toUtc().toIso8601String(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'lastSeen': lastSeen.toUtc().toIso8601String(),
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
      loginAt: loginAt,
      createdAt: createdAt,
      lastSeen: lastSeen,
    );
  }

  String get initial => nickname.isNotEmpty ? nickname[0].toUpperCase() : '?';
}
