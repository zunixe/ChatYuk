import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Gagang seret di atas bottom-sheet (garis 40x4 radius 2). Menggantikan
/// Container identik yang disalin di banyak sheet admin & user.
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppTheme.textSecondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
