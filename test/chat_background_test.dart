import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/chat_background.dart';

/// Fase 2 — `warmChatBackground`: load asset + decode jadi ui.Image global.
/// Hermetic: rootBundle di-mock dengan JPEG sintetis (tanpa baca file asli).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> log;

  setUp(() {
    log = [];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    chatBackgroundImage?.dispose();
    chatBackgroundImage = null;
  });

  void mockAsset(Uint8List bytes) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      log.add(MethodCall('get', key));
      if (key == 'assets/chat_bg.jpg') {
        return ByteData.view(bytes.buffer);
      }
      return null;
    });
  }

  test('warmChatBackground memuat asset & mengisi chatBackgroundImage',
      () async {
    final jpg = _jpeg(64, 96);
    mockAsset(jpg);

    expect(chatBackgroundImage, isNull);
    await warmChatBackground();

    expect(chatBackgroundImage, isNotNull);
    expect(chatBackgroundImage!.width, 64);
    expect(chatBackgroundImage!.height, 96);
    expect(log.any((c) => c.arguments == 'assets/chat_bg.jpg'), isTrue);
  });
}

Uint8List _jpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(40, 60, 90));
  return Uint8List.fromList(img.encodeJpg(im, quality: 80));
}
