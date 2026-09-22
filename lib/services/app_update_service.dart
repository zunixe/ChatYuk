import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_flavor.dart';
import '../config/supabase_config.dart';
import '../utils.dart';

/// Kebijakan update dari `app_settings` (baris id='global').
///
/// Diisi admin; klien membandingkan [latestVersion] dengan versionName lokal.
class UpdatePolicy {
  final bool enabled;
  final String latestVersion;
  final String minVersion;
  final String notes;

  const UpdatePolicy({
    required this.enabled,
    required this.latestVersion,
    required this.minVersion,
    required this.notes,
  });

  /// Tidak ada kebijakan / fitur dimatikan / latest kosong.
  bool get isEmpty => !enabled || latestVersion.trim().isEmpty;
}

/// Status installer Play — menentukan apakah Play Core bisa dipakai.
enum PlayAvailability {
  /// Install dari Google Play → Play Core tersedia.
  available,

  /// Di-sideload (apkpure/ADB/APKPure) → Play Core TIDAK bisa dipakai.
  notFromPlay,

  /// Bukan Android / platform lain.
  unsupported,
}

/// Service I/O fitur update: baca kebijakan server, versi lokal, banding
/// semver, deteksi installer Play, dan jalankan Play Core In-App Update.
///
/// Boundary: hanya service/provider yang boleh memanggil ini — screen TIDAK
/// import services (lihat AGENTS.md Modularitas).
class AppUpdateService {
  /// Channel native tipis (MainActivity.kt) — deteksi installer package.
  static const MethodChannel _channel =
      MethodChannel('com.chatyuk.chatyuk/update');

  final SupabaseClient? _injected;

  AppUpdateService._([SupabaseClient? sb]) : _injected = sb;

  static AppUpdateService instance = AppUpdateService._();

  @visibleForTesting
  factory AppUpdateService.forTest({SupabaseClient? sb, AppUpdateClient? client}) {
    final s = AppUpdateService._(sb);
    if (client != null) s._client = client;
    return s;
  }

  @visibleForTesting
  static void overrideInstance(AppUpdateService s) => instance = s;

  @visibleForTesting
  static void restoreInstance() => instance = AppUpdateService._();

  /// Injeksi wrapper Play Core (test tidak bisa memanggil plugin asli).
  AppUpdateClient? _client;
  AppUpdateClient get _playCore => _client ??= const PlayCoreClient();

  /// Override hasil (khusus test `check()` end-to-end tanpa jaringan/plugin).
  @visibleForTesting
  UpdatePolicy? debugPolicyOverride;
  @visibleForTesting
  ({String version, int buildNumber})? debugLocalVersionOverride;
  @visibleForTesting
  PlayAvailability? debugPlayAvailabilityOverride;

  SupabaseClient get _sb => _injected ?? SupabaseConfig.client;

  /// URL listing Play — untuk fallback non-Play (apkpure) & tombol manual.
  static const String playListing =
      'https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk';

  /// Ambil kebijakan update dari `app_settings`. Return null bila gagal
  /// (tidak ada sesi / offline / kolom belum ada → fitur cukup di-skip).
  Future<UpdatePolicy?> fetchPolicy() async {
    if (debugPolicyOverride != null) return debugPolicyOverride;
    try {
      final row = await _sb
          .from('app_settings')
          .select('update_enabled,latest_version,min_version,update_notes')
          .eq('id', 'global')
          .maybeSingle();
      if (row == null) return null;
      return UpdatePolicy(
        enabled: row['update_enabled'] == true,
        latestVersion: '${row['latest_version'] ?? ''}',
        minVersion: '${row['min_version'] ?? ''}',
        notes: '${row['update_notes'] ?? ''}',
      );
    } catch (e) {
      dlog('[UPDATE] fetchPolicy error (abaikan): $e');
      return null;
    }
  }

  /// Versi lokal app (versionName + versionCode) via package_info_plus.
  Future<({String version, int buildNumber})> currentVersion() async {
    if (debugLocalVersionOverride != null) return debugLocalVersionOverride!;
    try {
      final p = await PackageInfo.fromPlatform();
      return (
        version: p.version.trim(),
        buildNumber: int.tryParse(p.buildNumber) ?? 0,
      );
    } catch (e) {
      dlog('[UPDATE] currentVersion error: $e');
      return (version: '', buildNumber: 0);
    }
  }

