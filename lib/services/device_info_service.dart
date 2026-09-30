import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/screen_secure_service.dart';
import 'attribution_service.dart';

/// Kumpulkan identitas perangkat (brand/model/OS/versi app) + install ID
/// unik per-install, lalu sync ke server (RPC upsert_device).
///
/// install ID = UUID acak disimpan sekali di secure storage — TIDAK berubah
/// selama app ter-install (beda dengan fcm_token yang bisa di-rotate).
/// Dipakai admin untuk melacak device mana yang dipakai akun mana.
class DeviceInfoService {
  /// Client opsional (LAZY) — test menyuntik client palsu.
  final SupabaseClient? _injected;
  DeviceInfoService._([SupabaseClient? sb]) : _injected = sb;

  static DeviceInfoService instance = DeviceInfoService._();

  @visibleForTesting
  factory DeviceInfoService.forTest(SupabaseClient sb) =>
      DeviceInfoService._(sb);

  @visibleForTesting
  static void overrideInstance(DeviceInfoService s) => instance = s;

  @visibleForTesting
  static void restoreInstance() => instance = DeviceInfoService._();

  static const _kInstallId = 'install_id';
  static const _storage = FlutterSecureStorage();

  SupabaseClient get _sb => _injected ?? SupabaseConfig.client;

