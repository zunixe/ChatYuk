import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';

/// Badge status lokasi user di daftar admin "Per User":
///   - **GPS asli**  → ada `lat_gps` & tidak ter-flag `location_mocked`.
///   - **Fake GPS**  → `location_mocked = true` (emulator/static/shared/spoof).
///   - **IP saja**   → tidak ada GPS (lokasi cuma perkiraan IP).
///   - null          → tidak ada data lokasi sama sekali (tak tampil).
///
/// [device] = baris user (hasil `admin_stats_users_page`), punya kunci:
/// `location_mocked`, `lat_gps`, `loc_source`.
class GpsBadge extends StatelessWidget {
  final Map<String, dynamic> device;
  final S s;

  const GpsBadge({super.key, required this.device, required this.s});

  @override
  Widget build(BuildContext context) {
    final mocked = device['location_mocked'] == true;
    final hasGps = device['lat_gps'] != null;
    final source = '${device['loc_source'] ?? ''}';

    late final Color color;
    late final IconData icon;
    late final String label;

    if (mocked) {
      color = AppTheme.danger;
      icon = Icons.warning_amber_rounded;
      final reason = '${device['location_mock_reason'] ?? ''}'.trim();
      label = reason.isEmpty
          ? s.adminGpsFake
          : '${s.adminGpsFake} · $reason';
    } else if (hasGps) {
      color = AppTheme.online;
      icon = Icons.gps_fixed_rounded;
      label = s.adminGpsReal;
    } else if (source == 'ip') {
      color = AppTheme.idle;
      icon = Icons.public_rounded;
      label = s.adminGpsIpOnly;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.micro.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
