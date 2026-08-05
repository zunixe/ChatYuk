import 'package:cloud_firestore/cloud_firestore.dart';

DateTime parseDate(dynamic v) {
  if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
  if (v is DateTime) return v;
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

int colorHashForUid(String uid) {
  int hash = 0;
  for (int i = 0; i < uid.length; i++) {
    hash = uid.codeUnitAt(i) + ((hash << 5) - hash);
  }
  return hash.abs();
}

const userColorPalette = [
  0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFFB8C00,
  0xFF8E24AA, 0xFF00ACC1, 0xFFD81B60, 0xFF3949AB,
  0xFF689F38, 0xFF6D4C41, 0xFF546E7A, 0xFFF4511E,
];

String formatTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

int notifIdForKey(String key) {
  int hash = 0;
  for (int i = 0; i < key.length; i++) {
    hash = key.codeUnitAt(i) + ((hash << 5) - hash);
  }
  return hash.abs() & 0x7FFFFFFF;
}
