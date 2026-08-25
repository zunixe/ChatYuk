import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'screen_secure_service.dart';

/// Kumpulkan identitas perangkat (brand/model/OS/versi app) + install ID
/// unik per-install, lalu sync ke server (RPC upsert_device).
///
/// install ID = UUID acak disimpan sekali di secure storage — TIDAK berubah
/// selama app ter-install (beda dengan fcm_token yang bisa di-rotate).
/// Dipakai admin untuk melacak device mana yang dipakai akun mana.
class DeviceInfoService {
  DeviceInfoService._();
  static final DeviceInfoService instance = DeviceInfoService._();

  static const _kInstallId = 'install_id';
  static const _storage = FlutterSecureStorage();

  SupabaseClient get _sb => SupabaseConfig.client;

  /// ID unik per HP fisik:
  ///  - Android → ANDROID_ID (Settings.Secure) via MethodChannel — unik per
  ///    perangkat + signing key, STABIL walau app di-reinstall (hanya berubah
  ///    saat factory reset). Inilah yang dipakai admin agar 1 HP = 1 device.
  ///  - iOS → identifierForVendor.
  ///  - Fallback → UUID di secure storage (jarang terpakai).
  Future<String> installId() async {
    // 1. Android ID (via MethodChannel) — sumber utama & stabil.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final aid = await ScreenSecureService.androidId();
      if (aid.isNotEmpty && aid.trim().length >= 6) {
        return 'android-${aid.trim()}';
      }
    }
    // 2. iOS identifierForVendor.
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        final idfv = (i.identifierForVendor ?? '').trim();
        if (idfv.isNotEmpty) return 'ios-$idfv';
      }
    } catch (_) {}
    // 3. Fallback: UUID per-install di secure storage.
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
  Future<({String brand, String model, String osName, String osVersion, String appVersion})>
      collectDeviceInfo() async {
    String brand = '';
    String model = '';
    String osName = '';
    String osVersion = '';
    String appVersion = '';

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
      debugPrint('[DEVICE] collectDevice failed: $e');
    }

    try {
      final p = await PackageInfo.fromPlatform();
      appVersion = p.version;
    } catch (e) {
      debugPrint('[DEVICE] packageInfo failed: $e');
    }

    return (
      brand: brand,
      model: model,
      osName: osName,
      osVersion: osVersion,
      appVersion: appVersion,
    );
  }

  /// Kirim identitas device ke server (fire-and-forget, gagal diam).
  Future<void> syncToServer({String ipAddress = ''}) async {
    try {
      final id = await installId();
      final info = await collectDeviceInfo();
      final user = _sb.auth.currentUser;
      // Snapshot nickname dipakai untuk melacak device milik user yang
      // sudah dihapus (user_id di-SET NULL, nickname tetap tersimpan).
      String nickname = '';
      if (user != null) {
        try {
          final row = await _sb
              .from('profiles')
              .select('nickname')
              .eq('id', user.id)
              .maybeSingle();
          nickname = '${row?['nickname'] ?? ''}';
        } catch (_) {}
      }
      await _sb.rpc('upsert_device', params: {
        'p_install_id': id,
        'p_brand': info.brand,
        'p_model': info.model,
        'p_os_name': info.osName,
        'p_os_version': info.osVersion,
        'p_app_version': info.appVersion,
        'p_ip': ipAddress,
        'p_nickname': nickname,
      });
    } catch (e) {
      debugPrint('[DEVICE] syncToServer error: $e');
    }
  }
}