import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../utils.dart';

class DeletedCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final S s;
  final String reasonLabel;
  final VoidCallback onTap;
  const DeletedCard({
    required this.entry,
    required this.s,
    required this.reasonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nick = '${entry['nickname'] ?? '?'}';
    final email = '${entry['email'] ?? ''}';
    final registered = entry['is_registered'] == true;
    final deletedAt = entry['deleted_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${entry['deleted_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    final lastSeen = entry['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${entry['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.divider),
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
                child: Center(
                  child: Text(
                    nick.isNotEmpty ? nick[0].toUpperCase() : '?',
                    style: AppText.bodyStrong.copyWith(
                      color: registered ? AppTheme.primary : AppTheme.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nick,
                      style: AppText.bodyStrong.copyWith(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      [
                        reasonLabel,
                        if (lastSeen.isNotEmpty)
                          '${s.adminDeviceLastSeen}: $lastSeen',
                      ].join(' · '),
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (deletedAt.isNotEmpty)
                    Text(
                      deletedAt,
                      style: AppText.micro.copyWith(
                        color: AppTheme.danger,
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
