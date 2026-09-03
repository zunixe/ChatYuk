import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/locale_provider.dart';

// ── Shared chat UI: satu sumber untuk PrivateChatScreen & RoomChatScreen ──
// Dulu: duplikat di kedua screen (76 cluster ≥5 baris identik/mirip) —
// bug fix satu sisi tidak otomatis ke sisi lain. Unifikasi inkremental.

/// Resize proporsional (sisi terpanjang 800) + JPEG q75, return base64.
/// Harus top-level untuk `compute()` isolate.
String? processChatImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final w = decoded.width;
  final h = decoded.height;
  final img.Image resized = (w <= 800 && h <= 800)
      ? decoded
      : img.copyResize(
          decoded,
          width: w > h ? 800 : null,
          height: h >= w ? 800 : null,
        );
  return base64Encode(img.encodeJpg(resized, quality: 75));
}

/// Tombol ikon bulat kecil di row composer (attach + / kamera).
/// Satu widget menggantikan `_InputIconBtn` & `_RoomInputIconBtn`.
class ChatIconButton extends StatelessWidget {
  /// null = mode rotasi (ikon + ↔ ✕) mengikuti [open].
  final IconData? icon;
  final bool open;
  final VoidCallback onTap;
  final String tooltip;
  const ChatIconButton({
    super.key,
    this.icon,
    required this.open,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primary.withValues(alpha: open ? 0.16 : 0.12),
          ),
          child: AnimatedRotation(
            turns: open ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: Icon(
                icon ?? (open ? Icons.close_rounded : Icons.add_rounded),
                key: ValueKey(icon ?? open),
                color: AppTheme.primary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip menu attach (kirim foto / view once / koin) ala WhatsApp.
/// Satu widget menggantikan `_AttachChip` & `_RoomAttachChip`.
class ChatAttachChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const ChatAttachChip({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        // Lebar chip FIXED agar pusat ikon selalu di posisi yang sama —
        // label yang panjang (mis. "Foto Sekali Lihat") tidak menggeser
        // posisi ikon, jadi jeda antar ikon rata. Harus muat 4 chip
        // sekaligus di layar terkecil (Redmi 393dp): 4×82 + 3×10 = 358dp.
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bubble titik-titik "sedang mengetik" / "merekam suara" lawan bicara.
/// Satu widget menggantikan `_TypingBubble` private (room belum punya —
/// ditambahkan supaya alur sama ketika room memakai typing indicator).
class ChatTypingBubble extends StatefulWidget {
  final bool isRecording;
  const ChatTypingBubble({super.key, this.isRecording = false});

  @override
  State<ChatTypingBubble> createState() => _ChatTypingBubbleState();
}

class _ChatTypingBubbleState extends State<ChatTypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgInput,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_rounded, color: Colors.red, size: 16),
            const SizedBox(width: 6),
            Text(
              context.read<LocaleProvider>().s.recordingStatus,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = TweenSequence<double>([
            TweenSequenceItem(
              tween: Tween(begin: 0.3, end: 1.0)
                  .chain(CurveTween(curve: Curves.easeInOut)),
              weight: 50,
            ),
            TweenSequenceItem(
              tween: Tween(begin: 1.0, end: 0.3)
                  .chain(CurveTween(curve: Curves.easeInOut)),
              weight: 50,
            ),
          ]).animate(
            CurvedAnimation(
              parent: _ctrl,
              curve: Interval(i * 0.15, 1, curve: Curves.linear),
            ),
          );
          return FadeTransition(
            opacity: t,
            child: Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }
}
