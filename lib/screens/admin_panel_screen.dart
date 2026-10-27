import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_riverpod/flutter_riverpod.dart' as rv;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as lpn;
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../config/strings_docs.dart';
import '../widgets/admin_error_view.dart';
import '../core/perf/perf_probe.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../utils.dart';
import 'admin_chat_list_screen.dart';
import 'admin_room_list_screen.dart';
import 'admin_contact_tab.dart';
import 'admin_devices_tab.dart';
import 'admin_deleted_tab.dart';
import 'admin_dummy_tab.dart';
import 'admin_global_setting_tab.dart';
import 'admin_attribution_tab.dart';
import 'admin_story_tab.dart';
import 'admin_timeline_tab.dart';
import 'admin_docs_tab.dart';
import 'admin_marketing_tab.dart';
import 'admin_panel/widgets/usermap_card.dart';
import 'admin_panel/widgets/storageusage_card.dart';
import 'admin_panel/widgets/registrationschart_card.dart';
import 'admin_panel/widgets/geo_stats_card.dart';
import 'admin_panel/widgets/stat_detail_sheet.dart';
import 'admin_panel/widgets/point_tab_cards.dart';
import 'admin_panel/widgets/overview_cards.dart';
import 'admin_panel/widgets/app_stats_card.dart';
import '../providers/riverpod/theme_provider.dart';
import '../widgets/app_gesture.dart';
import '../main.dart' show localNotifications, resumeWarmup;
import '../providers/riverpod/admin_provider.dart';
import 'admin_moderation_tab.dart';

class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

/// Identitas tiap tab panel admin — SATU sumber urutan untuk label (TabBar)
/// dan isi (TabBarView). Dulu label & body ditulis sebagai dua daftar terpisah
/// dan bisa bergeser (insiden: tab "Timeline" menampilkan Dokumentasi karena
/// `AdminTimelineTab` ditaruh di indeks body 13 sementara label-nya indeks 11).
/// Dengan enum ini label dan body TIDAK mungkin lagi tidak sinkron.
enum _AdminTab {
  globalSetting,
  overview,
  point,
  chatMonitor,
  roomMonitor,
  dummy,
  contact,
  device,
  deleted,
  attribution,
  story,
  timeline,
  docs,
  moderation,
  marketing,
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen>
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

  /// Daftar user Ghost Mode — dimuat SEKALI (bukan di dalam `build`, karena
  /// `FutureBuilder(future: ...di-build-di-sini)` akan memanggil RPC setiap
  /// rebuild → spam request. Di-refresh saat sheet dibuka.
  Future<List<Map<String, dynamic>>>? _ghostFuture;

  // Pengaturan nominal poin (diambil dari server, diedit admin).
  final Map<String, TextEditingController> _pointCtrls = {};
  final _shareUrlCtrl = TextEditingController();
  bool _pointSettingsLoaded = false;
  bool _savingPointSettings = false;
  // Toggle boolean (Switch) pengaturan YukCoin.
  final Map<String, bool> _pointFlags = {};

  // Urutan & label field pengaturan YukCoin (selaras app_settings live).
  // Semua nilai bertipe int kecuali yang ditandai (bool/url ditangani terpisah).
  // Label bilingual via `s.` (AGENTS.md: tak boleh hardcode Indonesia).
  static const List<(String, String)> _pointFields = [
    // ── Call berbayar (per menit) ──
    ('call_audio_cost_per_min', 'Call audio — koin / menit'),
    ('call_video_cost_per_min', 'Call video — koin / menit'),
    ('call_cut_pct', 'Bagian platform dari call (%)'),
    // ── Filter gender & orang sekitar (per hari) ──
    ('filter_gender_cost', 'Filter gender (koin / hari)'),
    ('nearby_cost', 'Orang sekitar (koin / hari)'),
    // ── YukCoin v2 (fitur koin generik) ──
    ('cost_undo_message', 'Hapus pesan (undo)'),
    ('cost_edit_message', 'Edit pesan'),
    ('cost_extra_photo_slot', 'Slot foto tambahan'),
    ('cost_ghost_mode_daily', 'Mode invisible (per hari)'),
    // ── Foto berbayar ──
    ('photo_upload_reward', 'Reward upload foto'),
    ('photo_unlock_once', 'Buka foto: lihat sekali'),
    ('photo_unlock_perm', 'Buka foto: permanen'),
    ('photo_unlock_owner_pct', '% ke pemilik foto'),
    // ── Biaya chat ──
    ('cost_chat_text', 'Biaya kirim teks'),
    ('cost_chat_image', 'Biaya kirim foto'),
    ('cost_view_once', 'Biaya kirim view-once'),
    // ── Room berbayar ──
    ('room_create_paid', 'Buat room'),
    ('room_create_pw_paid', 'Buat room +password'),
    ('room_join_paid', 'Join room'),
    ('room_extend_paid', 'Perpanjang room'),
    ('bonus_price_multiplier', 'Pengali harga tier bonus'),
    // ── Gift & subscribe ──
    ('gift_cut_pct', 'Potongan platform gift (%)'),
    ('subscribe_cut_pct', 'Potongan subscribe (%)'),
    ('subscription_duration_days', 'Durasi subscribe (hari)'),
    // ── Welcome bonus user baru (anti-farming per install/IP) ──
    ('welcome_anon_coins', 'Welcome bonus — anon'),
    ('welcome_register_coins', 'Welcome bonus — register email'),
    ('welcome_max_claims_per_ip_day', 'Maks klaim welcome / IP / hari'),
  ];

