import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import '../models/message_model.dart';

// Item list chat: pesan atau separator tanggal (selipan di antara grup hari).
class ChatItem {
  final MessageModel? msg;
  final String? dateLabel;
  const ChatItem.message(this.msg) : dateLabel = null;
  const ChatItem.date(String label) : msg = null, dateLabel = label;
}

/// Label chip tanggal — Hari ini/Kemarin, selain itu tanggal lengkap.
String dateChipLabel(DateTime dt, S s) {
  final now = DateTime.now();
  final local = dt.toLocal();
  final todayStart = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(local.year, local.month, local.day);
  final diff = todayStart.difference(msgDay).inDays;
  if (diff == 0) return s.labelToday;
  if (diff == 1) return s.labelYesterday;
  return DateFormat('EEEE, d MMMM yyyy').format(local);
}

/// Selipan tanggal di tengah chat, pola WhatsApp.
class DateChip extends StatelessWidget {
  final String label;
  const DateChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}