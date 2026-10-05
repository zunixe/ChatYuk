import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import '../providers/riverpod/nav_provider.dart';

/// Dialog "lengkapi email" untuk user anon yang mencoba aksi terbatas —
/// dipakai FAB "+" (app.dart), CTA timeline tab Postinganku, dan ikon
/// Orang Sekitar (online_users_screen). Tampilan mengikuti empty state
/// timeline: ikon di atas, teks rata tengah.
///
/// [title]/[message] opsional supaya konteksnya pas (posting vs Orang
/// Sekitar dsb) tanpa menduplikasi form/dialog. Default = konteks posting.
void showAnonPromptDialog(
  BuildContext context, {
  String? title,
  String? message,
  IconData icon = Icons.edit_rounded,
}) {
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
                Icon(icon, size: 48, color: AppTheme.primary),
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
            Text(
              title ?? s.promptCompleteEmailTitle,
              style: AppText.bodyStrong,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6),
            Text(
              message ?? s.promptCompleteEmailMsg,
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
                    ProviderScope.containerOf(context, listen: false).read(navProvider.notifier).goTo(3);
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
