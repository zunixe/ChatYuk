import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:permission_handler/permission_handler.dart';

import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';

/// Info izin panggilan gagal — dipakai bersama caller (chat & profil user)
/// dan callee (layar panggilan masuk) supaya perilakunya identik.
///
/// [permanentlyDenied] = true → user sudah menekan "Jangan tanya lagi";
/// dialog OS tak akan muncul lagi, jadi satu-satunya jalan adalah Pengaturan
/// aplikasi → tampilkan tombol "Buka Pengaturan".
void showCallPermissionDialog(
  BuildContext context, {
  required bool video,
  required bool permanentlyDenied,
}) {
  final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
  final message = video ? s.errCallPermissionVideo : s.errCallPermission;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              video ? Icons.videocam_off_rounded : Icons.mic_off_rounded,
              size: 44,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            s.msgCallError,
            style: AppText.bodyStrong,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
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
              if (permanentlyDenied) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    openAppSettings();
                  },
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: Text(s.btnOpenSettings),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}
