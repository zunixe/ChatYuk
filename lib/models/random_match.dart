/// Model fitur Random Video Call (Match Nearby).
///
/// Dipisah dari layar supaya provider & widget test bisa memakainya tanpa
/// menyentuh I/O (patuh boundary AGENTS.md).
library;

/// Lawan yang sedang tersambung.
class RandomPartner {
  final String uid;
  final String nickname;
  final String gender;
  final int? age;
  final String city;
  final String avatar;
  final double? distanceKm;

  const RandomPartner({
    required this.uid,
    required this.nickname,
    this.gender = 'other',
    this.age,
    this.city = '',
    this.avatar = '',
    this.distanceKm,
  });

  static RandomPartner? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final uid = '${raw['uid'] ?? ''}';
    if (uid.isEmpty) return null;
    final dist = raw['distance_km'];
    return RandomPartner(
      uid: uid,
      nickname: '${raw['nickname'] ?? 'User'}',
      gender: '${raw['gender'] ?? 'other'}',
      age: raw['age'] is num ? (raw['age'] as num).toInt() : null,
      city: '${raw['city'] ?? ''}',
      avatar: '${raw['avatar'] ?? ''}',
      distanceKm: dist is num ? dist.toDouble() : null,
    );
  }
}

/// Satu baris riwayat random call.
class RandomCallEntry {
  final String callId;
  final String partnerId;
  final String partnerName;
  final String partnerAvatar;
  final String partnerGender;
  final int? partnerAge;
  final String partnerCity;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSec;
  final bool online;
  final String status;

  const RandomCallEntry({
    required this.callId,
    required this.partnerId,
    required this.partnerName,
    this.partnerAvatar = '',
    this.partnerGender = 'other',
    this.partnerAge,
    this.partnerCity = '',
    required this.startedAt,
    this.endedAt,
    this.durationSec = 0,
    this.online = false,
    this.status = 'ended',
  });

  bool get isMissed => status == 'missed' || durationSec == 0;

  static RandomCallEntry? tryParse(Map<String, dynamic> r) {
    final id = '${r['call_id'] ?? ''}';
    if (id.isEmpty) return null;
    DateTime? parse(Object? v) {
      if (v == null) return null;
      return DateTime.tryParse('$v')?.toLocal();
    }

    return RandomCallEntry(
      callId: id,
      partnerId: '${r['partner_id'] ?? ''}',
      partnerName: '${r['partner_name'] ?? 'User'}',
      partnerAvatar: '${r['partner_avatar'] ?? ''}',
      partnerGender: '${r['partner_gender'] ?? 'other'}',
      partnerAge: r['partner_age'] is num
          ? (r['partner_age'] as num).toInt()
          : null,
      partnerCity: '${r['partner_city'] ?? ''}',
      startedAt: parse(r['started_at']) ?? DateTime.now(),
      endedAt: parse(r['ended_at']),
      durationSec: r['duration_sec'] is num
          ? (r['duration_sec'] as num).toInt()
          : 0,
      online: r['online'] == true,
      status: '${r['status'] ?? 'ended'}',
    );
  }
}

/// Avatar yang melayang di radar (user online di sekitar).
class RandomRadarUser {
  final String uid;
  final String nickname;
  final String gender;
  final String avatar;
  final String city;
  final double? distanceKm;

  const RandomRadarUser({
    required this.uid,
    required this.nickname,
    this.gender = 'other',
    this.avatar = '',
    this.city = '',
    this.distanceKm,
  });

  /// Label jarak: "12.4km" bila ada, selain itu kota (privasi lokasi).
  String get distanceLabel {
    final d = distanceKm;
    if (d == null) return city;
    if (d < 1) return '<1km';
    return '${d.toStringAsFixed(1)}km';
  }

  static RandomRadarUser? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final uid = '${raw['uid'] ?? ''}';
    if (uid.isEmpty) return null;
    final dist = raw['distance_km'];
    return RandomRadarUser(
      uid: uid,
      nickname: '${raw['nickname'] ?? 'User'}',
      gender: '${raw['gender'] ?? 'other'}',
      avatar: '${raw['avatar'] ?? ''}',
      city: '${raw['city'] ?? ''}',
      distanceKm: dist is num ? dist.toDouble() : null,
    );
  }
}
