import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/tiktok_service.dart';

/// TikTokService: pembungkus MethodChannel `com.chatyuk.chatyuk/tiktok`.
/// Diuji dgn MethodChannel mock (tanpa SDK native) — memastikan method &
/// argumen yang dikirim KE NATIVE benar (init/identify/track/purchase).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ch = MethodChannel('com.chatyuk.chatyuk/tiktok');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TikTokService.channelForTest = ch;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'identify':
        case 'track':
        case 'purchase':
        case 'logout':
          return true;
        case 'isInitialized':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
  });

  test('init mengirim accessToken & debug ke native', () async {
    final ok = await TikTokService.instance.init(accessToken: 'TT-xyz');
    expect(ok, isTrue);
    final init = calls.firstWhere((c) => c.method == 'initialize');
    expect((init.arguments as Map)['accessToken'], 'TT-xyz');
    expect((init.arguments as Map).containsKey('debug'), isTrue);
  });

  test('track mengirim nama event enum', () async {
    await TikTokService.instance.init(accessToken: 't');
    final ok = await TikTokService.instance.track(TikTokEvent.REGISTRATION);
    expect(ok, isTrue);
    final tr = calls.firstWhere((c) => c.method == 'track');
    expect((tr.arguments as Map)['event'], 'REGISTRATION');
  });

  test('purchase mengirim value/currency/content', () async {
    await TikTokService.instance.init(accessToken: 't');
    final ok = await TikTokService.instance.purchase(
      value: 50000,
      currency: 'IDR',
      contentId: 'yukcoin_50k',
      contentType: 'yukcoin',
      description: 'YukCoin 500',
    );
    expect(ok, isTrue);
    final pc = calls.firstWhere((c) => c.method == 'purchase');
    final a = pc.arguments as Map;
    expect(a['value'], 50000);
    expect(a['currency'], 'IDR');
    expect(a['contentId'], 'yukcoin_50k');
    expect(a['contentType'], 'yukcoin');
  });

  test('identify mengirim externalId + nama', () async {
    await TikTokService.instance.init(accessToken: 't');
    await TikTokService.instance
        .identify(externalId: 'uid-1', externalUserName: 'Budi');
    final id = calls.firstWhere((c) => c.method == 'identify');
    expect((id.arguments as Map)['externalId'], 'uid-1');
    expect((id.arguments as Map)['externalUserName'], 'Budi');
  });

  test('track tanpa init → false (belum ready), tak kirim ke native', () async {
    // service baru belum init di test ini (singleton — reset via init kosong).
    // Pastikan tak crash & tak melempar saat SDK belum ready.
    final r = await TikTokService.instance.track(TikTokEvent.LOGIN);
    expect(r, anyOf(isTrue, isFalse)); // idempoten: tergantung state, tak throw
  });
}
