
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;

import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import 'app_gesture.dart';

// ── Shared chat UI: satu sumber untuk PrivateChatScreen & RoomChatScreen ──
// Dulu: duplikat di kedua screen (76 cluster ≥5 baris identik/mirip) —
// bug fix satu sisi tidak otomatis ke sisi lain. Unifikasi inkremental.

/// Tombol ikon bulat kecil di row composer (attach + / kamera).
/// Satu widget menggantikan `_InputIconBtn` & `_RoomInputIconBtn`.
class ChatIconButton extends StatelessWidget {
  /// null = mode rotasi (ikon + ↔ ✕) mengikuti [open].
  final IconData? icon;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String tooltip;
  const ChatIconButton({
    super.key,
    this.icon,
    required this.open,
    required this.onTap,
    this.onLongPress,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    // Isi tombol (lingkaran ikon) — sama untuk tap maupun tahan.
    // AnimatedContainer: warna lingkaran ikut halus saat state berubah.
    final core = Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.primary.withValues(alpha: open ? 0.16 : 0.12),
        ),
        child: AnimatedRotation(
          // Rotasi (+ → ✕), TANPA crossfade ikon: crossfade menumpuk dua
          // glif 180ms sehingga terlihat seperti ikon rusak/glitch.
          turns: open ? 0.125 : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          // SATU glif saja (+ / ikon yang diberikan). Saat `open`, glif itu
          // diputar 45° → membentuk ✕ secara alami. Dulu ikon DIGANTI
          // sekaligus (add → close) sehingga yang terlihat berputar justru ✕
          // (putaran tak nyambung).
          child: Icon(
            icon ?? Icons.add_rounded,
            color: AppTheme.primary,
            // 18px di kotak 30px → margin 6px tiap sisi (proporsional).
            size: 18,
          ),
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      // Bila ada aksi tekan-tahan (mis. kamera → rekam video), Tooltip
      // TIDAK boleh merebut long-press (default tooltip mobile muncul saat
      // ditahan → long-press tak sampai). Pakai trigger manual + AppGesture.
      triggerMode: onLongPress != null
          ? TooltipTriggerMode.manual
          : TooltipTriggerMode.longPress,
      child: SizedBox(
        width: 32,
        height: 44,
        // Bila ada aksi tahan: pakai AppGestureDetector (long-press 450ms,
        // lebih cepat & andal daripada InkWell default 500ms yang sering
        // terasa "tidak merekam"). Tanpa aksi tahan: InkWell biasa.
        child: onLongPress == null
            ? InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: core,
              )
            : AppGestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                onLongPress: onLongPress,
                child: core,
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
              ProviderScope.containerOf(context, listen: false).read(localeProvider).s.recordingStatus,
              style: AppText.chatBodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
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
