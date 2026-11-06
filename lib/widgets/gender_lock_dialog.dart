import 'package:flutter/material.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';

/// Dialog konfirmasi gender — dipakai saat registrasi & edit profil.
///
/// Gender hanya bisa dipilih SEKALI dan terkunci permanen di server
/// (trigger `guard_gender_lock`). Dialog ini memastikan user sadar sebelum
/// menyimpan.
///
/// Mengembalikan `true` bila user menekan tombol konfirmasi.
Future<bool> confirmGenderLock(
  BuildContext context, {
  required String gender, // 'male' | 'female'
  bool isRegister = false,
}) async {
  final s = S(isId: AppLocale.isId);
  final label = gender == 'female' ? s.labelGenderFemale : s.labelGenderMale;
  final emoji = gender == 'female' ? '👩' : '👨';

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.genderLockTitle,
              style: AppText.title.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.genderLockWarning,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bgInput,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              s.genderLockCurrent(label),
              style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            s.genderCancel,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            isRegister ? s.genderLockConfirmRegister : s.genderLockConfirmYes,
            style: AppText.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  // Emoji dipakai agar pemanggil bisa menampilkan label bila perlu.
  assert(emoji.isNotEmpty);
  return ok == true;
}
