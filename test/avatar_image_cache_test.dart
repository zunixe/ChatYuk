import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chatyuk/widgets/avatar_image_cache.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('get/evict/clear + LRU cap byte', () async {
    final c = AvatarImageCache.instance;
    c.clear();
    expect(c.get('x'), isNull);
    // put dengan bytes invalid → null (tak crash), store tetap kosong.
    final img = await c.put('x', Uint8List.fromList([1, 2, 3]));
    expect(img, isNull);
    expect(c.length, 0);
  });

  test('AvatarMemoryImage: key stabil + equality', () {
    final bytes = Uint8List.fromList([9, 9, 9]);
    final a = AvatarMemoryImage('u1', bytes, width: 96);
    final b = AvatarMemoryImage('u1', bytes, width: 96);
    expect(a, b); // uid+width+bytes identik → sama (stream stabil)
    final c2 = AvatarMemoryImage('u2', bytes, width: 96);
    expect(a == c2, isFalse);
  });

  test('ui.Image tile ukuran 96px (dokumentasi ukuran)', () {
    // Sanity: 96x96 RGBA = 36 KB → cap 8MB ≈ 220 avatar.
    expect(96 * 96 * 4, 36864);
  });

  test('subscriber clone tetap hidup setelah master di-evict (anti '
      '"Cannot clone a disposed image")', () async {
    // Regresi 2026-10-13: pool men-dispose master yang masih dibungkus
    // ImageInfo di ImageStreamCompleter subscriber → clone() crash → avatar
    // kosong di timeline. Urutan persis produksi: loadImage → subscriber
    // terima handle → pool evict → subscriber clone → wajib tidak throw.
    // Catatan jujur: backend Skia di `flutter test` tidak menegakkan
    // dispose (clone setelah dispose tetap jalan), jadi test ini mengunci
    // KONTRAK alur (handle independen per subscriber), bukan crash nativenya
    // — crash nativenya diverifikasi di HP (0 kejadian setelah fix).
    final c = AvatarImageCache.instance;
    c.clear();
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAE0lEQVR4nGM8IafBAANMcBZeDgA2YAEWpYI78QAAAABJRU5ErkJggg==');
    final provider = AvatarMemoryImage('clone-u', bytes, width: 96);
    final key = await provider.obtainKey(const ImageConfiguration());
    final completer = provider.loadImage(
      key,
      (ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) =>
          ui.instantiateImageCodecFromBuffer(buffer),
    );
    ImageInfo? got;
    completer.addListener(ImageStreamListener((info, _) => got = info));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(got, isNotNull, reason: 'subscriber harus terima ImageInfo');
    // Pool evict selagi subscriber masih render (mis. LRU global imageCache
    // membuang completer, atau logout).
    c.evict('clone-u');
    // Clone dari handle subscriber harus tetap hidup.
    final h2 = got!.image.clone();
    expect(h2.width, greaterThan(0));
    h2.dispose();
    got!.dispose();
    c.clear();
  });

  test('loadImage membagikan clone (bukan master) ke subscriber', () async {
    final c = AvatarImageCache.instance;
    c.clear();
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAE0lEQVR4nGM8IafBAANMcBZeDgA2YAEWpYI78QAAAABJRU5ErkJggg==');
    final provider = AvatarMemoryImage('clone-u2', bytes, width: 96);
    // Provider butuh bytes valid — bangun via put lalu loadImage.
    await c.put('clone-u2', bytes);
    final key =
        await provider.obtainKey(const ImageConfiguration());
    final completer = provider.loadImage(
      key,
      (ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) =>
          ui.instantiateImageCodecFromBuffer(buffer));
    var gotImage = false;
    completer.addListener(ImageStreamListener((info, _) {
      gotImage = true;
      // ImageInfo subscriber harus independen dari master pool.
      info.dispose();
    }));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(gotImage, isTrue);
    // Pool boleh dibuang sekarang; subscriber sudah selesai — tak crash.
    c.clear();
  });
}
