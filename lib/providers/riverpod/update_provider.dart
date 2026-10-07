import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/env.dart';
import '../../core/admin_gate.dart';
import '../../services/app_update_service.dart';
import '../../utils.dart';
import '../../widgets/update_dialog.dart';

/// Fase popup update.
enum UpdatePhase {
  idle,
  checking,
  available,
  downloading,
  readyToInstall,
  failed,
  openStore,
}

/// State UpdateProvider (immutable).
class UpdateState {
  final UpdatePhase phase;
  final bool force;
  final String latestVersion;
  final String notes;
  final int progress;
  final bool fromPlay;
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.force = false,
    this.latestVersion = '',
    this.notes = '',
    this.progress = 0,
    this.fromPlay = false,
  });

  UpdateState copyWith({
    UpdatePhase? phase,
    bool? force,
    String? latestVersion,
    String? notes,
    int? progress,
    bool? fromPlay,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        force: force ?? this.force,
        latestVersion: latestVersion ?? this.latestVersion,
        notes: notes ?? this.notes,
        progress: progress ?? this.progress,
        fromPlay: fromPlay ?? this.fromPlay,
      );

  @override
  bool operator ==(Object other) =>
      other is UpdateState &&
      other.phase == phase &&
      other.force == force &&
      other.latestVersion == latestVersion &&
      other.notes == notes &&
      other.progress == progress &&
      other.fromPlay == fromPlay;

  @override
  int get hashCode => Object.hash(
        phase,
        force,
        latestVersion,
        notes,
        progress,
        fromPlay,
      );
}

/// Provider fitur update (Riverpod) — jembatan screen (dialog) ↔ service.
///
/// Migrasi dari ChangeNotifier + singleton `instance` → Notifier + Provider.
/// Untuk akses non-widget (bootstrap `checkOnStart`), pakai
/// `updateContainerProvider`/container global di main.dart.
class UpdateNotifier extends Notifier<UpdateState> {
  final AppUpdateService service;

  UpdateNotifier([AppUpdateService? service])
      : service = service ?? AppUpdateService.instance;

  static const String _snoozeKey = 'update_snooze_v1';
  static const Duration _snoozeWindow = Duration(hours: 24);
  static const String _lastPushKey = 'update_push_seen_v1';

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _dialogOpen = false;

  @override
  UpdateState build() {
    ref.onDispose(() {
      // service.dispose() TIDAK dipanggil di sini: service = AppUpdateService
      // singleton (instance) — dibagi lintas provider/test.
    });
    return const UpdateState();
  }