  /// Bandingkan dua versionName `X.Y.Z` (numerik, tahan panjang beda).
  /// Return >0 bila [a] lebih baru dari [b], 0 bila sama, <0 bila lebih lama.
  static int compareSemver(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  static List<int> _parse(String v) {
    final clean = v.trim().split('+').first; // buang suffix build `+N`
    return clean
        .split(RegExp(r'[.\-]'))
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  /// Apakah ada versi lebih baru dari yang terpasang.
  static bool isUpdateAvailable({
    required String local,
    required String latest,
  }) {
    if (local.isEmpty || latest.isEmpty) return false;
    return compareSemver(latest, local) > 0;
  }

  /// Apakah versi lokal di bawah batas minimum (update wajib/force).
  static bool isForceRequired({
    required String local,
    required String minVersion,
  }) {
    if (local.isEmpty || minVersion.isEmpty) return false;
    return compareSemver(local, minVersion) < 0;
  }

  /// Deteksi apakah app di-install dari Google Play (butuh Play Core).
  /// Fast-path: flavor `play`. Sumber kebenaran: installer package native
  /// (`com.android.vending`) — build play yang di-sideload tetap non-Play.
  Future<PlayAvailability> detectPlayAvailability() async {
    if (debugPlayAvailabilityOverride != null) {
      return debugPlayAvailabilityOverride!;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return PlayAvailability.unsupported;
    }
    try {
      final installer =
          await _channel.invokeMethod<String>('getInstallerPackage');
      if (installer == 'com.android.vending') {
        return PlayAvailability.available;
      }
      return PlayAvailability.notFromPlay;
    } catch (e) {
      dlog('[UPDATE] getInstallerPackage error (anggap non-Play): $e');
      // Fallback: kalau flavor memang play & channel gagal, tetap coba.
      return AppFlavor.isPlay
          ? PlayAvailability.available
          : PlayAvailability.notFromPlay;
    }
  }

  /// Jalankan update flexible (unduh di background oleh Play, user tetap
  /// pakai app). [onStatus] dipanggil untuk tiap perubahan InstallStatus.
  Future<AppUpdateResult> startFlexible({
    required void Function(InstallStatus) onStatus,
  }) async {
    await _playCore.checkForUpdate();
    _coreSub?.cancel();
    _coreSub = _playCore.installStatusStream.listen(onStatus);
    return _playCore.startFlexibleUpdate();
  }

  /// Terapkan update flexible yang sudah selesai diunduh → app restart.
  Future<void> completeFlexible() => _playCore.completeFlexibleUpdate();

  /// Update immediate (layar penuh Play, wajib sampai selesai) — untuk force.
  Future<AppUpdateResult> startImmediate() =>
      _playCore.performImmediateUpdate();

  StreamSubscription<InstallStatus>? _coreSub;

  /// Apakah Play melaporkan update tersedia (sumber tambahan dari kebijakan
  /// app_settings — dipakai bila admin belum mengisi latest_version).
  Future<bool> playReportsUpdate() async {
    try {
      final info = await _playCore.checkForUpdate();
      return info.updateAvailability == UpdateAvailability.updateAvailable;
    } catch (e) {
      dlog('[UPDATE] playReportsUpdate error: $e');
      return false;
    }
  }

  /// Buka listing Play di browser (fallback non-Play / tombol manual).
  Future<void> openPlayListing() async {
    try {
      final uri = Uri.parse(playListing);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      dlog('[UPDATE] openPlayListing error: $e');
    }
  }

  void dispose() {
    _coreSub?.cancel();
    _coreSub = null;
  }
}

/// Abstraksi tipis di atas plugin `in_app_update` — supaya provider bisa
/// diuji tanpa memanggil MethodChannel native.
abstract class AppUpdateClient {
  Future<AppUpdateInfo> checkForUpdate();
  Future<AppUpdateResult> startFlexibleUpdate();
  Future<AppUpdateResult> performImmediateUpdate();
  Future<void> completeFlexibleUpdate();
  Stream<InstallStatus> get installStatusStream;
}

/// Implementasi nyata (plugin Play Core).
class PlayCoreClient implements AppUpdateClient {
  const PlayCoreClient();

  @override
  Future<AppUpdateInfo> checkForUpdate() => InAppUpdate.checkForUpdate();

  @override
  Future<AppUpdateResult> startFlexibleUpdate() =>
      InAppUpdate.startFlexibleUpdate();

  @override
  Future<AppUpdateResult> performImmediateUpdate() =>
      InAppUpdate.performImmediateUpdate();

  @override
  Future<void> completeFlexibleUpdate() => InAppUpdate.completeFlexibleUpdate();

  @override
  Stream<InstallStatus> get installStatusStream =>
      InAppUpdate.installUpdateListener;
}
