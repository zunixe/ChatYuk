import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../utils.dart';
import 'avatar_circle.dart';

/// Bottom sheet rincian satu kartu statistik: daftar user/room/pesan.
/// [item] = record (judul, subtitle, ikon, warna, key detail).
Future<void> showStatDetailSheet(
  BuildContext context,
  (String, String, IconData, Color, String) item,
) async {
  final admin = context.read<AdminProvider>();
  final s = context.read<LocaleProvider>().s;
  final detail = await admin.fetchStatsDetail();
  if (!context.mounted) return;

  final key = item.$5;
  var list = (detail[key] as List<dynamic>?) ?? const [];
  // Refresh manual di dalam sheet — list beku saat dibuka + cache
  // provider 60 dtk, tanpa ini daftar (mis. anon) terlihat tidak update.
  var refreshing = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgScreen,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      Widget row(String name, String sub, String right) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.$4.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: item.$4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Text(
                right,
                style: AppText.caption.copyWith(
                  color: item.$4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }

      // Baris khusus user: tampilkan IP + link Google Maps berdasar lokasi.
      // Avatar + ikon mengikuti gender ala Pengguna Online (biru/pink).
      Widget userRow(Map<String, dynamic> u) {
        final name = '${u['nickname'] ?? '?'}';
        final gender = '${u['gender'] ?? ''}';
        final gColor = gender == 'male'
            ? AppTheme.male
            : gender == 'female'
            ? AppTheme.female
            : item.$4;
        final email = '${u['email'] ?? ''}';
        final ip = '${u['ip_address'] ?? ''}';
        final city = '${u['city'] ?? ''}';
        final country = '${u['country'] ?? ''}';
        final lat = (u['lat'] as num?)?.toDouble();
        final lon = (u['lon'] as num?)?.toDouble();
        final sub = [
          if ((u['age'] ?? 0) > 0) '${u['age']}',
          if (country.isNotEmpty) country,
          if (city.isNotEmpty) city,
          (u['is_registered'] == true) ? 'registered' : 'anon',
        ].join(' · ');
        final lastSeen = u['last_seen'] != null
            ? formatRelativeTime(
                DateTime.tryParse('${u['last_seen']}') ?? DateTime.now(),
                isId: s.isId,
              )
            : '';
        // Prioritas: koordinat presisi (lat/lon) → pin tepat di Maps.
        // Fallback: search kota+negara kalau koordinat belum ada.
        final hasCoord = lat != null && lon != null;
        final mapsUrl = hasCoord
            ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lon'
            : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent([city, country].where((e) => e.isNotEmpty).join(', '))}';
        final canMap = hasCoord || city.isNotEmpty || country.isNotEmpty;
        // Label lokasi: koordinat presisi (lat, lon) kalau ada, tanpa
        // embel-embel 'approx'.
        final locLabel = hasCoord ? '$lat, $lon' : s.adminViewOnMaps;
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminAvatarCircle(
                uid: '${u['id'] ?? ''}',
                name: name,
                color: gColor,
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
                            name,
                            style: AppText.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (gender == 'male' || gender == 'female') ...[
                          const SizedBox(width: 4),
                          Icon(
                            gender == 'male'
                                ? Icons.male
                                : Icons.female,
                            size: 15,
                            color: gColor,
                          ),
                        ],
                      ],
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (email.isNotEmpty && email != 'null')
                      Row(
                        children: [
                          Icon(
                            Icons.alternate_email,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              email,
                              style: AppText.caption.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        if (ip.isNotEmpty) ...[
                          Icon(
                            Icons.lan_outlined,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          SizedBox(width: 3),
                          Text(
                            ip,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                        if (ip.isNotEmpty && canMap) const SizedBox(width: 8),
                        if (canMap)
                          InkWell(
                            onTap: () => launchUrl(
                              Uri.parse(mapsUrl),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  size: 12,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  locLabel,
                                  style: AppText.caption.copyWith(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                lastSeen,
                style: AppText.caption.copyWith(
                  color: item.$4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }

      // Baris khusus pesan hari ini (avatar + ikon gender Pengguna Online).
      Widget msgRow(Map<String, dynamic> m) {
        final sender = '${m['sender_name'] ?? '?'}';
        final senderGender = '${m['sender_gender'] ?? ''}';
        final sgColor = senderGender == 'male'
            ? AppTheme.male
            : senderGender == 'female'
            ? AppTheme.female
            : item.$4;
        final text = '${m['text'] ?? ''}';
        final t = m['created_at'] != null
            ? formatRelativeTime(
                DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
                isId: s.isId,
              )
            : '';
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminAvatarCircle(
                uid: '${m['sender_id'] ?? ''}',
                name: sender,
                color: sgColor,
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
                            sender,
                            style: AppText.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (senderGender == 'male' ||
                            senderGender == 'female') ...[
                          const SizedBox(width: 4),
                          Icon(
                            senderGender == 'male'
                                ? Icons.male
                                : Icons.female,
                            size: 15,
                            color: sgColor,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      text,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                t,
                style: AppText.caption.copyWith(
                  color: item.$4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }

      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (ctx, scrollCtrl) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(item.$3, color: item.$4, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.$1} (${list.length})',
                        style: AppText.titleEmphasis,
                      ),
                    ),
                    IconButton(
                      icon: refreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      tooltip: s.btnRefresh,
                      onPressed: refreshing
                          ? null
                          : () async {
                              setSheet(() => refreshing = true);
                              final d =
                                  await admin.fetchStatsDetail(force: true);
                              if (ctx.mounted) {
                                setSheet(() {
                                  list =
                                      (d[key] as List<dynamic>?) ?? const [];
                                  refreshing = false;
                                });
                              }
                            },
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Divider(height: 1),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                          s.adminNoUsers,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        // Builder = baris (termasuk fetch avatar) hanya
                        // jalan untuk viewport yang tampil → lazy & ringan.
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          if (key == 'rooms_active') {
                            final r = list[i] as Map<String, dynamic>;
                            return row(
                              '${r['room_name'] ?? r['room_id'] ?? '?'}',
                              (r['is_private'] == true)
                                  ? s.roomPrivateLabel
                                  : '',
                              '${r['user_count'] ?? 0} ${s.roomOnlineCount}',
                            );
                          }
                          if (key == 'messages_today') {
                            return msgRow(
                              list[i] as Map<String, dynamic>,
                            );
                          }
                          return userRow(
                            list[i] as Map<String, dynamic>,
                          );
                        },
                      ),
              ),
            ],
          ),
      ),
        ),
      );
    },
  );
}
