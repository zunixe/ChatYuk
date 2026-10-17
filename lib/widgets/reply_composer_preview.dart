import 'package:flutter/material.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/chat/chat_location.dart';
import '../models/message_model.dart';

/// Kartu preview "membalas" di atas kolom ketik (private + room), ala
/// WhatsApp: kartu solid berpinggir bulat dengan garis aksen kiri, nama
/// pengirim, ringkasan pesan (ikon + label untuk foto/video/lokasi) dan
/// tombol tutup. Warna solid [AppTheme.bgCard] agar tidak menyatu dengan
/// wallpaper chat.
class ReplyComposerPreview extends StatelessWidget {
  final MessageModel message;
  final String senderLabel;
  final S s;
  final VoidCallback onCancel;

  const ReplyComposerPreview({
    super.key,
    required this.message,
    required this.senderLabel,
    required this.s,
    required this.onCancel,
  });

  ({IconData? icon, String text}) _summary() {
    final m = message;
    final t = m.text.trim();
    if (m.type == 'image') {
      return (icon: Icons.photo_outlined, text: t.isNotEmpty ? t : s.msgPhoto);
    }
    if (m.type == 'location' || isLocationPayload(m.text)) {
      return (icon: Icons.location_on_outlined, text: s.msgLocation);
    }
    if (m.type == 'voice') return (icon: Icons.mic_none, text: s.msgVoice);
    if (m.type == 'file') {
      return (icon: Icons.insert_drive_file_outlined, text: t);
    }
    return (icon: null, text: t.isNotEmpty ? t : s.msgPhoto);
  }

  @override
  Widget build(BuildContext context) {
    final sum = _summary();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: AppTheme.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        senderLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.chatCaption.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          if (sum.icon != null) ...[
                            Icon(
                              sum.icon,
                              size: 14,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              sum.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.chatBodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                onPressed: onCancel,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
