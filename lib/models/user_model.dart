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
  final bool shareLocation;
  final int followersCount;
  final int followingCount;
  final int subscriberCount;
  final int subscriptionPrice;
  final int friendsCount;

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
    this.shareLocation = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.subscriberCount = 0,
    this.subscriptionPrice = 0,
    this.friendsCount = 0,
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
      hashtags: map['hashtags'] is List
          ? (map['hashtags'] as List).cast<String>()
          : const [],
      points: map['points'] ?? 50,
      shareLocation: map['shareLocation'] == true,
      followersCount: (map['followersCount'] as num?)?.toInt() ?? 0,
      followingCount: (map['followingCount'] as num?)?.toInt() ?? 0,
      subscriberCount: (map['subscriberCount'] as num?)?.toInt() ?? 0,
      subscriptionPrice: (map['subscriptionPrice'] as num?)?.toInt() ?? 0,
      friendsCount: (map['friendsCount'] as num?)?.toInt() ?? 0,
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
    bool? shareLocation,
    int? followersCount,
    int? followingCount,
    int? subscriberCount,
    int? subscriptionPrice,
    int? friendsCount,
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
      shareLocation: shareLocation ?? this.shareLocation,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      subscriptionPrice: subscriptionPrice ?? this.subscriptionPrice,
      friendsCount: friendsCount ?? this.friendsCount,
    );
  }

  String get initial => nickname.isNotEmpty ? nickname[0].toUpperCase() : '?';
}
