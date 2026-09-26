import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Baris "label: nilai" untuk sheet detail (admin: profil/device/arsip,
/// user: info profil). Menggantikan salinan `_kv` yang berulang.
///
/// [labelWidth] null → label `Expanded` (nilai di kanan, gaya
/// storage/tabel). Diisi → label lebar tetap (nilai di bawah/kanan,
/// gaya detail sheet).
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final double? labelWidth;
  final EdgeInsets padding;

  const DetailRow(
    this.label,
    this.value, {
    super.key,
    this.labelWidth,
    this.padding = const EdgeInsets.symmetric(vertical: 2),
  });

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      style: labelWidth == null
          ? AppText.bodySmall.copyWith(color: AppTheme.textSecondary)
          : AppText.caption.copyWith(color: AppTheme.textSecondary),
    );
    if (labelWidth == null) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: labelText),
            Text(value, style: AppText.bodySmall),
          ],
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: labelWidth, child: labelText),
          Expanded(child: Text(value, style: AppText.bodySmall)),
        ],
      ),
    );
  }
}
