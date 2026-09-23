import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import '../core/admin_gate.dart';
import '../services/app_update_service.dart';
import '../utils.dart';
import '../widgets/update_dialog.dart';

/// Fase popup update.
enum UpdatePhase {
  /// Belum ada aksi.
  idle,

  /// Sedang cek versi (silent).
  checking,

  /// Ada versi lebih baru → popup harus tampil.
  available,

  /// Play Core sedang mengunduh di background (flexible).
  downloading,

  /// Unduhan selesai → tinggal restart untuk menerapkan.
  readyToInstall,

  /// Gagal (jaringan / Play error) — popup menampilkan opsi buka Play Store.
  failed,

  /// Platform/non-Play → tombol diarahkan ke listing Play di browser.
  openStore,
}

/// Provider fitur update — satu-satunya jembatan antara screen (dialog)
/// dan `AppUpdateService`. Screen TIDAK import services/.
class UpdateProvider extends ChangeNotifier {
  final AppUpdateService service;

  UpdateProvider({AppUpdateService? service})
      : service = service ?? AppUpdateService.instance;

  static UpdateProvider? _instance;

  /// Instance global (dipakai `checkOnStart` dari bootstrap).
  static UpdateProvider get instance => _instance ??= UpdateProvider();

  UpdatePhase _phase = UpdatePhase.idle;
  UpdatePhase get phase => _phase;

  bool _force = false;
  bool get force => _force;

  String _latestVersion = '';
  String get latestVersion => _latestVersion;

  String _notes = '';
  String get notes => _notes;

  int _progress = 0;
  int get progress => _progress;

  /// Navigator root untuk dismiss eksplisit + key dialog yang sedang tampil.
  /// Auto-pop via fase `idle` TIDAK bisa diandalkan: transisi idle→
  /// downloading terjadi dalam microtask yang sama tanpa frame di antaranya,
  /// sehingga frame idle tak pernah ter-render dan dialog tak pernah tutup.
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _dialogOpen = false;

  /// True bila app di-install dari Play → tombol melakukan update in-app.
  bool _fromPlay = false;
  bool get fromPlay => _fromPlay;

  /// Kunci snooze: `update_snooze_v1` → `{"version":"1.2.5","ts":<ms>}`.
  static const String _snoozeKey = 'update_snooze_v1';
  static const Duration _snoozeWindow = Duration(hours: 24);

  /// Dipanggil dari bootstrap (fire-and-forget) — silent, tidak menahan TTI.
  ///
  /// [navigatorKey] dipakai untuk menampilkan dialog tanpa BuildContext.
  static Future<void> checkOnStart(GlobalKey<NavigatorState> navigatorKey) async {
    await UpdateProvider.instance.check(navigatorKey: navigatorKey);
  }