  /// `android-<ANDROID_ID>` bila tersedia — dipakai sebagai
  /// `p_legacy_install_id` supaya server memigrasi baris device lama
  /// (pra-MediaDrm) ke identifier baru in-place, bukan bikin baris baru.
  Future<String> _legacyAndroidId() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return '';
    final aid = await ScreenSecureService.androidId();
    return aid.trim().length >= 6 ? 'android-${aid.trim()}' : '';
  }

  /// ID unik per HP fisik:
  ///  - Android → MediaDrm (Widevine) deviceUniqueId — stabil untuk SATU
  ///    perangkat fisik: tetap sama walau app di-reinstall, ganti signing
  ///    key, atau dibuka dari user profile lain (Second Space/Dual Apps).
  ///    Fallback ke ANDROID_ID bila Widevine tidak tersedia.
  ///  - iOS → identifierForVendor.
  ///  - Fallback → UUID di secure storage (jarang terpakai).
  Future<String> installId() async {
    // 1. MediaDrm deviceUniqueId — paling stabil (tahan reinstall/keystore/
    //    profil user). Menutup celah ANDROID_ID yang berubah saat signing
    //    key berubah → dulu bikin device ter-exclude "muncul lagi".
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final drmId = await ScreenSecureService.deviceUniqueId();
      if (drmId.trim().length >= 16) {
        return 'drm-${drmId.trim()}';
      }
    }
    // 2. Android ID (via MethodChannel) — fallback bila Widevine tak ada.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final aid = await ScreenSecureService.androidId();
      if (aid.isNotEmpty && aid.trim().length >= 6) {
        return 'android-${aid.trim()}';
      }
    }
    // 3. iOS identifierForVendor.
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        final idfv = (i.identifierForVendor ?? '').trim();
        if (idfv.isNotEmpty) return 'ios-$idfv';
      }
    } catch (_) {}
    // 4. Fallback: UUID per-install di secure storage.
    try {
      final existing = await _storage.read(key: _kInstallId);
      if (existing != null && existing.isNotEmpty) return existing;
      final newId = _generateId();
      await _storage.write(key: _kInstallId, value: newId);
      return newId;
    } catch (_) {
      return _ephemeralId;
    }
  }

  /// ID sementara kalau secure storage tidak tersedia (mis. web/test).
  String? _ephemeral;

  String get _ephemeralId {
    _ephemeral ??= _generateId();
    return _ephemeral!;
  }

  String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20, 32),
    ].join('-');
  }

  /// Info perangkat — brand, model, OS, versi app. Return record null-safe.
  Future<({String brand, String model, String osName, String osVersion, String appVersion, String buildNumber})>
      collectDeviceInfo() async {
    String brand = '';
    String model = '';
    String osName = '';
    String osVersion = '';
    String appVersion = '';
    String buildNumber = '';

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
        if (defaultTargetPlatform == TargetPlatform.android) {
          final a = await deviceInfo.androidInfo;
          brand = a.brand;
          model = a.model;
          osName = 'android';
          osVersion = a.version.release;
        } else {
          final i = await deviceInfo.iosInfo;
          brand = i.isPhysicalDevice ? 'Apple' : 'Simulator';
          model = i.model;
          osName = 'ios';
          osVersion = i.systemVersion;
        }
      }
    } catch (e) {
      dlog('[DEVICE] collectDevice failed: $e');
    }

    try {
      final p = await PackageInfo.fromPlatform();
      appVersion = p.version;
      buildNumber = p.buildNumber;
    } catch (e) {
      dlog('[DEVICE] packageInfo failed: $e');
    }

    return (
      brand: brand,
      model: model,
      osName: osName,
      osVersion: osVersion,
      appVersion: appVersion,
      buildNumber: buildNumber,
    );
  }

  // Identitas BRAND/MODEL/OS/VERSI + install id + legacy — MAHAL (native
  // MediaDrm + plugin) tapi KONSTAN selama sesi → cache. Supaya resume
  // berkala hanya melakukan upsert (murah), bukan menghitung ulang tiap kali.
  String? _cachedInstallId;
  String? _cachedLegacy;
  ({
    String brand,
    String model,
    String osName,
    String osVersion,
    String appVersion,
    String buildNumber,
  })? _cachedInfo;

  /// Kirim identitas device ke server (device id + info) — dengan RETRY.
  /// Idempoten (upsert). Dipanggil saat login & tiap online/resume supaya
  /// kegagalan sesaat tidak membuat device "tak terdeteksi" selamanya.
  Future<void> syncToServer({String ipAddress = ''}) async {
    final user = _sb.auth.currentUser;
    if (user == null) return; // perlu auth.uid untuk upsert
    // Hitung identitas sekali per sesi (native mahal) lalu pakai cache.
    try {
      _cachedInstallId ??= await installId();
      _cachedLegacy ??= await _legacyAndroidId();
      _cachedInfo ??= await collectDeviceInfo();
    } catch (e) {
      dlog('[DEVICE] collect error: $e');
      return;
    }
    final id = _cachedInstallId!;
    final legacy = _cachedLegacy!;
    final info = _cachedInfo!;
    // Snapshot nickname (best-effort).
    String nickname = '';
    try {
      final row = await _sb
          .from('profiles')
          .select('nickname')
          .eq('id', user.id)
          .maybeSingle();
      nickname = '${row?['nickname'] ?? ''}';
    } catch (_) {}
    final params = <String, dynamic>{
      'p_install_id': id,
      'p_brand': info.brand,
      'p_model': info.model,
      'p_os_name': info.osName,
      'p_os_version': info.osVersion,
      'p_app_version': info.appVersion,
      'p_ip': ipAddress,
      'p_nickname': nickname,
      // Baris device lama (`android-<id>`) dimigrasi in-place ke `id`
      // sekarang bila berbeda (mis. baru pindah ke MediaDrm).
      if (legacy.isNotEmpty && legacy != id) 'p_legacy_install_id': legacy,
    };
    // Atribusi sumber (FB/IG/Google/TikTok/referral/organik) — server
    // 'tulis sekali', jadi resume berkala tidak menimpa kanal asli.
    try {
      params.addAll(await AttributionService.instance.attributionParams());
    } catch (e) {
      dlog('[DEVICE] attribution params gagal: $e');
    }
    // Uji coba 3× dengan jeda singkat — jaringan HP sering gagal sesaat.
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _sb.rpc('upsert_device', params: params);
        dlog('[DEVICE] syncToServer OK id=$id uid=${user.id}');
        return;
      } catch (e) {
        lastErr = e;
        dlog('[DEVICE] syncToServer attempt$attempt error: $e');
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    // Terlihat juga di RILIS (print → logcat) — kegagalan senyap membuat
    // device tak terdeteksi di admin tanpa jejak yang bisa didiagnosis.
    // ignore: avoid_print
    print('[DEVICE] syncToServer FAIL id=$id uid=${user.id}: $lastErr');
  }
}