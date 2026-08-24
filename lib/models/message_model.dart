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
  });

  factory MessageModel.fromMap(String id, Map<String, dynamic> map) {
    return MessageModel(
      // Prefer id dari map — bisa int (dari server PostgREST) atau String
      // (dari cache). Fallback ke argumen kalau null/kosong.
      id: (map['id']?.toString() ?? '').isNotEmpty ? map['id'].toString() : id,
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Anon',
      senderGender: map['senderGender'] ?? 'other',
      isRegistered: map['isRegistered'] == true,
      text: map['text'] ?? '',
      type: map['type'] ?? 'text',
      edited: map['edited'] == true,
      isDeleted: map['isDeleted'] == true,
      imageData: map['imageData'] ?? '',
      timestamp: parseDate(map['timestamp'] ?? map['createdAt']),
      repliedToId: map['repliedToId'] is String ? map['repliedToId'] : null,
      repliedToText: map['repliedToText'],
      repliedToSenderName: map['repliedToSenderName'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'senderGender': senderGender,
      'isRegistered': isRegistered,
      'text': text,
      'type': type,
      'imageData': imageData,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'repliedToId': repliedToId,
      'repliedToText': repliedToText,
      'repliedToSenderName': repliedToSenderName,
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
  }) {
    return MessageModel(
      id: id,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      isRegistered: isRegistered,
      text: text ?? this.text,
      type: type ?? this.type,
      imageData: imageData ?? this.imageData,
      timestamp: timestamp,
      edited: edited ?? this.edited,
      isDeleted: isDeleted ?? this.isDeleted,
      repliedToId: repliedToId ?? this.repliedToId,
      repliedToText: repliedToText ?? this.repliedToText,
      repliedToSenderName: repliedToSenderName ?? this.repliedToSenderName,
    );
  }
}
