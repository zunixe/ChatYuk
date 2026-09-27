/// Pengelompokan baris device (admin tab Perangkat) — MURNI & teruji.
///
/// Tiap baris `user_devices` (device+user) dikelompokkan per `install_id`;
/// satu device bisa dipakai banyak user. Logika ini sebelumnya terbenam di
/// `admin_devices_tab.dart` (tak teruji) dan dipakai dua kali (group + filter).

/// Kelompokkan baris device per install_id.
/// Tiap grup: brand/model/os/app/ip/last_seen_at + `users[]` (dedupe uid|nick).
List<Map<String, dynamic>> groupByDevice(List<Map<String, dynamic>> rows) {
  final map = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final key = '${r['install_id'] ?? ''}';
    if (key.isEmpty) continue;
    final group = map.putIfAbsent(key, () {
      return {
        'install_id': key,
        'brand': r['brand'],
        'model': r['model'],
        'os_name': r['os_name'],
        'os_version': r['os_version'],
        'app_version': r['app_version'],
        'ip_address': r['ip_address'],
        'last_seen_at': r['last_seen_at'],
        'users': <Map<String, dynamic>>[],
        '_namesHash': <String>{},
      };
    });
    final users = group['users'] as List<Map<String, dynamic>>;
    final seenNicks = group['_namesHash'] as Set<String>;
    final uid = '${r['user_id'] ?? ''}';
    final nick = '${r['nickname'] ?? ''}';
    final pairKey = '$uid|$nick';
    if (!seenNicks.contains(pairKey)) {
      seenNicks.add(pairKey);
      users.add({
        'user_id': r['user_id'],
        'nickname': r['nickname'],
        'is_registered': r['is_registered'],
        'last_seen_at': r['last_seen_at'],
      });
    }
    // last_seen grup = baris terbaru.
    final seen = (r['last_seen_at'] as String?) ?? '';
    final cur = '${group['last_seen_at'] ?? ''}';
    if (seen.compareTo(cur) > 0) group['last_seen_at'] = r['last_seen_at'];
  }
  final list = map.values.toList();
  list.sort(
    (a, b) =>
        '${b['last_seen_at'] ?? ''}'.compareTo('${a['last_seen_at'] ?? ''}'),
  );
  return list;
}

/// Gabungkan daftar SEMUA user (profiles) dengan baris device.
///
/// [users]: baris `admin_stats_users_page` (punya `id` + `nickname`).
/// [devices]: baris `user_devices` (punya `user_id` + info device).
///
/// Tiap user yang PUNYA device → map device (info lengkap, utk DeviceCard).
/// User TANPA device → map ringkas dari data profil (ditandai `_hasDevice`
/// false) supaya tetap TAMPIL di "Per User". Urutan mengikuti [users].
List<Map<String, dynamic>> mergeUsersWithDevices(
  List<Map<String, dynamic>> users,
  List<Map<String, dynamic>> devices,
) {
  // userId → device terbaru (last_seen_at).
  final byUser = <String, Map<String, dynamic>>{};
  for (final d in devices) {
    final uid = '${d['user_id'] ?? ''}';
    if (uid.isEmpty) continue;
    final cur = byUser[uid];
    final curSeen = '${cur?['last_seen_at'] ?? ''}';
    final seen = '${d['last_seen_at'] ?? ''}';
    if (cur == null || seen.compareTo(curSeen) > 0) byUser[uid] = d;
  }
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final u in users) {
    final uid = '${u['id'] ?? u['user_id'] ?? ''}';
    if (uid.isEmpty || !seen.add(uid)) continue;
    final dev = byUser[uid];
    if (dev != null) {
      out.add({...dev, '_nick': '${u['nickname'] ?? dev['nickname'] ?? '?'}', '_hasDevice': true});
    } else {
      out.add({
        'user_id': uid,
        'nickname': u['nickname'],
        'is_registered': u['is_registered'] == true,
        'last_seen_at': u['last_seen'],
        '_nick': '${u['nickname'] ?? '?'}',
        '_hasDevice': false,
      });
    }
  }
  return out;
}

/// Filter grup device: cocokkan device (brand/model/install_id) ATAU salah
/// satu user-nya (nickname/user_id).
List<Map<String, dynamic>> filterDeviceGroups(
  List<Map<String, dynamic>> groups,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return groups;
  return groups.where((g) {
    final brand = '${g['brand'] ?? ''}'.toLowerCase();
    final model = '${g['model'] ?? ''}'.toLowerCase();
    final installId = '${g['install_id'] ?? ''}'.toLowerCase();
    if (brand.contains(q) || model.contains(q) || installId.contains(q)) {
      return true;
    }
    final users = (g['users'] as List<Map<String, dynamic>>? ?? const []);
    return users.any((u) {
      final nick = '${u['nickname'] ?? ''}'.toLowerCase();
      final uid = '${u['user_id'] ?? ''}'.toLowerCase();
      return nick.contains(q) || uid.contains(q);
    });
  }).toList();
}
