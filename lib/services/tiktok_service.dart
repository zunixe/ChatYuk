import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils.dart';

/// TikTok App Events (Business) SDK — pembungkus Dart dari MethodChannel
/// native `com.chatyuk.chatyuk/tiktok` (lihat android/.../TikTokBridge.kt).
///
/// Tujuan: kirim event in-app (install/login/registrasi/purchase) ke TikTok
/// Events Manager untuk optimasi iklan TikTok (AEO/VBO).
///
/// Sifat: BEST-EFFORT. Kegagalan TikTok TIDAK PERNAH menggagalkan alur app —
/// semua method menelan error & return bool/null. Hanya jalan di Android
/// (iOS/web = no-op).
///
/// Konfigurasi:
///   - App ID & TikTok App ID: dari AndroidManifest meta-data
///     (com.tiktok.sdk.app_id / tt_app_id) — diisi di res/values/strings.xml.
///   - Access Token (rahasia): dari `--dart-define=TIKTOK_ACCESS_TOKEN=...`
///     (lihat AppEnv). Tidak ditulis di source.
class TikTokService {
  TikTokService._();
  static final TikTokService instance = TikTokService._();

  static const MethodChannel _realChannel =
      MethodChannel('com.chatyuk.chatyuk/tiktok');

  /// Channel efektif — mock-able di test (default channel asli).
  static MethodChannel get _channel => channelForTest;

  bool _initTried = false;
  bool _ready = false;
  String? _pendingIdentifyExternalId;
  // Antrean event (standard + purchase) bila SDK belum ready — supaya event
  // yang datang lebih awal (mis. REGISTRATION tepat setelah daftar) TIDAK
  // hilang. Dikirim begitu init selesai.
  final List<TikTokEvent> _pendingEvents = [];
  final List<Map<String, dynamic>> _pendingPurchases = [];

  @visibleForTesting
  static MethodChannel channelForTest = _realChannel;

  /// Reset state (khusus test): biar singleton bisa diuji antar-skenario.
  @visibleForTesting
  void resetForTest() {
    _initTried = false;
    _ready = false;
    _pendingIdentifyExternalId = null;
    _pendingEvents.clear();
    _pendingPurchases.clear();
  }

  /// True bila SDK sudah ter-init di native.
  bool get isReady => _ready;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Init SDK sekali. `accessToken` dari dart-define (rahasia).
  Future<bool> init({String accessToken = '', bool debug = false}) async {
    if (!_supported) return false;
    if (_initTried && _ready) return true;
    _initTried = true;
    try {
      final ok = await _channel.invokeMethod<bool>('initialize', {
        'accessToken': accessToken,
        'debug': debug || kDebugMode,
      });
      _ready = ok == true;
      dlog('[TIKTOK] init ready=$_ready');
      // Bila ada permintaan identify yang datang sebelum init, kirim sekarang.
      final pending = _pendingIdentifyExternalId;
      if (_ready && pending != null) {
        _pendingIdentifyExternalId = null;
        await identify(externalId: pending);
      }
      // Kirim event yang sempat di-antre (datang sebelum SDK siap).
      if (_ready) {
        final evts = List<TikTokEvent>.of(_pendingEvents);
        _pendingEvents.clear();
        for (final e in evts) {
          await track(e);
        }
        final purch = _pendingPurchases
            .map((m) => Map<String, dynamic>.of(m))
            .toList();
        _pendingPurchases.clear();
        for (final m in purch) {
          await purchase(
            value: (m['value'] as num).toDouble(),
            currency: m['currency'] as String? ?? 'IDR',
            description: m['description'] as String? ?? '',
            contentId: m['contentId'] as String? ?? '',
            contentType: m['contentType'] as String? ?? '',
          );
        }
      }
      return _ready;
    } catch (e) {
      dlog('[TIKTOK] init error: $e');
      _ready = false;
      return false;
    }
  }

  /// Set identitas user (external id/nama/phone/email). Panggil tiap login/
  /// daftar & saat profil berubah. Bila SDK belum init → antre sekali.
  Future<bool> identify({
    required String externalId,
    String externalUserName = '',
    String phoneNumber = '',
    String email = '',
  }) async {
    if (!_supported) return false;
    if (!_ready) {
      // Simpan externalId; dikirim setelah init selesai.
      if (externalId.isNotEmpty) _pendingIdentifyExternalId = externalId;
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('identify', {
            'externalId': externalId,
            'externalUserName': externalUserName,
            'phoneNumber': phoneNumber,
            'email': email,
          }) ??
          false;
    } catch (e) {
      dlog('[TIKTOK] identify error: $e');
      return false;
    }
  }

  /// Reset identitas (panggil saat logout).
  Future<void> logout() async {
    if (!_supported || !_ready) return;
    try {
      await _channel.invokeMethod<bool>('logout');
      _pendingIdentifyExternalId = null;
    } catch (e) {
      dlog('[TIKTOK] logout error: $e');
    }
  }

  /// Event standar tanpa konten (LOGIN/REGISTRATION/GENERATE_LEAD/RATE/dll).
  /// Bila SDK belum siap → di-antre & dikirim setelah init (tak hilang).
  Future<bool> track(TikTokEvent event) async {
    if (!_supported) return false;
    if (!_ready) {
      _pendingEvents.add(event);
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('track', {
            'event': event.name,
          }) ??
          false;
    } catch (e) {
      dlog('[TIKTOK] track ${event.name} error: $e');
      return false;
    }
  }

  /// Event Purchase (pendapatan). [value] total, [currency] ISO 4217.
  /// Bila SDK belum siap → di-antre & dikirim setelah init (tak hilang).
  Future<bool> purchase({
    required double value,
    String currency = 'IDR',
    String description = '',
    String contentId = '',
    String contentType = '',
  }) async {
    if (!_supported) return false;
    if (!_ready) {
      _pendingPurchases.add({
        'value': value,
        'currency': currency,
        'description': description,
        'contentId': contentId,
        'contentType': contentType,
      });
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('purchase', {
            'value': value,
            'currency': currency,
            if (description.isNotEmpty) 'description': description,
            if (contentId.isNotEmpty) 'contentId': contentId,
            if (contentType.isNotEmpty) 'contentType': contentType,
          }) ??
          false;
    } catch (e) {
      dlog('[TIKTOK] purchase error: $e');
      return false;
    }
  }
}

/// Subset EventName TikTok yang didukung app (samakan enum native).
enum TikTokEvent {
  LOGIN,
  REGISTRATION,
  GENERATE_LEAD,
  RATE,
  START_TRIAL,
  SUBSCRIBE,
  LAUNCH_APP,
  ADD_PAYMENT_INFO,
  COMPLETE_TUTORIAL,
  SEARCH,
  SPEND_CREDITS,
  IN_APP_AD_CLICK,
  IN_APP_AD_IMPR,
}
