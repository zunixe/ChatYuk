/// Model ringkas satu baris daftar **Pesan(private)** yang dipakai bersama
/// oleh lapisan cache/merge (`lib/core/chat/`) dan service.
///
/// Kenapa di `core/`: `chat_list_merge.dart` (core, helper murni) butuh tipe
/// ini untuk menyusun daftar tersemat. Dulu tipe ini tinggal di
/// `services/chat_service.dart` sehingga core mengimpor services — melanggar
/// aturan boundary (`scripts/check_screen_boundary.sh`): core hanya boleh
/// berisi helper murni tanpa dependensi services/providers.
///
/// `chat_service.dart` me-re-export tipe ini (`export`), jadi seluruh import
/// lama tetap jalan tanpa perubahan.
library;

class PrivateChatInfo {
  final String chatId;
  final List<String> participants;
  final Map<String, String> participantNames;
  final Map<String, String> participantGenders;
  final Map<String, String> participantLocations;
  final Map<String, int> participantAges;
  final Map<String, bool> participantRegistered;
  final String lastMessage;
  final DateTime lastMessageAt;
  final String lastSenderId;
  final int messageCount;
  final Map<String, int> unreadCounts;
  final Map<String, DateTime> lastReadAt;
  final List<String> pinnedBy;
  final Map<String, DateTime> pinnedAt;
  final List<String> mutedBy;
  final List<String> archivedBy;

  /// UID lawan bicara yang akunnya SUDAH DIHAPUS. Baris ini hanya ada di
  /// perangkat lokal (server sudah menghapus chat-nya demi privasi) — dipakai
  /// menampilkan label "Akun dihapus" + mengunci kirim pesan. Kosong = normal.
  final String deletedOtherUid;

  PrivateChatInfo({
    required this.chatId,
    required this.participants,
    required this.participantNames,
    this.participantGenders = const {},
    this.participantLocations = const {},
    this.participantAges = const {},
    this.participantRegistered = const {},
    required this.lastMessage,
    required this.lastMessageAt,
    this.lastSenderId = '',
    this.messageCount = 0,
    this.unreadCounts = const {},
    this.lastReadAt = const {},
    this.pinnedBy = const [],
    this.pinnedAt = const {},
    this.mutedBy = const [],
    this.archivedBy = const [],
    this.deletedOtherUid = '',
  });

  /// Akun lawan sudah dihapus (penanda lokal) → UI tampilkan label khusus,
  /// kirim pesan dikunci, dan user boleh menghapus chat ini.
  bool get otherDeleted => deletedOtherUid.isNotEmpty;

  bool isPinnedFor(String uid) => pinnedBy.contains(uid);
  DateTime? pinnedAtFor(String uid) => pinnedAt[uid];
  bool isMutedFor(String uid) => mutedBy.contains(uid);
  bool isArchivedFor(String uid) => archivedBy.contains(uid);

  Map<String, dynamic> toMap() => {
    'chatId': chatId,
    'participants': participants,
    'participantNames': participantNames,
    'participantGenders': participantGenders,
    'participantLocations': participantLocations,
    'participantAges': participantAges,
    'participantRegistered': participantRegistered,
    'lastMessage': lastMessage,
    'lastMessageAt': lastMessageAt.toIso8601String(),
    'lastSenderId': lastSenderId,
    'messageCount': messageCount,
    'unreadCounts': unreadCounts,
    'lastReadAt': lastReadAt.map((k, v) => MapEntry(k, v.toIso8601String())),
    'pinnedBy': pinnedBy,
    'pinnedAt': pinnedAt.map((k, v) => MapEntry(k, v.toIso8601String())),
    'mutedBy': mutedBy,
    'archivedBy': archivedBy,
    'deletedOtherUid': deletedOtherUid,
  };

  static Map<String, String> _strMap(dynamic v) =>
      ((v as Map?) ?? {}).map((k, e) => MapEntry('$k', '$e'));

  factory PrivateChatInfo.fromMap(Map<String, dynamic> d) {
    return PrivateChatInfo(
      chatId: '${d['chatId'] ?? ''}',
      participants: List<String>.from(d['participants'] ?? const []),
      participantNames: _strMap(d['participantNames']),
      participantGenders: _strMap(d['participantGenders']),
      participantLocations: _strMap(d['participantLocations']),
      participantAges: ((d['participantAges'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', (v as num).toInt()),
      ),
      participantRegistered: ((d['participantRegistered'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', v == true),
      ),
      lastMessage: '${d['lastMessage'] ?? ''}',
      lastMessageAt:
          DateTime.tryParse('${d['lastMessageAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastSenderId: '${d['lastSenderId'] ?? ''}',
      messageCount: (d['messageCount'] as num?)?.toInt() ?? 0,
      unreadCounts: ((d['unreadCounts'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', (v as num).toInt()),
      ),
      lastReadAt: ((d['lastReadAt'] as Map?) ?? {}).map(
        (k, v) =>
            MapEntry('$k', DateTime.tryParse('$v') ?? DateTime(2000)),
      ),
      pinnedBy: List<String>.from(d['pinnedBy'] ?? const []),
      pinnedAt: ((d['pinnedAt'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', DateTime.tryParse('$v') ?? DateTime(2000)),
      ),
      mutedBy: List<String>.from(d['mutedBy'] ?? const []),
      archivedBy: List<String>.from(d['archivedBy'] ?? const []),
      deletedOtherUid: '${d['deletedOtherUid'] ?? ''}',
    );
  }

  PrivateChatInfo copyWith({
    String? chatId,
    List<String>? participants,
    Map<String, String>? participantNames,
    Map<String, String>? participantGenders,
    Map<String, String>? participantLocations,
    Map<String, int>? participantAges,
    Map<String, bool>? participantRegistered,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastSenderId,
    int? messageCount,
    Map<String, int>? unreadCounts,
    Map<String, DateTime>? lastReadAt,
    List<String>? pinnedBy,
    Map<String, DateTime>? pinnedAt,
    List<String>? mutedBy,
    List<String>? archivedBy,
    String? deletedOtherUid,
  }) {
    return PrivateChatInfo(
      chatId: chatId ?? this.chatId,
      participants: participants ?? this.participants,
      participantNames: participantNames ?? this.participantNames,
      participantGenders: participantGenders ?? this.participantGenders,
      participantLocations: participantLocations ?? this.participantLocations,
      participantAges: participantAges ?? this.participantAges,
      participantRegistered:
          participantRegistered ?? this.participantRegistered,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      messageCount: messageCount ?? this.messageCount,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      pinnedBy: pinnedBy ?? this.pinnedBy,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      mutedBy: mutedBy ?? this.mutedBy,
      archivedBy: archivedBy ?? this.archivedBy,
      deletedOtherUid: deletedOtherUid ?? this.deletedOtherUid,
    );
  }
}
