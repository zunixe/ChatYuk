import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../providers/riverpod/locale_provider.dart';

/// Badge visibilitas story milik sendiri — ikon + label pendek di
/// header viewer (Semua orang / Pengikut / Teman), gaya menyatu dgn
/// header (teks putih + shadow, tanpa kotak supaya tidak berat).
class StoryVisibilityBadge extends ConsumerWidget {
  final String visibility;

  /// Slide private (dulu "dihapus") — hanya pembuat (atau admin) yang lihat.
  final bool ownerOnly;
  const StoryVisibilityBadge({
    required this.visibility,
    this.ownerOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final isEveryone = visibility == 'everyone';
    final isFriends = visibility == 'friends';
    final icon = ownerOnly
        ? Icons.lock
        : isEveryone
        ? Icons.public
        : (isFriends ? Icons.favorite_rounded : Icons.group_rounded);
    final label = ownerOnly
        ? s.storyVisibilityPrivate
        : isEveryone
        ? s.storyVisibilityEveryone
        : (isFriends ? s.storyVisibilityFriends : s.storyVisibilityFollowers);
    const shadows = [
      Shadow(color: Color(0xCC000000), blurRadius: 6),
      Shadow(color: Color(0x80000000), blurRadius: 2, offset: Offset(1, 1)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white70, shadows: shadows),
        const SizedBox(width: 3),
        Text(
          label,
          style: AppText.caption.copyWith(
            color: Colors.white70,
            shadows: shadows,
          ),
        ),
      ],
    );
  }
}

/// Tombol bulat kecil di dalam foto (like / share / kirim) — GestureDetector
/// murni 40px supaya rapat dan tidak menambah padding Material.
///
/// [popOnTap]: beri animasi "pop" singkat saat ditekan (scale naik-turun +
/// hati kecil terbang ke atas). Dipakai untuk tombol LIKE supaya feedback-nya
/// terasa halus, bukan "kaku lalu diam".
class StoryCircleBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool busy;
  final VoidCallback? onTap;
  final bool popOnTap;

  const StoryCircleBtn({
    required this.icon,
    required this.color,
    this.busy = false,
    required this.onTap,
    this.popOnTap = false,
  });

  @override
  State<StoryCircleBtn> createState() => StoryCircleBtnState();
}

class StoryCircleBtnState extends State<StoryCircleBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Scale: 1.0 → 1.35 (cepat) → 1.0 (elastis).
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.35,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.35,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65,
      ),
    ]).animate(_pop);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.popOnTap) _pop.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: widget.busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(widget.icon, size: 20, color: Colors.white),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Hati kecil terbang ke atas saat pop (feedback like) — hanya saat
            // popOnTap agar tombol lain tak menampilkannya.
            if (widget.popOnTap)
              AnimatedBuilder(
                animation: _pop,
                builder: (context, child) {
                  if (_pop.value == 0) return const SizedBox.shrink();
                  final t = _pop.value;
                  // Muncul lalu memudar; naik sedikit ke atas.
                  final opacity = (1 - t).clamp(0.0, 1.0);
                  final dy = -18 * Curves.easeOut.transform(t);
                  return Positioned(
                    top: dy,
                    child: Opacity(
                      opacity: opacity,
                      child: const Icon(
                        Icons.favorite,
                        size: 16,
                        color: AppTheme.danger,
                      ),
                    ),
                  );
                },
              ),
            ScaleTransition(scale: _scale, child: circle),
          ],
        ),
      ),
    );
  }
}

/// Tombol header viewer yang rapat — IconButton Material 3 selalu
/// menambah tap-target/padding internal (48px) walau padding: zero →
/// ikon tidak pernah menempel tepi. Pakai GestureDetector murni.
class StoryHeaderBtn extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;

  const StoryHeaderBtn({
    required this.icon,
    this.iconSize = 20,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Bayangan ganda — ikon putih tetap kontras di foto terang/gelap.
    const shadows = [
      Shadow(color: Color(0xCC000000), blurRadius: 8),
      Shadow(color: Color(0x80000000), blurRadius: 2, offset: Offset(1, 1)),
    ];
    final ic = Icon(
      icon,
      color: Colors.white,
      size: iconSize,
      shadows: shadows,
    );
    final btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: iconSize + 4,
        height: iconSize + 8,
        // Icon RATA KANAN dalam kotak → glyph terakhir menempel tepi layar.
        child: Align(alignment: Alignment.centerRight, child: ic),
      ),
    );
    // Tooltip MENambah margin 4px + padding 8px → tombol terdorong dari tepi.
    // Hapus Tooltip supaya glyph menempel tepi layar.
    return btn;
  }
}
