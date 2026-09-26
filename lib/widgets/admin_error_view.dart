import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../core/admin_err.dart';

/// Layar error admin: ikon + pesan ramah (kategori, bukan exception mentah)
/// + hint opsional + tombol Coba Lagi. Menggantikan salinan identik di
/// tab Perangkat/Terhapus/Monitor Chat/Panel.
class AdminErrorView extends StatelessWidget {
  final S s;
  final AdminErrKind error;
  final VoidCallback onRetry;

  const AdminErrorView({
    super.key,
    required this.s,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final hint = s.adminErrHintOf(error);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
          const SizedBox(height: 8),
          // Kategori ramah (detail exception hanya ke dlog).
          Text(
            s.adminErrTextOf(error),
            style: const TextStyle(color: AppTheme.danger),
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: Text(s.btnRetry)),
        ],
      ),
    );
  }
}
