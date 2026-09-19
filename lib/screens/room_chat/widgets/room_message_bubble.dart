import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/gifts.dart';
import '../../../utils.dart';
import '../../../config/theme.dart';
import '../../../models/message_model.dart';
import '../../../providers/locale_provider.dart';
import '../../../services/link_preview_service.dart';
import '../../../widgets/link_preview.dart';
import '../../../widgets/mention_spans.dart';
import '../../../widgets/private_chat_message.dart';
import '../../../widgets/reply_quote.dart';
import '../../../widgets/voice_bubble.dart';

class RoomMessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final bool isPending;
  final bool isQueued;
  /// Mode seleksi: border primary digambar mengikuti bentuk bubble
  /// (bukan pembungkus selebar baris) — sama seperti private chat.
  final bool isSelected;
  final Color color;
  final String roomId;
  final VoidCallback onTapUser;
  /// Set pesan ( room) yang berstatus terhapus — dipakai untuk meredam
  /// quote reply yang menunjuk pesan terhapus (isi tidak boleh bocor).
  final Set<String> deletedIds;
  /// Highlight `@all` — hanya private room/grup (owner/admin). Global room
  /// selalu false.
  final bool highlightMentionAll;
  const RoomMessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    this.isPending = false,
    this.isQueued = false,
    this.isSelected = false,
    required this.color,
    required this.roomId,
    required this.onTapUser,
    this.deletedIds = const {},
    this.highlightMentionAll = false,
  });

  // Warna teks bubble mengikuti tema (gelap di light mode, terang di dark mode)
  // supaya sinkron dengan warna bubble (bgInput / primary alpha).
  static Color get _textColor => AppTheme.textPrimary;

  bool get _isMedia =>
      msg.type == 'image' ||
      msg.type == 'view_once' ||
      msg.type == 'view_once_expired';

  // Konten bubble: foto / view-once / teks — dipakai untuk pesan sendiri & orang lain.
  Widget _replyQuote(BuildContext context) {
    return ReplyQuote.fromMessage(
          context: context,
          repliedToText: msg.repliedToText,
          repliedToId: msg.repliedToId,
          repliedToSenderName: msg.repliedToSenderName,
          isMe: isMe,
          deletedIds: deletedIds,
          senderColor: AppTheme.primary,
        ) ??
        const SizedBox.shrink();
  }

  Widget _content(
    BuildContext context,
    String timeStr, {
    required bool alignRight,
  }) {
    final chatKey = 'room_$roomId';
    if (msg.type == 'voice' && msg.imageData.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _replyQuote(context),
          VoiceBubble(
            path: msg.imageData,
            durationMs: msg.durationMs ?? 0,
            isMe: isMe,
            timeStr: timeStr,
          ),
        ],
      );
    }
    if (msg.type == 'image' && msg.imageData.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _replyQuote(context),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                MessageImage(
                  imageData: msg.imageData,
                  chatKey: chatKey,
                  messageId: msg.id,
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      timeStr,
                      style: AppText.chatTime.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (msg.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: MentionAwareText(
                msg.text,
                style: AppText.chatBody.copyWith(color: _textColor),
                mentions: msg.mentions,
                highlightAll: highlightMentionAll,
              ),
            ),
        ],
      );
    }
    if (msg.type == 'view_once' || msg.type == 'view_once_expired') {
      return Stack(
        children: [
          ViewOnceImage(
            imageData: msg.imageData,
            chatKey: chatKey,
            isMe: isMe,
            messageId: msg.id,
            isExpired: msg.type == 'view_once_expired',
            isRoom: true,
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                timeStr,
                style: AppText.chatTime.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    // Bubble gift: emoji besar + nama gift (mirip room streaming).
    if (msg.type == 'gift') {
      final gift = giftById(msg.text);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0x26FF2D95), Color(0x26FF8A00)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.pinkAccent.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(gift?.emoji ?? '🎁',
                    style: TextStyle(fontSize: AppGlyph.lg)),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gift == null
                          ? msg.text
                          : (context.read<LocaleProvider>().s.isId
                              ? gift.nameId
                              : gift.nameEn),
                      style: AppText.chatName.copyWith(color: _textColor),
                    ),
                    Text(
                      '🎁 gift',
                      style: AppText.chatTime.copyWith(
                        color: Colors.pinkAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              timeStr,
              style: AppText.chatTime.copyWith(
                color: _textColor.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _replyQuote(context),
        if (LinkPreviewService.instance.extractUrl(msg.text) != null) LinkPreview(text: msg.text),
        MessageTextWithTime(
          text: msg.text,
          timeStr: timeStr,
          textStyle: AppText.chatBody.copyWith(color: _textColor),
          timeStyle: AppText.chatTime.copyWith(
            color: _textColor.withValues(alpha: 0.45),
            fontWeight: FontWeight.w400,
          ),
          alignRight: alignRight,
          mentions: msg.mentions,
          highlightMentionAll: highlightMentionAll,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    if (msg.isDeleted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Text(s.messageDeleted, style: AppText.chatBodySmall.copyWith(color: AppTheme.textSecondary, fontStyle: FontStyle.italic)),
          ],
        ),
      );
    }
    final timeStr = formatBubbleTime(msg.timestamp);

    // Pesan sendiri: biru muda (sama private), rata kanan, tanpa avatar
    if (isMe) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                ),
                padding: _isMedia
                    ? const EdgeInsets.all(4)
                    : const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(4),
                  ),
                  // Mode seleksi: border mengikuti bentuk bubble (sama
                  // private chat) — hanya area bubble, bukan sepajang baris.
                  border: isSelected
                      ? Border.all(color: AppTheme.primary, width: 2)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _content(context, timeStr, alignRight: true),
                    // Room & grup TANPA centang status (beda dari private 1:1):
                    // hanya teks "menunggu koneksi" saat pesan terantre offline.
                    if (isQueued)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          s.msgWaitingConnection,
                          style: AppText.chatTime.copyWith(
                            color: _textColor.withValues(alpha: 0.55),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Pesan user lain: avatar + nama warna + bubble abu-abu (sama private), rata kiri
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTapUser,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: Text(
                msg.senderName.isNotEmpty
                    ? msg.senderName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppGlyph.avatarInitial(32),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onTapUser,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg.senderName,
                        style: AppText.chatName.copyWith(
                          color: color,
                          letterSpacing: 0,
                        ),
                      ),
                      if (msg.isRegistered) ...[
                        SizedBox(width: 3),
                        Icon(
                          Icons.verified,
                          size: 14,
                          color: Color(0xFF4A90E2),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 2),
                Container(
                  // Kurangi offset avatar (32) + gap (8) supaya tepi kanan bubble
                  // sama dengan bubble private chat (80% lebar layar).
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.8 - 40,
                  ),
                  padding: _isMedia
                      ? EdgeInsets.all(4)
                      : const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.bgInput,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(10),
                    ),
                    // Mode seleksi: border mengikuti bentuk bubble.
                    border: isSelected
                        ? Border.all(color: AppTheme.primary, width: 2)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.repliedToId != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: const Border(
                              left: BorderSide(
                                color: AppTheme.primary,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                msg.repliedToSenderName ?? '',
                                style: AppText.chatName.copyWith(
                                  color: AppTheme.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                msg.repliedToText ?? '',
                                style: AppText.chatBodySmall.copyWith(
                                  color: _textColor.withValues(alpha: 0.6),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      _content(context, timeStr, alignRight: false),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// Toggle header room: pill squircle dengan icon beranimasi
/// anggota ⇄ chat — lebih jelas afordansinya daripada icon polos.
