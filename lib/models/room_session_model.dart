/// Sesi terjadwal di room (Room v2 — `room_sessions`).
/// Dibaca lewat RPC `next_room_sessions` (join host + flag reminder).
class RoomSessionInfo {
  final int sessionId;
  final String roomId;
  final String title;
  final String format;
  final DateTime startsAt;
  final DateTime endsAt;

  /// 'live' | 'scheduled' (ended/cancelled tidak dikirim ke client).
  final String status;
  final String hostUid;
  final String hostName;
  final String hostAvatar;
  final int peakViewers;
  final int giftsTotal;
  final bool reminded;

  const RoomSessionInfo({
    required this.sessionId,
    required this.roomId,
    required this.title,
    required this.format,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.hostUid,
    required this.hostName,
    required this.hostAvatar,
    this.peakViewers = 0,
    this.giftsTotal = 0,
    this.reminded = false,
  });

  bool get isLive => status == 'live';

  factory RoomSessionInfo.fromJson(Map<String, dynamic> j) {
    return RoomSessionInfo(
      sessionId: (j['session_id'] as num).toInt(),
      roomId: (j['room_id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      format: (j['format'] ?? 'bebas').toString(),
      startsAt: DateTime.tryParse('${j['starts_at']}')?.toLocal() ??
          DateTime.now(),
      endsAt:
          DateTime.tryParse('${j['ends_at']}')?.toLocal() ?? DateTime.now(),
      status: (j['status'] ?? 'scheduled').toString(),
      hostUid: (j['host_uid'] ?? '').toString(),
      hostName: (j['host_name'] ?? 'Host').toString(),
      hostAvatar: (j['host_avatar'] ?? '').toString(),
      peakViewers: (j['peak_viewers'] as num?)?.toInt() ?? 0,
      giftsTotal: (j['gifts_total'] as num?)?.toInt() ?? 0,
      reminded: j['reminded'] == true,
    );
  }

  RoomSessionInfo copyWith({bool? reminded, String? status, int? peakViewers}) {
    return RoomSessionInfo(
      sessionId: sessionId,
      roomId: roomId,
      title: title,
      format: format,
      startsAt: startsAt,
      endsAt: endsAt,
      status: status ?? this.status,
      hostUid: hostUid,
      hostName: hostName,
      hostAvatar: hostAvatar,
      peakViewers: peakViewers ?? this.peakViewers,
      giftsTotal: giftsTotal,
      reminded: reminded ?? this.reminded,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoomSessionInfo &&
      other.sessionId == sessionId &&
      other.status == status &&
      other.reminded == reminded &&
      other.peakViewers == peakViewers &&
      other.title == title;

  @override
  int get hashCode =>
      Object.hash(sessionId, status, reminded, peakViewers, title);
}
