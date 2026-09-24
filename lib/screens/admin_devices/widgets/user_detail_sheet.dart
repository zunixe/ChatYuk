import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../utils.dart';
import '../../admin_chat_view_screen.dart';

/// Bottom sheet detail satu user: profil + semua device + daftar chat +
/// riwayat lokasi.
class UserDetailSheet extends StatefulWidget {
  final Map<String, dynamic> detail;
  final S s;
  const UserDetailSheet({super.key, required this.detail, required this.s});

  @override
  State<UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<UserDetailSheet> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final profile =
        (widget.detail['profile'] as Map<String, dynamic>?) ?? const {};
    final devices =
        (widget.detail['devices'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];
    final chats =
        (widget.detail['chats'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];
    final locHist =
        (widget.detail['location_history'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];

    final nick = '${profile['nickname'] ?? '?'}';
    final uid = '${profile['user_id'] ?? ''}';
    final email = '${profile['email'] ?? ''}';
    final registered = profile['is_registered'] == true;
    final status = '${profile['status'] ?? ''}';
    final ageVal = profile['age'];
    final gender = '${profile['gender'] ?? ''}';
    final city = '${profile['city'] ?? ''}';
    final country = '${profile['country'] ?? ''}';
    final points = '${profile['points'] ?? 0}';
    final ip = '${profile['ip_address'] ?? ''}';
    final isDummy = profile['is_dummy'] == true;

    final lastLogin = profile['login_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${profile['login_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '-';
    final created = profile['created_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${profile['created_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '-';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (registered ? AppTheme.primary : AppTheme.accent)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nick, style: AppText.title),
                        Text(
                          [
                            registered ? s.adminDeviceRegistered : s.adminDeviceAnon,
                            if (isDummy) 'Dummy',
                          ].join(' · '),
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.adminDeviceCopyId,
                    icon: Icon(Icons.copy_rounded, size: 18, color: AppTheme.primary),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: uid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(s.adminDeviceCopied),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _section(s.adminDeviceProfile),
                  _kv(s.adminDeviceUserid, uid),
                  if (email.isNotEmpty) _kv(s.adminDeviceEmail, email),
                  _kv(s.adminDeviceStatus, status),
                  _kv(s.adminDeviceLastLogin, lastLogin),
                  _kv(s.adminDeviceCreated, created),
                  if (ageVal is int && ageVal > 0) _kv(s.adminDeviceAge, '$ageVal'),
                  if (gender.isNotEmpty) _kv(s.adminDeviceGender, gender),
                  if (city.isNotEmpty) _kv(s.adminDeviceCity, '$city, $country'),
                  _kv(s.adminDevicePoints, points),
                  if (ip.isNotEmpty) _kv(s.adminDeviceIp, ip),
                  const SizedBox(height: 12),

                  _section(s.adminDeviceDevices),
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.adminDeviceNoDevices,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (final d in devices) _deviceTile(d),
                  const SizedBox(height: 12),

                  _section(s.adminDeviceChats),
                  if (chats.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.adminDeviceNoChats,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (final c in chats) _chatTile(c, uid),
                  const SizedBox(height: 12),

                  if (locHist.isNotEmpty) ...[
                    _section(s.adminDeviceLocation),
                    for (final l in locHist.take(20)) _locTile(l),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(title, style: AppText.label.copyWith(color: AppTheme.primary)),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(v, style: AppText.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _deviceTile(Map<String, dynamic> d) {
    final brand = '${d['brand'] ?? ''}';
    final model = '${d['model'] ?? ''}';
    final os = [
      '${d['os_name'] ?? ''}',
      '${d['os_version'] ?? ''}',
    ].where((e) => e.isNotEmpty).join(' ');
    final active = d['is_active'] == true;
    final lastSeen = d['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${d['last_seen_at']}') ?? DateTime.now(),
            isId: widget.s.isId,
          )
        : '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? AppTheme.primary.withValues(alpha: 0.35)
              : AppTheme.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.phone_android,
            size: 16,
            color: active ? AppTheme.primary : AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [brand, model].where((e) => e.isNotEmpty).join(' '),
                  style: AppText.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (os.isNotEmpty)
                  Text(
                    os,
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                if (lastSeen.isNotEmpty)
                  Text(
                    '${widget.s.adminDeviceLastSeen}: $lastSeen',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: (active ? Colors.green : AppTheme.textSecondary)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              active
                  ? widget.s.adminDeviceActive
                  : widget.s.adminDeviceInactive,
              style: AppText.micro.copyWith(
                color: active ? Colors.green : AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatTile(Map<String, dynamic> c, String selfUid) {
    final names = (c['participant_names'] as Map<dynamic, dynamic>?) ?? {};
    final participants = (c['participants'] as List<dynamic>?) ?? const [];
    String otherName = '';
    for (final p in participants) {
      if ('$p' != selfUid) {
        otherName = '${names['$p'] ?? ''}';
        break;
      }
    }
    if (otherName.isEmpty) {
      otherName = names.values
          .where((e) => e != null && '$e'.isNotEmpty)
          .map((e) => '$e')
          .join(', ');
    }
    final lastMsg = '${c['last_message'] ?? ''}'.trim();
    final lastAt = c['last_message_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${c['last_message_at']}') ?? DateTime.now(),
            isId: widget.s.isId,
          )
        : '';
    final chatId = '${c['chat_id'] ?? ''}';
    final orderUids = participants.map((p) => '$p').toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: chatId.isEmpty
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminChatViewScreen(
                      chatId: chatId,
                      chatLabel: otherName.isEmpty ? 'Chat' : otherName,
                      participantOrder: orderUids,
                    ),
                  ),
                );
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      otherName.isEmpty ? 'Chat' : otherName,
                      style: AppText.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (lastMsg.isNotEmpty)
                      Text(
                        lastMsg,
                        style: AppText.micro.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (lastAt.isNotEmpty)
                Text(
                  lastAt,
                  style: AppText.micro.copyWith(color: AppTheme.textSecondary),
                ),
              Icon(Icons.chevron_right, size: 18, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locTile(Map<String, dynamic> l) {
    final lat = '${l['lat'] ?? ''}';
    final lon = '${l['lon'] ?? ''}';
    final source = '${l['source'] ?? ''}';
    final at = l['at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${l['at']}') ?? DateTime.now(),
            isId: widget.s.isId,
          )
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.place_outlined, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(
            '$lat, $lon',
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const Spacer(),
          if (source.isNotEmpty)
            Text(
              source,
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          if (at.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              at,
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
