import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../utils/bounded_cache.dart';
import '../../../config/theme.dart';
import '../../../providers/locale_provider.dart';

class NearbyCard extends StatelessWidget {
  /// Cache bytes avatar (bounded) — dipindah dari nearby_screen.
  static final avatarBytesCache = BoundedCache<String, Uint8List>(80);

  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const NearbyCard({required this.data, required this.onTap});

  Color _statusColor(String status) => AppTheme.statusColor(status);

  String _distanceLabel(dynamic s, double km) {
    if (km < 1) return s.nearbyDistanceM((km * 1000).round());
    return s.nearbyDistanceKm(km.toStringAsFixed(1));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
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

    final avatarBytes = avatar.isNotEmpty
        ? avatarBytesCache.putIfAbsent(avatar, () {
            try {
              return base64Decode(avatar);
            } catch (_) {
              return Uint8List(0);
            }
          })
        : null;
    final hasAvatar = avatarBytes?.isNotEmpty == true;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
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
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.15),
                        border: Border.all(color: color, width: 1.5),
                        image: hasAvatar
                            ? DecorationImage(
                                // Kartu 44px — cap decode biar tidak
                                // raster avatar penuh.
                                image: ResizeImage(MemoryImage(avatarBytes!),
                                    width: 96),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: hasAvatar
                          ? null
                          : Center(
                              child: Text(
                                nickname.isNotEmpty
                                    ? nickname[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: color,
                                  fontSize: AppGlyph.avatarInitial(44),
                                  fontWeight: FontWeight.w700,
                                ),
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
                            Icon(
                              Icons.verified,
                              size: 15,
                              color: Color(0xFF4A90E2),
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
