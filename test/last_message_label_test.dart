import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/core/chat/last_message_label.dart';

/// Label media dari server (Indonesia) diterjemahkan ke bahasa UI.
void main() {
  final en = S(isId: false);
  final id = S(isId: true);

  test('label server → bahasa UI', () {
    expect(localizeLastMessage('[Stiker]', en), '[Sticker]');
    expect(localizeLastMessage('[Pesan suara]', en), '[Voice message]');
    expect(localizeLastMessage('[Foto]', en), '[Photo]');
    expect(localizeLastMessage('[Koin]', en), '[Coin]');
    expect(localizeLastMessage('[Stiker]', id), '[Stiker]');
  });

  test('teks biasa tidak diubah', () {
    expect(localizeLastMessage('halo [Stiker] lucu', en), 'halo [Stiker] lucu');
    expect(localizeLastMessage('📊 Makan apa?', en), '📊 Makan apa?');
  });
}
