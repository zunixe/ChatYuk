import 'package:flutter/material.dart';

import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../config/theme.dart';
import '../../../utils.dart';

/// Waktu statistik admin terakhir di-refresh. Diisi hub (polling 60 dtk) dan
/// halaman Ringkasan/YukCoin (pull-to-refresh) — dibaca header semua halaman
/// statistik supaya tetap sinkron walau tiap menu kini route terpisah.
final adminStatsUpdatedAt = ValueNotifier<DateTime?>(null);

void markAdminStatsUpdated() => adminStatsUpdatedAt.value = DateTime.now();

/// Banner tipis saat kegagalan terakhir karena koneksi TAPI data lama masih
/// ada — user tetap melihat datanya, bukan layar error.
class AdminStaleBanner extends StatelessWidget {
  final S s;
  const AdminStaleBanner({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: AppTheme.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.adminErrStaleBanner,
              style: AppText.bodySmall.copyWith(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminLastUpdatedHeader extends StatelessWidget {
  final S s;
  const AdminLastUpdatedHeader({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: adminStatsUpdatedAt,
      builder: (context, ts, _) {
        if (ts == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${s.adminLastUpdate} ${formatRelativeTime(ts, isId: s.isId)}',
            style: AppText.micro.copyWith(color: AppTheme.textSecondary),
          ),
        );
      },
    );
  }
}
