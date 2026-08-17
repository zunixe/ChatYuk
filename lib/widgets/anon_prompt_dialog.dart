import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../providers/nav_provider.dart';

/// Dialog "lengkapi email" untuk user anon yang mencoba membuat postingan —
/// dipakai FAB "+" (app.dart) dan CTA timeline tab Postinganku.
/// Tampilan mengikuti empty state timeline: ikon di atas, teks rata tengah.
void showAnonPromptDialog(BuildContext context) {
  final s = context.read<LocaleProvider>().s;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(Icons.edit_rounded, size: 48, color: AppTheme.primary),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(Icons.add, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(s.promptCompleteEmailTitle,
                style: AppText.bodyStrong, textAlign: TextAlign.center),
            SizedBox(height: 6),
            Text(
              s.promptCompleteEmailMsg,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(s.btnCancel),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.read<NavProvider>().goTo(3);
                  },
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: Text(s.btnGoProfile),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}