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
  // 4 kunci user dimuat ber-paginasi (RPC admin_stats_users_page) supaya
  // sheet tidak menarik full list profiles; kunci lain (rooms/messages)
  // kecil & teragregasi → tetap dari detail seperti dulu.
  const userKinds = {
    'users_all': 'all',
    'users_active': 'active',
    'users_registered': 'registered',
    'users_anonymous': 'anonymous',
  };
  const pageSize = 100;
  final userKind = userKinds[key];
  var list = <dynamic>[];
  var total = 0;
  var loadingMore = false;
  if (userKind != null) {
    final first = await admin.listStatsUsers(userKind, limit: pageSize);
    if (!context.mounted) return;
    list = (first['items'] as List<dynamic>?) ?? const [];
    total = (first['total'] as num?)?.toInt() ?? list.length;
  } else {
    list = (detail[key] as List<dynamic>?) ?? const [];
    total = list.length;
  }

  // Dipanggil dari scroll listener di dalam setSheet (agar rebuild),
  // dan dari refresh flow. Mengembalikan true bila list bertambah.
  Future<bool> loadMore() async {
    if (userKind == null || loadingMore || list.length >= total) return false;
    loadingMore = true;
    final res = await admin.listStatsUsers(
      userKind,
      limit: pageSize,
      offset: list.length,
    );
    final before = list.length;
    list = [
      ...list,
      ...((res['items'] as List<dynamic>?) ?? const []),
    ];
    total = (res['total'] as num?)?.toInt() ?? total;
    loadingMore = false;
    return list.length > before;
  }

  // Refresh manual di dalam sheet — list beku saat dibuka + cache
  // provider 60 dtk, tanpa ini daftar (mis. anon) terlihat tidak update.
  var refreshing = false;

  Future<void> doRefresh(StateSetter setSheet) async {
    setSheet(() => refreshing = true);
    if (userKind != null) {
      final first = await admin.listStatsUsers(userKind, limit: pageSize);
      if (!context.mounted) return;
      list = (first['items'] as List<dynamic>?) ?? const [];
      total = (first['total'] as num?)?.toInt() ?? list.length;
    } else {
      final d = await admin.fetchStatsDetail(force: true);
      if (!context.mounted) return;
      list = (d[key] as List<dynamic>?) ?? const [];
      total = list.length;
    }
    if (context.mounted) setSheet(() => refreshing = false);
  }

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
                        // Badge EXCLUDED: user tetap tampil (admin lihat semua)
                        // tapi ditandai agar tidak bingung kenapa ter-exclude.
                        if (u['excluded'] == true) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              s.adminExcludedBadge,
                              style: AppText.micro.copyWith(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
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
                    // Titik GPS terakhir user (koordinat presisi dari HP).
                    // HANYA tampil bila loc_source='gps' — supaya koordinat
                    // hasil resolve IP TIDAK salah diberi label "GPS"
                    // (sumber inkonsistensi "GPS aneh"). Sumber IP sudah
                    // tampil di baris lokasi di atas (ikon pin biru).
                    if (hasCoord && '${u['loc_source'] ?? ''}' == 'gps')
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(
                              u['location_mocked'] == true
                                  ? Icons.gpp_bad
                                  : Icons.my_location,
                              size: 12,
                              color: u['location_mocked'] == true
                                  ? AppTheme.danger
                                  : Colors.teal,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                u['location_mocked'] == true
                                    ? '${s.gpsFake}: $lat, $lon'
                                    : '${s.gpsLast}: $lat, $lon',
                                style: AppText.caption.copyWith(
                                  color: u['location_mocked'] == true
                                      ? AppTheme.danger
                                      : Colors.teal,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
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

  // Listener scroll dipasang SEKALI (builder jalan ulang tiap setSheet;
  // pasang di sini akan menumpuk listener + bocor).
  var scrollHooked = false;

      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (ctx, scrollCtrl) => StatefulBuilder(
            builder: (ctx, setSheet) {
              if (!scrollHooked && userKind != null) {
                scrollHooked = true;
                scrollCtrl.addListener(() {
                  // Infinite scroll khusus kunci user (paginasi server).
                  if (!scrollCtrl.hasClients) return;
                  if (scrollCtrl.position.pixels >=
                      scrollCtrl.position.maxScrollExtent - 300) {
                    loadMore().then((grew) {
                      if (grew && ctx.mounted) setSheet(() {});
                    });
                  }
                });
              }
              return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(item.$3, color: item.$4, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.$1} ($total)',
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
                          : () => doRefresh(setSheet),
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
                        itemCount: list.length + (loadingMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= list.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            );
                          }
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
          );
            },
      ),
        ),
      );
    },
  );
}
