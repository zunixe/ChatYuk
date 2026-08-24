/// Call 1:1 yang sedang aktif — hasil RPC admin_active_calls().
class ActiveCallInfo {
  final String id;
  final String chatId;
  final String callerId;
  final String calleeId;
  final String callerName;
  final String calleeName;
  final String callType; // 'audio' | 'video'
  final String status; // 'ringing' | 'answered'
  final DateTime createdAt;
  final DateTime? answeredAt;

  const ActiveCallInfo({
    required this.id,
    required this.chatId,
    required this.callerId,
    required this.calleeId,
    required this.callerName,
    required this.calleeName,
    required this.callType,
    required this.status,
    required this.createdAt,
    this.answeredAt,
  });

  factory ActiveCallInfo.fromJson(Map<String, dynamic> j) {
    return ActiveCallInfo(
      id: '${j['id'] ?? ''}',
      chatId: '${j['chat_id'] ?? ''}',
      callerId: '${j['caller_id'] ?? ''}',
      calleeId: '${j['callee_id'] ?? ''}',
      callerName: '${j['caller_name'] ?? 'Unknown'}',
      calleeName: '${j['callee_name'] ?? 'Unknown'}',
      callType: '${j['call_type'] ?? 'video'}',
      status: '${j['status'] ?? 'ringing'}',
      createdAt:
          DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal() ??
          DateTime.now(),
      answeredAt: DateTime.tryParse('${j['answered_at'] ?? ''}')?.toLocal(),
    );
  }

  /// Durasi berjalan (detik) sejak call dijawab / dibuat.
  int get elapsedSeconds {
    final base = answeredAt ?? createdAt;
    final diff = DateTime.now().difference(base).inSeconds;
    return diff < 0 ? 0 : diff;
  }
}
