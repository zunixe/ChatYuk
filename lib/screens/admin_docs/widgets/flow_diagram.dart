import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/theme.dart';

/// Diagram alur gaya ASCII — monospace, scroll horizontal (art lebar),
/// bisa disalin (long-press) supaya dev bisa tempel ke chat/issue.
class FlowDiagram extends StatelessWidget {
  final String title;
  final String art;
  final String hint;
  final IconData icon;
  final Color color;

  const FlowDiagram({
    super.key,
    required this.title,
    required this.art,
    required this.hint,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header diagram: ikon + judul + tombol salin.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: AppText.bodyStrong.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                _CopyButton(text: art, hint: hint),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Judul + hint scroll.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  Icons.swipe_rounded,
                  size: 13,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hint,
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Area art: scroll horizontal + selectable + salin.
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.bgInput,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                art,
                style: AppText.micro.copyWith(
                  color: AppTheme.textPrimary,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tombol kecil untuk menyalin isi diagram ke clipboard.
class _CopyButton extends StatelessWidget {
  final String text;
  final String hint;
  const _CopyButton({required this.text, required this.hint});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(hint),
              duration: const Duration(seconds: 2),
            ),
          );
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.copy_rounded,
          size: 16,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
