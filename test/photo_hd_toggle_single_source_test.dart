import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HD dipilih di SATU tempat: panel galeri (`gallery_picker_sheet.dart`).
/// Toggle HD kedua di preview composer sudah dihapus (minta user 2026-10-20:
/// "pas preview ga usah ada HD lagi jadinya double").
void main() {
  test('HD hanya di gallery picker, tidak di composer preview', () {
    final composer = File(
      'lib/widgets/chat_composer_input.dart',
    ).readAsStringSync();
    expect(composer.contains('photoHd'), isFalse);
    expect(composer.contains('onHdChanged'), isFalse);
    expect(composer.contains('photoHdLabel'), isFalse);

    final sheet = File(
      'lib/widgets/gallery_picker_sheet.dart',
    ).readAsStringSync();
    expect(sheet.contains('_hdButton()'), isTrue);
    expect(sheet.contains('hd: _hd'), isTrue);
  });
}
