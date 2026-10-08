import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;

import '../../../config/theme.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/verified_badge.dart';

class NearbyCard extends ConsumerWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const NearbyCard({super.key, required this.data, required this.onTap});

  Color _statusColor(String status) => AppTheme.statusColor(status);

  String _distanceLabel(dynamic s, double km) {
    if (km < 1) return s.nearbyDistanceM((km * 1000).round());
    return s.nearbyDistanceKm(km.toStringAsFixed(1));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final nickname = '${data['nickname'] ?? ''}';
    final gender = '${data['gender'] ?? ''}';
    final age = (data['age'] as num?)?.toInt() ?? 0;
    final city = '${data['city'] ?? ''}';
    final country = '${data['country'] ?? ''}';
    final status = '${data['status'] ?? 'online'}';
    final avatar = '${data['avatar'] ?? ''}';
    final isRegistered = data['is_registered'] == true;
    final distanceKm = (data['distance_km'] as num?)?.toDouble() ?? 0;
    final color = gender == 'male'
        ? AppTheme.male
        : gender == 'female'
        ? AppTheme.female
        : AppTheme.accent;
    final genderLabel = gender == 'male'
        ? s.genderMale
        : gender == 'female'
        ? s.genderFemale
        : s.genderOther;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        // Tanpa boxShadow blur & tanpa border: shadow per-kartu mahal saat
        // scroll (satu operasi blur GPU per kartu). Pemisahan kartu cukup dari
        // kontras warna bgCard di atas bgScreen — hemat, visual tetap rapi.
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Stack(
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.15),
                        ),
                        clipBehavior: Clip.antiAlias,
                        // Avatar modular (user_avatar): sumber bisa base64
                        // ATAU path storage, decode di isolate + cap 96px,
                        // anti-kedip — sama seperti daftar Pengguna Online.
                        child: UserAvatar(
                          key: ValueKey('${data['id'] ?? nickname}'),
                          uid: '${data['id'] ?? ''}',
                          avatarB64: avatar,
                          initial: nickname.isNotEmpty
                              ? nickname[0].toUpperCase()
                              : '?',
                          color: color,
                          borderColor: color,
                          borderWidth: 1.5,
                          // Ring "disamarkan" (transparan) saat foto tampil —
                          // kontrak kartu Nearby (lihat widgets_nearby_ring_test).
                          keepRingForPhoto: true,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _statusColor(status),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nickname,
                              style: AppText.bodyStrong,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isRegistered) ...[
                            SizedBox(width: 4),
                            VerifiedBadgeForUid(
                              uid: '${data['uid'] ?? ''}',
                              size: 15,
                              tooltip: s.phoneVerifiedBadge,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '$genderLabel $age · $city, $country',
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 12,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _distanceLabel(s, distanceKm),
                            style: AppText.caption.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
