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
    // Overlay chip 20% di kedua mode (gelap: putih 20%, terang: hitam 20%).
    final isDark = AppTheme.isDark;
    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 6),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.20)
              : Colors.black.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppText.label.copyWith(
            color: isDark ? AppTheme.textSecondary : const Color(0xFF424242),
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
