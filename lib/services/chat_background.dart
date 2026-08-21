import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;

ui.Image? chatBackgroundImage;

Future<void> warmChatBackground() async {
  final data = await rootBundle.load('assets/chat_bg.jpg');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final codec = await ui.instantiateImageCodec(bytes);
  chatBackgroundImage = (await codec.getNextFrame()).image;
}
