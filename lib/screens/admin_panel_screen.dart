import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as lpn;
import '../config/theme.dart';
import '../config/strings_admin.dart';
import '../core/perf/perf_probe.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import '../utils.dart';
import '../main.dart' show localNotifications, resumeWarmup;
import '../providers/riverpod/admin_provider.dart';
import 'admin_panel/admin_menu.dart';
import 'admin_panel/widgets/menu_grid.dart';
import 'admin_panel/widgets/stats_status.dart' show markAdminStatsUpdated;

/// Halaman utama panel admin: strip statistik mini + ikon menu per kategori.
/// Tiap ikon membuka [AdminMenuPage] (route sendiri). Daftar menu, label,
/// ikon dan isinya ada di `admin_panel/admin_menu.dart` (satu sumber).
///
/// Hub ini tetap berada di bawah stack selama admin di panel, jadi polling
/// statistik, notifikasi device/moderasi dan lifecycle tetap dipegang di sini.
class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen>
    with WidgetsBindingObserver {
  Timer? _statsTimer;
  Timer? _notifyTimer;
  StreamSubscription<String>? _notifSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    Future.microtask(() async {
      await admin.fetchStats();
      markAdminStatsUpdated();
    });
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
    // Polling 60 detik — server meng-cache admin_stats 5 menit, jadi poll =
    // O(1) di DB. Realtime call & device sudah instan lewat subscription.
    _statsTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _pollStats(),
    );
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

  Future<void> _pollStats() async {
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    await admin.refreshStats();
    if (mounted) markAdminStatsUpdated();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statsTimer?.cancel();
    _notifyTimer?.cancel();
    _notifSub?.cancel();
    super.dispose();
  }

  void _open(AdminMenu m) => AdminMenuPage.open(context, m);

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('AdminPanel');
    ref.watch(themeProvider);
    // GRANULAR: hub TIDAK me-watch adminProvider — hanya [AdminStatsStrip]
    // yang select 3 angka, sehingga grid ikon tidak ikut rebuild tiap poll.
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
              if (mounted) markAdminStatsUpdated();
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        children: [
          AdminStatsStrip(s: s, onTap: () => _open(AdminMenu.overview)),
          for (final c in AdminMenuCategory.values) ...[
            const SizedBox(height: 10),
            AdminMenuSection(category: c, s: s, onOpen: _open),
          ],
        ],
      ),
    );
  }
}
