import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';

const kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏', '😁'];

const kMoreReactions = [
  '😍',
  '😭',
  '👏',
  '🎉',
  '🔥',
  '💯',
  '🤔',
  '😎',
  '🥳',
  '👎',
  '💔',
  '🤣',
  '😅',
  '🙌',
  '👀',
  '💪',
];

class ReactionBar extends StatelessWidget {
  final void Function(String emoji) onReact;
  final VoidCallback? onMore;
  const ReactionBar({super.key, required this.onReact, this.onMore});

  @override
  Widget build(BuildContext context) {
    // Beda dari bubble chat: tint biru seleksi + border primary, supaya
    // jelas ini toolbar reaksi (nyambung dengan border bubble terpilih
    // dan header seleksi), bukan bubble pesan. bgCard polos bikin bingung
    // karena sama persis dengan warna bubble lawan.
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          AppTheme.primary.withValues(alpha: 0.14),
          AppTheme.bgCard,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        // Kunci dekorasi teks: emoji di overlay sempat mewarisi garis bawah
        // (double, kuning) dari style default konteks overlay di HP — paksa
        // none supaya bar reaksi bersih seperti WA.
        child: DefaultTextStyle(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in kQuickReactions)
              GestureDetector(
                onTap: () => onReact(e),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    e,
                    style: TextStyle(fontSize: AppGlyph.lg),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () {
                if (onMore != null) {
                  onMore!();
                } else {
                  showMoreReactions(context, onReact);
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

Future<void> showMoreReactions(
  BuildContext context,
  void Function(String emoji) onReact,
) async {
  final s = context.read<LocaleProvider>().s;
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.btnEmoji, style: AppText.bodyStrong),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: kMoreReactions.length,
              itemBuilder: (_, i) {
                final e = kMoreReactions[i];
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    onReact(e);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Text(
                      e,
                      style: TextStyle(fontSize: AppGlyph.md),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class ReactionBadge extends StatelessWidget {
  final Map<String, int> counts;
  final bool isMe;
  const ReactionBadge({super.key, required this.counts, required this.isMe});

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = entries.take(3).map((e) => e.key).join();
    final total = entries.fold<int>(0, (p, e) => p + e.value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
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
          Text(shown, style: TextStyle(fontSize: AppGlyph.sm)),
          if (total > 1) ...[
            const SizedBox(width: 3),
            Text(
              '$total',
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
