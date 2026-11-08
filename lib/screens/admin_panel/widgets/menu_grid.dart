import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rv;

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../providers/riverpod/admin_provider.dart';
import '../../../widgets/app_gesture.dart';
import '../admin_menu.dart';

/// Strip statistik mini di atas grid menu. Hanya strip ini yang rebuild saat
/// polling stats (select 3 angka), bukan seluruh halaman utama.
class AdminStatsStrip extends StatelessWidget {
  final S s;
  final VoidCallback onTap;
  const AdminStatsStrip({super.key, required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return rv.Consumer(
      builder: (context, ref, _) {
        final v = ref.watch(
          adminProvider.select((a) {
            final st = a.stats;
            return (
              '${st?['total_users'] ?? '-'}',
              '${st?['active_today'] ?? '-'}',
              '${st?['messages_today'] ?? '-'}',
            );
          }),
        );
        return Material(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          child: AppGestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _stat(Icons.people_outline, AppTheme.primary, v.$1,
                      s.statsUsers),
                  _stat(Icons.online_prediction, Colors.green, v.$2,
                      s.statsActive),
                  _stat(Icons.message_outlined, Colors.deepPurple, v.$3,
                      s.statsMsgs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stat(IconData icon, Color color, String value, String label) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: AppText.bodyStrong.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.micro.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu section kategori: judul + grid ikon 4 kolom.
class AdminMenuSection extends StatelessWidget {
  final AdminMenuCategory category;
  final S s;
  final ValueChanged<AdminMenu> onOpen;
  const AdminMenuSection({
    super.key,
    required this.category,
    required this.s,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final menus = adminMenuLayout[category] ?? const <AdminMenu>[];
    final color = adminCategoryColor(category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text(
            adminCategoryLabel(category, s).toUpperCase(),
            style: AppText.label.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        Material(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            // Tinggi sel tetap (bukan aspect ratio) supaya seluruh menu muat
            // satu layar HP tanpa scroll.
            child: GridView(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisExtent: 76,
              ),
              // WAJIB zero: padding null → GridView menambah inset status
              // bar + nav bar (MediaQuery) ke TIAP kartu → ruang kosong besar.
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final m in menus)
                  _AdminMenuTile(
                    icon: adminMenuIcon(m),
                    label: adminMenuLabel(m, s),
                    color: color,
                    onTap: () => onOpen(m),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AdminMenuTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
