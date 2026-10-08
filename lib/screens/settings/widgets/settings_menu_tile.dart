import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Baris menu Pengaturan/Akun: lingkaran ikon 36 + judul + deskripsi +
/// trailing (chevron / switch). Struktur disamakan dengan tile profil lama
/// supaya ikon & teks sejajar rapi satu kolom.
class SettingsMenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? desc;
  final Widget? trailing;

  /// Widget kecil di samping KANAN judul (mis. badge terverifikasi).
  final Widget? titleTrailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  const SettingsMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor = AppTheme.primary,
    this.desc,
    this.trailing,
    this.titleTrailing,
    this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    // Seragam dengan tile Notifikasi: ListTile + lingkaran ikon 36.
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: AppText.bodyStrong.copyWith(color: titleColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (titleTrailing != null) ...[
            const SizedBox(width: 5),
            titleTrailing!,
          ],
        ],
      ),
      subtitle: desc == null
          ? null
          : Text(
              desc!,
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(Icons.chevron_right, color: AppTheme.textSecondary)),
      onTap: onTap,
    );
  }
}
