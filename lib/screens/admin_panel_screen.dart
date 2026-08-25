import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as lpn;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../config/supabase_config.dart';
import '../providers/admin_provider.dart';
import '../providers/points_provider.dart';
import '../providers/locale_provider.dart';
import '../services/admin_service.dart';
import '../services/geo_service.dart';
import '../utils.dart';
import 'admin_chat_list_screen.dart';
import 'admin_contact_tab.dart';
import 'admin_devices_tab.dart';
import 'admin_deleted_tab.dart';
import 'admin_dummy_tab.dart';
import 'admin_global_setting_tab.dart';
import '../providers/theme_provider.dart';
import '../main.dart' show localNotifications;

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _bonusCtrl = TextEditingController(text: '100');
  final _logoutCtrl = TextEditingController();
  Timer? _statsTimer;
  Timer? _notifyTimer;
  StreamSubscription<String>? _notifSub;
  DateTime? _lastUpdated;

  // Pengaturan nominal poin (diambil dari server, diedit admin).
  final Map<String, TextEditingController> _pointCtrls = {};
  final _shareUrlCtrl = TextEditingController();
  bool _pointSettingsLoaded = false;
  bool _savingPointSettings = false;

  // Urutan & label field pengaturan poin.
  static const List<(String, String)> _pointFields = [
    ('photo_upload_reward', 'Reward upload foto (slot 2-6)'),
    ('photo_unlock_once', 'Buka foto: lihat sekali'),
    ('photo_unlock_perm', 'Buka foto: permanen'),
    ('photo_unlock_owner_pct', '% ke pemilik foto'),
    ('bonus_registered', 'Bonus daftar email'),
    ('bonus_rated', 'Bonus rating app'),
    ('bonus_shared', 'Bonus share app'),
    ('bonus_profile', 'Bonus profil lengkap'),
    ('bonus_first_photo', 'Bonus foto pertama'),
    ('bonus_room_read', 'Bonus baca room'),
    ('bonus_new_chat', 'Bonus chat orang baru'),
    ('bonus_invited', 'Bonus invite teman'),
    ('bonus_first_room', 'Bonus room chat pertama'),
    ('bonus_referral', 'Bonus referral install'),
    ('bonus_online_5min', 'Bonus online 5 menit'),
    ('bonus_online_30min', 'Bonus online 30 menit'),
    ('bonus_online_60min', 'Bonus online 60 menit'),
    ('bonus_online_120min', 'Bonus online 120 menit'),
    ('bonus_price_multiplier', 'Pengali harga tier bonus'),
    ('room_create_paid', 'Buat room (paid)'),
    ('room_create_pw_paid', 'Buat room +password (paid)'),
    ('room_join_paid', 'Join room (paid)'),
    ('room_extend_paid', 'Perpanjang room (paid)'),
    ('room_reads_daily_limit', 'Limit baca room / hari'),
    ('new_chats_daily_limit', 'Limit chat baru / hari'),
    ('subscribe_cut_pct', 'Potongan subscribe (%)'),
    ('subscription_duration_days', 'Durasi subscribe (hari)'),
    ('cost_chat_text', 'Biaya kirim teks'),
    ('cost_chat_image', 'Biaya kirim foto'),
    ('cost_view_once', 'Biaya kirim view-once'),
    ('share_click_reward', 'Reward per klik link share'),
    ('share_click_cap_daily', 'Maks reward klik/hari'),
  ];

  @override
  void initState() {
    super.initState();
    final admin = context.read<AdminProvider>();
    Future.microtask(() => admin.fetchStats());
    _loadPointSettings();
    // Notifikasi device baru / video call aktif.
    // Arm DULU (muat seen + seed device eksisting tanpa notifikasi),
    // baru mulai polling — mencegah notifikasi palsu saat pertama buka.
    unawaited(
      admin.armNotifications().then((_) => _startNotifyPolling()),
    );
    _notifSub = admin.notifications.listen((msg) => _showAdminNotification(msg));
    // Polling ringan → angka statistik selalu segar tanpa loading flash.
    _statsTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollStats(),
    );
  }

  void _startNotifyPolling() {
    if (!mounted) return;
    _notifyTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final a = context.read<AdminProvider>();
      a.fetchDevices();
      a.fetchActiveCalls();
    });
  }

  Future<void> _showAdminNotification(String msg) async {
    if (!mounted) return;
    // Notifikasi sistem (bisa dilihat walau admin lagi di tab lain).
    try {
      await localNotifications.show(
        id: 9991,
        title: 'ChatYuk Admin',
        body: msg,
        notificationDetails: lpn.NotificationDetails(
          android: lpn.AndroidNotificationDetails(
            'admin_alerts',
            'ChatYuk Admin Alerts',
            channelDescription: 'Device baru & video call aktif',
            importance: lpn.Importance.high,
            priority: lpn.Priority.high,
          ),
        ),
      );
    } catch (_) {}
    if (!mounted) return;
    // Snackbar di layar panel.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<void> _loadPointSettings() async {
    try {
      final data = await AdminService(SupabaseConfig.client).getPointSettings();
      for (final f in _pointFields) {
        _pointCtrls[f.$1] = TextEditingController(text: '${data[f.$1] ?? ''}');
      }
      _shareUrlCtrl.text = '${data['share_url'] ?? ''}';
      if (mounted) setState(() => _pointSettingsLoaded = true);
    } catch (e) {
      debugPrint('[ADMIN] loadPointSettings error: $e');
    }
  }

  Future<void> _savePointSettings() async {
    setState(() => _savingPointSettings = true);
    try {
      final payload = <String, dynamic>{'share_url': _shareUrlCtrl.text.trim()};
      for (final e in _pointCtrls.entries) {
        final v = int.tryParse(e.value.text.trim());
        if (v != null) payload[e.key] = v;
      }
      await AdminService(SupabaseConfig.client).updatePointSettings(payload);
      _toast('Pengaturan poin tersimpan');
    } catch (e) {
      _toast('Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _savingPointSettings = false);
    }
  }

  Future<void> _pollStats() async {
    final admin = context.read<AdminProvider>();
    await admin.refreshStats();
    if (mounted) setState(() => _lastUpdated = DateTime.now());
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _notifyTimer?.cancel();
    _notifSub?.cancel();
    _bonusCtrl.dispose();
    _logoutCtrl.dispose();
    _shareUrlCtrl.dispose();
    for (final c in _pointCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final admin = context.watch<AdminProvider>();
    final s = context.watch<LocaleProvider>().s;
    final stats = admin.stats;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppTheme.bgScreen,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings,
                size: 20,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(s.adminPanel),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.refresh_rounded,
                size: 20,
                color: AppTheme.primary,
              ),
              onPressed: () async {
                await admin.fetchStats();
                if (mounted) setState(() => _lastUpdated = DateTime.now());
              },
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            labelStyle: AppText.bodySmall.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            unselectedLabelStyle: AppText.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              Tab(text: s.adminGlobalSettingTab),
              Tab(text: s.adminOverview),
              Tab(text: s.adminPointTab),
              Tab(text: s.adminChatMonitor),
              Tab(text: s.adminDummyTab),
              Tab(text: s.adminContactTab),
              Tab(text: s.adminDeviceTab),
              Tab(text: s.adminDeletedTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const AdminGlobalSettingTab(),
            admin.loading
                ? const Center(child: CircularProgressIndicator())
                : admin.error != null
                ? _errorView(admin, s)
                : RefreshIndicator(
                    onRefresh: () async {
                      await admin.fetchStats();
                      if (mounted)
                        setState(() => _lastUpdated = DateTime.now());
                    },
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        MediaQuery.of(context).padding.bottom + 24,
                      ),
                      children: [
                        _lastUpdatedHeader(s),
                        const SizedBox(height: 8),
                        _statsGrid(stats, s),
                        const SizedBox(height: 12),
                        _StorageUsageCard(),
                        const SizedBox(height: 12),
                        const _RegistrationsChartCard(),
                        const SizedBox(height: 12),
                        _UserMapCard(),
                        const SizedBox(height: 12),
                        _reportedUsers(stats, s),
                        const SizedBox(height: 12),
                        _forceLogout(s),
                        const SizedBox(height: 12),
                        _dangerZone(admin, s),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
            admin.loading
                ? const Center(child: CircularProgressIndicator())
                : admin.error != null
                ? _errorView(admin, s)
                : RefreshIndicator(
                    onRefresh: () async {
                      await admin.fetchStats();
                      if (mounted)
                        setState(() => _lastUpdated = DateTime.now());
                    },
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        MediaQuery.of(context).padding.bottom + 24,
                      ),
                      children: [
                        _lastUpdatedHeader(s),
                        const SizedBox(height: 8),
                        _pointStats(stats, s),
                        const SizedBox(height: 12),
                        _controls(admin, s),
                        const SizedBox(height: 12),
                        _pointSettingsCard(s),
                        const SizedBox(height: 12),
                        _topEarners(stats, s),
                        const SizedBox(height: 12),
                        _massBonus(admin, s),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
            const AdminChatListScreen(),
            const AdminDummyTab(),
            const AdminContactTab(),
            const AdminDevicesTab(),
            const AdminDeletedTab(),
          ],
        ),
      ),
    );
  }

  Widget _errorView(AdminProvider admin, S s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
          const SizedBox(height: 8),
          Text(admin.error!, style: const TextStyle(color: AppTheme.danger)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => admin.fetchStats(),
            child: Text(s.btnRetry),
          ),
        ],
      ),
    );
  }

  Widget _lastUpdatedHeader(S s) {
    final ts = _lastUpdated;
    if (ts == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        '${s.adminLastUpdate} ${formatRelativeTime(ts, isId: s.isId)}',
        style: AppText.micro.copyWith(color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _statsGrid(Map<String, dynamic>? stats, S s) {
    final items = [
      (
        s.statsUsers,
        '${stats?['total_users'] ?? '-'}',
        Icons.people_outline,
        AppTheme.primary,
        'users_all',
      ),
      (
        s.statsActive,
        '${stats?['active_today'] ?? '-'}',
        Icons.online_prediction,
        Colors.green,
        'users_active',
      ),
      (
        s.statsMsgs,
        '${stats?['messages_today'] ?? '-'}',
        Icons.message_outlined,
        Colors.deepPurple,
        'messages_today',
      ),
      (
        s.statsRooms,
        '${stats?['rooms_active'] ?? '-'}',
        Icons.chat_bubble_outline,
        Colors.teal,
        'rooms_active',
      ),
      (
        s.statsReg,
        '${stats?['registered_users'] ?? '-'}',
        Icons.verified_outlined,
        Colors.blue,
        'users_registered',
      ),
      (
        s.statsAnon,
        '${stats?['anonymous_users'] ?? '-'}',
        Icons.person_outline,
        Colors.orange,
        'users_anonymous',
      ),
    ];
    Widget cell(int i) {
      return Expanded(
        child: Material(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: items[i].$5.isEmpty
                ? null
                : () => _showStatDetail(context, items[i]),
            child: Container(
              height: 76,
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(items[i].$3, size: 15, color: items[i].$4),
                  SizedBox(height: 5),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        items[i].$2,
                        style: AppText.titleEmphasis.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    items[i].$1,
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            cell(0),
            const SizedBox(width: 8),
            cell(1),
            const SizedBox(width: 8),
            cell(2),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            cell(3),
            const SizedBox(width: 8),
            cell(4),
            const SizedBox(width: 8),
            cell(5),
          ],
        ),
      ],
    );
  }

  Widget _pointStats(Map<String, dynamic>? stats, S s) {
    final items = [
      (
        s.statsAvg,
        '${stats?['avg_points'] ?? '-'}',
        Icons.trending_up,
        Colors.amber.shade700,
      ),
      (
        s.statsTotal,
        '${stats?['total_points'] ?? '-'}',
        Icons.monetization_on_outlined,
        Colors.pink,
      ),
    ];
    Widget cell(int i) {
      return Expanded(
        child: Material(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 76,
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(items[i].$3, size: 15, color: items[i].$4),
                SizedBox(height: 5),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      items[i].$2,
                      style: AppText.titleEmphasis.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  items[i].$1,
                  style: AppText.micro.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [cell(0), const SizedBox(width: 8), cell(1)]),
      ],
    );
  }

  Future<void> _showStatDetail(
    BuildContext context,
    (String, String, IconData, Color, String) item,
  ) async {
    final admin = context.read<AdminProvider>();
    final s = context.read<LocaleProvider>().s;
    final detail = await admin.fetchStatsDetail();
    if (!context.mounted) return;

    final key = item.$5;
    final list = (detail[key] as List<dynamic>?) ?? const [];

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
        Widget userRow(Map<String, dynamic> u) {
          final name = '${u['nickname'] ?? '?'}';
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

        // Baris khusus pesan hari ini.
        Widget msgRow(Map<String, dynamic> m) {
          final sender = '${m['sender_name'] ?? '?'}';
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
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: item.$4.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      sender.isNotEmpty ? sender[0].toUpperCase() : '?',
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
                        sender,
                        style: AppText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            builder: (ctx, scrollCtrl) => Column(
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
                      : ListView(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          children: [
                            if (key == 'users_all' ||
                                key == 'users_active' ||
                                key == 'users_registered' ||
                                key == 'users_anonymous')
                              for (final u in list)
                                userRow(u as Map<String, dynamic>),
                            if (key == 'rooms_active')
                              for (final r in list)
                                row(
                                  '${r['room_name'] ?? r['room_id'] ?? '?'}',
                                  (r['is_private'] == true)
                                      ? s.roomPrivateLabel
                                      : '',
                                  '${r['user_count'] ?? 0} ${s.roomOnlineCount}',
                                ),
                            if (key == 'messages_today')
                              for (final m in list)
                                msgRow(m as Map<String, dynamic>),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _topEarners(Map<String, dynamic>? stats, S s) {
    final earners = (stats?['top_earners'] as List?) ?? [];
    return _card(s.adminTopEarners, Icons.emoji_events_outlined, Colors.amber, [
      if (earners.isEmpty)
        Text(
          s.adminNoUsers,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
      for (var i = 0; i < earners.length && i < 5; i++)
        Padding(
          padding: EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '${i + 1}',
                  style: AppText.caption.copyWith(
                    color: i == 0 ? Colors.amber : AppTheme.textSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${earners[i]['nickname'] ?? '?'}',
                  style: AppText.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${earners[i]['points'] ?? 0} pts',
                  style: AppText.caption.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      if ((stats?['stuck_users'] ?? 0) > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: AppTheme.danger,
              ),
              const SizedBox(width: 4),
              Text(
                '${stats!['stuck_users']} ${s.adminStuckUsers}',
                style: AppText.caption.copyWith(color: AppTheme.danger),
              ),
            ],
          ),
        ),
    ]);
  }

  /// Toggle: tombol call tampil ke semua user (termasuk anon/guest).
  Widget _controls(AdminProvider admin, S s) {
    return _card(
      s.adminPointsSystem,
      Icons.toggle_on_outlined,
      AppTheme.primary,
      [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (admin.pointsEnabled ? Colors.green : AppTheme.danger)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: admin.pointsEnabled ? Colors.green : AppTheme.danger,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    admin.pointsEnabled ? s.adminRunning : s.adminPaused,
                    style: AppText.bodySmall.copyWith(
                      color: admin.pointsEnabled
                          ? Colors.green
                          : AppTheme.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Switch(
              value: admin.pointsEnabled,
              onChanged: (v) {
                admin.togglePointsSystem(v);
                context.read<PointsProvider>().refreshEnabled();
              },
              activeColor: AppTheme.primary,
            ),
          ],
        ),
        SizedBox(height: 2),
        Text(
          s.adminRealtimeDesc,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _pointSettingsCard(S s) {
    return _card(s.adminPointSettings, Icons.tune, Colors.indigo, [
      if (!_pointSettingsLoaded)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
        )
      else ...[
        TextField(
          controller: _shareUrlCtrl,
          keyboardType: TextInputType.url,
          style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Link tujuan share (Google Play / apkpure)',
            isDense: true,
            filled: true,
            fillColor: AppTheme.bgInput,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Klik link share user → redirect ke link ini. Ganti ke Google Play nanti.',
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
        SizedBox(height: 10),
        for (final f in _pointFields)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    f.$2,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _pointCtrls[f.$1],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: AppText.bodyStrong,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _savingPointSettings ? null : _savePointSettings,
            icon: _savingPointSettings
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(s.adminSavePointSettings),
          ),
        ),
      ],
    ]);
  }

  Widget _massBonus(AdminProvider admin, S s) {
    return _card(s.adminMassBonus, Icons.card_giftcard, Colors.amber, [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _bonusCtrl,
              keyboardType: TextInputType.number,
              style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: s.pointsBalance,
                isDense: true,
                filled: true,
                fillColor: AppTheme.bgInput,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () async {
              final amount = int.tryParse(_bonusCtrl.text) ?? 0;
              if (amount <= 0) return;
              final result = await admin.massBonus(amount);
              if (result != null)
                _toast('+$amount → ${result['affected']} users');
            },
            icon: Icon(Icons.send_rounded, size: 16),
            label: Text(s.btnSend),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
      SizedBox(height: 4),
      Text(
        s.adminRegisteredOnly,
        style: AppText.caption.copyWith(color: AppTheme.textSecondary),
      ),
    ]);
  }

  Widget _reportedUsers(Map<String, dynamic>? stats, S s) {
    final reports = (stats?['reported_users'] as List?) ?? [];
    return _card(s.adminReports, Icons.flag_outlined, Colors.orange, [
      if (reports.isEmpty)
        Text(
          s.adminNoReports,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
      for (var i = 0; i < reports.length && i < 8; i++)
        Padding(
          padding: EdgeInsets.only(bottom: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${reports[i]['reported_id']?.toString().substring(0, 8) ?? '?'}...',
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${reports[i]['report_count']}x',
                  style: AppText.caption.copyWith(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _forceLogout(S s) {
    return _card(s.adminForceLogout, Icons.logout, Colors.orange, [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _logoutCtrl,
              style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: s.labelUserId,
                isDense: true,
                filled: true,
                fillColor: AppTheme.bgInput,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final uid = _logoutCtrl.text.trim();
              if (uid.isEmpty) return;
              try {
                // Await — forceLogout melempar saat gagal; tanpa await
                // error jadi unhandled dan toast "sukses" tampil keliru.
                await context.read<AdminProvider>().forceLogout(uid);
                _toast('Force logout: ${uid.substring(0, 8)}...');
                _logoutCtrl.clear();
              } catch (e) {
                _toast('Failed: $e');
              }
            },
            icon: const Icon(Icons.logout, size: 16, color: Colors.orange),
            label: Text(
              s.adminLogout,
              style: const TextStyle(color: Colors.orange),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _dangerZone(AdminProvider admin, S s) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: AppTheme.danger),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.adminDangerZone,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  s.adminResetAllPoints,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.bgCard,
                  title: Text(
                    s.adminResetAllTitle,
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                  content: Text(
                    s.adminResetAllBody,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(s.btnCancel),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final count = await admin.resetAllPoints();
                        if (count != null) _toast('$count users reset');
                      },
                      child: Text(
                        s.adminWipeAll,
                        style: const TextStyle(color: AppTheme.danger),
                      ),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(
              Icons.delete_sweep_rounded,
              size: 16,
              color: AppTheme.danger,
            ),
            label: Text(
              s.adminReset,
              style: const TextStyle(color: AppTheme.danger),
            ),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.danger.withValues(alpha: 0.08),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    String title,
    IconData icon,
    Color iconColor,
    List<Widget> children,
  ) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              SizedBox(width: 8),
              Text(
                title,
                style: AppText.caption.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// Peta posisi user (admin) — marker dari lat/lon login terakhir
/// (gps hijau / ip oranye) plus resolve IP online untuk yang belum punya
/// koordinat (ungu).
class _UserMapCard extends StatefulWidget {
  const _UserMapCard();
  @override
  State<_UserMapCard> createState() => _UserMapCardState();
}

class _UserMapCardState extends State<_UserMapCard> {
  final MapController _mapCtrl = MapController();
  final Map<String, GeoInfo?> _ipCache = {};
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _resolving = false;
  String? _error;
  int _resolveFail = 0;
  RealtimeChannel? _channel;
  Timer? _notifyDebounce;
  bool _live = false;

  // Batas resolve IP per load (hindari rate-limit provider gratis).
  static const _maxIpResolve = 40;
  // Batas marker yang dirender (users_all diurutkan last_seen desc).
  static const _maxMarkers = 300;

  // Kolom profiles yang dipantau realtime dan dipakai peta.
  static const _trackedFields = [
    'nickname',
    'gender',
    'age',
    'country',
    'city',
    'ip_address',
    'status',
    'is_registered',
    'last_seen',
    'lat',
    'lon',
    'loc_source',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _notifyDebounce?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  /// Realtime: pantau perubahan profiles (login user baru = INSERT,
  /// update lokasi/last_seen = UPDATE) supaya peta selalu segar
  /// tanpa refresh manual.
  void _subscribeRealtime() {
    _channel = Supabase.instance.client.channel('admin-user-map')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'profiles',
        callback: _onProfileChange,
      )
      ..subscribe((status, _) {
        if (!mounted) return;
        setState(() {
          _live = status == RealtimeSubscribeStatus.subscribed;
        });
      });
  }

  void _onProfileChange(PostgresChangePayload payload) {
    final rec = payload.newRecord;
    if (rec.isEmpty) {
      // DELETE: id hanya ada di oldRecord (replica identity default).
      final oldId = '${payload.oldRecord['id'] ?? ''}';
      if (oldId.isNotEmpty) {
        _users.removeWhere((u) => '${u['id'] ?? ''}' == oldId);
      }
      _notify();
      return;
    }
    final id = '${rec['id'] ?? ''}';
    Map<String, dynamic>? existing;
    for (final u in _users) {
      if (id.isNotEmpty && '${u['id'] ?? ''}' == id) {
        existing = u;
        break;
      }
    }
    // Fallback RPC lama tanpa kolom id: cocokkan nickname + ip.
    if (existing == null && id.isNotEmpty) {
      for (final u in _users) {
        if (u['id'] == null &&
            '${u['nickname'] ?? ''}' == '${rec['nickname'] ?? ''}' &&
            '${u['ip_address'] ?? ''}' == '${rec['ip_address'] ?? ''}') {
          existing = u;
          break;
        }
      }
    }
    if (existing == null) {
      final entry = <String, dynamic>{'id': id};
      for (final f in _trackedFields) {
        entry[f] = rec[f];
      }
      _users.insert(0, entry);
    } else {
      for (final f in _trackedFields) {
        if (rec.containsKey(f)) existing[f] = rec[f];
      }
      // Koordinat asli dari server menimpa hasil resolve client.
      if (rec['lat'] != null && rec['lon'] != null) {
        existing.remove('resolved_ip');
      }
      // Naikkan ke depan list (urut last_seen desc) agar tidak
      // tergeser batas _maxMarkers.
      _users.remove(existing);
      _users.insert(0, existing);
    }
    _notify();
    // User baru tanpa koordinat tapi punya IP → resolve agar pin muncul.
    if (rec['lat'] == null &&
        rec['lon'] == null &&
        '${rec['ip_address'] ?? ''}'.isNotEmpty) {
      _resolveIps();
    }
  }

  /// Gabungkan event realtime yang berdekatan jadi satu rebuild peta.
  void _notify() {
    if (!mounted) return;
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final admin = context.read<AdminProvider>();
      final detail = await admin.fetchStatsDetail();
      final list =
          (detail['users_all'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      if (!mounted) return;
      setState(() {
        _users = list;
        _loading = false;
      });
      await _resolveIps();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// Resolve IP untuk user yang belum punya lat/lon (login tanpa GPS).
  /// Paralel per batch (6) + setState per batch — bukan per user —
  /// supaya peta tidak rebuild 40× dan loading tidak menunggu sequential.
  Future<void> _resolveIps() async {
    if (_resolving) return;
    _resolving = true;
    if (mounted) setState(() {});
    final targets = _users
        .where((u) {
          final lat = (u['lat'] as num?)?.toDouble();
          final lon = (u['lon'] as num?)?.toDouble();
          final ip = '${u['ip_address'] ?? ''}';
          return (lat == null || lon == null) && ip.isNotEmpty;
        })
        .take(_maxIpResolve)
        .toList();
    var fail = 0;
    const batchSize = 6;
    for (var i = 0; i < targets.length; i += batchSize) {
      final batch = targets.skip(i).take(batchSize).toList();
      await Future.wait(
        batch.map((u) async {
          final ip = '${u['ip_address'] ?? ''}';
          GeoInfo? info;
          if (_ipCache.containsKey(ip)) {
            info = _ipCache[ip];
          } else {
            info = await GeoService().detectByIp(ip);
            _ipCache[ip] = info;
          }
          if (info?.lat != null && info?.lon != null) {
            u['lat'] = info!.lat;
            u['lon'] = info.lon;
            u['resolved_ip'] = true;
          } else {
            fail++;
          }
        }),
      );
      if (mounted) setState(() {});
    }
    if (mounted) {
      setState(() {
        _resolving = false;
        _resolveFail = fail;
      });
    }
  }

  void _showDetail(Map<String, dynamic> u, Color color, S s) {
    final lat = (u['lat'] as num?)?.toDouble();
    final lon = (u['lon'] as num?)?.toDouble();
    final city = '${u['city'] ?? ''}';
    final country = '${u['country'] ?? ''}';
    final name = '${u['nickname'] ?? '?'}';
    final lastSeen = u['last_seen'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${u['last_seen']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    final source = u['resolved_ip'] == true
        ? s.mapSourceResolved
        : u['loc_source'] == 'gps'
        ? s.mapSourceGps
        : s.mapSourceIp;
    final mapsUrl = lat != null && lon != null
        ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lon'
        : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent([city, country].where((e) => e.isNotEmpty).join(', '))}';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgScreen,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: AppText.titleEmphasis.copyWith(color: color),
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
                      if (lastSeen.isNotEmpty)
                        Text(
                          s.adminLastUpdate + ' ' + lastSeen,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    source,
                    style: AppText.label.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if ((u['age'] ?? 0) > 0 ||
                city.isNotEmpty ||
                country.isNotEmpty) ...[
              SizedBox(height: 10),
              Text(
                [
                  if ((u['age'] ?? 0) > 0)
                    '${u['age']} ${u['gender'] == 'female'
                        ? 'Perempuan'
                        : u['gender'] == 'male'
                        ? 'Laki-laki'
                        : ''}',
                  if (city.isNotEmpty) city,
                  if (country.isNotEmpty) country,
                ].where((e) => e.isNotEmpty).join(' · '),
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(mapsUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: Text(s.mapOpenMaps),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker? _marker(Map<String, dynamic> u, S s) {
    final lat = (u['lat'] as num?)?.toDouble();
    final lon = (u['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final isGps = u['loc_source'] == 'gps';
    final isResolved = u['resolved_ip'] == true;
    final color = isGps
        ? Colors.green
        : isResolved
        ? Colors.deepPurple
        : Colors.orange;
    final name = '${u['nickname'] ?? '?'}';
    return Marker(
      point: LatLng(lat, lon),
      width: 26,
      height: 26,
      child: GestureDetector(
        onTap: () => _showDetail(u, color, s),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: AppText.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final withPos = _users
        .where((u) => (u['lat'] as num?) != null && (u['lon'] as num?) != null)
        .length;
    final gpsCount = _users.where((u) => u['loc_source'] == 'gps').length;
    final resolvedCount = _users.where((u) => u['resolved_ip'] == true).length;
    final ipLoginCount = withPos - gpsCount - resolvedCount;
    final noLoc = _users.length - withPos;

    Widget legendChip(Color color, String label, int count) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: 4),
            Text(
              '$label $count',
              style: AppText.micro.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.map_outlined, size: 16, color: Colors.teal),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.adminMapTitle,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      s.adminMapSubtitle,
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (_live)
                Container(
                  margin: EdgeInsets.only(right: 6),
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        s.mapLive,
                        style: AppText.micro.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_resolving)
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppTheme.primary,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              legendChip(Colors.green, s.mapSourceGps, gpsCount),
              legendChip(Colors.orange, s.mapSourceIp, ipLoginCount),
              legendChip(Colors.deepPurple, s.mapSourceResolved, resolvedCount),
              if (_resolveFail > 0)
                legendChip(Colors.redAccent, s.mapResolveFailed, _resolveFail),
            ],
          ),
          SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 280,
              child: _loading
                  ? Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.danger,
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapCtrl,
                          options: MapOptions(
                            initialCenter: LatLng(-2.5489, 118.0149),
                            initialZoom: 4,
                            minZoom: 2,
                            interactionOptions: InteractionOptions(
                              flags:
                                  InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.chatyuk.chatyuk',
                            ),
                            MarkerLayer(
                              markers: _users
                                  .take(_maxMarkers)
                                  .map((u) => _marker(u, s))
                                  .whereType<Marker>()
                                  .toList(),
                            ),
                          ],
                        ),
                        if (noLoc > 0)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Text(
                                _resolving
                                    ? s.mapResolving
                                    : '$noLoc ${s.mapNoLocation}',
                                style: AppText.micro.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        if (withPos == 0 && !_resolving)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                s.mapTapHint,
                                style: AppText.micro.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar chart registrasi email per hari — filter bulan (12 bulan terakhir).
/// Bottom sheet daftar user yang registrasi email (nama + email + tgl).
class _RegistrationsSheet extends StatefulWidget {
  const _RegistrationsSheet();
  @override
  State<_RegistrationsSheet> createState() => _RegistrationsSheetState();
}

class _RegistrationsSheetState extends State<_RegistrationsSheet> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => context.read<AdminProvider>().fetchRegistrations(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final list = admin.registrations;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(s.adminRegListTitle, style: AppText.title),
            ),
            Expanded(
              child: admin.registrationsLoading && list.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : list.isEmpty
                  ? Center(
                      child: Text(
                        s.adminNoUsers,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final r = list[i];
                        final nick = r['nickname'] ?? '?';
                        final email = r['email'] ?? '-';
                        final created = r['created_at'] != null
                            ? formatRelativeTime(
                                DateTime.tryParse(r['created_at']) ??
                                    DateTime.now(),
                                isId: s.isId,
                              )
                            : '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$nick'.isNotEmpty
                                        ? '$nick'[0].toUpperCase()
                                        : '?',
                                    style: AppText.bodyStrong.copyWith(
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(nick, style: AppText.bodyStrong),
                                    Text(
                                      email,
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
                                created,
                                style: AppText.micro.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Card penggunaan data Supabase: pie chart DB vs gambar + kuota +
/// pertumbuhan per hari/minggu/bulan.
class _StorageUsageCard extends StatefulWidget {
  const _StorageUsageCard();
  @override
  State<_StorageUsageCard> createState() => _StorageUsageCardState();
}

class _StorageUsageCardState extends State<_StorageUsageCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final a = context.read<AdminProvider>();
      a.fetchStorageStats();
      a.fetchCfUsage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final st = admin.storageStats;
    final loading = admin.storageStatsLoading && st == null;

    final dbBytes = ((st?['db_bytes'] ?? 0) as num).toInt();
    final storBytes = ((st?['storage_bytes'] ?? 0) as num).toInt();
    final files = ((st?['storage_files'] ?? 0) as num).toInt();
    final total = ((st?['total_bytes'] ?? 0) as num).toInt();
    final quotaDb = ((st?['quota_db_bytes'] ?? 1) as num).toInt();
    final quotaStor = ((st?['quota_storage_bytes'] ?? 1) as num).toInt();

    final growth = (st?['growth'] as Map<String, dynamic>?) ?? const {};

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.donut_small_rounded,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(s.adminStorageTitle, style: AppText.bodyStrong),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Pie chart DB vs Storage.
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CustomPaint(
                        painter: _UsagePiePainter(dbBytes, storBytes),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Builder(builder: (_) {
                      final dbPct = quotaDb > 0 ? dbBytes / quotaDb : 0.0;
                      final storPct =
                          quotaStor > 0 ? storBytes / quotaStor : 0.0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _legendRow(AppTheme.primary, s.adminStorageDb,
                              formatBytes(dbBytes)),
                          _legendRow(AppTheme.accent, s.adminStorageImages,
                              formatBytes(storBytes)),
                          const Divider(height: 18),
                          _kv(s.adminStorageTotal, formatBytes(total)),
                          _kv('${s.adminStorageDb} (${s.adminQuotaLabel})',
                              '${formatBytes(dbBytes)} / ${formatBytes(quotaDb)}'),
                          _progress(dbPct.clamp(0.0, 1.0), AppTheme.primary),
                          _kv('${s.adminStorageImages} (${s.adminQuotaLabel})',
                              '${formatBytes(storBytes)} / ${formatBytes(quotaStor)}'),
                          _progress(storPct.clamp(0.0, 1.0), AppTheme.accent),
                          _kv(s.adminStorageFiles, '$files'),
                        ],
                      );
                    })),
                  ],
                ),
                const SizedBox(height: 16),
                Text(s.adminStorageGrowth, style: AppText.bodyStrong),
                const SizedBox(height: 6),
                _growthTable(s, growth),
                const SizedBox(height: 16),
                Text(s.adminCfTitle, style: AppText.bodyStrong),
                const SizedBox(height: 8),
                _cfSection(admin, s),
              ],
            ),
    );
  }

Widget _cfSection(AdminProvider admin, S s) {
    final cf = admin.cfUsage;
    if (cf == null) {
      return Text(
        '...',
        style: AppText.caption.copyWith(color: AppTheme.textSecondary),
      );
    }
    if (cf['configured'] != true) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.bgInput.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          s.adminCfNotConfigured,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }
    if (cf['error'] != null) {
      return Text(
        '${cf['error']}',
        style: AppText.caption.copyWith(color: AppTheme.danger),
      );
    }
    final monthBytes = ((cf['month_bytes'] ?? 0) as num).toInt();
    final weekBytes = ((cf['week_bytes'] ?? 0) as num).toInt();
    final dayBytes = ((cf['day_bytes'] ?? 0) as num).toInt();
    final quota = ((cf['quota_bytes'] ?? 1) as num).toInt();
    final pct = quota > 0 ? (monthBytes / quota).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${s.adminCfMonth}: ${formatBytes(monthBytes)}',
                style: AppText.bodySmall,
              ),
            ),
            Text(
              '${s.adminQuotaLabel}: ${formatBytes(quota)}',
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct <= 0 ? null : pct,
              minHeight: 5,
              backgroundColor: AppTheme.divider.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(
                pct > 0.85 ? AppTheme.danger : AppTheme.primary,
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${s.adminGrowthDay}: ${formatBytes(dayBytes)}',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                '${s.adminGrowthWeek}: ${formatBytes(weekBytes)}',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                '${(pct * 100).toStringAsFixed(1)}%',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendRow(Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, style: AppText.bodySmall),
          ),
          Text(value, style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
          ),
          Text(v, style: AppText.bodySmall),
        ],
      ),
    );
  }

  Widget _progress(double pct, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct <= 0 ? null : pct,
          minHeight: 5,
          backgroundColor: AppTheme.divider.withValues(alpha: 0.4),
          valueColor: AlwaysStoppedAnimation<Color>(
            pct > 0.85 ? AppTheme.danger : color,
          ),
        ),
      ),
    );
  }

  Widget _growthTable(S s, Map<String, dynamic> growth) {
    final rows = [
      (
        s.adminGrowthDay,
        growth['day'] ?? const {},
      ),
      (s.adminGrowthWeek, growth['week'] ?? const {}),
      (s.adminGrowthMonth, growth['month'] ?? const {}),
    ];
    Widget cellHeader(String t, {bool count = false}) => Expanded(
          child: Align(
            alignment: count ? Alignment.centerRight : Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                t,
                maxLines: 1,
                style: AppText.micro.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
    String fmtCell(Map m, String key, {bool count = false}) {
      final v = (m[key] ?? 0) as num;
      return count ? '$v' : (v <= 0 ? '-' : formatBytes(v));
    }
    Widget cellValue(String t, {bool strong = false}) => Expanded(
          child: Text(
            t,
            maxLines: 1,
            style: strong
                ? AppText.caption.copyWith(fontWeight: FontWeight.w700)
                : AppText.micro.copyWith(color: AppTheme.textSecondary),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(children: [
            const SizedBox(width: 70),
            cellHeader(s.adminGrowthMessages),
            cellHeader(s.adminGrowthSignals),
            cellHeader(s.adminGrowthImages),
            cellHeader(s.adminGrowthRegistrations, count: true),
          ]),
          const SizedBox(height: 6),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(r.$1, style: AppText.caption),
                  ),
                  cellValue(fmtCell(r.$2 as Map, 'messages')),
                  cellValue(fmtCell(r.$2 as Map, 'signals')),
                  cellValue(fmtCell(r.$2 as Map, 'storage')),
                  cellValue(
                    fmtCell(r.$2 as Map, 'registrations', count: true),
                    strong: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pie chart sederhana DB vs Storage (CustomPaint, tanpa dependency).
class _UsagePiePainter extends CustomPainter {
  final int dbBytes;
  final int storBytes;
  _UsagePiePainter(this.dbBytes, this.storBytes);

  @override
  void paint(Canvas canvas, Size size) {
    final total = dbBytes + storBytes;
    final paint = Paint()..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Ring luar (track).
    paint.color = AppTheme.divider.withValues(alpha: 0.35);
    canvas.drawArc(rect.deflate(2), -pi / 2, pi * 2, true, paint);

    if (total > 0) {
      final dbFrac = dbBytes / total;
      paint.color = AppTheme.primary;
      canvas.drawArc(rect.deflate(8), -pi / 2, pi * 2 * dbFrac, true, paint);
      paint.color = AppTheme.accent;
      canvas.drawArc(rect.deflate(8), -pi / 2 + pi * 2 * dbFrac,
          pi * 2 * (1 - dbFrac), true, paint);
    }
  }

  @override
  bool shouldRepaint(_UsagePiePainter oldDelegate) =>
      oldDelegate.dbBytes != dbBytes || oldDelegate.storBytes != storBytes;
}

class _RegistrationsChartCard extends StatefulWidget {
  const _RegistrationsChartCard();
  @override
  State<_RegistrationsChartCard> createState() =>
      _RegistrationsChartCardState();
}

class _RegistrationsChartCardState extends State<_RegistrationsChartCard> {
  static const _barW = 18.0;
  static const _chartH = 110.0;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _fetch();
  }

  void _fetch() {
    context.read<AdminProvider>().fetchRegistrationsDaily(
      _month.year,
      _month.month,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final data = admin.regDaily;
    final now = DateTime.now();
    final months = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i),
    ];
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final maxCount = data.isEmpty
        ? 1
        : data.values.reduce((a, b) => a > b ? a : b);
    final total = data.values.fold<int>(0, (a, b) => a + b);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showRegistrationsSheet(context),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bar_chart_rounded,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(s.adminRegTitle, style: AppText.bodyStrong),
              const Spacer(),
              DropdownButton<DateTime>(
                value: _month,
                isDense: true,
                underline: const SizedBox.shrink(),
                iconSize: 18,
                style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
                items: [
                  for (final m in months)
                    DropdownMenuItem(
                      value: m,
                      child: Text('${s.monthShort[m.month - 1]} ${m.year}'),
                    ),
                ],
                onChanged: (m) {
                  if (m == null) return;
                  setState(() => _month = m);
                  _fetch();
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${s.adminRegPerDay} · ${s.adminRegTotal}: $total',
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          if (admin.regLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (data.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  s.adminRegEmpty,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var d = 1; d <= days; d++)
                    _bar(d, data[d] ?? 0, maxCount, s),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _bar(int day, int count, int maxCount, S s) {
    final h = count == 0
        ? 2.0
        : (count / maxCount * _chartH).clamp(3.0, _chartH);
    final showLabel = day == 1 || day % 5 == 0 || day == 31;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            count > 0 ? '$count' : '',
            style: AppText.micro.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Container(
            width: _barW,
            height: h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  AppTheme.primary.withValues(alpha: 0.45),
                  AppTheme.primary,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 12,
            child: showLabel
                ? Text(
                    '$day',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// Bottom sheet daftar user yang registrasi (email + tanggal).
  Future<void> _showRegistrationsSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => const _RegistrationsSheet(),
    );
  }
}
