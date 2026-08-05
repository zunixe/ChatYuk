import '../utils.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String senderGender;
  final String text;
  final String type;
  final String imageData;
  final DateTime timestamp;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderGender,
    required this.text,
    required this.type,
    required this.imageData,
    required this.timestamp,
  });

  factory MessageModel.fromMap(String id, Map<String, dynamic> map) {
    return MessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Anon',
      senderGender: map['senderGender'] ?? 'other',
      text: map['text'] ?? '',
      type: map['type'] ?? 'text',
      imageData: map['imageData'] ?? '',
      timestamp: parseDate(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderGender': senderGender,
      'text': text,
      'type': type,
      'imageData': imageData,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }
}
