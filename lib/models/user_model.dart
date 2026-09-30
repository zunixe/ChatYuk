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
  /// true bila user sudah pernah memilih username (atau user lama hasil
  /// backfill). false → app wajib minta isi username dulu sebelum masuk main.
  /// Default true supaya profil lama/cache lama tidak tiba-tiba ter-gate.
  final bool nicknameSet;
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
  final String email;
  final String about;
  /// Tanggal lahir asli (Pengaturan › Akun). null = belum diisi.
  final DateTime? birthDate;
  /// Nomor HP (Pengaturan › Akun). '' = belum diisi.
  final String phone;

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
    this.nicknameSet = true,
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
    this.email = '',
    this.about = '',
    this.birthDate,
    this.phone = '',
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
      // Default true bila kolom belum ada (DB lama / cache lama) supaya
      // user yang sudah pakai tidak tiba-tiba diminta isi username.
      nicknameSet: map['nicknameSet'] != false,
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
      email: map['email'] ?? '',
      about: map['about'] ?? '',
      birthDate: _parseBirthDate(map['birthDate'] ?? map['birth_date']),
      phone: map['phone'] ?? '',
    );
  }

  /// Tanggal lahir dari server bisa String `YYYY-MM-DD` (kolom `date`) atau
  /// ISO penuh. Toleran terhadap keduanya; null bila kosong/tdk valid.
  static DateTime? _parseBirthDate(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    if (s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    // Normalisasi ke tanggal (buang jam) — kolom `date`.
    return DateTime(d.year, d.month, d.day);
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
      'nicknameSet': nicknameSet,
      'loginAt': loginAt.toUtc().toIso8601String(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'lastSeen': lastSeen.toUtc().toIso8601String(),
      'hashtags': hashtags,
      'points': points,
      'email': email,
      'about': about,
      'birthDate': birthDate?.toIso8601String(),
      'phone': phone,
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
    bool? nicknameSet,
    DateTime? lastSeen,
    List<String>? hashtags,
    int? points,
    bool? shareLocation,
    int? followersCount,
    int? followingCount,
    int? subscriberCount,
    int? subscriptionPrice,
    int? friendsCount,
    String? email,
    String? about,
    DateTime? birthDate,
    String? phone,
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
      nicknameSet: nicknameSet ?? this.nicknameSet,
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
      email: email ?? this.email,
      about: about ?? this.about,
      birthDate: birthDate ?? this.birthDate,
      phone: phone ?? this.phone,
    );
  }

  String get initial => nickname.isNotEmpty ? nickname[0].toUpperCase() : '?';
}
