import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/crypto_native.dart';

/// CryptoNative: di environment test TANPA channel native, semua op FALLBACK
/// ke implementasi Dart (`package:cryptography`) dan tetap benar. Channel
/// native (Android Keystore) hanya ada di device — lihat crypto/CryptoBridge.kt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock flutter_secure_storage (in-memory) agar fallback Dart bisa ambil kunci.
  final store = <String, String>{};
  const secureCh = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    store.clear();
    CryptoNative.resetAvailabilityForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureCh, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'read':
          return store[args['key'] as String];
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'containsKey':
          return store.containsKey(args['key'] as String);
        default:
          return null;
      }
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureCh, null);
  });

  test('isAvailable false tanpa channel native', () async {
    expect(await CryptoNative.isAvailable(), isFalse);
  });

  test('encryptString → decryptString roundtrip', () async {
    const plain = 'halo dunia 🌏 test cache pesan';
    final enc = await CryptoNative.encryptString(plain);
    expect(enc, isNotEmpty);
    expect(enc, isNot(plain));
    final dec = await CryptoNative.decryptString(enc);
    expect(dec, plain);
  });

  test('payload format {n,c,m} (kompatibel Dart lama)', () async {
    final enc = (await CryptoNative.dartEncryptForTest('x')).toString();
    // decrypt balik lewat jalur Dart.
    final dec = await CryptoNative.dartDecryptForTest(enc);
    expect(dec, 'x');
  });

  test('encrypt berbeda tiap kali (nonce acak)', () async {
    final a = await CryptoNative.encryptString('sama');
    final b = await CryptoNative.encryptString('sama');
    expect(a, isNot(b));
    expect(await CryptoNative.decryptString(a), 'sama');
    expect(await CryptoNative.decryptString(b), 'sama');
  });

  test('decrypt payload rusak → null (tidak crash)', () async {
    expect(await CryptoNative.decryptString('bukan-base64!!!'), isNull);
    expect(await CryptoNative.decryptString(''), isNull);
  });

  test('decryptFiles map kosong → kosong', () async {
    expect(await CryptoNative.decryptFiles({}), isEmpty);
  });

  test('string UTF-8 panjang roundtrip (base64 foto besar)', () async {
    final big = 'A' * 500000;
    final enc = await CryptoNative.encryptString(big);
    expect(await CryptoNative.decryptString(enc), big);
  });
}