  /// Cek versi. Aman dipanggil berulang (idempotent selama fase idle/checking).
  Future<void> check({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (navigatorKey != null) _navigatorKey = navigatorKey;
    // Skip: web, non-Android, build dev (Supabase local), build admin.
    if (kIsWeb || AppEnv.isDev || AdminGate.enabled) {
      dlog('[UPDATE] dilewati (web/dev/admin)');
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_phase != UpdatePhase.idle && _phase != UpdatePhase.failed) return;
    _phase = UpdatePhase.checking;
    _notify();
    try {
      final policy = await service.fetchPolicy();
      final local = await service.currentVersion();
      if (local.version.isEmpty) {
        _phase = UpdatePhase.idle;
        _notify();
        return;
      }
      final play = await service.detectPlayAvailability();
      _fromPlay = play == PlayAvailability.available;

      // Kebijakan dari server (app_settings) sebagai sumber utama.
      var available = policy != null &&
          !policy.isEmpty &&
          AppUpdateService.isUpdateAvailable(
            local: local.version,
            latest: policy.latestVersion,
          );
      var forceReq = policy != null &&
          AppUpdateService.isForceRequired(
            local: local.version,
            minVersion: policy.minVersion,
          );

      // Bila admin belum mengisi latest_version tapi app dari Play, tanya Play.
      if (!available && _fromPlay) {
        final playHas = await service.playReportsUpdate();
        if (playHas) available = true;
      }

      if (!available) {
        _phase = UpdatePhase.idle;
        _notify();
        return;
      }

      _latestVersion = policy?.latestVersion ?? '';
      _notes = policy?.notes ?? '';
      _force = forceReq;

      // Play sudah selesai mengunduh tapi install belum jalan (mis. app
      // terbunuh sebelum complete) → selesaikan diam-diam tanpa popup,
      // walau versi ini sempat di-snooze/ditandai.
      if (_fromPlay) {
        try {
          final st = await service.playInstallStatus();
          if (st == InstallStatus.downloaded) {
            dlog('[UPDATE] unduhan Play tertunda → selesaikan');
            await service.completeFlexible();
            _phase = UpdatePhase.idle;
            _notify();
            return;
          }
        } catch (e) {
          dlog('[UPDATE] auto-resume error (abaikan): $e');
        }
      }

      // Snooze: jangan popup versi yang sama dalam 24 jam — kecuali force.
      if (!forceReq && await _isSnoozed(_latestVersion)) {
        dlog('[UPDATE] di-snooze: $_latestVersion');
        _phase = UpdatePhase.idle;
        _notify();
        return;
      }

      _phase = UpdatePhase.available;
      _notify();
      if (navigatorKey != null) _presentDialog(navigatorKey);
    } catch (e) {
      dlog('[UPDATE] check error: $e');
      _phase = UpdatePhase.idle;
      _notify();
    }
  }

  /// Tandai user menekan "Nanti" → snooze versi ini 24 jam.
  Future<void> snooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _snoozeKey,
        '{"version":"$_latestVersion","ts":${DateTime.now().millisecondsSinceEpoch}}',
      );
    } catch (_) {}
    _phase = UpdatePhase.idle;
    _notify();
  }

  Future<bool> _isSnoozed(String version) async {
    if (version.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_snoozeKey);
      if (raw == null || raw.isEmpty) return false;
      final tsStart = raw.indexOf('"ts":');
      final verStart = raw.indexOf('"version":"');
      if (tsStart < 0 || verStart < 0) return false;
      final ts = int.tryParse(
        raw.substring(tsStart + 5).replaceAll(RegExp(r'[^0-9]'), ''),
      );
      final verEnd = raw.indexOf('"', verStart + 11);
      if (verEnd < 0) return false;
      final ver = raw.substring(verStart + 11, verEnd);
      if (ver != version || ts == null) return false;
      final elapsed = DateTime.now().millisecondsSinceEpoch - ts;
      return elapsed < _snoozeWindow.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  /// Mulai proses update — branch Play (flexible/immediate) vs non-Play.
  ///
  /// Popup LANGSUNG ditutup saat tombol ditekan (fase idle → dialog
  /// menutup sendiri); download lanjut di background dan otomatis
  /// di-install saat selesai. Versi ini ditandai supaya popup tidak
  /// dimunculkan lagi.
  Future<void> startUpdate() async {
    if (!_fromPlay) {
      _phase = UpdatePhase.openStore;
      _notify();
      await service.openPlayListing();
      return;
    }
    // Tutup popup DULU secara eksplisit, tandai versi, baru jalankan
    // Play flow di background.
    _dismissDialog();
    await snooze();
    try {
      if (_force) {
        // Immediate: layar penuh Play, wajib sampai selesai. App akan
        // restart sendiri oleh Play setelah selesai.
        final result = await service.startImmediate();
        if (result != AppUpdateResult.success) {
          throw StateError('immediate ditolak Play: $result');
        }
        return;
      }
      _phase = UpdatePhase.downloading;
      _progress = 0;
      _notify();
      final result = await service
          .startFlexible(onStatus: _onInstallStatus)
          // Anti-stuck: Play yang tidak merespons (mis. katalog Play belum
          // tahu versi ini) tidak boleh menggantung status "preparing".
          .timeout(const Duration(seconds: 30));
      if (result != AppUpdateResult.success) {
        throw StateError('flexible ditolak Play: $result');
      }
    } catch (e) {
      dlog('[UPDATE] startUpdate error: $e');
      _phase = UpdatePhase.failed;
      _notify();
    }
  }

  void _onInstallStatus(InstallStatus st) {
    switch (st) {
      case InstallStatus.downloading:
        _phase = UpdatePhase.downloading;
        _notify();
        break;
      case InstallStatus.downloaded:
        // Install otomatis tanpa prompt ulang — Play me-restart app.
        unawaited(_autoComplete());
        break;
      case InstallStatus.failed:
        dlog('[UPDATE] flexible gagal');
        _phase = UpdatePhase.failed;
        _notify();
        break;
      case InstallStatus.canceled:
        _phase = UpdatePhase.idle;
        _notify();
        break;
      default:
        break;
    }
  }

  Future<void> _autoComplete() async {
    try {
      await service.completeFlexible();
      _phase = UpdatePhase.idle;
    } catch (e) {
      dlog('[UPDATE] autoComplete error: $e');
      _phase = UpdatePhase.failed;
    }
    _notify();
  }

  /// Terapkan unduhan flexible yang sudah selesai → restart app.
  Future<void> applyAndRestart() async {
    try {
      await service.completeFlexible();
    } catch (e) {
      dlog('[UPDATE] completeFlexible error: $e');
      _phase = UpdatePhase.failed;
      _notify();
    }
  }

  /// Buka listing Play (dipakai juga saat gagal). Popup ikut ditutup dan
  /// versi ditandai supaya tidak dimunculkan lagi.
  Future<void> openStore() async {
    _dismissDialog();
    await snooze();
    await service.openPlayListing();
  }

  void _notify() {
    try {
      notifyListeners();
    } catch (_) {}
  }

  // ── Hook test (tidak dipakai produksi) ──
  @visibleForTesting
  void setFromPlayForTest(bool v) => _fromPlay = v;

  @visibleForTesting
  void setForceForTest(bool v) => _force = v;

  @visibleForTesting
  void setPhaseForTest(UpdatePhase v) {
    _phase = v;
    _notify();
  }

  @visibleForTesting
  Future<void> snoozeForTest({required String version}) async {
    _latestVersion = version;
    await snooze();
  }

  @visibleForTesting
  Future<void> writeSnoozeForTest({
    required String version,
    required int ts,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _snoozeKey,
      '{"version":"$version","ts":$ts}',
    );
  }

  @visibleForTesting
  Future<bool> isSnoozedForTest(String version) => _isSnoozed(version);

  /// Tampilkan kembali dialog bila masih relevan (dipanggil saat app
  /// kembali foreground — dialog mungkin tertutup oleh sistem/barrier).
  ///
  /// HANYA fase available yang dimunculkan ulang. Fase downloading berjalan
  /// diam-diam di background; failed/openStore tidak di-nag ulang karena
  /// versinya sudah ditandai saat user menekan tombol.
  void presentIfNeeded(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    if (_phase == UpdatePhase.available) {
      _presentDialog(navigatorKey);
    }
  }

  /// Tampilkan dialog update lewat root navigator (tanpa BuildContext).
  void _presentDialog(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    _dialogOpen = true;
    showUpdateDialog(ctx, this);
  }

  /// Dipanggil dialog saat benar-benar tertutup (sebab apa pun) supaya
  /// dismiss eksplisit tidak pernah menutup route yang salah.
  void notifyDialogClosed() {
    _dialogOpen = false;
  }

  /// Tutup popup update bila sedang terbuka. Dipakai saat user menekan
  /// tombol aksi — SEBELUM flow lanjut, agar penutupan deterministik
  /// (tidak bergantung frame transien).
  void _dismissDialog() {
    if (!_dialogOpen) return;
    _dialogOpen = false;
    try {
      final ctx = _navigatorKey?.currentContext;
      if (ctx == null) return;
      final nav = Navigator.of(ctx, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    } catch (_) {}
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }
}