  // Field boolean (Switch) — ditangani terpisah dari field int.
  // (reengage_enabled sengaja TIDAK di sini — bukan bagian halaman Poin.)
  static const List<String> _pointBoolFields = [
    'yukcoin_v2_enabled',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 14, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    Future.microtask(() => admin.fetchStats());
    _loadPointSettings();
    // Notifikasi device baru / video call aktif.
    // Arm DULU (muat seen + seed device eksisting tanpa notifikasi),
    // baru mulai polling — mencegah notifikasi palsu saat pertama buka.
    unawaited(
      admin.armNotifications().then((_) => _startNotifyPolling()),
    );
    _notifSub = admin.notifications.listen(
      (msg) => _showAdminNotification(msg),
      onError: (e) => dlog('[ADMIN] notif stream error: $e'),
    );
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
      // Data ghost bisa basi setelah app lama di background → muat ulang
      // saat kartu dibangun berikutnya.
      _ghostFuture = null;
      if (mounted && _statsTimer == null) {
        // Warm-up koneksi dulu (koneksi basi setelah idle) supaya RPC admin
        // tak menggantung ~13 dtk. Fire-and-forget, lalu refetch.
        unawaited(
          resumeWarmup().then((_) {
            if (mounted) _pollStats();
          }),
        );
        _statsTimer = Timer.periodic(
          const Duration(seconds: 60),
          (_) => _pollStats(),
        );
        // JANGAN fetch devices segera di sini (dulu immediate: true).
        // fetchDevices memuat 100 baris device + JSON-encode ke cache disk
        // SEKAAT resume → burst alokasi MB (terukur: GC Explicit dengan
        // 76 LOS objects = 8 MB) → frame stall 181ms. Cukup hidupkan timer
        // poll; data device akan menyusul pada tick berikutnya (60 dtk) atau
        // saat tab Perangkat dibuka.
        if (_notifyTimer == null) _startNotifyPolling();
      }
    }
  }

  void _startNotifyPolling({bool immediate = false}) {
    if (!mounted) return;
    if (immediate) {
      final a = ProviderScope.containerOf(context, listen: false).read(adminProvider);
      a.fetchDevices();
    }
    // 180 dtk (dulu 60): fetchDevices memuat 100 baris + JSON-encode cache —
    // mahal (burst alokasi MB → GC storm). Notifikasi "device baru" tidak
    // perlu cepat; call aktif sudah instan via realtime (ensureCallRealtime),
    // jadi fetchActiveCalls cukup lewat jaring poll yang lebih jarang.
    _notifyTimer = Timer.periodic(const Duration(seconds: 180), (_) {
      if (!mounted) return;
      final a = ProviderScope.containerOf(context, listen: false).read(adminProvider);
      a.fetchDevices();
      unawaited(a.checkModerationActivity());
    });
    // Aktivitas moderasi REALTIME (bukan nunggu poll 180s): event
    // INSERT/UPDATE tabel moderasi → bump → RPC ringan → notifikasi.
    ProviderScope.containerOf(context, listen: false)
        .read(adminProvider)
        .startModerationRealtime();
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
      final data = await ProviderScope.containerOf(context, listen: false).read(adminProvider).getPointSettings();
      for (final f in _pointFields) {
        _pointCtrls[f.$1] = TextEditingController(text: '${data[f.$1] ?? ''}');
      }
      for (final key in _pointBoolFields) {
        _pointFlags[key] = data[key] == true;
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
      for (final e in _pointFlags.entries) {
        payload[e.key] = e.value;
      }
      await ProviderScope.containerOf(context, listen: false).read(adminProvider).updatePointSettings(payload);
      // Sinkron ulang status YukCoin v2 ke provider poin supaya perubahan
      // toggle (mis. membuka jalur topup) langsung terlihat tanpa restart.
      if (mounted) {
        unawaited(ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).refreshYukcoinV2());
        unawaited(ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).refreshMeteredPricing());
      }
      if (mounted) _toast(ProviderScope.containerOf(context, listen: false).read(localeProvider).s.adminPointSettingsSaved);
    } catch (e) {
      if (mounted) _toast(ProviderScope.containerOf(context, listen: false).read(localeProvider).s.adminSaveFailed('$e'));
    } finally {
      if (mounted) setState(() => _savingPointSettings = false);
    }
  }

  Future<void> _pollStats() async {
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
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
    PerfProbe.buildCount('AdminPanel');
    ref.watch(themeProvider);
    // GRANULAR: JANGAN select revStats di root — dulu itu membuat SELURUH
    // panel + semua tab yang dibangun ikut rebuild tiap statistik berubah
    // (polling 60 dtk / realtime). Hanya tab Overview & Poin yang butuh
    // stats; keduanya membungkus dirinya dengan Consumer<AdminProvider>
    // (lihat body) sehingga tab lain (Perangkat/Terhapus/Chat) tak tersentuh.
    // Nilai non-reaktif dibaca via read (tidak menambah dependency).
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final s = ref.watch(localeProvider).s;

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
            for (final tab in _AdminTab.values)
              Tab(text: _tabLabel(tab, s)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Lazy tab: halaman data-berat hanya dibangun (dan di-fetch)
          // saat tab-nya pertama dibuka. Placeholder menjaga indeks stabil.
          // Urutan diambil dari `_AdminTab.values` — SATU sumber kebenaran
          // dengan label TabBar sehingga index label == index body.
          for (var i = 0; i < _AdminTab.values.length; i++)
            _visitedTabs.contains(i)
                ? _tabBody(_AdminTab.values[i], s)
                : const SizedBox.shrink(),
        ],
      ),
    );
  }

  /// Label tab (dipakai TabBar). Satu-satunya tempat teks label per tab.
  String _tabLabel(_AdminTab tab, S s) => switch (tab) {
        _AdminTab.globalSetting => s.adminGlobalSettingTab,
        _AdminTab.overview => s.adminOverview,
        _AdminTab.point => s.adminPointTab,
        _AdminTab.chatMonitor => s.adminChatMonitor,
        _AdminTab.roomMonitor => s.adminRoomMonitor,
        _AdminTab.dummy => s.adminDummyTab,
        _AdminTab.contact => s.adminContactTab,
        _AdminTab.device => s.adminDeviceTab,
        _AdminTab.deleted => s.adminDeletedTab,
        _AdminTab.attribution => s.adminAttributionTab,
        _AdminTab.story => s.adminStoryTab,
        _AdminTab.timeline => s.adminTimelineTab,
        _AdminTab.docs => s.adminDocsTab,
        _AdminTab.moderation => s.adminModerationTab,
        _AdminTab.marketing => s.adminMarketingTab,
      };

  /// Isi tab (dipakai TabBarView). Urutan mengikuti [_AdminTab.values] →
  /// tidak bisa lagi bergeser dari label.
  Widget _tabBody(_AdminTab tab, S s) => switch (tab) {
        _AdminTab.globalSetting => const AdminGlobalSettingTab(),
        _AdminTab.overview => rv.Consumer(
            builder: (ctx, ref, _) {
              final ap = ref.watch(adminProvider);
              return _buildOverviewTab(ap, s, ap.stats);
            },
          ),
        _AdminTab.point => rv.Consumer(
            builder: (ctx, ref, _) {
              final ap = ref.watch(adminProvider);
              return _buildPointTab(ap, s, ap.stats);
            },
          ),
        _AdminTab.chatMonitor => const AdminChatListScreen(),
        _AdminTab.roomMonitor => const AdminRoomListScreen(),
        _AdminTab.dummy => const AdminDummyTab(),
        _AdminTab.contact => const AdminContactTab(),
        _AdminTab.device => const AdminDevicesTab(),
        _AdminTab.deleted => const AdminDeletedTab(),
        _AdminTab.attribution => const AdminAttributionTab(),
        _AdminTab.story => const AdminStoryTab(),
        _AdminTab.timeline => const AdminTimelineTab(),
        _AdminTab.docs => const AdminDocsTab(),
        _AdminTab.moderation => const AdminModerationTab(),
        _AdminTab.marketing => const AdminMarketingTab(),
      };

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
                AdminAppStatsCard(stats: stats, s: s),
                const SizedBox(height: 12),
                AdminStorageUsageCard(),
                const SizedBox(height: 12),
                const AdminRegistrationsChartCard(),
                const SizedBox(height: 12),
                const AdminGeoStatsCard(),
                const SizedBox(height: 12),
                AdminUserMapCard(),
                const SizedBox(height: 12),
                ReportedUsersCard(stats: stats, s: s),
                const SizedBox(height: 12),
                PrivacyUsersCard(stats: stats, s: s),
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
                FeaturePublishCard(s: s, onToast: _toast),
                const SizedBox(height: 12),
                PointSettingsCard(
                  s: s,
                  loaded: _pointSettingsLoaded,
                  shareCtrl: _shareUrlCtrl,
                  fields: _pointFields,
                  ctrls: _pointCtrls,
                  flags: _pointFlags,
                  onFlagChanged: (k, v) => setState(() => _pointFlags[k] = v),
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
    return AdminErrorView(
      s: s,
      error: admin.error!,
      onRetry: () => admin.fetchStats(),
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
          child: AppGestureDetector(
            behavior: HitTestBehavior.opaque,
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
        const SizedBox(height: 8),
        // BARIS GHOST: user yang membeli "mode invisible" (Ghost Mode).
        // Dulu TIDAK tercatat di mana pun → admin tak bisa membedakan user
        // ghost dari user biasa. Sumber: RPC admin_ghost_users.
        Row(
          children: [
            Expanded(
              child: Material(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(10),
                child: AppGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showGhostUsers(),
                  child: Container(
                    height: 76,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 15,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(height: 5),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: FutureBuilder<List<Map<String, dynamic>>>(
                              future: _ghostFuture ??= ref
                                  .read(adminProvider)
                                  .fetchGhostUsers(),
                              builder: (context, snap) => Text(
                                snap.hasData
                                    ? '${snap.data!.length}'
                                    : (snap.hasError ? '-' : '…'),
                                style: AppText.titleEmphasis.copyWith(
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mode invisible',
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
            ),
            // Baris ini hanya 1 kartu → lebarkan 2 slot sisa supaya grid
            // tetap 3 kolom (lebar kartu konsisten dgn baris di atas).
            const SizedBox(width: 8),
            const Spacer(flex: 2),
          ],
        ),
      ],
    );
  }

  /// Daftar user yang sedang Ghost Mode (invisible berbayar).
  Future<void> _showGhostUsers() async {
    // Refresh data setiap sheet dibuka (kartu ikut ter-update), sekali saja.
    final future = ref.read(adminProvider).fetchGhostUsers();
    setState(() => _ghostFuture = future);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (c, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const SizedBox(
              height: 160,
              child: Center(child: Text('Tidak ada user mode invisible')),
            );
          }
          return SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rows.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppTheme.divider,
              ),
              itemBuilder: (c2, i) {
                final r = rows[i];
                final nama = '${r['nickname'] ?? '-'}';
                final sisa = r['ghost_sisa_jam'];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.visibility_off_outlined,
                    size: 20,
                    color: Colors.deepPurple,
                  ),
                  title: Text(nama, style: AppText.bodyStrong),
                  subtitle: Text(
                    'status: ${r['status'] ?? '-'} · sisa ${sisa ?? '-'} jam',
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }



}

/// Peta posisi user (admin) — marker dari lat/lon login terakhir
/// (gps hijau / ip oranye) plus resolve IP online untuk yang belum punya
/// koordinat (ungu).