  /// Cek versi. Idempotent selama fase idle/checking.
  Future<void> check({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (navigatorKey != null) _navigatorKey = navigatorKey;
    if (kIsWeb || AppEnv.isDev || AdminGate.enabled) {
      dlog('[UPDATE] dilewati (web/dev/admin)');
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final st0 = state;
    if (st0.phase != UpdatePhase.idle && st0.phase != UpdatePhase.failed) return;
    state = state.copyWith(phase: UpdatePhase.checking);
    try {
      final policy = await service.fetchPolicy();
      final local = await service.currentVersion();
      if (local.version.isEmpty) {
        state = state.copyWith(phase: UpdatePhase.idle);
        return;
      }
      final play = await service.detectPlayAvailability();
      final fromPlay = play == PlayAvailability.available;

      final available = policy != null &&
          !policy.isEmpty &&
          AppUpdateService.isUpdateAvailable(
            local: local.version,
            latest: policy.latestVersion,
          );
      final forceReq = policy != null &&
          AppUpdateService.isForceRequired(
            local: local.version,
            minVersion: policy.minVersion,
          );

      if (!available && !forceReq) {
        state = state.copyWith(phase: UpdatePhase.idle, fromPlay: fromPlay);
        return;
      }

      if (fromPlay) {
        try {
          final st = await service.playInstallStatus();
          if (st == InstallStatus.downloaded) {
            dlog('[UPDATE] unduhan Play tertunda → selesaikan');
            await service.completeFlexible();
            state = state.copyWith(phase: UpdatePhase.idle, fromPlay: fromPlay);
            return;
          }
        } catch (e) {
          dlog('[UPDATE] auto-resume error (abaikan): $e');
        }
      }

      final pol = policy;
      final pushedNow = await _hasFreshManualPush(pol.pushAt);
      if (!pushedNow && !forceReq) {
        dlog('[UPDATE] menunggu push manual admin (tidak nag)');
        state = state.copyWith(phase: UpdatePhase.idle, fromPlay: fromPlay);
        return;
      }

      state = state.copyWith(
        latestVersion: pol.latestVersion,
        notes: pol.notes,
        force: forceReq,
        fromPlay: fromPlay,
      );

      if (!forceReq && !pushedNow && await _isSnoozed(state.latestVersion)) {
        dlog('[UPDATE] di-snooze: ${state.latestVersion}');
        state = state.copyWith(phase: UpdatePhase.idle);
        return;
      }

      if (pushedNow) await _markManualPushSeen(pol.pushAt);

      state = state.copyWith(phase: UpdatePhase.available);
      if (navigatorKey != null) _presentDialog(navigatorKey);
    } catch (e) {
      dlog('[UPDATE] check error: $e');
      state = state.copyWith(phase: UpdatePhase.idle);
    }
  }

  Future<bool> _hasFreshManualPush(DateTime? serverPush) async {
    if (serverPush == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getString(_lastPushKey);
      if (seen == null || seen.isEmpty) return true;
      final seenAt = DateTime.tryParse(seen)?.toUtc();
      if (seenAt == null) return true;
      return serverPush.isAfter(seenAt);
    } catch (_) {
      return false;
    }
  }

  Future<void> _markManualPushSeen(DateTime? serverPush) async {
    if (serverPush == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPushKey, serverPush.toUtc().toIso8601String());
    } catch (_) {}
  }

  /// User menekan "Nanti" → snooze versi ini 24 jam.
  Future<void> snooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _snoozeKey,
        '{"version":"${state.latestVersion}","ts":${DateTime.now().millisecondsSinceEpoch}}',
      );
    } catch (_) {}
    state = state.copyWith(phase: UpdatePhase.idle);
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

  Future<void> startUpdate() async {
    if (!state.fromPlay) {
      state = state.copyWith(phase: UpdatePhase.openStore);
      await service.openPlayListing();
      return;
    }
    _dismissDialog();
    await snooze();
    try {
      if (state.force) {
        final result = await service.startImmediate();
        if (result != AppUpdateResult.success) {
          throw StateError('immediate ditolak Play: $result');
        }
        return;
      }
      state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
      final result = await service
          .startFlexible(onStatus: _onInstallStatus)
          .timeout(const Duration(seconds: 30));
      if (result != AppUpdateResult.success) {
        throw StateError('flexible ditolak Play: $result');
      }
    } catch (e) {
      dlog('[UPDATE] startUpdate error: $e');
      state = state.copyWith(phase: UpdatePhase.failed);
    }
  }

  void _onInstallStatus(InstallStatus st) {
    switch (st) {
      case InstallStatus.downloading:
        state = state.copyWith(phase: UpdatePhase.downloading);
        break;
      case InstallStatus.downloaded:
        unawaited(_autoComplete());
        break;
      case InstallStatus.failed:
        dlog('[UPDATE] flexible gagal');
        state = state.copyWith(phase: UpdatePhase.failed);
        break;
      case InstallStatus.canceled:
        state = state.copyWith(phase: UpdatePhase.idle);
        break;
      default:
        break;
    }
  }

  Future<void> _autoComplete() async {
    try {
      await service.completeFlexible();
      state = state.copyWith(phase: UpdatePhase.idle);
    } catch (e) {
      dlog('[UPDATE] autoComplete error: $e');
      state = state.copyWith(phase: UpdatePhase.failed);
    }
  }

  Future<void> applyAndRestart() async {
    try {
      await service.completeFlexible();
    } catch (e) {
      dlog('[UPDATE] completeFlexible error: $e');
      state = state.copyWith(phase: UpdatePhase.failed);
    }
  }

  Future<void> openStore() async {
    _dismissDialog();
    await snooze();
    await service.openPlayListing();
  }

  /// Tampilkan ulang dialog bila fase available (dipanggil saat foreground).
  void presentIfNeeded(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    if (state.phase == UpdatePhase.available) {
      _presentDialog(navigatorKey);
    }
  }

  void _presentDialog(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    _dialogOpen = true;
    showUpdateDialog(ctx, this);
  }

  void notifyDialogClosed() => _dialogOpen = false;

  // ── Hook test (tidak dipakai produksi) ──
  @visibleForTesting
  void setFromPlayForTest(bool v) => state = state.copyWith(fromPlay: v);

  @visibleForTesting
  void setForceForTest(bool v) => state = state.copyWith(force: v);

  @visibleForTesting
  void setPhaseForTest(UpdatePhase v) => state = state.copyWith(phase: v);

  @visibleForTesting
  Future<void> snoozeForTest({required String version}) async {
    state = state.copyWith(latestVersion: version);
    await snooze();
  }

  @visibleForTesting
  Future<void> writeSnoozeForTest({
    required String version,
    required int ts,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snoozeKey, '{"version":"$version","ts":$ts}');
  }

  @visibleForTesting
  Future<bool> isSnoozedForTest(String version) => _isSnoozed(version);

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
}

final updateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
