import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/media_disk_cache.dart';

import 'test_helper.dart';

/// Fase 2 — MediaDiskCache pada filesystem nyata (temp dir via mock
/// path_provider). Logic-only: tanpa Supabase/plugin lain.
///
/// CATATAN: `mockPathProvider()` bawaan mengembalikan temp dir BARU tiap
/// panggilan — itu membuat write & read mendarat di folder berbeda. Di sini
/// kita pakai satu dir stabil supaya menyerupai path_provider asli.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    mockPathProvider();
    root = Directory.systemTemp.createTempSync('chatyuk_mdc_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => root.path,
    );
    await MediaDiskCache.instance.clearAll();
    await MediaDiskCache.instance.prewarm();
  });

  tearDown(() async {
    await MediaDiskCache.instance.clearAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('prewarm → isReady true & readSync aman dipakai', () async {
    expect(MediaDiskCache.instance.isReady, isTrue);
    // Belum ada file → null, bukan crash.
    expect(MediaDiskCache.instance.readSync('avatars/a.jpg'), isNull);
  });

  test('write lalu read mengembalikan bytes yang sama', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await MediaDiskCache.instance.write('avatars/u1/pic.jpg', bytes);
    final out = await MediaDiskCache.instance.read('avatars/u1/pic.jpg');
    expect(out, bytes);
  });

  test('write lalu readSync (jalur avatar instan) mengembalikan bytes',
      () async {
    final bytes = Uint8List.fromList([9, 8, 7]);
    await MediaDiskCache.instance.write('avatars/u2/pic.jpg', bytes);
    expect(MediaDiskCache.instance.readSync('avatars/u2/pic.jpg'), bytes);
  });

  test('read path belum pernah ditulis → null', () async {
    expect(await MediaDiskCache.instance.read('avatars/none/x.jpg'), isNull);
  });

  test('write path kosong / bytes kosong → no-op (tidak crash)', () async {
    await MediaDiskCache.instance.write('', Uint8List.fromList([1]));
    await MediaDiskCache.instance.write('avatars/u3/x.jpg', Uint8List(0));
    expect(await MediaDiskCache.instance.read('avatars/u3/x.jpg'), isNull);
  });

  test('fileFor mengembalikan null bila belum ter-cache', () async {
    expect(await MediaDiskCache.instance.fileFor('avatars/none/y.jpg'), isNull);
  });

  test('fileFor mengembalikan File bila sudah ada', () async {
    await MediaDiskCache.instance
        .write('voice/u4/v.m4a', Uint8List.fromList([1, 2]));
    final f = await MediaDiskCache.instance.fileFor('voice/u4/v.m4a');
    expect(f, isNotNull);
    expect(await f!.exists(), isTrue);
  });

  test('keepOnly menghapus file yang tidak ada di activePaths', () async {
    await MediaDiskCache.instance.write('avatars/keep.jpg', Uint8List(4));
    await MediaDiskCache.instance.write('avatars/drop.jpg', Uint8List(4));

    await MediaDiskCache.instance.keepOnly({'avatars/keep.jpg'});

    expect(
      await MediaDiskCache.instance.read('avatars/keep.jpg'),
      isNotNull,
    );
    expect(await MediaDiskCache.instance.read('avatars/drop.jpg'), isNull);
  });

  test('clearAll menghapus semua & mengosongkan index', () async {
    await MediaDiskCache.instance.write('avatars/z.jpg', Uint8List(4));
    await MediaDiskCache.instance.clearAll();
    expect(await MediaDiskCache.instance.read('avatars/z.jpg'), isNull);
  });
}
