import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as lpn;
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
import '../utils.dart';
import 'admin_chat_list_screen.dart';
import 'admin_contact_tab.dart';
import 'admin_devices_tab.dart';
import 'admin_deleted_tab.dart';
import 'admin_dummy_tab.dart';
import 'admin_global_setting_tab.dart';
import 'admin_panel/widgets/usermap_card.dart';
import 'admin_panel/widgets/storageusage_card.dart';
import 'admin_panel/widgets/registrationschart_card.dart';
import 'admin_panel/widgets/avatar_circle.dart';
import '../providers/theme_provider.dart';
import '../main.dart' show localNotifications;

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _bonusCtrl = TextEditingController(text: '100');
  final _logoutCtrl = TextEditingController();
  Timer? _statsTimer;
  Timer? _notifyTimer;
  StreamSubscription<String>? _notifSub;
  DateTime? _lastUpdated;
  late final TabController _tabCtrl;
  // Tab yang pernah dikunjungi — halaman hanya di-build saat pertama kali
  // dibuka (lazy). Tab data-berat (Chat Monitor, Perangkat, Terhapus, dst)
  // tidak mem-fetch apa pun sebelum tab-nya benar-benar dibuka.
  final Set<int> _visitedTabs = {0};

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
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 8, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
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
    // Polling dijarangkan ke 60 detik (dulu 30s) — server meng-cache
    // admin_stats 5 menit, jadi poll = O(1) di DB. Realtime call & device
    // sudah instan lewat subscription, statistik tidak perlu sedemikian
    // agresif.
    _statsTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _pollStats(),
    );
  }

  /// Tandai tab yang pernah dibuka supaya hanya tab aktif yang di-build.
  void _onTabChanged() {
    if (!_tabCtrl.indexIsChanging) return;
    if (mounted) setState(() => _visitedTabs.add(_tabCtrl.index));
  }

  /// App di-background → stop semua polling (hemat baterai & beban DB);
  /// resume → refresh sekarang lalu jalan lagi.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _statsTimer?.cancel();
      _statsTimer = null;
      _notifyTimer?.cancel();
      _notifyTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && _statsTimer == null) {
        unawaited(_pollStats());
        _statsTimer = Timer.periodic(
          const Duration(seconds: 60),
          (_) => _pollStats(),
        );
        if (_notifyTimer == null) _startNotifyPolling(immediate: true);
      }
    }
  }

  void _startNotifyPolling({bool immediate = false}) {
    if (!mounted) return;
    if (immediate) {
      final a = context.read<AdminProvider>();
      a.fetchDevices();
      a.fetchActiveCalls();
    }
    // 60 dtk cukup — realtime call sudah instan; devices hanya sumber
    // notifikasi "device baru" (RPC ter-index, murah).
    _notifyTimer = Timer.periodic(const Duration(seconds: 60), (_) {
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
      dlog('[ADMIN] loadPointSettings error: $e');
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
      if (mounted) _toast(context.read<LocaleProvider>().s.adminPointSettingsSaved);
    } catch (e) {
      if (mounted) _toast(context.read<LocaleProvider>().s.adminSaveFailed('$e'));
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
    WidgetsBinding.instance.removeObserver(this);
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
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

    return Scaffold(
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
          controller: _tabCtrl,
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
        controller: _tabCtrl,
        children: [
          // Lazy tab: halaman data-berat hanya dibangun (dan di-fetch)
          // saat tab-nya pertama dibuka. Placeholder menjaga indeks stabil.
          if (_visitedTabs.contains(0))
            const AdminGlobalSettingTab()
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(1))
            _buildOverviewTab(admin, s, stats)
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(2))
            _buildPointTab(admin, s, stats)
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(3))
            const AdminChatListScreen()
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(4))
            const AdminDummyTab()
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(5))
            const AdminContactTab()
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(6))
            const AdminDevicesTab()
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(7))
            const AdminDeletedTab()
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(AdminProvider admin, S s, Map<String, dynamic>? stats) {
    return admin.loading
        ? const Center(child: CircularProgressIndicator())
        : admin.error != null
        ? _errorView(admin, s)
        : RefreshIndicator(
            onRefresh: () async {
              // force = server hitung ulang sekarang (lewati cache 5 mnt).
              await admin.fetchStats(force: true);
              // List user per kartu (anon/dll) di-cache terpisah 60 dtk —
              // buang juga supaya sheet berikutnya segar.
              admin.invalidateStatsDetail();
              if (mounted) setState(() => _lastUpdated = DateTime.now());
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
                AdminStorageUsageCard(),
                const SizedBox(height: 12),
                const AdminRegistrationsChartCard(),
                const SizedBox(height: 12),
                AdminUserMapCard(),
                const SizedBox(height: 12),
                _reportedUsers(stats, s),
                const SizedBox(height: 12),
                _forceLogout(s),
                const SizedBox(height: 12),
                _dangerZone(admin, s),
                const SizedBox(height: 24),
              ],
            ),
          );
  }

  Widget _buildPointTab(AdminProvider admin, S s, Map<String, dynamic>? stats) {
    return admin.loading
        ? const Center(child: CircularProgressIndicator())
        : admin.error != null
        ? _errorView(admin, s)
        : RefreshIndicator(
            onRefresh: () async {
              await admin.fetchStats(); // cache server 5 mnt — cukup
              if (mounted) setState(() => _lastUpdated = DateTime.now());
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
                AdminAvatarCircle(
                  uid: '${u['id'] ?? ''}',
                  name: name,
                  color: item.$4,
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
            labelText: s.adminShareLinkLabel,
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
