import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as lpn;
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
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
import 'admin_panel/widgets/stat_detail_sheet.dart';
import 'admin_panel/widgets/point_tab_cards.dart';
import 'admin_panel/widgets/overview_cards.dart';
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
      final data = await context.read<AdminProvider>().getPointSettings();
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
      await context.read<AdminProvider>().updatePointSettings(payload);
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
    // Layar error penuh HANYA bila memang belum ada data sama sekali
    // (cold start + offline). Kalau data lama ada → tetap tampilkan + banner.
    final noData = stats == null || stats.isEmpty;
    if (admin.error != null && noData) return _errorView(admin, s);
    if (admin.loading && noData) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
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
                // Kegagalan koneksi tapi data lama ada → banner, bukan error.
                if (admin.error != null) ...[
                  _staleBanner(s),
                  const SizedBox(height: 8),
                ],
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
                ReportedUsersCard(stats: stats, s: s),
                const SizedBox(height: 12),
                ForceLogoutCard(
                  s: s,
                  logoutCtrl: _logoutCtrl,
                  onToast: _toast,
                ),
                const SizedBox(height: 12),
                DangerZoneCard(admin: admin, s: s, onToast: _toast),
                const SizedBox(height: 24),
              ],
            ),
          );
  }

  Widget _buildPointTab(AdminProvider admin, S s, Map<String, dynamic>? stats) {
    final noData = stats == null || stats.isEmpty;
    if (admin.error != null && noData) return _errorView(admin, s);
    if (admin.loading && noData) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
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
                if (admin.error != null) ...[
                  _staleBanner(s),
                  const SizedBox(height: 8),
                ],
                _lastUpdatedHeader(s),
                const SizedBox(height: 8),
                PointStatsCard(stats: stats, s: s),
                const SizedBox(height: 12),
                PointsSystemCard(admin: admin, s: s),
                const SizedBox(height: 12),
                PointSettingsCard(
                  s: s,
                  loaded: _pointSettingsLoaded,
                  shareCtrl: _shareUrlCtrl,
                  fields: _pointFields,
                  ctrls: _pointCtrls,
                  saving: _savingPointSettings,
                  onSave: _savePointSettings,
                ),
                const SizedBox(height: 12),
                TopEarnersCard(stats: stats, s: s),
                const SizedBox(height: 12),
                MassBonusCard(
                  s: s,
                  bonusCtrl: _bonusCtrl,
                  admin: admin,
                  onToast: _toast,
                ),
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
          // Kategori ramah (bukan pesan exception mentah — lihat
          // lib/core/admin_err.dart; detail asli hanya ke dlog).
          Text(s.adminErrTextOf(admin.error!), style: const TextStyle(color: AppTheme.danger)),
          if (s.adminErrHintOf(admin.error!).isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                s.adminErrHintOf(admin.error!),
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => admin.fetchStats(),
            child: Text(s.btnRetry),
          ),
        ],
      ),
    );
  }

  /// Banner tipis saat kegagalan terakhir karena koneksi TAPI data lama masih
  /// ada. User tetap melihat datanya (permintaan: "offline tetap tampilkan
  /// data terakhir"), bukan layar error.
  Widget _staleBanner(S s) {
    return Container(
      width: double.infinity,
      color: AppTheme.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: AppTheme.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.adminErrStaleBanner,
              style: AppText.bodySmall.copyWith(color: AppTheme.danger),
            ),
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
                : () => showStatDetailSheet(context, items[i]),
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



}

/// Peta posisi user (admin) — marker dari lat/lon login terakhir
/// (gps hijau / ip oranye) plus resolve IP online untuk yang belum punya
/// koordinat (ungu).
