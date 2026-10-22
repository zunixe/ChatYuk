part of '../private_chat_message.dart';

// Badge reaksi inline pada bubble (dipisah dari private_chat_message.dart
// agar file utama < 1000 baris). Perilaku tidak berubah.

class _InlineReactionBadge extends StatelessWidget {
  final Map<String, int> counts;
  final VoidCallback? onTap;
  const _InlineReactionBadge({required this.counts, this.onTap});
  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = entries.take(3).map((e) => e.key).join();
    final total = entries.fold<int>(0, (p, e) => p + e.value);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(shown, style: TextStyle(fontSize: AppGlyph.xs)),
          if (total > 1) ...[
            const SizedBox(width: 3),
            Text(
              '$total',
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
      ),
    );
  }
}
