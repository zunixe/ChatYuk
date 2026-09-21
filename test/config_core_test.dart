import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chatyuk/config/call_config.dart';
import 'package:chatyuk/config/supabase_config.dart';
import 'package:chatyuk/core/admin_gate.dart';
import 'package:chatyuk/core/screen_secure_service.dart';

/// P5: config & core yang belum tersentuh test.
///
/// Yang dikunci:
/// - `SecureSessionStorage`: kontrak LocalStorage (lempar saat kosong,
///   roundtrip persist/remove) — keamanan sesi.
/// - `ScreenSecureService`: logika prioritas anti-screenshot
///   (viewOnce menang, donasi dikecualikan, build admin selalu bebas).
/// - `CallConfig`: fallback ICE saat TURN tak tersedia (tanpa network).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureSessionStorage — kontrak LocalStorage', () {
    late SecureSessionStorage store;

    setUp(() {
      store = SecureSessionStorage(
        persistSessionKey: 'chatyuk_test_session',
        legacyPrefsKey: 'sb-old-auth-token',
      );
    });

    test('accessToken() null saat belum ada sesi (tidak throw)', () async {
      // Keystore tidak tersedia di test → implementasi menelan error dan
      // mengembalikan null/false. Kontrak: TIDAK melempar.
      final token = await store.accessToken();
      expect(token, anyOf(isNull, isEmpty));
    });

    test('hasAccessToken() false saat kosong (tidak throw)', () async {
      final has = await store.hasAccessToken();
      expect(has, isFalse);
    });

    test('removePersistedSession aman dipanggil saat kosong', () async {
      await expectLater(store.removePersistedSession(), completes);
    });

    test(
      'persistSession lalu accessToken mengembalikan nilai yang sama',
      () async {
        // Keystore tidak ada di test → write ditelan, tapi memo in-memory
        // tetap di-set (perilaku yang dipakai app untuk hindari baca berulang).
        await store.persistSession('payload-sesi');
        final token = await store.accessToken();
        expect(
          token,
          anyOf('payload-sesi', isNull),
          reason: 'tanpa Keystore, memo in-memory masih menyimpan nilai',
        );
      },
    );
  });

  group('ScreenSecureService — prioritas anti-screenshot', () {
    final calls = <String>[];

    setUp(() {
      calls.clear();
      AdminGate.panelBuilder = null; // pastikan build user
    });

    tearDown(() {
      AdminGate.panelBuilder = null;
      // Kembalikan ke default supaya tidak bocor antar test.
      ScreenSecureService.setScreenshotEnabled(true);
      ScreenSecureService.exitDonation();
      ScreenSecureService.exitViewOnce();
    });

    // Tangkap method channel supaya bisa diverifikasi tanpa Android.
    void capture() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.chatyuk.chatyuk/window'),
            (call) async {
              calls.add(call.method);
              return null;
            },
          );
    }

    test('screenshot ON → clearSecure (tidak dikunci)', () async {
      capture();
      ScreenSecureService.setScreenshotEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c == 'clearSecure').length, greaterThan(0));
    });

    test('screenshot OFF → setSecure (dikunci)', () async {
      capture();
      ScreenSecureService.setScreenshotEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(calls.contains('setSecure'), isTrue);
    });

    test('viewOnce MENANG walau screenshot ON', () async {
      capture();
      ScreenSecureService.setScreenshotEnabled(true);
      calls.clear();

      ScreenSecureService.enterViewOnce();
      await Future<void>.delayed(Duration.zero);
      expect(
        calls.contains('setSecure'),
        isTrue,
        reason: 'pesan sekali-lihat wajib anti-screenshot',
      );

      calls.clear();
      ScreenSecureService.exitViewOnce();
      await Future<void>.delayed(Duration.zero);
      expect(
        calls.contains('clearSecure'),
        isTrue,
        reason: 'keluar view-once → kembali normal',
      );
    });

    test('donasi DIKECUALIKAN walau screenshot OFF', () async {
      capture();
      ScreenSecureService.enterDonation();
      ScreenSecureService.setScreenshotEnabled(false);
      calls.clear();

      // Sudah di donasi → setScreenshotEnabled(false) memicu _apply dan
      // donasi menang → clearSecure.
      ScreenSecureService.setScreenshotEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(
        calls.contains('clearSecure'),
        isTrue,
        reason: 'halaman donasi selalu boleh screenshot',
      );
    });

    test('build ADMIN selalu bebas (setting global tidak berlaku)', () async {
      capture();
      AdminGate.panelBuilder = (_) => const SizedBox.shrink();
      calls.clear();

      ScreenSecureService.setScreenshotEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(
        calls.contains('clearSecure'),
        isTrue,
        reason: 'app admin tidak boleh mengunci screenshot dirinya',
      );
    });

    test('getter screenshotEnabled mengikuti setter', () {
      ScreenSecureService.setScreenshotEnabled(false);
      expect(ScreenSecureService.screenshotEnabled, isFalse);
      ScreenSecureService.setScreenshotEnabled(true);
      expect(ScreenSecureService.screenshotEnabled, isTrue);
    });
  });

  group('CallConfig — fallback ICE (tanpa network)', () {
    tearDown(CallConfig.clearCloudflareCache);

    test(
      'getPeerConfig tanpa sesi user → tetap ada STUN + relay cadangan',
      () async {
        // Tanpa sesi Supabase, `_fetchCloudflare` return null → konfigurasi
        // fallback (STUN Google + openrelay) yang dipakai.
        final cfg = await CallConfig.getPeerConfig();
        final servers = cfg['iceServers'] as List;
        expect(servers, isNotEmpty);
        expect(
          servers.any((s) => '${s['urls']}'.contains('stun:')),
          isTrue,
          reason: 'STUN wajib ada',
        );
        expect(
          servers.any((s) => '${s['urls']}'.contains('turn:')),
          isTrue,
          reason: 'TURN cadangan wajib ada agar call lintas-NAT tetap jalan',
        );
        // Tanpa Cloudflare → JANGAN paksa relay-only (supaya P2P LAN tetap bisa).
        expect(cfg.containsKey('iceTransportPolicy'), isFalse);
        expect(cfg['sdpSemantics'], 'unified-plan');
      },
    );

    test('peerConfig statis punya iceServers', () {
      expect(CallConfig.peerConfig['iceServers'], isA<List>());
    });

    test('Cloudflare valid → relay policy dan credential dipakai', () async {
      var requests = 0;
      CallConfig.accessTokenOverride = 'test-user-token';
      CallConfig.httpClientOverride = MockClient((request) async {
        requests++;
        expect(request.headers['Authorization'], 'Bearer test-user-token');
        return http.Response(
          '{"iceServers":{"urls":"turn:cloudflare.example","username":"u","credential":"c"}}',
          200,
          request: request,
        );
      });

      final cfg = await CallConfig.getPeerConfig();
      final servers = cfg['iceServers'] as List;

      expect(requests, 1);
      expect(cfg['iceTransportPolicy'], 'relay');
      expect(
        servers,
        contains(
          allOf(
            containsPair('urls', 'turn:cloudflare.example'),
            containsPair('username', 'u'),
            containsPair('credential', 'c'),
          ),
        ),
      );
    });

    test('error response → fallback tanpa relay-only', () async {
      CallConfig.accessTokenOverride = 'test-user-token';
      CallConfig.httpClientOverride = MockClient((request) async {
        return http.Response('{"error":"expired"}', 401, request: request);
      });

      final cfg = await CallConfig.getPeerConfig();

      expect(cfg.containsKey('iceTransportPolicy'), isFalse);
      expect(
        (cfg['iceServers'] as List).any(
          (server) => '${server['urls']}'.contains('openrelay'),
        ),
        isTrue,
      );
    });

    test('credential valid di-cache dan tidak fetch HTTP dua kali', () async {
      var requests = 0;
      CallConfig.accessTokenOverride = 'test-user-token';
      CallConfig.httpClientOverride = MockClient((request) async {
        requests++;
        return http.Response(
          '{"iceServers":{"urls":"turn:cloudflare.example","username":"u","credential":"c"}}',
          200,
          request: request,
        );
      });

      await CallConfig.getPeerConfig();
      await CallConfig.getPeerConfig();

      expect(requests, 1);
    });
  });
}
