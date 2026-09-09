import '../utils.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String senderGender;
  final bool isRegistered;
  final String text;
  final String type;
  final String imageData;
  final DateTime timestamp;
  final bool edited;
  final bool isDeleted;
  final String? repliedToId;
  final String? repliedToText;
  final String? repliedToSenderName;
  final int? durationMs;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderGender,
    required this.isRegistered,
    required this.text,
    required this.type,
    required this.imageData,
    required this.timestamp,
    this.edited = false,
    this.isDeleted = false,
    this.repliedToId,
    this.repliedToText,
    this.repliedToSenderName,
    this.durationMs,
  });

  factory MessageModel.fromMap(String id, Map<String, dynamic> map) {
    final deleted = map['isDeleted'] == true;
    return MessageModel(
      // Prefer id dari map — bisa int (dari server PostgREST) atau String
      // (dari cache). Fallback ke argumen kalau null/kosong.
      id: (map['id']?.toString() ?? '').isNotEmpty ? map['id'].toString() : id,
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Anon',
      senderGender: map['senderGender'] ?? 'other',
      isRegistered: map['isRegistered'] == true,
      // PRIVASI: pesan terhapus TIDAK PERNAH membawa isi — teks & media
      // dikosongkan di sumber (cache lama yang belum ber-flag tetap aman).
      text: deleted ? '' : (map['text'] ?? ''),
      type: deleted ? 'text' : (map['type'] ?? 'text'),
      edited: map['edited'] == true,
      isDeleted: deleted,
      // imageData: base64 lama ATAU path storage (voicePath/imagePath).
      // Pakai isNotEmpty (bukan ??) karena '' bukan null — path harus tetap terpakai.
      imageData: deleted
          ? ''
          : _firstNonEmpty([map['imageData'], map['voicePath'], map['voice_path'], map['imagePath'], map['image_path']]),
      timestamp: parseDate(map['timestamp'] ?? map['createdAt']),
      repliedToId: map['repliedToId'] is String ? map['repliedToId'] : null,
      repliedToText: map['repliedToText'],
      repliedToSenderName: map['repliedToSenderName'],
      durationMs: (map['durationMs'] ?? map['duration_ms'] ?? map['duration']) is num ? (map['durationMs'] ?? map['duration_ms'] ?? map['duration'] as num).toInt() : null,
    );
  }

  static String _firstNonEmpty(List<dynamic> vals) {
    for (final v in vals) {
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'senderGender': senderGender,
      'isRegistered': isRegistered,
      // PRIVASI: isi pesan terhapus tidak masuk cache disk.
      'text': isDeleted ? '' : text,
      'type': isDeleted ? 'text' : type,
      'imageData': isDeleted ? '' : imageData,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'edited': edited,
      'isDeleted': isDeleted,
      'repliedToId': repliedToId,
      'repliedToText': repliedToText,
      'repliedToSenderName': repliedToSenderName,
      'durationMs': durationMs,
    };
  }

  MessageModel copyWith({
    String? imageData,
    String? type,
    String? text,
    bool? edited,
    bool? isDeleted,
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    int? durationMs,
  }) {
    final newDeleted = isDeleted ?? this.isDeleted;
    // PRIVASI: begitu berstatus terhapus, konten dikosongkan — update
    // realtime (is_deleted=true) tidak menyisakan teks/media di memori.
    return MessageModel(
      id: id,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      isRegistered: isRegistered,
      text: newDeleted ? '' : (text ?? this.text),
      type: newDeleted ? 'text' : (type ?? this.type),
      imageData: newDeleted ? '' : (imageData ?? this.imageData),
      timestamp: timestamp,
      edited: edited ?? this.edited,
      isDeleted: newDeleted,
      repliedToId: repliedToId ?? this.repliedToId,
      repliedToText: repliedToText ?? this.repliedToText,
      repliedToSenderName: repliedToSenderName ?? this.repliedToSenderName,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}
