import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../utils.dart';

class DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final S s;
  final VoidCallback onTap;
  const DeviceCard({
    required this.device,
    required this.s,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nick = '${device['nickname'] ?? '?'}';
    final uid = '${device['user_id'] ?? ''}';
    final brand = '${device['brand'] ?? ''}';
    final model = '${device['model'] ?? ''}';
    final osName = '${device['os_name'] ?? ''}';
    final osVersion = '${device['os_version'] ?? ''}';
    final appVer = '${device['app_version'] ?? ''}';
    final ip = '${device['ip_address'] ?? ''}';
    final active = device['is_active'] == true;
    final registered = device['is_registered'] == true;
    final lastSeen = device['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${device['last_seen_at']}') ?? DateTime.now(),
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
        side: BorderSide(
          color: active
              ? AppTheme.primary.withValues(alpha: 0.35)
              : AppTheme.divider,
        ),
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
                  color: (registered ? AppTheme.primary : AppTheme.accent)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.phone_android,
                  color: registered ? AppTheme.primary : AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nick,
                            style: AppText.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: (active ? Colors.green : AppTheme.textSecondary)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            active ? s.adminDeviceActive : s.adminDeviceInactive,
                            style: AppText.micro.copyWith(
                              color: active
                                  ? Colors.green
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (deviceLabel.isNotEmpty)
                      Text(
                        deviceLabel,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Row(
                      children: [
                        if (osLabel.isNotEmpty) ...[
                          Icon(
                            Icons.phone_iphone,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              osLabel,
                              style: AppText.micro.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (ip.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.lan_outlined,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            ip,
                            style: AppText.micro.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
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
                    '${uid.length >= 8 ? uid.substring(0, 8) : uid}',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                      fontFeatures: const [],
                    ),
                  ),
                  if (appVer.isNotEmpty)
                    Text(
                      'v$appVer',
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                      ),
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
