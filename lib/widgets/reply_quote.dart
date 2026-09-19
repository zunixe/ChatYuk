import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';

/// Kutipan balasan (reply quote) di dalam bubble chat — dipakai bersama oleh
/// bubble private (`private_chat_message.dart`) dan bubble room
/// (`room_chat_screen.dart`).
///
/// Sebelumnya blok ini disalin di dua tempat dengan satu-satunya perbedaan
/// warna nama pengirim (room memakai `primary`). PRIVASI: bila pesan yang
/// dibalas sudah dihapus (`targetDeleted`), teks ditampilkan miring sebagai
/// "Pesan dihapus" — jangan hapus guard ini.
class ReplyQuote extends StatelessWidget {
  final String? senderName;
  final String text;
  final bool isMe;
  final bool targetDeleted;

  /// Warna nama pengirim. Null → warna default tema (`AppText.chatName`).
  final Color? senderColor;

  const ReplyQuote({
    super.key,
    required this.senderName,
    required this.text,
    required this.isMe,
    required this.targetDeleted,
    this.senderColor,
  });

  /// Helper: bangun dari data pesan + daftar id terhapus. Mengembalikan
  /// null bila tidak ada teks balasan (pemanggil tetap memutuskan layout).
  static ReplyQuote? fromMessage({
    required BuildContext context,
    required String? repliedToText,
    required String? repliedToId,
    required String? repliedToSenderName,
    required bool isMe,
    required Set<String> deletedIds,
    Color? senderColor,
  }) {
    if (repliedToText == null || repliedToText.isEmpty) return null;
    return ReplyQuote(
      senderName: repliedToSenderName,
      text: repliedToText,
      isMe: isMe,
      targetDeleted: repliedToId != null && deletedIds.contains(repliedToId),
      senderColor: senderColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    final nameStyle = senderColor == null
        ? AppText.chatName
        : AppText.chatName.copyWith(color: senderColor);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : AppTheme.bgScreen.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(senderName ?? '', style: nameStyle),
          Text(
            targetDeleted ? s.messageDeleted : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.chatBodySmall.copyWith(
              fontStyle: targetDeleted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}
