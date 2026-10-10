import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/theme.dart';
import '../../../models/message_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../utils.dart';
import 'bubble_tail_painter.dart';

/// Bangun + tampilkan overlay "pesan belum dibaca" yang nempel di ujung kartu
/// user (di atas atau di bawah kartu sesuai ruang).
///
/// Mengembalikan [OverlayEntry] yang sudah di-insert (agar pemanggil bisa
/// menyimpan referensi & memaksa-remove), atau `null` bila tak ada pesan /
/// uid kosong. Pemanggil bertanggung jawab atas auto-close & anti-tumpuk.
Future<OverlayEntry?> showUnreadBubbleOverlay({
  required BuildContext cardCtx,
  required UserModel user,
  required int unreadCount,
  required Offset globalPos,
  required Rect cardRect,
}) async {
  final myUid = ProviderScope.containerOf(
    cardCtx,
    listen: false,
  ).read(authProvider.notifier).uid;
  final s = ProviderScope.containerOf(
    cardCtx,
    listen: false,
  ).read(localeProvider).s;
  if (myUid == null) return null;
  final ids = [myUid, user.uid]..sort();
  final chatId = '${ids[0]}_${ids[1]}';
  List<MessageModel> msgs = [];
  try {
    final rows = await Supabase.instance.client
        .from('private_messages')
        .select(
          'id, sender_id, sender_name, text, type, image_data, created_at',
        )
        .eq('chat_id', chatId)
        .eq('sender_id', user.uid)
        .order('created_at', ascending: false)
        .limit(unreadCount > 8 ? 8 : unreadCount);
    msgs = rows
        .map(
          (r) => MessageModel.fromMap('${r['id']}', {
            'senderId': r['sender_id'],
            'senderName': r['sender_name'],
            'text': r['text'] ?? '',
            'type': r['type'] ?? 'text',
            'imageData': r['image_data'] ?? '',
            'createdAt': r['created_at'],
          }),
        )
        .toList();
  } catch (_) {}
  if (!cardCtx.mounted || msgs.isEmpty) return null;
  HapticFeedback.mediumImpact();
  final overlay = Overlay.of(cardCtx);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      final size = MediaQuery.of(ctx).size;
      final bubbleWidth = 280.0;
      final bubbleHeight = (msgs.length * 48.0 + 40)
          .clamp(72, 280)
          .toDouble();
      // NEMPEL DI UJUNG KARTU: pakai RECT kartu yang sebenarnya (dikirim
      // pemanggil). Bila rect tak valid (fallback) → pakai titik jari.
      final hasCard = cardRect.height > 0;
      final cardTop = hasCard ? cardRect.top : globalPos.dy;
      final cardBottom = hasCard ? cardRect.bottom : globalPos.dy;
      final cardCenterX = hasCard ? cardRect.center.dx : globalPos.dx;
      double left = cardCenterX - bubbleWidth / 2;
      left = left.clamp(12.0, size.width - bubbleWidth - 12.0);
      // Utamakan ATAS kartu (nempel tepat di tepi atas, gap 6px); kalau
      // tak cukup ruang → BANYAK bawah kartu (nempel tepi bawah, gap 6).
      final spaceAbove = cardTop;
      final spaceBelow = size.height - cardBottom;
      final isAbove =
          spaceAbove >= bubbleHeight + 12 || spaceAbove >= spaceBelow;
      double top;
      if (isAbove) {
        top = cardTop - bubbleHeight - 6;
      } else {
        top = cardBottom + 6;
      }
      top = top.clamp(8.0, size.height - bubbleHeight - 8.0);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => entry.remove(),
              child: Container(color: Colors.black.withValues(alpha: 0.15)),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isAbove) ...[
                    CustomPaint(
                      size: const Size(14, 8),
                      painter: BubbleTailPainter(
                        color: AppTheme.bgInput,
                        isTop: true,
                      ),
                    ),
                  ],
                  Container(
                    width: bubbleWidth,
                    constraints: const BoxConstraints(maxWidth: 280),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgInput,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                      border: Border.all(
                        color: AppTheme.divider.withValues(alpha: 0.8),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(user.nickname, style: AppText.bodyStrong),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s.newCount(unreadCount),
                                style: AppText.micro.copyWith(
                                  color: AppTheme.danger,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => entry.remove(),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        Divider(
                          height: 1,
                          color: AppTheme.divider.withValues(alpha: 0.5),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final m in msgs) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                  horizontal: 2,
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        m.text.isNotEmpty
                                            ? m.text
                                            : (m.type == 'image'
                                                  ? s.msgPhoto
                                                  : m.type),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.bodySmall,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      formatBubbleTime(m.timestamp),
                                      style: AppText.micro.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (m != msgs.last)
                                Divider(
                                  height: 1,
                                  color: AppTheme.divider.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isAbove) ...[
                    CustomPaint(
                      size: const Size(14, 8),
                      painter: BubbleTailPainter(
                        color: AppTheme.bgInput,
                        isTop: false,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
  return entry;
}
