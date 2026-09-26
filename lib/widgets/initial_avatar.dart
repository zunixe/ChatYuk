import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Kotak avatar inisial (bukan lingkaran): huruf pertama nama di atas kotak
/// ber-tint. Menggantikan salinan Container serupa di banyak kartu/sheet
/// admin (ukuran & radius berbeda-beda -> parameter).
class InitialAvatarBox extends StatelessWidget {
  final String name;
  final double size;
  final double radius;
  final Color color;
  final TextStyle? textStyle;

  const InitialAvatarBox({
    super.key,
    required this.name,
    this.size = 40,
    this.radius = 10,
    this.color = AppTheme.primary,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Text(
          initial,
          style: textStyle ?? AppText.bodyStrong.copyWith(color: color),
        ),
      ),
    );
  }
}

/// Varian lingkaran (mirror `_PersonAvatar` lama): untuk daftar pilihan
/// kecualian privasi dsb.
class InitialAvatarCircle extends StatelessWidget {
  final String name;
  final double radius;
  final Color color;

  const InitialAvatarCircle({
    super.key,
    required this.name,
    this.radius = 18,
    this.color = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: AppText.label.copyWith(color: color),
      ),
    );
  }
}
