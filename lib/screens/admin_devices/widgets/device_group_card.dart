import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../utils.dart';

class DeviceGroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final S s;
  final VoidCallback onTap;
  const DeviceGroupCard({
    required this.group,
    required this.s,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = '${group['brand'] ?? ''}';
    final model = '${group['model'] ?? ''}';
    final osName = '${group['os_name'] ?? ''}';
    final osVersion = '${group['os_version'] ?? ''}';
    final users = (group['users'] as List<Map<String, dynamic>>? ?? const []);
    final lastSeen = group['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${group['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    final deviceLabel = [
      if (brand.isNotEmpty) brand,
      if (model.isNotEmpty) model,
    ].join(' ').trim();
    final osLabel = [
      if (osName.isNotEmpty) osName,
      if (osVersion.isNotEmpty) osVersion,
    ].join(' ').trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.phone_android,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceLabel.isEmpty ? 'Unknown device' : deviceLabel,
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (osLabel.isNotEmpty)
                      Text(
                        osLabel,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    // Nama user yang pernah login di device ini.
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final u in users)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (u['is_registered'] == true
                                      ? AppTheme.primary
                                      : AppTheme.accent)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${u['nickname'] ?? '?'}',
                              style: AppText.micro.copyWith(
                                color: u['is_registered'] == true
                                    ? AppTheme.primary
                                    : AppTheme.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (lastSeen.isNotEmpty)
                      Text(
                        '${s.adminDeviceLastSeen}: $lastSeen',
                        style: AppText.micro.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${users.length} ${s.adminDeviceCount}',
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
