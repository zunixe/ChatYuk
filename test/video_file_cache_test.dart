import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/video_file_cache.dart';

import 'test_helper.dart';

/// VideoFileCache: cache FILE video PERSISTEN (seperti voice) — sekali dibuka,
/// cold start berikutnya langsung kebuka tanpa unduh ulang.
///
/// Regresi 2026-10-11: card video "ngeload/kedip" tiap cold start karena video
/// bytes disimpan di temp dir (bisa dibersihkan OS) atau di MediaDiskCache
/// (kuota 250MB bersama → evict LRU). Sekarang direktori khusus `video_cache/`
/// di documents + kuota 1GB sendiri + LRU.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    mockPathProvider();
    root = Directory.systemTemp.createTempSync('chatyuk_vfc_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => root.path,
    );
    await VideoFileCache.instance.clearAll();
    await VideoFileCache.instance.prewarm();
  });

  tearDown(() async {
    await VideoFileCache.instance.clearAll();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('prewarm → isReady true', () async {
    expect(VideoFileCache.instance.isReady, isTrue);
  });

  test('put → fileForSync HIT (persisten, seperti voice)', () async {
    const path = 'chat/c1/vid1.mp4';
    final bytes = Uint8List.fromList(List<int>.filled(1024, 7));
    final f = await VideoFileCache.instance.put(path, bytes);
    expect(f, isNotNull);
    final hit = VideoFileCache.instance.fileForSync(path);
    expect(hit, isNotNull);
    expect(hit!.lengthSync(), 1024);
  });

  test('fileForSync null untuk path yang belum disimpan', () {
    expect(
      VideoFileCache.instance.fileForSync('chat/c1/belum-ada.mp4'),
      isNull,
    );
  });

  test('put path SAMA menimpa (idempoten, tanpa duplikat)', () async {
    const path = 'chat/c1/sama.mp4';
    await VideoFileCache.instance.put(
      path,
      Uint8List.fromList(List<int>.filled(100, 1)),
    );
    await VideoFileCache.instance.put(
      path,
      Uint8List.fromList(List<int>.filled(200, 2)),
    );
    final hit = VideoFileCache.instance.fileForSync(path);
    expect(hit, isNotNull);
    expect(hit!.lengthSync(), 200);
  });

  test('remove menghapus entri', () async {
    const path = 'chat/c1/hapus.mp4';
    await VideoFileCache.instance.put(
      path,
      Uint8List.fromList(List<int>.filled(64, 9)),
    );
    expect(VideoFileCache.instance.fileForSync(path), isNotNull);
    await VideoFileCache.instance.remove(path);
    expect(VideoFileCache.instance.fileForSync(path), isNull);
  });
}
